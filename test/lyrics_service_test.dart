import 'dart:convert';

import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const track =
      Track(id: 'ytm:example', title: 'Example Song', artist: 'Artist');

  test('provider outage falls back to lyrics tied to the YouTube video',
      () async {
    final client = MockClient((request) async {
      if (request.url.host == 'lrclib.net') return http.Response('', 429);
      final body = jsonDecode(request.body) as Map;
      if (request.url.path.endsWith('/next')) {
        expect(body['videoId'], 'example');
        return http.Response(
            jsonEncode({
              'tabRenderer': {
                'endpoint': {
                  'browseEndpoint': {'browseId': 'MPLYtLyrics'}
                },
              }
            }),
            200);
      }
      expect(body['browseId'], 'MPLYtLyrics');
      return http.Response(
          jsonEncode({
            'musicDescriptionShelfRenderer': {
              'description': {
                'runs': [
                  {'text': 'Fallback lyrics'}
                ]
              },
            }
          }),
          200);
    });
    final service = LyricsService(client: client);
    final result = await service.getLyrics(track);
    expect(result?.source, 'YouTube Music');
    expect(result?.plainText, 'Fallback lyrics');
    // The LRCLIB cooldown must not suppress another provider.
    service.clearCachedLyrics(track.id);
    expect((await service.getLyrics(track))?.source, 'YouTube Music');
  });

  test('empty primary lyrics continue to the next provider', () async {
    final service = LyricsService(client: MockClient((request) async {
      if (request.url.host == 'lrclib.net') {
        return http.Response(
            jsonEncode({
              'trackName': 'Example Song',
              'artistName': 'Artist',
              'plainLyrics': '',
              'syncedLyrics': '',
            }),
            200);
      }
      return http.Response(
          jsonEncode(request.url.path.endsWith('/next')
              ? {
                  'tabRenderer': {
                    'endpoint': {
                      'browseEndpoint': {'browseId': 'MPLYtLyrics'}
                    }
                  }
                }
              : {
                  'musicDescriptionShelfRenderer': {
                    'description': {'simpleText': 'Available'}
                  }
                }),
          200);
    }));
    expect((await service.getLyrics(track))?.plainText, 'Available');
  });

  test('synced primary lyrics do not wait for the secondary provider',
      () async {
    final service = LyricsService(client: MockClient((request) async {
      expect(request.url.host, 'lrclib.net');
      return http.Response(
          jsonEncode({
            'trackName': 'Example Song',
            'artistName': 'Artist',
            'syncedLyrics': '[00:01.00]Synced',
          }),
          200);
    }));
    final result = await service.getLyrics(track);
    expect(result?.source, 'LRCLIB');
    expect(result?.syncedLines.single.text, 'Synced');
  });

  test('usable primary text survives failure of the secondary provider',
      () async {
    final service = LyricsService(client: MockClient((request) async {
      if (request.url.host != 'lrclib.net') return http.Response('', 503);
      return http.Response(
          jsonEncode({
            'trackName': 'Example Song',
            'artistName': 'Artist',
            'plainLyrics': 'Keep me',
          }),
          200);
    }));
    expect((await service.getLyrics(track))?.plainText, 'Keep me');
  });

  test('parses timestamps and finds the active synced line', () {
    final lines = LyricsService.parseLrc(
      '[00:01.25]First line\n'
      '[00:04.500][00:08.00]Second line\n'
      '[ar:Example]',
    );
    final lyrics = LyricsData(
      syncedLines: lines,
      plainText: null,
      instrumental: false,
    );

    expect(lines.length, 3);
    expect(lines.first.time, const Duration(milliseconds: 1250));
    expect(lines[1].time, const Duration(milliseconds: 4500));
    expect(lyrics.activeLineAt(const Duration(milliseconds: 500)), -1);
    expect(lyrics.activeLineAt(const Duration(seconds: 5)), 1);
    expect(lyrics.activeLineAt(const Duration(seconds: 9)), 2);
  });

  test('uses a matching record when exact lookup is unavailable', () async {
    final client = MockClient((request) async {
      expect(
        request.headers.entries.any((header) =>
            header.key.toLowerCase() == 'user-agent' &&
            header.value.contains('Cloudio/')),
        isTrue,
      );
      if (request.url.path == '/api/get') {
        return http.Response('', 404);
      }
      return http.Response(
        jsonEncode([
          {
            'trackName': 'Other Song',
            'artistName': 'Bruno Mars',
            'duration': 180,
            'syncedLyrics': '[00:01.00]Wrong',
          },
          {
            'trackName': 'Example Song',
            'artistName': 'Bruno Mars',
            'duration': 181,
            'syncedLyrics': '[00:01.00]Right',
            'plainLyrics': 'Right',
          },
        ]),
        200,
      );
    });
    final service = LyricsService(client: client);
    const track = Track(
      id: 'ytm:example',
      title: 'Example Song',
      artist: 'Bruno Mars',
      duration: Duration(seconds: 180),
    );

    final lyrics = await service.getLyrics(track);

    expect(lyrics?.syncedLines.single.text, 'Right');
    expect(lyrics?.plainText, 'Right');
  });
}
