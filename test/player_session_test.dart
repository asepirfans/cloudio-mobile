import 'dart:convert';

import 'package:cloudio_mobile/controllers/listening_history_controller.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/player_session_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const first = Track(
    id: 'ytm:first',
    title: 'First Song',
    artist: 'Artist',
    duration: Duration(minutes: 3));
const second = Track(
    id: 'ytm:second',
    title: 'Second Song',
    artist: 'Artist',
    duration: Duration(minutes: 4));

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

  test('stores queue, progress, manual picks, and playback modes in order',
      () async {
    final store = PlayerSessionStore();
    final older = store.save(const PlayerSession(
        queue: [first], currentIndex: 0, position: Duration(seconds: 1)));
    final latest = store.save(const PlayerSession(
        queue: [first, second],
        currentIndex: 1,
        position: Duration(seconds: 95),
        repeatMode: 2,
        isShuffle: true,
        shuffledIndices: [1, 0],
        manualQueueIds: ['ytm:first']));
    await Future.wait([older, latest]);
    final restored = (await PlayerSessionStore().load())!;
    expect(restored.currentTrack.id, second.id);
    expect(restored.position, const Duration(seconds: 95));
    expect(restored.queue.map((track) => track.id), [first.id, second.id]);
    expect(restored.repeatMode, 2);
    expect(restored.isShuffle, isTrue);
    expect(restored.shuffledIndices, [1, 0]);
    expect(restored.manualQueueIds, [first.id]);
  });

  test('invalid stored data is ignored and progress is clamped', () async {
    SharedPreferences.setMockInitialValues(
        {PlayerSessionStore.storageKey: 'broken json'});
    expect(await PlayerSessionStore().load(), isNull);
    final invalid = const PlayerSession(
            queue: [first], currentIndex: 4, position: Duration.zero)
        .toJson();
    SharedPreferences.setMockInitialValues(
        {PlayerSessionStore.storageKey: jsonEncode(invalid)});
    expect(await PlayerSessionStore().load(), isNull);
    final parsed = PlayerSession.fromJson(const PlayerSession(
        queue: [first],
        currentIndex: 0,
        position: Duration(minutes: 10),
        repeatMode: 99,
        isShuffle: true,
        shuffledIndices: [9]).toJson());
    expect(parsed.position, first.duration);
    expect(parsed.repeatMode, 0);
    expect(parsed.isShuffle, isFalse);
  });

  test('relaunch restores paused player and seeking survives another relaunch',
      () async {
    await PlayerSessionStore().save(const PlayerSession(
        queue: [first, second],
        currentIndex: 1,
        position: Duration(seconds: 95),
        repeatMode: 2,
        manualQueueIds: ['ytm:first']));
    final original = PlayerController.forTesting();
    await original.ensureInitialized();
    expect(original.currentTrack?.id, second.id);
    expect(original.position, const Duration(seconds: 95));
    expect(original.duration, second.duration);
    expect(original.isPlaying, isFalse);
    expect(original.player.audioSource, isNull);
    expect(original.repeatMode, RepeatMode.one);
    expect(original.isManualQueued(first), isTrue);
    // Native idle position events must not reset a restored position to zero.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(original.playbackPosition, const Duration(seconds: 95));
    await original.seek(const Duration(seconds: 120));
    await original.pause();
    original.dispose();
    final relaunched = PlayerController.forTesting();
    await relaunched.ensureInitialized();
    expect(relaunched.currentTrack?.id, second.id);
    expect(relaunched.position, const Duration(seconds: 120));
    expect(relaunched.isPlaying, isFalse);
    expect(relaunched.queue.map((track) => track.id), [first.id, second.id]);
    relaunched.dispose();
  });

  test('upgrade can recover the last track from existing listening history',
      () async {
    await ListeningHistoryController.instance.record(first);
    final player = PlayerController.forTesting();
    await player.ensureInitialized();
    expect(player.currentTrack?.id, first.id);
    expect(player.isPlaying, isFalse);
    expect(player.position, Duration.zero);
    player.dispose();
  });
}
