import 'dart:async';
import 'dart:convert';
import 'audio_timeline_test.dart' as timeline;
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/music_service.dart';
import 'package:cloudio_mobile/services/audio_resolver.dart';
import 'package:cloudio_mobile/services/youtube_music_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cloudio_mobile/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const first = Track(
    id: 'ytm:first',
    title: 'First song',
    artist: 'Artist',
    duration: Duration(minutes: 3));
const second = Track(
    id: 'ytm:second',
    title: 'Second song',
    artist: 'Artist',
    duration: Duration(minutes: 3));

// Models the native completion contract: logical playing stays true, but a
// replaced completed source needs a fresh play command to actually start.
class CompletionPlayer extends AudioPlayer {
  CompletionPlayer() : super(handleAudioSessionActivation: false);
  final states = StreamController<PlayerState>.broadcast();
  final commands = <String>[];
  final sequences = StreamController<SequenceState?>.broadcast();
  UriAudioSource? currentSource;
  @override
  int? get currentIndex => source is ConcatenatingAudioSource
      ? (source as ConcatenatingAudioSource).children.indexOf(currentSource!)
      : 0;
  @override
  SequenceState? get sequenceState {
    final items = source is ConcatenatingAudioSource
        ? (source as ConcatenatingAudioSource)
            .children
            .cast<IndexedAudioSource>()
        : <IndexedAudioSource>[];
    return items.isEmpty
        ? null
        : SequenceState(items, currentIndex ?? 0,
            List.generate(items.length, (i) => i), false, LoopMode.off);
  }

  @override
  Stream<SequenceState?> get sequenceStateStream => sequences.stream;
  void transition({bool notify = true}) {
    final playlist = source as ConcatenatingAudioSource;
    currentSource =
        playlist.children[(currentIndex ?? 0) + 1] as UriAudioSource;
    nativePosition = Duration.zero;
    if (notify) sequences.add(sequenceState);
  }

  bool active = false;
  ProcessingState state = ProcessingState.idle;
  AudioSource? source;
  int starts = 0;
  int nativeSeeks = 0;
  int playFailures = 0;
  final events = StreamController<PlaybackEvent>.broadcast();
  Duration nativePosition = Duration.zero;
  Duration nativeDuration = const Duration(minutes: 3);
  Duration nativeBuffered = Duration.zero;
  @override
  Duration get position => nativePosition;
  @override
  Duration? get duration => nativeDuration;
  @override
  Duration get bufferedPosition => nativeBuffered;
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState => state;
  @override
  AudioSource? get audioSource => source;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<Duration?> get durationStream => Stream.value(first.duration);
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<Duration> createPositionStream(
          {int steps = 800,
          Duration minPeriod = const Duration(milliseconds: 200),
          Duration maxPeriod = const Duration(milliseconds: 200)}) =>
      const Stream.empty();
  @override
  Future<void> setAutomaticallyWaitsToMinimizeStalling(bool value) async {}
  @override
  Future<void> setLoopMode(LoopMode value) async {}
  @override
  Future<Duration?> setAudioSource(AudioSource newSource,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    source = newSource;
    currentSource = (newSource is ConcatenatingAudioSource
        ? newSource.children.first
        : newSource) as UriAudioSource;
    nativePosition = initialPosition ?? Duration.zero;
    commands.add('load:${(currentSource!.tag as MediaItem).id}');
    state = ProcessingState.ready;
    states.add(PlayerState(active, state));
    return first.duration;
  }

  @override
  Future<void> play() async {
    if (active) return;
    active = true;
    starts++;
    commands.add('play:${(currentSource!.tag as MediaItem).id}');
    states.add(PlayerState(active, state));
    if (playFailures > 0) {
      playFailures--;
      throw StateError('Native decoder rejected stream');
    }
  }

  @override
  Future<void> pause() async {
    active = false;
    commands.add('pause');
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    nativeSeeks++;
    nativePosition = position ?? Duration.zero;
    if (nativeDuration == Duration.zero) {
      nativeDuration = const Duration(minutes: 3);
    }
    state = ProcessingState.ready;
    states.add(PlayerState(active, state));
  }

