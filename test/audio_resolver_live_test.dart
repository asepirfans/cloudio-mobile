import 'package:cloudio_mobile/services/audio_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('actual iOS audio bytes for music and DJ', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(AudioResolverService.instance.dispose);
    for (final id in ['K3ahuED9v88', '8NXfWci2muY']) {
      final url = await AudioResolverService.instance.resolveStreamUrl(id);
      final response = await http.get(Uri.parse(url), headers: {
        'Range': 'bytes=0-1023'
      }).timeout(const Duration(seconds: 10));
      debugPrint(
          'video=$id status=${response.statusCode} bytes=${response.bodyBytes.length} type=${response.headers['content-type']}');
      expect(response.statusCode, anyOf(200, 206));
      expect(response.bodyBytes.length, greaterThan(0));
      expect(response.headers['content-type'], contains('audio'));
    }
  },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: !const bool.fromEnvironment('CLOUDIO_LIVE_STREAM_TEST'));
}
