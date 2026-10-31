import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../controllers/player_controller.dart';
import '../models/track.dart';

/// Exposes the existing Cloudio player to system media controls.
/// The OS never seeks a second native playlist: Next uses the same controller
/// path as the app and automatic completion.
class CloudioAudioHandler extends BaseAudioHandler with SeekHandler {
  CloudioAudioHandler(this._controller) {
    _controller.addListener(_broadcast);
    _controller.player.playerStateStream.listen(
      (_) => _broadcast(),
    );
    _controller.player.playbackEventStream.listen(
      (_) => _broadcast(),
      onError: (Object _, StackTrace __) => _broadcast(),
    );
    _broadcast();
  }

  final PlayerController _controller;
  List<String> _publishedQueueIds = const [];

  MediaItem _itemFor(Track track) => MediaItem(
        id: track.id,
        album: track.album ?? 'Cloudio',
        title: track.displayTitle,
        artist: track.displayArtist,
        artUri:
            track.artworkUrl == null ? null : Uri.tryParse(track.artworkUrl!),
        duration: track.duration,
      );

  void _broadcast() {
    final track = _controller.currentTrack;
    final current = track == null
        ? null
        : _itemFor(track).copyWith(
            duration: _controller.duration > Duration.zero
                ? _controller.duration
                : track.duration,
          );
    final queueIds = _controller.queue.map((item) => item.id).toList();
    if (queueIds.length != _publishedQueueIds.length ||
        Iterable.generate(queueIds.length).any(
          (index) => queueIds[index] != _publishedQueueIds[index],
        )) {
      _publishedQueueIds = queueIds;
      queue.add(_controller.queue.map(_itemFor).toList(growable: false));
    }
    if (mediaItem.valueOrNull?.id != current?.id ||
        mediaItem.valueOrNull?.duration != current?.duration) {
      mediaItem.add(current);
    }

    final nativeState = _controller.player.processingState;
    final transitioning = _controller.isTransitioningBetweenTracks ||
        (nativeState == ProcessingState.completed &&
            track != null &&
            !_controller.hasTerminalCompletion);
    final processingState = transitioning
        ? AudioProcessingState.loading
        : switch (nativeState) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          };
    final playing = (transitioning && track != null) ||
        (nativeState != ProcessingState.completed && _controller.isPlaying);
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      if (track != null) MediaControl.skipToNext,
    ];

    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: [
        0,
        1,
        if (controls.length > 3) 3,
      ],
      processingState: processingState,
      playing: playing,
      updatePosition: _controller.playbackPosition,
      bufferedPosition: _controller.player.bufferedPosition,
      speed: _controller.player.speed,
      queueIndex:
          _controller.currentIndex >= 0 ? _controller.currentIndex : null,
      repeatMode: switch (_controller.repeatMode) {
        RepeatMode.off => AudioServiceRepeatMode.none,
        RepeatMode.all => AudioServiceRepeatMode.all,
        RepeatMode.one => AudioServiceRepeatMode.one,
      },
      shuffleMode: _controller.isShuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  @override
  Future<void> play() => _controller.resume();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seek(Duration position) => _controller.seek(position);

  @override
  Future<void> skipToNext() => _controller.next();

  @override
  Future<void> skipToPrevious() => _controller.previous();

  @override
  Future<void> skipToQueueItem(int index) async {
    final items = _controller.queue;
    if (index < 0 || index >= items.length) return;
    await _controller.playTrack(items[index]);
  }

  @override
  Future<void> stop() async {
    await _controller.player.stop();
    _broadcast();
    await super.stop();
  }
}
