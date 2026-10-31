import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/tiktok_music_matcher.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:flutter_test/flutter_test.dart';

Track track(String id, String title, [String artist = 'JVKE']) =>
    Track(id: id, title: title, artist: artist);

void main() {
  const matcher = TikTokMusicMatcher();
  test('cleans presentation labels while retaining requested music versions',
      () {
    expect(
        matcher
            .queries(const TikTokSong(
                '♬ golden hour (Cello Version) (TikTok viral)',
                artist: 'JVKE'))
            .first,
        'golden hour (Cello Version) JVKE');
    expect(matcher.cleanTitle('DJ Garam & Madu Remix (Sped Up) [Viral TikTok]'),
        'DJ Garam & Madu Remix (Sped Up)');
    expect(matcher.cleanTitle('Beyoncé – Halo (Official Audio)'),
        contains('Halo'));
  });
  test(
      'original recording precedes covers and wrong artists; podcasts excluded',
      () {
    final results =
        matcher.rank(const TikTokSong('golden hour', artist: 'JVKE'), [
      track('cover', 'golden hour (cover)', 'Someone'),
      track('wrongArtist', 'golden hour', 'Another Artist'),
      track('podcast', 'golden hour podcast'),
      track('original', 'JVKE - golden hour (Official Audio)'),
      track('ytm:original', 'golden hour'),
      track('other', 'another song'),
    ]);
    expect(results.first.cleanVideoId, 'original');
    expect(results.where((t) => t.cleanVideoId == 'original').length, 1);
    expect(results.map((t) => t.id), isNot(contains('podcast')));
    expect(results.map((t) => t.id), isNot(contains('other')));
  });
  test('cellos, remixes and sped up retain their preferred versions', () {
    for (final version in ['Cello Version', 'Remix', 'Sped Up']) {
      final song = TikTokSong('golden hour ($version)', artist: 'JVKE');
      expect(
          matcher
              .rank(song, [
                track('original', 'golden hour'),
                track('version', 'golden hour ($version)')
              ])
              .first
              .id,
          'version');
    }
  });
  test('Unicode song titles are matched without collapsing to empty tokens',
      () {
    expect(
        matcher.rank(const TikTokSong('夜に駆ける', artist: 'YOASOBI'), [
          track('wrong', '別の曲', 'YOASOBI'),
          track('right', '夜に駆ける', 'YOASOBI'),
        ]).map((t) => t.id),
        ['right']);
  });
  test('retries weaker queries and ranks merged results', () async {
    final queries = <String>[];
    final results = await matcher
        .search(const TikTokSong('golden hour', artist: 'JVKE'), (query) async {
      queries.add(query);
      return query == 'golden hour JVKE'
          ? [track('cover', 'golden hour (cover)', 'Someone')]
          : [track('original', 'golden hour')];
    });
    expect(queries, ['golden hour JVKE', 'golden hour']);
    expect(results.first.id, 'original');
  });
  test('stops extra searches after a strong match or an obsolete request',
      () async {
    var calls = 0;
    await matcher.search(const TikTokSong('golden hour', artist: 'JVKE'),
        (_) async {
      calls++;
      return [track('exact', 'golden hour')];
    });
    expect(calls, 1);
    var current = true;
    await matcher.search(const TikTokSong('golden hour', artist: 'JVKE'),
        (_) async {
      calls++;
      current = false;
      return [];
    }, isCurrent: () => current);
    expect(calls, 2);
  });
}
