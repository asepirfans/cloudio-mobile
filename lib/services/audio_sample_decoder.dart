import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Local platform decoders avoid uploading a TikTok video to another server.
class AudioSampleDecoder {
  static const _channel = MethodChannel('com.cloudiolabs.cloudio/audio_sample');
  static Future<Uint8List> decode(Uint8List media) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
        'decode', {'bytes': media}).timeout(const Duration(seconds: 20));
    if (result == null || result['pcm'] is! Uint8List) {
      throw const FormatException('No decoded audio');
    }
    return compute(resampleRecognitionAudio, result);
  }
}

Uint8List resampleRecognitionAudio(Map<String, dynamic> input) {
  final bytes = input['pcm'] as Uint8List;
  final rate = input['sampleRate'] as int;
  final channels = input['channels'] as int;
  if (rate < 8000 ||
      rate > 192000 ||
      channels < 1 ||
      channels > 8 ||
      bytes.length % (channels * 2) != 0) {
    throw const FormatException('Unsupported PCM format');
  }
  final frames = bytes.length ~/ (channels * 2);
  if (frames == 0) return Uint8List(0);
  final count = math.min(16000 * 12, frames * 16000 ~/ rate);
  final data = ByteData.sublistView(bytes);
  double mono(int frame) {
    var sum = 0;
    for (var c = 0; c < channels; c++) {
      sum += data.getInt16((frame * channels + c) * 2, Endian.little);
    }
    return sum / channels;
  }

  final output = Uint8List(count * 2);
  final out = ByteData.sublistView(output);
  for (var i = 0; i < count; i++) {
    final position = i * rate / 16000;
    final first = position.floor();
    final fraction = position - first;
    final sample = mono(first) * (1 - fraction) +
        mono(math.min(first + 1, frames - 1)) * fraction;
    out.setInt16(i * 2, sample.round().clamp(-32768, 32767), Endian.little);
  }
  return output;
}
