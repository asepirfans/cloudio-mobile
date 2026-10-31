import 'dart:io';
import 'package:cloudio_mobile/services/music_recognition_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const path = String.fromEnvironment('CLOUDIO_RECOGNITION_FIXTURE');
  test(
      'production matcher recognizes a known decoded sample without an API key',
      () async {
    final service = MusicRecognitionService();
    addTearDown(service.close);
    final pcm = await File(path).readAsBytes();
    final result = await service.recognizePcm(pcm);
    expect(result?.title.toLowerCase(), contains('i will survive'));
    expect(result?.artist.toLowerCase(), contains('gloria gaynor'));
    debugPrint('Recognized ${result!.title} — ${result.artist}');
  }, skip: path.isEmpty, timeout: const Timeout(Duration(seconds: 30)));
}
