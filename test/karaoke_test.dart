import 'dart:convert';

import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/karaoke_metadata.dart';
import 'package:cloudio_mobile/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('karaoke selection rejects vocal guides and ordinary song uploads', () {
    for (final title in [
      'Perfect (Karaoke Version)',
      'Perfect - no vocals',
      'Perfect backing track'
    ]) {
      expect(KaraokeMetadata.isKaraoke(title), isTrue);
    }
    for (final title in [
      'Perfect official audio',
      'Perfect karaoke with vocals',
      'Perfect karaoke guide vocals'
    ]) {
      expect(KaraokeMetadata.isKaraoke(title), isFalse);
    }
    expect(
        KaraokeMetadata.songQuery(
            'Adele - Someone Like You (Karaoke Version) [Lower Key]'),
        'Adele - Someone Like You');
  });

  test(
      'karaoke track source and lyric search hint survive playlist/session save',
      () {
    const track = Track(
        id: 'ytm:karaoke',
        title: 'Perfect karaoke',
        artist: 'Uploader',
        isKaraoke: true,
        karaokeQuery: 'Perfect Ed Sheeran');
    final restored = Track.fromJson(track.toJson());
    expect(restored.isKaraoke, isTrue);
    expect(
        restored.copyWith(title: 'Edited').karaokeQuery, 'Perfect Ed Sheeran');
    expect(
        Track.fromJson({'id': 'old', 'title': 'Old', 'artist': 'Artist'})
            .isKaraoke,
        isFalse);
  });

  test(
      'karaoke lyrics resolve the original song, ignore instrumental and support auto sync',
      () async {
    var calls = 0;
    final service = LyricsService(client: MockClient((request) async {
      calls++;
      expect(request.url.host, 'lrclib.net');
      expect(request.url.path, '/api/search');
      expect(request.url.queryParameters['q'], 'Adele - Someone Like You');
      return http.Response(
          jsonEncode([
            {
              'trackName': 'Someone Like You',
              'artistName': 'Other Artist',
              'plainLyrics': 'Wrong'
            },
            {
              'trackName': 'Someone Like You',
              'artistName': 'Adele',
              'instrumental': true
            },
            {
              'trackName': 'Someone Like You',
              'artistName': 'Adele',
              'duration': 285,
              'syncedLyrics': '[00:10.00]First line\n[00:20.00]Second line'
            },
          ]),
          200);
    }));
    const track = Track(
        id: 'ytm:karaoke',
        title: 'Adele - Someone Like You (Karaoke Version)',
        artist: 'Sing King',
        isKaraoke: true,
        karaokeQuery: 'Someone Like You Adele',
        duration: Duration(seconds: 310));
    final lyrics = await service.getLyrics(track);
    expect(lyrics?.plainText, 'First line\nSecond line');
    expect(lyrics?.syncedLines, isNotEmpty);
    expect(lyrics?.syncedLines.length, 2);
    expect(lyrics?.syncedLines.first.text, 'First line');
    expect(lyrics?.syncedLines.first.time, const Duration(seconds: 10));
    expect(lyrics?.instrumental, isFalse);
    expect(lyrics?.source, contains('Karaoke otomatis'));
    await service.getLyrics(track);
    expect(calls, 1);
  });

  test('ambiguous song title cannot select an unrelated artist automatically',
      () async {
    final service = LyricsService(
        client: MockClient((request) async => http.Response(
            jsonEncode([
              {
                'trackName': 'Perfect',
                'artistName': 'Wrong Artist',
                'plainLyrics': 'Wrong'
              },
            ]),
            200)));
    expect(
        await service.getLyrics(const Track(
            id: 'ytm:x',
            title: 'Perfect (Karaoke)',
            artist: 'Karaoke Channel',
            isKaraoke: true)),
        isNull);
  });
}