  void complete() {
    state = ProcessingState.completed;
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> dispose() async {
    await states.close();
    await sequences.close();
    await events.close();
    await super.dispose();
  }
}

class DelayedLoadPlayer extends CompletionPlayer {
  Completer<void>? loadGate;

  @override
  Future<Duration?> setAudioSource(AudioSource newSource,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    return super.setAudioSource(newSource,
        preload: preload,
        initialIndex: initialIndex,
        initialPosition: initialPosition);
  }
}

class RejectOncePlayer extends CompletionPlayer {
  bool rejectNextLoad = true;

  @override
  Future<Duration?> setAudioSource(AudioSource newSource,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    final duration = await super.setAudioSource(newSource,
        preload: preload,
        initialIndex: initialIndex,
        initialPosition: initialPosition);
    if (rejectNextLoad) {
      rejectNextLoad = false;
      events.addError(
          PlatformException(code: '403', message: 'load failed',
              details: {'index': 0}), StackTrace.current);
      throw PlayerException(403, 'load failed', {'index': 0});
    }
    return duration;
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (_) async => <String, dynamic>{});
  });
  PlayerController controller(CompletionPlayer native,
          {Future<List<Track>> Function(Track)? queue}) =>
      PlayerController.forTesting(
          player: native,
          resolveTrack: (_) async => 'https://example.test/audio.m4a',
          buildQueue: queue ?? (_) async => []);

  test(
      'TikTok sound uses its own source, keeps clip duration and never starts YouTube radio',
      () async {
    final native = CompletionPlayer();
    var radioCalls = 0;
    final player = PlayerController.forTesting(
      player: native,
      resolveTrack: (_) async => 'https://sample.tiktokcdn.com/post.mp4',
      buildQueue: (_) async {
        radioCalls++;
        return [second];
      },
    );
    addTearDown(player.dispose);
    const track = Track(
        id: 'tiktok:123',
        provider: 'tiktok',
        sourceUrl: 'https://www.tiktok.com/@creator/video/123/',
        title: 'Original sound (Slowed)',
        artist: '@creator',
        duration: Duration(seconds: 13));
    await player.playTrack(track, newQueue: [track]);
    await until(() => native.starts == 1);
    expect(radioCalls, 0);
    expect(player.queue, hasLength(1));
    expect(native.currentSource?.uri.host, 'sample.tiktokcdn.com');
    expect(
        native.currentSource?.headers?['Referer'], 'https://www.tiktok.com/');
    final metadata = native.currentSource!.tag as MediaItem;
    expect(metadata.title, 'Original sound (Slowed)');
    expect(metadata.duration, const Duration(seconds: 13));
  });

  test(
      'preload retries a transient MP4 failure and auto-next adopts the bounded duration',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final native = TimelinePlayer();
    final player = PlayerController.forTesting(
      player: native,
      resolveTrack: (track) async => Uri.https(ApiConfig.resolverHost,
          '/stream', {'id': 'controller-${track.cleanVideoId}'}).toString(),
      buildQueue: (_) async => [],
    );
    addTearDown(player.dispose);
    var nextAttempts = 0;
    await http.runWithClient(() async {
      await player.playTrack(first, newQueue: [first, second]);
      await until(() =>
          (native.source as ConcatenatingAudioSource).children.length == 2);
      final source = (native.source as ConcatenatingAudioSource).children[1]
          as ClippingAudioSource;
      expect(source.end, const Duration(microseconds: 190705487));
      native.transition(notify: false);
      player.checkPlaybackEnd();
      expect(player.currentTrack?.id, second.id);
      expect(player.duration, const Duration(microseconds: 190705487));
      expect(player.position, Duration.zero);
      expect(native.starts, 1);
    },
        () => MockClient((request) async {
              if (request.url.queryParameters['id'] == 'controller-second') {
                if (++nextAttempts == 1) {
                  return http.Response('cold cache', 503);
                }
                return http.Response.bytes(timeline.movie(44100, 8410112), 206);
              }
              return http.Response.bytes(timeline.movie(1000, 180000), 206);
            }));
    expect(nextAttempts, 2);
  });

  test('long natural queue trims one past source without advancing metadata',
      () async {
    final tracks = List.generate(
        12,
        (i) => Track(
            id: 'ytm:track$i',
            title: 'Song $i',
            artist: 'Artist',
            duration: const Duration(minutes: 3)));
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(tracks.first, newQueue: tracks);
    for (var i = 1; i <= 8; i++) {
      await until(() =>
          (native.source as ConcatenatingAudioSource).children.length >
          (native.currentIndex ?? 0) + 1);
      native.transition();
      await until(() => player.currentIndex == i);
    }
    await until(() =>
        (native.source as ConcatenatingAudioSource).children.length == 10);
    native.nativePosition = const Duration(seconds: 3);
    player.checkPlaybackEnd();
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 9);
    expect(player.currentIndex, 8);
    expect(player.currentTrack?.id, tracks[8].id);
    expect(native.currentIndex, 7);
    expect((native.currentSource!.tag as MediaItem).id, tracks[8].id);
    expect(native.starts, 1);
  });

  test(
      'missed sequence event reconciles track, duration and seek position on tick',
      () async {
    const longer = Track(
        id: 'ytm:longer',
        title: 'Longer song',
        artist: 'Artist',
        duration: Duration(minutes: 5));
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, longer]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    native.transition(notify: false);
    native.nativeDuration = longer.duration!;
    native.nativePosition = const Duration(seconds: 7);
    native.nativeBuffered = const Duration(seconds: 20);
    expect(player.currentTrack?.id, first.id);
    player.checkPlaybackEnd();
    expect(player.currentTrack?.id, longer.id);
    expect(player.duration, longer.duration);
    expect(player.position, const Duration(seconds: 7));
    expect(player.bufferedPosition, const Duration(seconds: 20));
    expect(native.starts, 1);
  });

  test('returning from background reconciles a silent native advance',
      () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    native.transition(notify: false);
    native.nativePosition = const Duration(seconds: 9);
    player.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(player.currentTrack?.id, second.id);
    expect(player.position, const Duration(seconds: 9));
  });

  test('failed preload retries once without interrupting active audio',
      () async {
    final native = CompletionPlayer();
    var nextLookups = 0;
    final player = PlayerController.forTesting(
        player: native,
        resolveTrack: (track) async {
          if (track.id == second.id) nextLookups++;
          return 'https://example.test/${track.cleanVideoId}.m4a';
        },
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    final playlist = native.source as ConcatenatingAudioSource;
    await until(() => playlist.children.length == 2);
    native.nativePosition = const Duration(seconds: 42);
    native.events.addError(
        PlatformException(code: '403', message: 'preload expired',
            details: {'index': 1}), StackTrace.current);
    await until(() =>
        playlist.children.length == 2 &&
        (playlist.children[1] as UriAudioSource).uri.host ==
            ApiConfig.resolverHost);
    expect(player.currentTrack?.id, first.id);
    expect(native.position, const Duration(seconds: 42));
    expect(native.playing, isTrue);
    expect(native.starts, 1);
    expect(native.commands.where((command) => command == 'pause').length, 1);
    native.events.addError(
        PlatformException(code: '503', message: 'gateway unavailable',
            details: {'index': 1}), StackTrace.current);
    await until(() => playlist.children.length == 1);
    await player.next();
    expect(player.currentTrack?.id, second.id);
    expect(native.starts, 2);
    expect(nextLookups, 2);
  });

  test('indexed failure after a silent transition recovers the active song',
      () async {
    final native = CompletionPlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('local blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    native.transition(notify: false);
    native.nativePosition = const Duration(seconds: 7);
    native.state = ProcessingState.idle;
    native.events.addError(
        PlatformException(code: '1', message: 'active source failed',
            details: {'index': 1}), StackTrace.current);
    await until(() => native.starts == 2);
    expect(player.currentTrack?.id, second.id);
    expect(native.position, const Duration(seconds: 7));
    expect(player.playbackError, isNull);
  });

  test('mid-song stall refreshes the same song at its saved position', () async {
    final native = CompletionPlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('local blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    native.nativePosition = const Duration(seconds: 40);
    native.nativeBuffered = const Duration(seconds: 40);
    native.state = ProcessingState.buffering;
    final now = DateTime.now();
    player.checkPlaybackEnd(now: now);
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 19)));
    expect(native.starts, 1);
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 21)));
    await until(() => native.starts == 2);
    expect(player.currentTrack?.id, first.id);
    expect(native.position, const Duration(seconds: 40));
    expect(player.queue.map((track) => track.id), [first.id, second.id]);
  });

  test('Pause during recovery keeps the replacement paused until Play',
      () async {
    final pending = Completer<void>();
    final native = DelayedLoadPlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('local blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first);
    native.loadGate = pending;
    native.nativePosition = const Duration(seconds: 35);
    native.events.addError(
        PlayerException(403, 'expired', {'index': 0}), StackTrace.current);
    await until(() => player.isLoadingTrack);
    await player.pause();
    pending.complete();
    await until(() => !player.isLoadingTrack);
    expect(native.playing, isFalse);
    expect(native.starts, 1);
    expect(native.position, const Duration(seconds: 35));
    await player.resume();
    await until(() => native.starts == 2);
    expect(native.playing, isTrue);
  });

  test('position progress and Pause reset the stall window', () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first);
    native.nativePosition = const Duration(seconds: 40);
    native.state = ProcessingState.buffering;
    final now = DateTime.now();
    player.checkPlaybackEnd(now: now);
    native.nativePosition = const Duration(seconds: 41);
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 19)));
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 21)));
    expect(native.starts, 1);
    expect(player.isLoadingTrack, isFalse);
    await player.pause();
    player.checkPlaybackEnd(now: now.add(const Duration(minutes: 2)));
    expect(native.starts, 1);
    expect(native.playing, isFalse);
  });

  test('load and event errors share one startup recovery', () async {
    final native = RejectOncePlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('local blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/rejected.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(() => native.starts == 1);
    expect(player.currentTrack?.id, first.id);
    expect(native.playing, isTrue);
    expect(native.commands.where((command) => command.startsWith('load:')).length,
        2);
    expect(native.currentSource!.uri.host, ApiConfig.resolverHost);
  });

  test('direct stream recovery keeps its original provider URL', () async {
    final native = CompletionPlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('must not use YouTube'));
    const direct = Track(
        id: 'direct:audio',
        provider: 'direct',
        sourceUrl: 'https://example.test/direct.m4a',
        title: 'Direct song',
        artist: 'Artist');
    final player = PlayerController.forTesting(
        player: native, resolver: resolver, buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(direct);
    native.nativePosition = const Duration(seconds: 10);
    native.events.addError(
        PlatformException(code: '1', message: 'connection lost',
            details: {'index': 0}), StackTrace.current);
    await until(() => native.starts == 2);
    expect(player.currentTrack?.id, direct.id);
    expect(native.currentSource!.uri.toString(), direct.sourceUrl);
    expect(native.position, const Duration(seconds: 10));
  });

  test('premature mid-song native advance recovers current song at saved position',
      () async {
    final native = CompletionPlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('local blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    native.nativePosition = const Duration(seconds: 45);
    player.checkPlaybackEnd();
    expect(player.position, const Duration(seconds: 45));
    // Simulate native player advancing to index 1 mid-song due to truncated stream
    native.transition();
    await until(() => native.starts == 2);
    expect(player.currentTrack?.id, first.id);
    expect(native.position, const Duration(seconds: 45));
    expect(native.currentSource!.uri.host, ApiConfig.resolverHost);
  });

  test('decoder failures exhaust a bounded ladder without consuming the queue',
      () async {
    final native = CompletionPlayer()..playFailures = 10;
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(() =>
        native.starts == 4 &&
        player.playbackError != null &&
        !player.isLoadingTrack);
    expect(player.currentTrack?.id, first.id);
    expect(player.queue.length, 2);
    expect(native.playing, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(native.starts, 4);
  });

  test('stream errors after native auto-advance recover the active song',
      () async {
    final native = CompletionPlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    native.transition();
    await until(() => player.currentTrack?.id == second.id);
    native.events.addError(StateError('stream expired'), StackTrace.current);
    await until(() => native.starts == 2);
    expect(player.currentTrack?.id, second.id);
    expect(player.playbackError, isNull);
  });

  test(
      'silent zero-duration stall enters compatibility recovery without skipping',
      () async {
    final native = CompletionPlayer();
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('blocked'));
    final player = PlayerController.forTesting(
        player: native,
        resolver: resolver,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    addTearDown(resolver.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    native.transition();
    await until(() => player.currentTrack?.id == second.id);
    native.nativeDuration = Duration.zero;
    native.state = ProcessingState.buffering;
    final now = DateTime.now();
    player.checkPlaybackEnd(now: now);
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 13)));
    await until(() => native.starts == 2);
    expect(player.currentTrack?.id, second.id);
    expect(player.queue.length, 2);
    expect((native.currentSource!.uri).host, ApiConfig.resolverHost);
  });

  test('zero-duration native transition refreshes its timeline without reload',
      () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    final source = native.source;
    native.nativeDuration = Duration.zero;
    native.transition();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(native.nativeSeeks, 1);
    expect(native.duration, const Duration(minutes: 3));
    expect(native.source, same(source));
    expect(player.currentTrack?.id, second.id);
    expect(native.starts, 1);
  });

  test('native preloaded successor advances without reloading or pausing',
      () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    final commands = List.of(native.commands);
    native.transition();
    await until(() => player.currentTrack?.id == second.id);
    expect(native.commands, commands);
    expect(native.starts, 1);
    expect(player.position, Duration.zero);
    expect(player.currentIndex, 1);
    // AVQueuePlayer may still deliver the first item's end notification. Its
    // source must remain addressable until the new item is playing stably.
    expect(
        ((native.source as ConcatenatingAudioSource).children.first
                as UriAudioSource)
            .tag,
        isA<MediaItem>().having((item) => item.id, 'id', first.id));
    expect(player.hasTerminalCompletion, isFalse);
  });

  test('removed successor is detached from the native queue', () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    await player.removeFromQueue(second);
    await until(
        () => (native.source as ConcatenatingAudioSource).children.length == 1);
    expect(player.currentTrack?.id, first.id);
  });

  test('late preload cannot append a removed successor', () async {
    final delayed = Completer<String>();
    final native = CompletionPlayer();
    final player = PlayerController.forTesting(
        player: native,
        resolveTrack: (track) => track.id == second.id
            ? delayed.future
            : Future.value('https://example.test/first.m4a'),
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await player.removeFromQueue(second);
    delayed.complete('https://example.test/second.m4a');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect((native.source as ConcatenatingAudioSource).children.length, 1);
  });

  test('completion sends a fresh play command for the next queued song',
      () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    expect(native.starts, 1);
    native.complete();
    expect(native.playing, isTrue);
    await until(
        () => player.currentTrack?.id == second.id && native.starts == 2);
    expect(native.commands, [
      'pause',
      'load:ytm:first',
      'play:ytm:first',
      'pause',
      'load:ytm:second',
      'play:ytm:second'
    ]);
    expect(player.hasTerminalCompletion, isFalse);
  });
  test(
      'single-song completion waits for radio, then starts exactly one next song',
      () async {
    final radio = Completer<List<Track>>();
    final native = CompletionPlayer();
    final player = controller(native, queue: (_) => radio.future);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first]);
    native.complete();
    native.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(native.starts, 1);
    radio.complete([first, second]);
    await until(
        () => player.currentTrack?.id == second.id && native.starts == 2);
    expect(player.queue.map((t) => t.id), [first.id, second.id]);
  });
  test('repeat all restarts the first song after the last one completes',
      () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.ensureInitialized();
    player.toggleRepeat();
    await player.playTrack(second, newQueue: [first, second]);
    native.complete();
    await until(
        () => player.currentTrack?.id == first.id && native.starts == 2);
  });
  test('repeat one sends play again when a completion event is delivered',
      () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.ensureInitialized();
    player.toggleRepeat();
    await player.ensureInitialized();
    player.toggleRepeat();
    await player.playTrack(first, newQueue: [first]);
    native.complete();
    await until(() => native.starts == 2);
    expect(player.currentTrack?.id, first.id);
  });
  test('a short valid radio response is retained for autoplay', () async {
    final catalog = YoutubeMusicCatalog(client: MockClient((request) async {
      expect(request.url.path, '/youtubei/v1/next');
      return http.Response(
          jsonEncode({
            'playlistPanelVideoRenderer': {
              'videoId': 'second',
              'title': {
                'runs': [
                  {'text': 'Second song'}
                ]
              },
              'longBylineText': {
                'runs': [
                  {'text': 'Artist'}
                ]
              },
              'lengthText': {
                'runs': [
                  {'text': '3:00'}
                ]
              },
            }
          }),
          200);
    }));
    final music = MusicService.forTesting(catalog);
    addTearDown(music.dispose);
    expect((await music.buildSmartQueue(first)).map((t) => t.id),
        [first.id, second.id]);
  });
  test(
      'missing completed event advances after the buffered native end, also in background',
      () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    native.nativePosition = native.nativeDuration;
    native.nativeBuffered = native.nativeDuration;
    native.state = ProcessingState.buffering;
    final now = DateTime.utc(2026);
    player.checkPlaybackEnd(now: now);
    expect(native.starts, 1);
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 3)));
    await until(
        () => player.currentTrack?.id == second.id && native.starts == 2);
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 4)));
    expect(native.starts, 2);
  });
  test('catalog end alone never skips a longer native stream', () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    await player.playTrack(first, newQueue: [first, second]);
    native.nativeDuration = const Duration(minutes: 4);
    native.nativePosition = const Duration(minutes: 3, seconds: 20);
    native.nativeBuffered = native.nativeDuration;
    final now = DateTime.utc(2026);
    player.checkPlaybackEnd(now: now);
    player.checkPlaybackEnd(now: now.add(const Duration(seconds: 5)));
    expect(player.currentTrack?.id, first.id);
    expect(player.duration, const Duration(minutes: 4));
    expect(player.position, const Duration(minutes: 3, seconds: 20));
    expect(native.starts, 1);
  });

  test('sanitizes doubled AVPlayer duration when playing fragmented MP4 on iOS', () async {
    final native = CompletionPlayer();
    final player = controller(native);
    addTearDown(player.dispose);
    const song = Track(
      id: 'four-min-song',
      title: 'Four Minute Song',
      artist: 'Artist',
      duration: Duration(minutes: 4),
    );
    await player.playTrack(song, newQueue: [song]);
    // Simulate AVPlayer emitting doubled native duration (8:00 instead of 4:00)
    native.nativeDuration = const Duration(minutes: 8);
    native.nativePosition = const Duration(minutes: 1);
    native.nativeBuffered = const Duration(minutes: 2);
    player.checkPlaybackEnd();

    expect(player.duration, const Duration(minutes: 4));
    expect(player.position, const Duration(minutes: 1));
  });
}

// Models a native player whose underlying MP4 duration may be doubled, while
// ClippingAudioSource carries the verified file timeline used for playback.
class TimelinePlayer extends CompletionPlayer {
  int index = 0;
  @override
  int get currentIndex => index;
  @override
  Future<Duration?> setAudioSource(AudioSource newSource,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    source = newSource;
    index = initialIndex ?? 0;
    final current = (newSource as ConcatenatingAudioSource).children[index]
        as ClippingAudioSource;
    currentSource = current.child;
    nativeDuration = current.end!;
    nativePosition = initialPosition ?? Duration.zero;
    state = ProcessingState.ready;
    states.add(PlayerState(active, state));
    return nativeDuration;
  }

  @override
  void transition({bool notify = true}) {
    index++;
    nativeDuration = ((source as ConcatenatingAudioSource).children[index]
            as ClippingAudioSource)
        .end!;
    nativePosition = Duration.zero;
    if (notify) sequences.add(sequenceState);
  }
}
