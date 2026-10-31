import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../services/music_recognition_service.dart';
import 'player_controller.dart';

enum RecognitionPhase {
  ready,
  preparing,
  listening,
  matching,
  noMatch,
  error,
  found
}

class MusicRecognitionController extends ChangeNotifier {
  MusicRecognitionController(
      {AudioRecorder? recorder, MusicRecognitionService? service})
      : _recorder = recorder ?? AudioRecorder(),
        _service = service ?? MusicRecognitionService();
  final AudioRecorder _recorder;
  final MusicRecognitionService _service;
  RecognitionPhase phase = RecognitionPhase.ready;
  String? error;
  RecognizedMusic? result;
  Duration elapsed = Duration.zero;
  Timer? _deadline;
  Timer? _progress;
  StreamSubscription<Uint8List>? _samples;
  BytesBuilder _pcm = BytesBuilder(copy: false);
  bool _disposed = false;
  int _version = 0;

  bool get busy =>
      phase == RecognitionPhase.preparing ||
      phase == RecognitionPhase.listening ||
      phase == RecognitionPhase.matching;

  Future<void> listen(PlayerController player) async {
    if (busy || _disposed) return;
    final version = ++_version;
    error = null;
    result = null;
    phase = RecognitionPhase.preparing;
    notifyListeners();
    try {
      final allowed = await _recorder.hasPermission();
      if (_disposed || version != _version) return;
      if (!allowed) {
        error = 'Izinkan mikrofon di Pengaturan untuk mengenali lagu.';
        phase = RecognitionPhase.error;
        notifyListeners();
        return;
      }
      await player.pause();
      if (_disposed || version != _version) return;
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      if (_disposed || version != _version) {
        await _recorder.cancel();
        return;
      }
      _pcm = BytesBuilder(copy: false);
      elapsed = Duration.zero;
      phase = RecognitionPhase.listening;
      final watch = Stopwatch()..start();
      _samples = stream.listen((chunk) {
        if (phase != RecognitionPhase.listening || _disposed) return;
        final remaining = MusicRecognitionService.maxPcmBytes - _pcm.length;
        _pcm.add(chunk.length <= remaining
            ? chunk
            : Uint8List.sublistView(chunk, 0, remaining));
        if (_pcm.length >= MusicRecognitionService.maxPcmBytes) {
          unawaited(_finish(version));
        }
      },
          onError: (Object _) =>
              unawaited(_fail('Mikrofon terputus. Coba lagi.', version)));
      _progress = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_disposed || version != _version) return;
        elapsed = watch.elapsed;
        notifyListeners();
      });
      _deadline =
          Timer(const Duration(seconds: 12), () => unawaited(_finish(version)));
      notifyListeners();
    } catch (_) {
      await _fail('Mikrofon belum bisa digunakan. Coba lagi.', version);
    }
  }

  Future<void> _stopRecording() async {
    _deadline?.cancel();
    _progress?.cancel();
    _deadline = null;
    _progress = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _samples?.cancel();
    _samples = null;
    if (!kIsWeb) {
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
        await session.setActive(true);
      } catch (_) {}
    }
  }

  Future<void> _finish(int version) async {
    if (_disposed ||
        version != _version ||
        phase != RecognitionPhase.listening) {
      return;
    }
    phase = RecognitionPhase.matching;
    notifyListeners();
    await _stopRecording();
    if (_disposed || version != _version) return;
    final pcm = _pcm.takeBytes();
    try {
      final recognized = await _service.recognizePcm(pcm);
      if (_disposed || version != _version) return;
      result = recognized;
      phase =
          result == null ? RecognitionPhase.noMatch : RecognitionPhase.found;
      notifyListeners();
    } on MusicRecognitionException catch (failure) {
      await _fail(failure.message, version);
    } catch (_) {
      await _fail('Gagal mengenali lagu. Coba lagi.', version);
    }
  }

  Future<void> _fail(String message, int version) async {
    if (_disposed || version != _version) return;
    phase = RecognitionPhase.error;
    error = message;
    await _stopRecording();
    _pcm = BytesBuilder(copy: false);
    if (!_disposed && version == _version) notifyListeners();
  }

  Future<void> cancel() async {
    ++_version;
    await _stopRecording();
    _pcm = BytesBuilder(copy: false);
    if (_disposed) return;
    phase = RecognitionPhase.ready;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_version;
    _deadline?.cancel();
    _progress?.cancel();
    _service.close();
    unawaited(() async {
      await _stopRecording();
      await _recorder.dispose();
    }());
    super.dispose();
  }
}
