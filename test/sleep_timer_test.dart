import 'dart:async';

import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_autoplay_test.dart' as fixture;

class SleepPlayer extends fixture.CompletionPlayer {
  LoopMode loop = LoopMode.off;
  Completer<void>? nextLoopGate;
  @override
  Future<void> setLoopMode(LoopMode value) async {
    loop = value;
    final gate = nextLoopGate;
    nextLoopGate = null;
    if (gate != null) await gate.future;
  }
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

  PlayerController create(SleepPlayer native) {
    final player = PlayerController.forTesting(
        player: native,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    return player;
  }

  test(
      'timed sleep pauses once at the deadline, retains progress, and can be resumed',
      () async {
    final native = SleepPlayer();
    final player = create(native);
    await player
        .playTrack(fixture.first, newQueue: [fixture.first, fixture.second]);
    native.nativePosition = const Duration(seconds: 42);
    await player.setSleepTimer(const Duration(minutes: 15));
    final deadline = player.sleepTimerDeadline!;
    await player.checkSleepTimer(
        now: deadline.subtract(const Duration(seconds: 1)));
    expect(native.playing, isTrue);
    final pauses = native.commands.where((c) => c == 'pause').length;
    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    await player.checkSleepTimer(now: deadline);
    await player.checkSleepTimer(now: deadline.add(const Duration(seconds: 1)));
    expect(native.playing, isFalse);
    expect(native.position, const Duration(seconds: 42));
    expect(native.commands.where((c) => c == 'pause').length, pauses + 1);
    expect(player.hasSleepTimer, isFalse);
    await player.resume();
    await fixture.until(() => native.playing);
    expect(player.currentTrack?.id, fixture.first.id);
  });

  test('the scheduled timer itself pauses playback without a UI tick',
      () async {
    final native = SleepPlayer();
    final player = create(native);
    await player.playTrack(fixture.first, newQueue: [fixture.first]);
    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    await player.setSleepTimer(const Duration(milliseconds: 30));
    await fixture.until(() => !native.playing);
    expect(player.hasSleepTimer, isFalse);
    expect(native.starts, 1);
  });

  test('manual Next keeps end-of-song sleep on the selected song', () async {
    final native = SleepPlayer();
    final player = create(native);
    await player
        .playTrack(fixture.first, newQueue: [fixture.first, fixture.second]);
    await player.setSleepAfterTrack();
    await player.next();
    expect(player.currentTrack?.id, fixture.second.id);
    expect(player.sleepAfterTrack, isTrue);
    native.complete();
    await fixture.until(() => !native.playing);
    expect(player.currentTrack?.id, fixture.second.id);
    expect(player.hasSleepTimer, isFalse);
  });

  test('replacing or cancelling a timer does not pause music', () async {
    final native = SleepPlayer();
    final player = create(native);
    await player.playTrack(fixture.first, newQueue: [fixture.first]);
    await player.setSleepTimer(const Duration(minutes: 5));
    final oldDeadline = player.sleepTimerDeadline!;
    await player.setSleepTimer(const Duration(minutes: 30));
    await player.checkSleepTimer(now: oldDeadline);
    expect(native.playing, isTrue);
    expect(player.sleepTimerDuration, const Duration(minutes: 30));
    final newDeadline = player.sleepTimerDeadline!;
    await player.cancelSleepTimer();
    await player.checkSleepTimer(now: newDeadline);
    expect(native.playing, isTrue);
    expect(player.hasSleepTimer, isFalse);
  });

  test(
      'end-of-song sleep removes native successor, overrides repeat-one, and stops before auto-next',
      () async {
    final native = SleepPlayer();
    final player = create(native);
    await player
        .playTrack(fixture.first, newQueue: [fixture.first, fixture.second]);
    await fixture.until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    player.toggleRepeat();
    player.toggleRepeat();
    expect(player.repeatMode, RepeatMode.one);
    await player.setSleepAfterTrack();
    expect(native.loop, LoopMode.off);
    expect((native.source as ConcatenatingAudioSource).children, hasLength(1));
    native.complete();
    await fixture.until(() => !native.playing && native.nativeSeeks > 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    player.checkPlaybackEnd();
    expect(player.currentTrack?.id, fixture.first.id);
    expect(native.starts, 1);
    expect(player.hasSleepTimer, isFalse);
    expect(player.repeatMode, RepeatMode.one);
    expect(native.loop, LoopMode.one);
    await player.resume();
    await fixture.until(() => native.starts == 2);
  });

  test(
      'cancelling end-of-song sleep restores native preloading without starting another song',
      () async {
    final native = SleepPlayer();
    final player = create(native);
    await player
        .playTrack(fixture.first, newQueue: [fixture.first, fixture.second]);
    await player.setSleepAfterTrack();
    expect((native.source as ConcatenatingAudioSource).children, hasLength(1));
    await player.cancelSleepTimer();
    await fixture.until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    expect(native.starts, 1);
    native.transition();
    await fixture.until(() => player.currentTrack?.id == fixture.second.id);
    expect(native.playing, isTrue);
  });

  test('a slow lookup cannot start playback after timed sleep expires',
      () async {
    final pending = Completer<String>();
    final native = SleepPlayer();
    final player = PlayerController.forTesting(
        player: native,
        resolveTrack: (_) => pending.future,
        buildQueue: (_) async => []);
    addTearDown(player.dispose);
    final loading = player.playTrack(fixture.first, newQueue: [fixture.first]);
    await fixture.until(() => player.currentTrack != null);
    await player.setSleepTimer(const Duration(minutes: 5));
    await player.checkSleepTimer(now: player.sleepTimerDeadline);
    pending.complete('https://example.test/audio.m4a');
    await loading;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(native.starts, 0);
    expect(native.playing, isFalse);
    await player.resume();
    await fixture.until(() => native.starts == 1);
  });

  test(
      'an already-buffered transition racing end-of-song sleep pauses with matching metadata',
      () async {
    final native = SleepPlayer();
    final player = create(native);
    await player
        .playTrack(fixture.first, newQueue: [fixture.first, fixture.second]);
    await fixture.until(
        () => (native.source as ConcatenatingAudioSource).children.length == 2);
    final gate = Completer<void>();
    native.nextLoopGate = gate;
    final setting = player.setSleepAfterTrack();
    await fixture.until(() => player.sleepAfterTrack);
    native.transition();
    await fixture.until(() => !native.playing);
    gate.complete();
    await setting;
    expect(player.hasSleepTimer, isFalse);
    expect(player.currentTrack?.id,
        (native.sequenceState!.currentSource!.tag as dynamic).id);
  });
}
