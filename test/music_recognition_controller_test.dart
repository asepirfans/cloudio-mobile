import 'dart:async';
import 'package:cloudio_mobile/controllers/music_recognition_controller.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/services/music_recognition_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player_autoplay_test.dart' as fixture;

class FakeRecorder extends AudioRecorder {
  bool allowed = true;
  int starts = 0;
  int permissionRequests = 0;
  Future<bool>? permission;
  final samples = StreamController<Uint8List>.broadcast();
  @override
  Future<bool> hasPermission() async {
    permissionRequests++;
    return permission ?? allowed;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    starts++;
    expect(config.sampleRate, 16000);
    expect(config.encoder, AudioEncoder.pcm16bits);
    return samples.stream;
  }

  @override
  Future<String?> stop() async => null;
  @override
  Future<void> dispose() async => samples.close();
}

class FakeRecognizer extends MusicRecognitionService {
  int calls = 0;
  Future<RecognizedMusic?>? response;
  @override
  Future<RecognizedMusic?> recognizePcm(Uint8List data) async {
    calls++;
    expect(data.length, lessThanOrEqualTo(MusicRecognitionService.maxPcmBytes));
    return response ?? const RecognizedMusic(title: 'Song', artist: 'Artist');
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
  PlayerController player(fixture.CompletionPlayer native) {
    final controller = PlayerController.forTesting(
        player: native,
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => []);
    addTearDown(controller.dispose);
    return controller;
  }

  test(
      'construction never records; denied permission does not interrupt playback',
      () async {
    final native = fixture.CompletionPlayer();
    final playback = player(native);
    await playback.playTrack(fixture.first, newQueue: [fixture.first]);
    final recorder = FakeRecorder()..allowed = false;
    final recognition = MusicRecognitionController(
        recorder: recorder, service: FakeRecognizer());
    addTearDown(recognition.dispose);
    expect(recorder.permissionRequests, 0);
    expect(recorder.starts, 0);
    await recognition.listen(playback);
    expect(recorder.starts, 0);
    expect(native.playing, isTrue);
    expect(recognition.phase, RecognitionPhase.error);
  });
  test(
      'explicit listening pauses own music and recognizes a bounded microphone sample',
      () async {
    final native = fixture.CompletionPlayer();
    final playback = player(native);
    await playback.playTrack(fixture.first, newQueue: [fixture.first]);
    final recorder = FakeRecorder();
    final service = FakeRecognizer();
    final recognition =
        MusicRecognitionController(recorder: recorder, service: service);
    addTearDown(recognition.dispose);
    await recognition.listen(playback);
    expect(native.playing, isFalse);
    recorder.samples.add(Uint8List(MusicRecognitionService.maxPcmBytes + 100));
    await fixture.until(() => recognition.phase == RecognitionPhase.found);
    expect(recognition.result?.title, 'Song');
    expect(service.calls, 1);
  });
  test(
      'cancelling during permission or matching never resumes recording or publishes a stale result',
      () async {
    final playback = player(fixture.CompletionPlayer());
    await playback.ensureInitialized();
    final granted = Completer<bool>();
    final recorder = FakeRecorder()..permission = granted.future;
    final pending = Completer<RecognizedMusic?>();
    final service = FakeRecognizer()..response = pending.future;
    final recognition =
        MusicRecognitionController(recorder: recorder, service: service);
    addTearDown(recognition.dispose);
    final starting = recognition.listen(playback);
    await recognition.cancel();
    granted.complete(true);
    await starting;
    expect(recorder.starts, 0);
    recorder.permission = null;
    await recognition.listen(playback);
    recorder.samples.add(Uint8List(MusicRecognitionService.maxPcmBytes));
    await fixture.until(() => service.calls == 1);
    await recognition.cancel();
    pending.complete(const RecognizedMusic(title: 'Late', artist: 'Old'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recognition.result, isNull);
    expect(recognition.phase, RecognitionPhase.ready);
  });
}
