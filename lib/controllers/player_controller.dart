import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '../models/track.dart';
import '../services/audio_resolver.dart';
import '../services/tiktok_sound_service.dart';
import '../services/tiktok_audio_cache.dart';
import '../services/lyrics_service.dart';
import '../services/audio_timeline.dart';
import '../services/music_service.dart';
import '../services/player_session_store.dart';
import '../services/playback_end_guard.dart';
import '../services/offline_storage_service.dart';
import 'listening_history_controller.dart';

enum RepeatMode { off, all, one }

class PlayerController extends ChangeNotifier with WidgetsBindingObserver {
  static final PlayerController instance = PlayerController._internal();
  PlayerController._internal({
    AudioPlayer? player,
    AudioResolverService? resolver,
    TikTokAudioCache? tikTokCache,
    TikTokSoundService? tikTokSounds,
    Future<String> Function(Track)? resolveTrack,
    Future<List<Track>> Function(Track)? buildQueue,
  })  : _player = player ?? _createPlayer(),
        _resolver = resolver ?? AudioResolverService.instance,
        _tiktokSounds = tikTokSounds ?? TikTokSoundService(),
        _tikTokCache = tikTokCache ?? TikTokAudioCache(),
        _resolveOverride = resolveTrack,
        _queueOverride = buildQueue {
    WidgetsBinding.instance.addObserver(this);
    _ready = _initialize();
  }

  @visibleForTesting
  PlayerController.forTesting({
    AudioPlayer? player,
    AudioResolverService? resolver,
    TikTokAudioCache? tikTokCache,
    TikTokSoundService? tikTokSounds,
    Future<String> Function(Track)? resolveTrack,
    Future<List<Track>> Function(Track)? buildQueue,
  }) : this._internal(
            player: player,
            resolver: resolver,
            tikTokCache: tikTokCache,
            tikTokSounds: tikTokSounds,
            resolveTrack: resolveTrack,
            buildQueue: buildQueue);

  final PlayerSessionStore _sessionStore = PlayerSessionStore();
  late final Future<void> _ready;
  Timer? _checkpointTimer;
  Timer? _endWatchTimer;
  final PlaybackEndGuard _endGuard = PlaybackEndGuard();
  bool _needsSourceRestore = false;
  bool _disposed = false;
  bool _isEditingNativeQueue = false;
  DateTime? _invalidTimelineSince;
  Duration? _lastProgressPosition;
  DateTime? _stalledSince;
  bool _playRequested = false;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  Duration? _sleepDuration;
  bool _sleepAfterTrack = false;
  int? _sleepPauseGeneration;
  Future<void>? _sleepStopWork;

  bool get hasSleepTimer => _sleepDeadline != null || _sleepAfterTrack;
  bool get sleepAfterTrack => _sleepAfterTrack;
  DateTime? get sleepTimerDeadline => _sleepDeadline;
  Duration? get sleepTimerDuration => _sleepDuration;
  Duration? get sleepTimerRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  LoopMode get _effectiveLoopMode =>
      !_sleepAfterTrack && _repeatMode == RepeatMode.one
          ? LoopMode.one
          : LoopMode.off;

