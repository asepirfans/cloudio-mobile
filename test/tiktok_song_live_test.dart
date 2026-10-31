import 'package:cloudio_mobile/services/music_service.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:cloudio_mobile/services/tiktok_music_matcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared original sound finds the correct cello recording', () async {
    final service = TikTokSongService();
    addTearDown(service.close);
    addTearDown(MusicService.instance.dispose);
    final song = await service.resolve('https://vt.tiktok.com/ZSbwo7d1r/');
    expect(song.title.toLowerCase(), contains('golden hour'));
    expect(song.title.toLowerCase(), contains('cello'));
    expect(song.artist, 'JVKE');
    final results = await const TikTokMusicMatcher()
        .search(song, (query) => MusicService.instance.search(query));
    expect(results, isNotEmpty);
    expect(results.first.title.toLowerCase(), contains('cello'));
    expect(const TikTokMusicMatcher().score(song, results.first),
        greaterThanOrEqualTo(0.95));
    debugPrint(
        'Resolved ${song.query}; best match: ${results.first.title} — ${results.first.artist}');
  },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: !const bool.fromEnvironment('CLOUDIO_LIVE_TIKTOK_TEST'));
}
