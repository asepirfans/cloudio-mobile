import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/lyrics_service.dart';

void main() {
  const testTrack = Track(
    id: 'kugou_test_1',
    title: 'Dan',
    artist: 'Sheila On 7',
    duration: Duration(seconds: 288),
  );

  test('LyricsService falls back to Kugou when LRCLIB has no lyrics', () async {
    final client = MockClient((request) async {
      // LRCLIB returns 404
      if (request.url.host == 'lrclib.net') {
        return http.Response('', 404);
      }
      // Kugou search
      if (request.url.host == 'mobilecdn.kugou.com') {
        return http.Response(
          jsonEncode({
            'status': 1,
            'errcode': 0,
            'data': {
              'info': [
                {
                  'songname': 'Dan... (Album Version)',
                  'singername': 'sheila on 7',
                  'duration': 288,
                  'hash': 'mock_kugou_hash_123',
                }
              ]
            }
          }),
          200,
        );
      }
      // Kugou lyric download
      if (request.url.host == 'm.kugou.com') {
        return http.Response(
          '[00:00.00]Dan... - Sheila On 7\n'
          '[00:16.50]Dan\n'
          '[00:19.80]Dan bila esok datang kembali\n'
          '[00:27.20]Seperti sedia kala\n',
          200,
        );
      }
      return http.Response('', 404);
    });

    final service = LyricsService(client: client);
    final lyrics = await service.getLyrics(testTrack);

    expect(lyrics, isNotNull);
    expect(lyrics!.source, 'Kugou Music');
    expect(lyrics.syncedLines.length, 4);
    expect(lyrics.syncedLines[1].text, 'Dan');
    expect(lyrics.syncedLines[1].time, const Duration(seconds: 16, milliseconds: 500));
    expect(lyrics.syncedLines[2].text, 'Dan bila esok datang kembali');
  });
}