  /// Wall-clock time: pausing playback does not extend the chosen deadline.
  Future<void> setSleepTimer(Duration duration) async {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration');
    }
    await _ready;
    if (_disposed) return;
    await _sleepStopWork;
    _sleepTimer?.cancel();
    _sleepAfterTrack = false;
    _sleepDuration = duration;
    _sleepDeadline = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () => unawaited(checkSleepTimer()));
    notifyListeners();
    await _player.setLoopMode(_effectiveLoopMode);
    unawaited(_warmNextTrack());
  }

  Future<void> setSleepAfterTrack() async {
    await _ready;
    if (_disposed || _currentTrack == null) return;
    await _sleepStopWork;
    _sleepTimer?.cancel();
    _sleepDeadline = null;
    _sleepDuration = null;
    _sleepAfterTrack = true;
    notifyListeners();
    // Keep the user's repeat setting, but stop the native queue at this item.
    await _player.setLoopMode(LoopMode.off);
    await _warmNextTrack();
  }

  Future<void> cancelSleepTimer() async {
    await _ready;
    if (_disposed) return;
    _clearSleepTimer();
    notifyListeners();
    await _player.setLoopMode(_effectiveLoopMode);
    unawaited(_warmNextTrack());
  }

  void _clearSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    _sleepDuration = null;
    _sleepAfterTrack = false;
  }

  @visibleForTesting
  Future<void> checkSleepTimer({DateTime? now}) async {
    final deadline = _sleepDeadline;
    if (_disposed ||
        deadline == null ||
        (now ?? DateTime.now()).isBefore(deadline)) return;
    await _finishSleep();
  }

  Future<void> _finishSleep({bool rewind = false}) => _sleepStopWork ??=
      _pauseForSleep(rewind: rewind).whenComplete(() => _sleepStopWork = null);

  Future<void> _pauseForSleep({required bool rewind}) async {
    final generation = _playlistGeneration;
    _playRequested = false;
    _sleepPauseGeneration = generation;
    _clearSleepTimer();
    _endGuard.reset();
    notifyListeners();
    try {
      await _player.pause();
      if (_disposed || generation != _playlistGeneration) return;
      if (rewind) {
        await _player.seek(Duration.zero);
        _position = Duration.zero;
      }
      await _player.setLoopMode(_effectiveLoopMode);
      await _saveSession();
      unawaited(_warmNextTrack());
    } catch (error, stackTrace) {
      developer.log('Could not apply sleep timer',
          name: 'PlayerController', error: error, stackTrace: stackTrace);
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> ensureInitialized() => _ready;

  Future<void> _initialize() async {
    var saved = await _sessionStore.load();
    // Upgrade existing installations using their already-saved last listen.
    if (saved == null) {
      final history = ListeningHistoryController.instance;
      await history.ensureLoaded();
      if (history.items.isNotEmpty) {
        saved = PlayerSession(
            queue: [history.items.first],
            currentIndex: 0,
            position: Duration.zero);
      }
    }
    if (_disposed) return;
    if (saved != null) {
      _queue = List.of(saved.queue);
      _currentIndex = saved.currentIndex;
      _currentTrack = saved.currentTrack;
      _position = saved.position;
      _duration = saved.currentTrack.duration ?? Duration.zero;
      _repeatMode = RepeatMode.values[saved.repeatMode];
      _isShuffle = saved.isShuffle;
      _shuffledIndices = List.of(saved.shuffledIndices);
      _manualQueueIds.addAll(saved.manualQueueIds);
      _radioHistory.addAll(_queue.map(_trackIdentity));
      _needsSourceRestore = true;
      notifyListeners();
    }
    await _initAudio();
    if (_disposed) return;
    _checkpointTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveSession());
    });
    _endWatchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(checkSleepTimer());
      if (hasSleepTimer && _shouldRefreshUi) notifyListeners();
      checkPlaybackEnd();
    });
  }

  /// Also runs in the background: UI position updates are not required for
  /// completion recovery. Use the stream's native duration, not catalog text.
  @visibleForTesting
  void checkPlaybackEnd({DateTime? now}) {
    _syncNativePlayback();
    if (_sleepStopWork != null ||
        _sleepPauseGeneration == _playlistGeneration) {
      return;
    }
    if (_disposed ||
        _isEditingNativeQueue ||
        _currentTrack == null ||
        _needsSourceRestore ||
        _isLoadingTrack ||
        _isSeeking ||
        _isHandlingCompletion ||
        _hasTerminalCompletion) {
      _lastProgressPosition = null;
      _stalledSince = null;
      return;
    }
    final checkedAt = now ?? DateTime.now();
    final nativeDuration = _player.duration;
    if (_playRequested &&
        _player.playing &&
        (nativeDuration == null || nativeDuration <= Duration.zero)) {
      _invalidTimelineSince ??= checkedAt;
      if (checkedAt.difference(_invalidTimelineSince!) >=
          const Duration(seconds: 12)) {
        _invalidTimelineSince = null;
        final track = _currentTrack!;
        // A ready/buffering asset with no timeline has already failed the
        // audio-only path. Move directly to compatibility instead of repeating it.
        if ((_fallbackAttempts[track.id] ?? 0) == 0) {
          _fallbackAttempts[track.id] = 1;
        }
        unawaited(_recoverPlayback(
            track,
            _playlistGeneration,
            StateError('Native audio timeline unavailable'),
            StackTrace.current));
        return;
      }
    } else {
      _invalidTimelineSince = null;
    }
    final effectiveDuration = nativeDuration != null &&
            nativeDuration > Duration.zero &&
            _duration > Duration.zero &&
            _duration < nativeDuration
        ? _duration
        : nativeDuration;
    final nativePosition = _player.position;
    if (_playRequested &&
        _player.playing &&
        effectiveDuration != null &&
        effectiveDuration > Duration.zero &&
        (_player.processingState == ProcessingState.ready ||
            _player.processingState == ProcessingState.buffering)) {
      if (_lastProgressPosition == null ||
          (nativePosition - _lastProgressPosition!).abs() >
              const Duration(milliseconds: 250)) {
        _lastProgressPosition = nativePosition;
        _stalledSince = checkedAt;
      } else if (_stalledSince != null &&
          checkedAt.difference(_stalledSince!) >= const Duration(seconds: 20) &&
          nativePosition < effectiveDuration - const Duration(milliseconds: 300)) {
        _stalledSince = null;
        unawaited(_recoverPlayback(_currentTrack!, _playlistGeneration,
            StateError('Playback stopped progressing'), StackTrace.current));
        return;
      }
    } else {
      _lastProgressPosition = null;
      _stalledSince = null;
    }
    if (_player.processingState == ProcessingState.completed) {
      unawaited(_handleTrackCompleted());
      return;
    }
    if ((_player.currentIndex ?? 0) >= 8 &&
        _player.processingState == ProcessingState.ready &&
        _player.position >= const Duration(seconds: 3)) {
      unawaited(_warmNextTrack());
    }
    // Reuse effectiveDuration computed above
    if (_endGuard.shouldAdvance(
      generation: _playlistGeneration,
      playing: _player.playing,
      busy: false,
      state: _player.processingState,
      position: _player.position,
      duration: effectiveDuration,
      bufferedPosition: _player.bufferedPosition,
      now: now ?? DateTime.now(),
    )) {
      developer.log(
          'Recovering missing stream completion for ${_currentTrack!.id}',
          name: 'PlayerController');
      unawaited(_handleTrackCompleted());
    }
  }

  Duration get playbackPosition =>
      _needsSourceRestore || _isLoadingTrack || _isSeeking
          ? _position
          : _clampSeekTarget(_player.position);

  Future<void> _saveSession() {
    if (_currentTrack == null || _currentIndex < 0 || _queue.isEmpty) {
      return Future<void>.value();
    }
    return _sessionStore.save(PlayerSession(
      queue: List.of(_queue),
      currentIndex: _currentIndex,
      position: playbackPosition,
      repeatMode: _repeatMode.index,
      isShuffle: _isShuffle,
      shuffledIndices: List.of(_shuffledIndices),
      manualQueueIds: _manualQueueIds.toList(),
    ));
  }

  static AudioPlayer _createPlayer() => AudioPlayer(
        audioLoadConfiguration: const AudioLoadConfiguration(
          darwinLoadControl: DarwinLoadControl(
            automaticallyWaitsToMinimizeStalling: true,
            preferredForwardBufferDuration: Duration(seconds: 12),
          ),
        ),
      );
  final AudioPlayer _player;
  final Future<String> Function(Track)? _resolveOverride;
  final Future<List<Track>> Function(Track)? _queueOverride;
  int _previousTrackGeneration = -1;
  Track? _previousTrackBeforeAdvance;
  Duration _previousPositionBeforeAdvance = Duration.zero;
  final AudioResolverService _resolver;
  final TikTokSoundService _tiktokSounds;
  final TikTokAudioCache _tikTokCache;
  int? _recoveringGeneration;
  final MusicService _musicService = MusicService.instance;
  final Map<String, Future<String>> _streamUrlFutures = {};
  final Map<String, DateTime> _prefetchedAt = {};
  final Map<String, int> _fallbackAttempts = {};
  ConcatenatingAudioSource? _nativePlaylist;
  StreamSubscription? _sequenceSub;
  Future<void> _preloadWork = Future<void>.value();
  int _preloadRevision = 0;
  String? _preloadFallbackId;
  final Set<String> _radioHistory = {};
  final Set<String> _manualQueueIds = {};
  int _playlistGeneration = 0;
  int _lastHistoryGeneration = -1;
  int _radioSession = 0;
  Future<bool>? _queueExtensionFuture;
  Future<void>? _nextOperation;
  String? _lastExpansionSeedId;

  List<Track> _queue = [];
  int _currentIndex = -1;
  Track? _currentTrack;

  String? _playbackError;
  bool _isLoadingTrack = false;
  bool _isBuffering = false;
  bool _isHandlingCompletion = false;
  bool _hasTerminalCompletion = false;
  bool _isSeeking = false;
  RepeatMode _repeatMode = RepeatMode.off;
  bool _isShuffle = false;
  List<int> _shuffledIndices = [];

  Track? _originalTrackBeforeKaraoke;
  bool _isSwitchingKaraoke = false;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _bufferedPositionSub;
  StreamSubscription? _playbackEventSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;

  // Getters
  AudioPlayer get player => _player;
  List<Track> get queue => _queue;
  int get currentIndex => _currentIndex;
  Track? get currentTrack => _currentTrack;
  String? get playbackError => _playbackError;
  bool get isPlaying => _player.playing;
  bool get isLoadingTrack => _isLoadingTrack;
  bool get isBuffering => _isBuffering;
  bool get isExtendingQueue => _queueExtensionFuture != null;
  bool get isTransitioningBetweenTracks =>
      _isHandlingCompletion || _isLoadingTrack;
  bool get hasTerminalCompletion => _hasTerminalCompletion;
  bool get shouldKeepMediaSessionAlive =>
      _currentTrack != null &&
      (isTransitioningBetweenTracks ||
          isExtendingQueue ||
          _nextQueuedTrack() != null ||
          _repeatMode != RepeatMode.off);
  bool get isBusy =>
      _isLoadingTrack || _isSeeking || (_isBuffering && !_player.playing);
  RepeatMode get repeatMode => _repeatMode;
  bool get isShuffle => _isShuffle;
  bool get isSwitchingKaraoke => _isSwitchingKaraoke;
  bool get isCurrentKaraoke => _currentTrack?.isKaraoke ?? false;

  Duration get position => _position;
  Duration get duration => _duration;
  Duration get bufferedPosition => _bufferedPosition;
  Map<String, Object?> get playbackDiagnosticState => {
        'trackId': _currentTrack?.id,
        'queueIndex': _currentIndex,
        'nativeIndex': _player.currentIndex,
        'nativePositionMs': _player.position.inMilliseconds,
        'nativeDurationMs': _player.duration?.inMilliseconds,
        'processingState': _player.processingState.name,
        'positionMs': _position.inMilliseconds,
        'durationMs': _duration.inMilliseconds,
        'playing': _player.playing,
        'loading': _isLoadingTrack,
        'seeking': _isSeeking,
        'editingQueue': _isEditingNativeQueue,
        'needsRestore': _needsSourceRestore,
        'generation': _playlistGeneration,
      };
  bool isManualQueued(Track track) => _manualQueueIds.contains(track.id);

  void replaceQueueForCurrent(Track track, List<Track> smartQueue) {
    if (_currentTrack?.id != track.id || smartQueue.isEmpty) return;
    final manualTracks = _queue
        .where(
          (item) => item.id != track.id && _manualQueueIds.contains(item.id),
        )
        .toList();
    final uniqueIds = <String>{track.id};
    final uniqueSongs = <String>{_trackIdentity(track)};
    final updatedQueue = <Track>[track];
    for (final item in [...manualTracks, ...smartQueue]) {
      if (uniqueIds.add(item.id) && uniqueSongs.add(_trackIdentity(item))) {
        updatedQueue.add(item);
      }
    }
    _queue = updatedQueue;
    _currentIndex = _queue.indexWhere((item) => item.id == track.id);
    _radioHistory.addAll(_queue.map(_trackIdentity));
    unawaited(_saveSession());
    _retainQueuePrefetches();
    unawaited(_warmNextTrack());
    unawaited(_ensureEndlessQueue());
    notifyListeners();
  }

  String _trackIdentity(Track track) {
    if (track.isTikTokSound) return track.id;
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(
          RegExp(
            r'\b(?:official|music video|video clip|audio|lyrics?|lirik|visualizer|'
            r'live|cover|karaoke|instrumental|remix|remastered|slowed|reverb|'
            r'sped up|nightcore|performance|session|hd|4k)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final artist = normalize(track.displayArtist)
        .replaceAll(RegExp(r'\b(?:topic|vevo)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    var title = normalize(track.displayTitle);
    if (artist.isNotEmpty) {
      title = title.replaceAll(artist, ' ');
    }
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Title-first identity intentionally treats alternate uploads of the same
    // recording as one song, even when their uploader/channel names differ.
    return title.isEmpty ? '$artist|${normalize(track.title)}' : title;
  }

  Future<bool> _ensureEndlessQueue({bool force = false}) {
    if (!force && _needsSourceRestore) return Future.value(false);
    final activeExtension = _queueExtensionFuture;
    if (activeExtension != null) return activeExtension;
    if (_queue.isEmpty) return Future.value(false);

    final remaining = _queue.length - _currentIndex - 1;
    if (!force && remaining > 5) return Future.value(false);

    final seed = _queue.last;
    if (seed.isTikTokSound || seed.isKaraoke) return Future.value(false);
    if (!force && _lastExpansionSeedId == seed.id) {
      return Future.value(false);
    }

    final session = _radioSession;
    late final Future<bool> operation;
    operation = _extendRadioQueue(seed, session).whenComplete(() {
      if (identical(_queueExtensionFuture, operation)) {
        _queueExtensionFuture = null;
        notifyListeners();
      }
    });
    _queueExtensionFuture = operation;
    notifyListeners();
    return operation;
  }

  Future<bool> _extendRadioQueue(Track seed, int session) async {
    try {
      final suggestions = await (_queueOverride?.call(seed) ??
          _musicService.buildSmartQueue(seed, limit: 24));
      if (session != _radioSession || _queue.isEmpty) return false;

      var added = 0;
      final queueIds = _queue.map((item) => item.id).toSet();
      for (final suggestion in suggestions) {
        final identity = _trackIdentity(suggestion);
        if (suggestion.id == seed.id ||
            !queueIds.add(suggestion.id) ||
            !_radioHistory.add(identity)) {
          continue;
        }
        _queue.add(suggestion);
        added++;
      }

      _lastExpansionSeedId = seed.id;
      if (added == 0) return false;
      if (_isShuffle) {
        _shuffledIndices = List.generate(_queue.length, (index) => index)
          ..shuffle();
      }
      _retainQueuePrefetches();
      unawaited(_saveSession());
      unawaited(_warmNextTrack());
      notifyListeners();
      developer.log(
        'Extended radio queue with $added tracks from ${seed.displayTitle}',
        name: 'PlayerController',
      );
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Could not extend radio queue from ${seed.displayTitle}',
        error: error,
        stackTrace: stackTrace,
        name: 'PlayerController',
      );
      return false;
    }
  }

  Future<String> _resolveTrackUrl(Track track) {
    if (OfflineStorageService.instance.isTrackDownloaded(track.id)) {
      final localPath =
          OfflineStorageService.instance.getLocalAudioPathSync(track.id);
      if (localPath != null && File(localPath).existsSync()) {
        return Future.value(Uri.file(localPath).toString());
      }
    }

    final fetched = _prefetchedAt[track.id];
    if (fetched == null ||
        DateTime.now().difference(fetched) > const Duration(minutes: 2)) {
      _streamUrlFutures.remove(track.id);
      _prefetchedAt[track.id] = DateTime.now();
    }
    return _streamUrlFutures.putIfAbsent(
      track.id,
      () => (_resolveOverride?.call(track) ??
              (track.provider == 'direct' && track.sourceUrl != null && track.sourceUrl!.isNotEmpty
                  ? Future.value(track.sourceUrl!)
                  : (track.isTikTokSound
                      ? _tikTokCache.playbackUrl(track, _tiktokSounds)
                      : _resolver.resolveStreamUrl(track.cleanVideoId))))
          .catchError(
        (Object error) {
          _streamUrlFutures.remove(track.id);
          throw error;
        },
      ),
    );
  }

  Future<bool> toggleKaraokeMode() async {
    final current = _currentTrack;
    if (current == null || _isLoadingTrack || _isSwitchingKaraoke) return false;

    if (current.isKaraoke) {
      final original = _originalTrackBeforeKaraoke;
      if (original != null) {
        final currentPos = _player.position;
        _originalTrackBeforeKaraoke = null;
        await playTrack(original, initialPosition: currentPos);
        return true;
      }
      return false;
    } else {
      _isSwitchingKaraoke = true;
      notifyListeners();
      try {
        final match = await _musicService.findMatchingKaraokeTrack(current);
        if (match != null && _currentTrack?.id == current.id) {
          _originalTrackBeforeKaraoke = current;
          final currentPos = _player.position;
          await playTrack(match, initialPosition: currentPos);
          return true;
        } else {
          developer.log(
            'No matching karaoke track found for "${current.displayTitle}" by "${current.displayArtist}"',
            name: 'PlayerController',
          );
          return false;
        }
      } catch (e) {
        developer.log('Failed to switch to karaoke: $e',
            name: 'PlayerController');
        return false;
      } finally {
        _isSwitchingKaraoke = false;
        notifyListeners();
      }
    }
  }

  void _retainQueuePrefetches() {
    final keepIds = <String>{
      if (_currentTrack != null) _currentTrack!.id,
      if (_nextQueuedTrack() != null) _nextQueuedTrack()!.id,
    };
    _streamUrlFutures.removeWhere((id, _) => !keepIds.contains(id));
    _prefetchedAt.removeWhere((id, _) => !keepIds.contains(id));
    if (!keepIds.contains(_preloadFallbackId)) _preloadFallbackId = null;
  }

  Track? _nextQueuedTrack() {
    if (_queue.isEmpty || _currentIndex < 0) return null;

    if (_isShuffle && _shuffledIndices.isNotEmpty) {
      final shuffledPosition = _shuffledIndices.indexOf(_currentIndex);
      if (shuffledPosition >= 0 &&
          shuffledPosition + 1 < _shuffledIndices.length) {
        return _queue[_shuffledIndices[shuffledPosition + 1]];
      }
    }

    if (_currentIndex + 1 < _queue.length) {
      return _queue[_currentIndex + 1];
    }
    if (_repeatMode == RepeatMode.all && _queue.isNotEmpty) {
      return _queue.first;
    }
    return null;
  }

  Future<void> _warmNextTrack() {
    final revision = ++_preloadRevision;
    final generation = _playlistGeneration;
    final playlist = _nativePlaylist;
    // Serialize native mutations; a slow lookup from an older queue must never
    // append a removed track or replace the next manual pick.
    _preloadWork = _preloadWork.then((_) async {
      bool isCurrent() =>
          !_disposed &&
          !_needsSourceRestore &&
          generation == _playlistGeneration &&
          revision == _preloadRevision &&
          playlist != null &&
          identical(playlist, _nativePlaylist);
      if (!isCurrent()) return;
      final nativeIndex = _player.currentIndex ?? 0;
      final candidate = _nextQueuedTrack();
      final nextTrack = _sleepAfterTrack ||
              _repeatMode == RepeatMode.one ||
              candidate?.id == _currentTrack?.id
          ? null
          : candidate;
      final children = playlist!.children;
      final nextId = nativeIndex + 1 < children.length
          ? ((children[nativeIndex + 1] as IndexedAudioSource).tag as MediaItem)
              .id
          : null;
      if (nextId != nextTrack?.id && nativeIndex + 1 < children.length) {
        await playlist.removeRange(nativeIndex + 1, children.length);
      }
      if (!isCurrent()) return;
      // Removing several past items at once mis-adjusts AVQueuePlayer's
      // current index in just_audio's Darwin implementation. Remove one at a
      // time, and don't interpret intermediate reindex broadcasts as auto-next.
      if (nativeIndex >= 8 &&
          !_isSeeking &&
          _player.processingState == ProcessingState.ready &&
          _player.position >= const Duration(seconds: 3)) {
        _isEditingNativeQueue = true;
        try {
          await playlist.removeAt(0);
          final expectedIndex = nativeIndex - 1;
          if (_player.currentIndex != expectedIndex) {
            await _player.currentIndexStream
                .firstWhere((index) => index == expectedIndex)
                .timeout(const Duration(seconds: 2));
          }
        } finally {
          _isEditingNativeQueue = false;
          scheduleMicrotask(_syncNativePlayback);
        }
      }
      if (!isCurrent() || nextTrack == null || nextId == nextTrack.id) return;
      final url = await _resolveTrackUrl(nextTrack);
      if (!isCurrent() || _nextQueuedTrack()?.id != nextTrack.id) return;
      final source = await _audioSource(nextTrack, url);
      if (!isCurrent() || _nextQueuedTrack()?.id != nextTrack.id) return;
      await playlist.add(source);
    }).catchError((Object error, StackTrace stackTrace) {
      developer.log('Could not prepare next native queue item',
          error: error, stackTrace: stackTrace, name: 'PlayerController');
    });
    return _preloadWork;
  }

  void _discardFailedPreload(
      ConcatenatingAudioSource playlist, int index, AudioSource source) {
    final revision = ++_preloadRevision;
    final generation = _playlistGeneration;
    final item = source is IndexedAudioSource ? source.tag : null;
    final candidate = _nextQueuedTrack();
    final retry = candidate != null &&
        item is MediaItem &&
        candidate.id == item.id &&
        !candidate.isTikTokSound &&
        candidate.provider != 'direct' &&
        _preloadFallbackId != candidate.id;
    if (retry) _preloadFallbackId = candidate.id;
    if (item is MediaItem) {
      _streamUrlFutures.remove(item.id);
      _prefetchedAt.remove(item.id);
      final queueIndex = _queue.indexWhere((track) => track.id == item.id);
      if (queueIndex >= 0 && !_queue[queueIndex].isTikTokSound) {
        _resolver.invalidate(_queue[queueIndex].cleanVideoId);
      }
    }
    _preloadWork = _preloadWork.then((_) async {
      if (_disposed ||
          !identical(playlist, _nativePlaylist) ||
          index <= (_player.currentIndex ?? 0) ||
          index >= playlist.children.length ||
          !identical(playlist.children[index], source)) return;
      await playlist.removeRange(index, playlist.children.length);
      if (!retry) return;
      final url = await _resolver.resolveStreamUrl(candidate.cleanVideoId,
          compatibilityFallback: true, forceRefresh: true);
      final replacement = await _audioSource(candidate, url);
      if (_disposed ||
          generation != _playlistGeneration ||
          revision != _preloadRevision ||
          _needsSourceRestore ||
          !identical(playlist, _nativePlaylist) ||
          _nextQueuedTrack()?.id != candidate.id) return;
      _streamUrlFutures[candidate.id] = Future.value(url);
      _prefetchedAt[candidate.id] = DateTime.now();
      await playlist.add(replacement);
    }).catchError((Object error, StackTrace stackTrace) {
      developer.log('Could not recover failed preload',
          name: 'PlayerController', error: error, stackTrace: stackTrace);
    });
  }

  void _adoptNativeTrack(SequenceState? state) {
    if (_disposed ||
        _isEditingNativeQueue ||
        _isLoadingTrack ||
        _recoveringGeneration == _playlistGeneration ||
        !identical(_player.audioSource, _nativePlaylist)) return;
    final playlist = _nativePlaylist;
    final index = _player.currentIndex;
    if (playlist == null ||
        index == null ||
        index < 0 ||
        index >= playlist.children.length) return;
    // Read the canonical native index, not a possibly lagging sequence snapshot.
    final source = playlist.children[index];
    final item = source is IndexedAudioSource ? source.tag : null;
    if (item is! MediaItem || item.id == _currentTrack?.id) return;
    if (_currentTrack != null &&
        _duration >= const Duration(seconds: 25) &&
        _position >= const Duration(seconds: 5) &&
        _position < _duration - const Duration(seconds: 5)) {
      _needsSourceRestore = true;
      unawaited(_player.pause());
      unawaited(_recoverPlayback(
          _currentTrack!,
          _playlistGeneration,
          StateError('Native player advanced prematurely at $_position / $_duration'),
          StackTrace.current));
      return;
    }
    final queueIndex = _queue.indexWhere((track) => track.id == item.id);
    if (_sleepAfterTrack && queueIndex < 0) {
      unawaited(_finishSleep());
      return;
    }
    if ((_repeatMode == RepeatMode.one && !_sleepAfterTrack) ||
        queueIndex < 0) {
      final expected = _nextQueuedTrack();
      // The logical queue changed at the same instant the native player moved.
      // Reconcile through the normal load path rather than playing a removed item.
      if (_repeatMode == RepeatMode.one && _currentTrack != null) {
        unawaited(playTrack(_currentTrack!));
      } else if (expected != null) {
        unawaited(playTrack(expected));
      } else {
        _needsSourceRestore = true;
        _hasTerminalCompletion = true;
        unawaited(_player.pause());
        notifyListeners();
      }
      return;
    }
    final stopForSleep = _sleepAfterTrack;
    final expected = _queue[queueIndex];
    final oldTrack = _currentTrack;
    final oldPosition = _position;
    _playlistGeneration++;
    _invalidTimelineSince = null;
    _previousTrackGeneration = _playlistGeneration;
    _previousTrackBeforeAdvance = oldTrack;
    _previousPositionBeforeAdvance = oldPosition;
    _endGuard.reset();
    _lastProgressPosition = null;
    _stalledSince = null;
    _hasTerminalCompletion = false;
    _needsSourceRestore = false;
    _isLoadingTrack = false;
    _recoveringGeneration = null;
    _currentTrack = expected;
    _currentIndex = queueIndex;
    _manualQueueIds.remove(expected.id);
    _fallbackAttempts.remove(expected.id);
    unawaited(_repairNativeTimeline(_playlistGeneration));
    _position = Duration.zero;
    _duration = expected.duration ?? _player.duration ?? Duration.zero;
    _bufferedPosition = Duration.zero;
    _playbackError = null;
    _retainQueuePrefetches();
    _recordCurrentTrackIfPlaying();
    unawaited(_saveSession());
    if (stopForSleep) {
      // A boundary may race the removal of an already-buffered successor.
      // Adopt its metadata first, then pause it instead of leaving stale UI.
      unawaited(_finishSleep(rewind: true));
    } else {
      unawaited(_warmNextTrack());
      unawaited(_ensureEndlessQueue());
    }
    notifyListeners();
  }

  void _syncNativePlayback() {
    if (_disposed || _isEditingNativeQueue || _isLoadingTrack || _isSeeking) {
      return;
    }
    if (_needsSourceRestore) {
      // A timed-out load can become playable later. Recover its metadata when
      // the installed native playlist proves it is already playing.
      if (_nativePlaylist == null ||
          !identical(_player.audioSource, _nativePlaylist) ||
          !_player.playing ||
          _player.processingState != ProcessingState.ready) return;
      _needsSourceRestore = false;
      _playbackError = null;
    }
    _adoptNativeTrack(null);
    if (_disposed ||
        _needsSourceRestore ||
        _isLoadingTrack ||
        _isSeeking ||
        !identical(_player.audioSource, _nativePlaylist)) return;
    final previousDuration = _duration;
    final metadataDuration = _currentTrack?.duration;
    final nativeDuration = _player.duration;
    if (nativeDuration != null && nativeDuration > Duration.zero) {
      // iOS AVPlayerItem calculates double the real duration on fragmented AAC/M4A streams.
      // If nativeDuration is roughly 2x metadataDuration, recover the accurate duration.
      if (metadataDuration != null &&
          metadataDuration > Duration.zero &&
          nativeDuration.inMilliseconds > metadataDuration.inMilliseconds * 1.75 &&
          nativeDuration.inMilliseconds < metadataDuration.inMilliseconds * 2.25) {
        final halvedNative =
            Duration(milliseconds: nativeDuration.inMilliseconds ~/ 2);
        final diff =
            (halvedNative.inMilliseconds - metadataDuration.inMilliseconds).abs();
        _duration = diff <= 3000 ? halvedNative : metadataDuration;
      } else {
        _duration = nativeDuration;
      }
    } else if (metadataDuration != null && metadataDuration > Duration.zero) {
      _duration = metadataDuration;
    }
    final position = _clampSeekTarget(_player.position);
    final buffered = _player.bufferedPosition;
    final changed = previousDuration != _duration ||
        position != _position ||
        buffered != _bufferedPosition;
    _position = position;
    _bufferedPosition = buffered;
    if (changed && _shouldRefreshUi) notifyListeners();
  }

  Future<void> _repairNativeTimeline(int generation) async {
    // AVQueuePlayer may announce the new index before the queued asset's
    // duration is available. A zero duration clamps Dart's position to zero
    // forever unless another native event refreshes the timeline.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_disposed ||
        generation != _playlistGeneration ||
        _needsSourceRestore ||
        _isLoadingTrack ||
        _isSeeking ||
        !_player.playing ||
        _player.processingState != ProcessingState.ready ||
        _player.duration != Duration.zero) return;
    try {
      await _player.seek(Duration.zero, index: _player.currentIndex);
    } catch (error, stackTrace) {
      final track = _currentTrack;
      if (track != null) {
        await _recoverPlayback(track, generation, error, stackTrace);
      }
    }
  }

  Future<void> _installSingleSource(
    Track track,
    String url,
    int generation, {
    Duration initialPosition = Duration.zero,
  }) async {
    if (generation != _playlistGeneration || _currentTrack?.id != track.id) {
      return;
    }

    // Completion leaves just_audio's playing flag true. Reset it before loading
    // the next item so play() sends a fresh native request instead of returning.
    await _player.pause();
    if (generation != _playlistGeneration || _disposed) return;

    final source = await _audioSource(track, url);

    if (generation != _playlistGeneration || _currentTrack?.id != track.id) {
      return;
    }
    final playlist = ConcatenatingAudioSource(
      useLazyPreparation: false,
      children: [source],
    );
    _nativePlaylist = playlist;
    _preloadRevision++;
    await _player
        .setAudioSource(
          playlist,
          initialPosition: initialPosition,
          preload: true,
        )
        .timeout(const Duration(seconds: 15));
    if (generation != _playlistGeneration) return;

    _needsSourceRestore = false;
    await _player.setLoopMode(
      _effectiveLoopMode,
    );

    unawaited(_warmNextTrack());
  }

  Future<void> _initAudio() async {
    try {
      // Configure audio session for background playback & lockscreen resilience
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await _player.setAutomaticallyWaitsToMinimizeStalling(true);
      if (_disposed) return;

      _playerStateSub = _player.playerStateStream.listen((state) {
        _syncNativePlayback();
        _isBuffering = state.processingState == ProcessingState.buffering ||
            state.processingState == ProcessingState.loading;

        _recordCurrentTrackIfPlaying();
        if (!_isLoadingTrack && !_needsSourceRestore) {
          unawaited(_saveSession());
        }

        if (state.processingState == ProcessingState.completed) {
          unawaited(_handleTrackCompleted());
        }
        notifyListeners();
      });

      // Consume native playback errors so AVPlayer failures do not become
      // unhandled asynchronous exceptions. Use the active song's generation,
      // including after a native transition, with a bounded recovery ladder.
      _playbackEventSub = _player.playbackEventStream.listen(
        (_) => scheduleMicrotask(_syncNativePlayback),
        onError: (Object error, StackTrace stackTrace) {
          if (error is PlayerInterruptedException ||
              (error is PlatformException && error.code == 'abort') ||
              _isLoadingTrack) return;
          final playlist = _nativePlaylist;
          final details = error is PlayerException
              ? error.details
              : error is PlatformException && error.details is Map
                  ? error.details as Map
                  : null;
          final failedIndex = details?['index'];
          if (failedIndex is int &&
              playlist != null &&
              identical(_player.audioSource, playlist)) {
            if (failedIndex < 0 || failedIndex >= playlist.children.length) {
              return;
            }
            final source = playlist.children[failedIndex];
            final item = source is IndexedAudioSource ? source.tag : null;
            // Preload failures must not restart a healthy active song.
            if (item is! MediaItem || item.id != _currentTrack?.id) {
              if (failedIndex > (_player.currentIndex ?? 0)) {
                _discardFailedPreload(playlist, failedIndex, source);
              } else if (failedIndex == _player.currentIndex) {
                _adoptNativeTrack(null);
                final track = _currentTrack;
                if (track != null) {
                  unawaited(_recoverPlayback(
                      track, _playlistGeneration, error, stackTrace));
                }
              } else if (item is MediaItem &&
                  _previousTrackGeneration == _playlistGeneration &&
                  _previousTrackBeforeAdvance?.id == item.id &&
                  _position < const Duration(seconds: 3)) {
                final prev = _previousTrackBeforeAdvance!;
                final prevPos = _previousPositionBeforeAdvance;
                final prevIndex = _queue.indexWhere((t) => t.id == prev.id);
                if (prevIndex >= 0) {
                  _currentTrack = prev;
                  _currentIndex = prevIndex;
                  _position = prevPos;
                  _duration = prev.duration ?? Duration.zero;
                  _needsSourceRestore = true;
                  unawaited(_recoverPlayback(
                      prev, _playlistGeneration, error, stackTrace));
                }
              }
              return;
            }
          } else {
            _adoptNativeTrack(null);
          }
          final track = _currentTrack;
          if (track != null) {
            unawaited(_recoverPlayback(
                track, _playlistGeneration, error, stackTrace));
          }
        },
      );

      _sequenceSub = _player.sequenceStateStream.listen(_adoptNativeTrack);
      _listenToPosition();

      _durationSub =
          _player.durationStream.listen((_) => _syncNativePlayback());
      _bufferedPositionSub =
          _player.bufferedPositionStream.listen((_) => _syncNativePlayback());
    } catch (e) {
      developer.log('Error initializing audio session: $e',
          name: 'PlayerController');
    }
  }

  void _listenToPosition() {
    _positionSub?.cancel();
    _positionSub = _player
        .createPositionStream(
      steps: 300,
      minPeriod: const Duration(seconds: 1),
      maxPeriod: const Duration(seconds: 1),
    )
        .listen((pos) {
      _syncNativePlayback();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(checkSleepTimer());
      _syncNativePlayback();
      _position = playbackPosition;
      _listenToPosition();
      notifyListeners();
    } else {
      unawaited(_saveSession());
    }
  }

  bool get _shouldRefreshUi {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Plays a given track, optionally replacing or populating the queue
  Future<void> playTrack(
    Track track, {
    List<Track>? newQueue,
    Duration initialPosition = Duration.zero,
  }) async {
    await _ready;
    await _sleepStopWork;
    if (_disposed) return;
    _sleepPauseGeneration = null;
    _playRequested = true;
    final generation = ++_playlistGeneration;
    _invalidTimelineSince = null;
    _lastProgressPosition = null;
    _stalledSince = null;
    _endGuard.reset();
    _hasTerminalCompletion = false;
    final shouldBootstrapSmartQueue = newQueue != null && newQueue.length == 1;
    if (newQueue != null && newQueue.isNotEmpty) {
      _manualQueueIds.clear();
      _radioSession++;
      _queueExtensionFuture = null;
      _radioHistory
        ..clear()
        ..addAll(newQueue.map(_trackIdentity));
      _lastExpansionSeedId = null;
      _queue = List.from(newQueue);
      _currentIndex = _queue.indexWhere((t) => t.id == track.id);
      if (_currentIndex == -1) {
        _queue.insert(0, track);
        _currentIndex = 0;
      }
      _radioHistory.add(_trackIdentity(track));
    } else {
      if (!_queue.any((t) => t.id == track.id)) {
        _queue.add(track);
      }
      _currentIndex = _queue.indexWhere((t) => t.id == track.id);
      _radioHistory.add(_trackIdentity(track));
    }

    _retainQueuePrefetches();

    _currentTrack = track;
    if (track.isKaraoke) {
      unawaited(LyricsService.instance
          .getLyrics(track)
          .then<void>((_) {}, onError: (Object _) {}));
    }
    _playbackError = null;
    _manualQueueIds.remove(track.id);
    _fallbackAttempts.remove(track.id);
    _duration = track.duration ?? Duration.zero;
    _position = _clampSeekTarget(initialPosition);
    final startPosition = _position;
    _needsSourceRestore = true;
    _isLoadingTrack = true;
    unawaited(_saveSession());
    notifyListeners();
    if (shouldBootstrapSmartQueue) {
      unawaited(_ensureEndlessQueue(force: true));
    }

    try {
      developer.log('Resolving audio for track: ${track.title} (${track.id})',
          name: 'PlayerController');
      final streamUrl = await _resolveTrackUrl(track);

      await _installSingleSource(track, streamUrl, generation,
          initialPosition: startPosition);
      if (generation != _playlistGeneration) return;
      unawaited(_ensureEndlessQueue(force: _queue.length <= 1));
      unawaited(_startPlayback(track, allowFallback: true));
    } catch (e, stack) {
      if (generation != _playlistGeneration) return;
      developer.log('Failed to play track ${track.title}: $e',
          error: e, stackTrace: stack, name: 'PlayerController');
      try {
        await _prepareFallback(track, generation,
            initialPosition: startPosition);
        if (_disposed || generation != _playlistGeneration) return;
        unawaited(_startPlayback(track, allowFallback: true));
      } catch (fallbackError, fallbackStack) {
        if (generation != _playlistGeneration) return;
        _playbackError = 'Audio belum bisa dimuat. Ketuk Play untuk coba lagi.';
        developer.log(
          'Fallback failed for ${track.title}: $fallbackError',
          error: fallbackError,
          stackTrace: fallbackStack,
          name: 'PlayerController',
        );
      }
    } finally {
      if (generation == _playlistGeneration && !_disposed) {
        _isLoadingTrack = false;
        notifyListeners();
      }
    }
  }

  Future<AudioSource> _audioSource(Track track, String url) async {
    final mediaItem = MediaItem(
      id: track.id,
      album: track.album ?? 'Cloudio',
      title: track.displayTitle,
      artist: track.displayArtist,
      artUri: track.artworkUrl != null ? Uri.tryParse(track.artworkUrl!) : null,
      duration: track.duration,
    );
    final uri = Uri.parse(url);
    final source = AudioSource.uri(
      uri,
      tag: mediaItem,
      headers: track.isTikTokSound && uri.scheme != 'file'
          ? TikTokSoundService.playbackHeaders
          : null,
    );
    final darwin = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final end =
        darwin ? await AudioTimeline.read(uri, mediaId: track.id) : null;
    return end == null
        ? source
        : ClippingAudioSource(child: source, end: end, tag: mediaItem);
  }

  void _recordCurrentTrackIfPlaying() {
    final track = _currentTrack;
    if (track == null ||
        _isLoadingTrack ||
        !_player.playing ||
        _player.processingState != ProcessingState.ready ||
        (_player.sequenceState?.currentSource?.tag as MediaItem?)?.id !=
            track.id ||
        _lastHistoryGeneration == _playlistGeneration) {
      return;
    }
    _lastHistoryGeneration = _playlistGeneration;
    unawaited(ListeningHistoryController.instance.record(track));
  }

  Future<void> _prepareFallback(
    Track track,
    int generation, {
    Duration initialPosition = Duration.zero,
  }) async {
    if (_currentTrack?.id != track.id || generation != _playlistGeneration) {
      return;
    }
    _isLoadingTrack = true;
    notifyListeners();
    while ((_fallbackAttempts[track.id] ?? 0) < 3) {
      final attempt = (_fallbackAttempts[track.id] ?? 0) + 1;
      _fallbackAttempts[track.id] = attempt;
      _streamUrlFutures.remove(track.id);
      if (!track.isTikTokSound) _resolver.invalidate(track.cleanVideoId);
      try {
        final url = track.provider == 'direct'
            ? await _resolveTrackUrl(track)
            : track.isTikTokSound
                ? await _tikTokCache.playbackUrl(track, _tiktokSounds,
                    attempt: attempt)
                : await _resolver.resolveStreamUrl(
                    track.cleanVideoId,
                    forceRefresh: true,
                    compatibilityFallback: attempt == 2,
                    gatewayOnly: attempt == 3,
                  );
        if (_disposed || generation != _playlistGeneration) return;
        await _installSingleSource(track, url, generation,
            initialPosition: initialPosition);
        return;
      } catch (_) {
        if (_disposed || generation != _playlistGeneration) return;
        if (attempt == 3) rethrow;
      }
    }
    throw StateError('Playback recovery exhausted');
  }

  Future<void> _startPlayback(
    Track track, {
    required bool allowFallback,
  }) async {
    final generation = _playlistGeneration;
    if (_disposed ||
        _currentTrack?.id != track.id ||
        !_playRequested ||
        _sleepPauseGeneration == generation) return;
    try {
      _playbackError = null;
      _isLoadingTrack = false;
      notifyListeners();

      final playback = _player.play();
      _recordCurrentTrackIfPlaying();
      await playback;
    } catch (error, stackTrace) {
      if (allowFallback) {
        await _recoverPlayback(track, generation, error, stackTrace);
      }
    }
  }

  Future<void> _recoverPlayback(
      Track track, int generation, Object error, StackTrace stackTrace) async {
    if (_disposed ||
        generation != _playlistGeneration ||
        _currentTrack?.id != track.id ||
        _recoveringGeneration == generation) return;
    _recoveringGeneration = generation;
    final resumePosition = playbackPosition;
    _position = resumePosition;
    _lastProgressPosition = null;
    _stalledSince = null;
    _needsSourceRestore = true;
    _playbackError = null;
    try {
      await _prepareFallback(track, generation,
          initialPosition: resumePosition);
      if (_disposed || generation != _playlistGeneration) return;
      _playbackError = null;
      _isLoadingTrack = false;
      // Release the recovery guard before play() can fail on the next strategy.
      _recoveringGeneration = null;
      unawaited(_startPlayback(track, allowFallback: true));
    } catch (fallbackError, fallbackStack) {
      if (_disposed || generation != _playlistGeneration) return;
      _needsSourceRestore = true;
      _playRequested = false;
      _playbackError = 'Audio belum bisa diputar. Ketuk Play untuk coba lagi.';
      developer.log('Playback recovery exhausted for ${track.id}',
          error: fallbackError,
          stackTrace: fallbackStack,
          name: 'PlayerController');
      try {
        await _player.pause();
      } catch (pauseError, pauseStack) {
        developer.log('Could not pause failed playback',
            name: 'PlayerController', error: pauseError, stackTrace: pauseStack);
      }
    } finally {
      if (_recoveringGeneration == generation) _recoveringGeneration = null;
      if (!_disposed && generation == _playlistGeneration) {
        _isLoadingTrack = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing || (_playRequested && _isLoadingTrack)) {
      await pause();
    } else {
      await resume();
    }
    notifyListeners();
  }

  Future<void> resume() async {
    await _ready;
    await _sleepStopWork;
    if (_disposed) return;
    _sleepPauseGeneration = null;
    _playRequested = true;
    if (_isLoadingTrack) return;
    if (_currentTrack != null) {
      if (_needsSourceRestore) {
        await playTrack(_currentTrack!, initialPosition: _position);
      } else {
        unawaited(_startPlayback(_currentTrack!, allowFallback: true));
      }
    } else if (_queue.isNotEmpty) {
      await playTrack(_queue.first);
    }
  }

  Future<void> pause() async {
    _playRequested = false;
    _lastProgressPosition = null;
    _stalledSince = null;
    await _ready;
    _endGuard.reset();
    await _player.pause();
    await _saveSession();
  }

  void previewSeek(Duration target) {
    _position = _clampSeekTarget(target);
    notifyListeners();
  }

  Future<void> seek(Duration target) async {
    await _ready;
    _endGuard.reset();
    _lastProgressPosition = null;
    _stalledSince = null;
    final safeTarget = _clampSeekTarget(target);
    _position = safeTarget;
    _isSeeking = true;
    notifyListeners();
    try {
      if (!_needsSourceRestore) await _player.seek(safeTarget);
    } catch (error, stackTrace) {
      developer.log(
        'Native seek failed',
        error: error,
        stackTrace: stackTrace,
        name: 'PlayerController',
      );
    } finally {
      await _saveSession();
      _isSeeking = false;
      notifyListeners();
    }
  }

  Duration _clampSeekTarget(Duration target) {
    if (target.isNegative) return Duration.zero;
    if (_duration.inMilliseconds > 0 && target.compareTo(_duration) > 0) {
      return _duration;
    }
    return target;
  }

  Future<void> next() {
    final active = _nextOperation;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _advanceToNext().whenComplete(() {
      if (identical(_nextOperation, operation)) _nextOperation = null;
    });
    _nextOperation = operation;
    return operation;
  }

  Future<void> _advanceToNext() async {
    if (_queue.isEmpty) return;
    if (_isShuffle && _shuffledIndices.isNotEmpty) {
      final currentPosInShuffle = _shuffledIndices.indexOf(_currentIndex);
      if (currentPosInShuffle >= 0 &&
          currentPosInShuffle + 1 < _shuffledIndices.length) {
        final nextIdx = _shuffledIndices[currentPosInShuffle + 1];
        await playTrack(_queue[nextIdx]);
        return;
      }
    }

    if (_currentIndex + 1 < _queue.length) {
      await playTrack(_queue[_currentIndex + 1]);
    } else if (_repeatMode == RepeatMode.all) {
      await playTrack(_queue.first);
    } else {
      final extended = await _ensureEndlessQueue(force: true);
      final generatedNext = extended ? _nextQueuedTrack() : null;
      if (generatedNext != null) await playTrack(generatedNext);
    }
  }

  Future<void> previous() async {
    if (_position.inSeconds > 4) {
      await seek(Duration.zero);
      return;
    }

    if (_queue.isEmpty) return;

    if (_currentIndex - 1 >= 0) {
      await playTrack(_queue[_currentIndex - 1]);
    } else {
      await seek(Duration.zero);
    }
  }

  /// Adds a user-selected song after all existing manual picks and before the
  /// remaining smart recommendations. Manual picks therefore keep insertion
  /// order and always win over radio-generated items.
  Future<bool> addToQueue(Track track) async {
    await _ready;
    if (_currentTrack == null) {
      await playTrack(track, newQueue: [track]);
      return true;
    }
    if (_currentTrack!.id == track.id ||
        _trackIdentity(_currentTrack!) == _trackIdentity(track)) {
      return false;
    }

    final identity = _trackIdentity(track);
    final existingIndex = _queue.indexWhere(
      (item) => item.id == track.id || _trackIdentity(item) == identity,
    );
    if (existingIndex >= 0) {
      final existing = _queue[existingIndex];
      if (_manualQueueIds.contains(existing.id)) return false;
      _queue.removeAt(existingIndex);
      if (existingIndex < _currentIndex) _currentIndex--;
      _manualQueueIds.remove(existing.id);
    }

    var insertionIndex = (_currentIndex + 1).clamp(0, _queue.length).toInt();
    while (insertionIndex < _queue.length &&
        _manualQueueIds.contains(_queue[insertionIndex].id)) {
      insertionIndex++;
    }
    _queue.insert(insertionIndex, track);
    _manualQueueIds.add(track.id);
    _radioHistory.add(identity);

    if (_isShuffle) {
      _shuffledIndices.clear();
      _isShuffle = false;
    }
    _retainQueuePrefetches();
    unawaited(_saveSession());
    notifyListeners();
    unawaited(_warmNextTrack());
    return true;
  }

  Future<void> removeFromQueue(Track track) async {
    await _ready;
    if (_currentTrack?.id == track.id) return;

    final queueIndex = _queue.indexWhere((item) => item.id == track.id);
    if (queueIndex < 0) return;

    _queue.removeAt(queueIndex);
    _manualQueueIds.remove(track.id);
    if (queueIndex < _currentIndex) {
      _currentIndex--;
    }

    if (_isShuffle) {
      _shuffledIndices = List.generate(_queue.length, (index) => index)
        ..shuffle();
    }

    _retainQueuePrefetches();
    unawaited(_saveSession());
    notifyListeners();
    unawaited(_warmNextTrack());
    unawaited(_ensureEndlessQueue());
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        unawaited(_player.setLoopMode(LoopMode.off));
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        unawaited(_player.setLoopMode(_effectiveLoopMode));
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        unawaited(_player.setLoopMode(LoopMode.off));
        break;
    }
    unawaited(_warmNextTrack());
    unawaited(_saveSession());
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle && _queue.isNotEmpty) {
      _shuffledIndices = List.generate(_queue.length, (i) => i)..shuffle();
    } else {
      _shuffledIndices.clear();
    }
    unawaited(_warmNextTrack());
    unawaited(_saveSession());
    notifyListeners();
  }

  Future<void> _handleTrackCompleted() async {
    if (_sleepStopWork != null ||
        _sleepPauseGeneration == _playlistGeneration ||
        _disposed ||
        _isHandlingCompletion ||
        _isLoadingTrack ||
        _needsSourceRestore ||
        _recoveringGeneration == _playlistGeneration ||
        _hasTerminalCompletion) {
      return;
    }
    if (_sleepAfterTrack) {
      await _finishSleep(rewind: true);
      return;
    }
    _isHandlingCompletion = true;

    try {
      _position = _duration;
      notifyListeners();
      if (_repeatMode == RepeatMode.one) {
        await _player.pause();
        await seek(Duration.zero);
        if (_currentTrack != null) {
          unawaited(_startPlayback(_currentTrack!, allowFallback: true));
        }
        return;
      }

      // Lock-screen Next and automatic completion deliberately use one path.
      final generation = _playlistGeneration;
      await next();
      if (generation == _playlistGeneration) {
        _hasTerminalCompletion = true;
      }
    } catch (error, stackTrace) {
      _hasTerminalCompletion = true;
      developer.log(
        'Could not advance after track completion',
        error: error,
        stackTrace: stackTrace,
        name: 'PlayerController',
      );
    } finally {
      _isHandlingCompletion = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_saveSession());
    _disposed = true;
    _sleepTimer?.cancel();
    _checkpointTimer?.cancel();
    _endWatchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedPositionSub?.cancel();
    _playbackEventSub?.cancel();
    _sequenceSub?.cancel();
    _tiktokSounds.close();
    _tikTokCache.close();
    _player.dispose();
    super.dispose();
  }
}
