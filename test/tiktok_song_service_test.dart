import 'dart:convert';

import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const videoUrl = 'https://www.tiktok.com/@creator/video/123456789';

http.Response jsonResponse(dynamic data) => http.Response(jsonEncode(data), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

String musicPage(Map<String, dynamic> music) =>
    '<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">'
    '${jsonEncode({
          '__DEFAULT_SCOPE__': {
            'webapp.video-detail': {
              'itemInfo': {
                'itemStruct': {'id': '123456789', 'music': music}
              },
            }
          }
        })}</script>';

void main() {
  test('extracts links from share text and rejects lookalike hosts', () {
    expect(
        TikTokSongService.extractLink('Lihat ini (https://vt.tiktok.com/Abc/).')
            ?.host,
        'vt.tiktok.com');
    expect(
        TikTokSongService.extractLink(
            'https://www.tiktok.com.evil.test/video/123'),
        isNull);
    expect(
        TikTokSongService.extractLink('https://evil.test/tiktok.com/video/123'),
        isNull);
    expect(TikTokSongService.extractLink('lagu viral tiktok'), isNull);
  });

  test('resolves short links and reads only the sound anchor, not the caption',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.host == 'vt.tiktok.com') {
        expect(request.followRedirects, isFalse);
        return http.Response('', 302, headers: {'location': videoUrl});
      }
      if (request.url.path != '/oembed') return http.Response('', 403);
      expect(request.url.path, '/oembed');
      expect(request.url.queryParameters['url'], videoUrl);
      return jsonResponse({
        'title': 'Arbitrary caption',
        'html': '<a href="https://www.tiktok.com/@creator">Creator</a>'
            '<a title="♬ Garam &amp; Madu - Tenxi" href="https://www.tiktok.com/music/song-1">sound</a>'
      });
    }));
    addTearDown(service.close);
    final song = await service.resolve('https://vt.tiktok.com/Abc/');
    expect(song.query, 'Garam & Madu - Tenxi');
  });

  test('photo share resolves through video-form oEmbed for the same post ID',
      () async {
    const photo =
        'https://www.tiktok.com/@yesaakundua/photo/7692640922059918610';
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.host == 'vt.tiktok.com') {
        return http.Response('', 302, headers: {'location': photo});
      }
      if (request.url.path == '/oembed') {
        expect(request.url.queryParameters['url'],
            photo.replaceFirst('/photo/', '/video/'));
        return jsonResponse({
          'html':
              '<a title="♬ Test Song" href="https://www.tiktok.com/music/test-123">Test Song</a>'
        });
      }
      return http.Response('', 403);
    }));
    addTearDown(service.close);
    expect((await service.resolve('https://vt.tiktok.com/ZSg6kvyRp/')).title,
        'Test Song');
  });

  test('original sound on a photo gives an audio recognition explanation',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') {
        return jsonResponse({
          'html':
              '<a title="♬ suara asli - Hanif" href="https://www.tiktok.com/music/suara-asli-Hanif-7654494865204185863">sound</a>'
        });
      }
      return http.Response('', 403);
    }));
    addTearDown(service.close);
    await expectLater(
        service.resolve(
            'https://www.tiktok.com/@yesaakundua/photo/7692640922059918610'),
        throwsA(isA<TikTokSongException>().having(
            (e) => e.message, 'explanation', contains('pengenalan audio'))));
  });

  test('falls back to the requested video metadata when oEmbed fails',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') return http.Response('', 403);
      return http.Response(
          musicPage({'title': 'Lagu Baru', 'authorName': 'Musisi'}), 200);
    }));
    addTearDown(service.close);
    expect((await service.resolve(videoUrl)).query, 'Lagu Baru Musisi');
  });

  test('trailing slash and tracking do not hide the requested post metadata',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') return http.Response('', 403);
      return http.Response(
          musicPage({'title': 'Lagu Baru', 'authorName': 'Musisi'}), 200);
    }));
    addTearDown(service.close);
    expect((await service.resolve('$videoUrl/?share=abc')).query,
        'Lagu Baru Musisi');
  });

  test('original sound can resolve via public Apple song IDs without tokens',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') return http.Response('', 403);
      if (request.url.host == 'itunes.apple.com') {
        expect(request.url.queryParameters['id'], '1680872835');
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.url.toString().contains('unused-token'), isFalse);
        return jsonResponse({
          'results': [
            {
              'kind': 'song',
              'trackName': 'golden hour (Cello Version)',
              'artistName': 'JVKE'
            }
          ]
        });
      }
      return http.Response(
          musicPage({
            'title': 'original sound - Creator',
            'original': true,
            'tt2dsp': {
              'tt_to_dsp_song_infos': [
                {
                  'Platform': 1,
                  'SongId': '1680872835',
                  'Token': {
                    'AppleMusicToken': {'DeveloperToken': 'unused-token'}
                  }
                }
              ]
            },
          }),
          200);
    }));
    addTearDown(service.close);
    expect((await service.resolve(videoUrl)).query,
        'golden hour (Cello Version) JVKE');
  });

  test('falls back to a public Spotify track reference', () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.host == 'open.spotify.com') {
        expect(request.url.queryParameters['url'],
            'https://open.spotify.com/track/3eNP9IPBwoMjXHSMB2tHct');
        return jsonResponse({'title': 'golden hour (Cello Version)'});
      }
      if (request.url.path == '/oembed') {
        return jsonResponse({
          'html':
              '<a href="https://www.tiktok.com/music/original-1">♬ original sound - Creator</a>'
        });
      }
      return http.Response(
          musicPage({
            'title': 'original sound - Creator',
            'tt2dsp': {
              'tt_to_dsp_song_infos': [
                {'Platform': 3, 'SongId': '3eNP9IPBwoMjXHSMB2tHct'}
              ]
            },
          }),
          200);
    }));
    addTearDown(service.close);
    expect(
        (await service.resolve(videoUrl)).title, 'golden hour (Cello Version)');
  });

  test('unknown original sounds never become caption or creator searches',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') {
        return jsonResponse({
          'title': 'Famous Song Caption',
          'html':
              '<a href="https://www.tiktok.com/music/original-1">♬ original sound - Creator</a>'
        });
      }
      return http.Response(
          '${musicPage({'title': 'original sound - Creator'})}'
          '<script id="recommendations">{"music":{"title":"Wrong Song"}}</script>',
          200);
    }));
    addTearDown(service.close);
    await expectLater(
        service.resolve(videoUrl), throwsA(isA<TikTokSongException>()));
  });

  test('rejects redirects outside TikTok and unsupported profile links',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      expect(request.url.host, anyOf('vt.tiktok.com', 'www.tiktok.com'));
      return http.Response('', 302,
          headers: {'location': 'https://example.com/video/1'});
    }));
    addTearDown(service.close);
    await expectLater(service.resolve('https://vt.tiktok.com/Abc/'),
        throwsA(isA<TikTokSongException>()));
    await expectLater(service.resolve('https://www.tiktok.com/@creator'),
        throwsA(isA<TikTokSongException>()));
  });
  test('page song identity overrides an incomplete embed and creator label',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') {
        return jsonResponse({
          'html':
              '<a href="https://www.tiktok.com/music/creator-label-1">Creator Label</a>'
        });
      }
      if (request.url.host == 'itunes.apple.com') {
        return jsonResponse({
          'results': [
            {'kind': 'song', 'trackName': 'golden hour', 'artistName': 'JVKE'}
          ]
        });
      }
      return http.Response(
          musicPage({
            'title': 'Chill vibe',
            'original': true,
            'authorName': 'Uploader',
            'tt2dsp': {
              'tt_to_dsp_song_infos': [
                {'Platform': 1, 'SongId': '1680872835'}
              ]
            }
          }),
          200);
    }));
    addTearDown(service.close);
    expect((await service.resolve(videoUrl)).query, 'golden hour JVKE');
  });

  test('repeated and simultaneous pastes share successful metadata lookups',
      () async {
    var calls = 0;
    final service = TikTokSongService(client: MockClient((request) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return request.url.path == '/oembed'
          ? http.Response('', 403)
          : http.Response(
              musicPage({'title': 'Song', 'authorName': 'Artist'}), 200);
    }));
    addTearDown(service.close);
    final songs = await Future.wait(
        [service.resolve(videoUrl), service.resolve('$videoUrl?share=123')]);
    expect(songs.map((song) => song.query), ['Song Artist', 'Song Artist']);
    await service.resolve(videoUrl);
    expect(calls, 2);
  });

  test('explicit caption clues are labeled tentative', () async {
    final page = musicPage({'title': 'original sound - Creator'}).replaceAll(
        '"id":"123456789"',
        '"id":"123456789","desc":"Judul lagu: Garam dan Madu #viral"');
    final service = TikTokSongService(
        client: MockClient((request) async => request.url.path == '/oembed'
            ? http.Response('', 403)
            : http.Response(page, 200)));
    addTearDown(service.close);
    final song = await service.resolve(videoUrl);
    expect(song.title, 'Garam dan Madu');
    expect(song.isHint, isTrue);
  });

  test(
      'rejects metadata for a different video or music nested in recommendations',
      () async {
    for (final page in [
      musicPage({'title': 'Wrong Song'})
          .replaceAll('"id":"123456789"', '"id":"999999999"'),
      musicPage({'title': 'original sound - Creator'}).replaceAll(
          '"id":"123456789"',
          '"id":"123456789","recommended":{"music":{"title":"Wrong Song"}}'),
    ]) {
      final service = TikTokSongService(
          client: MockClient((request) async => request.url.path == '/oembed'
              ? http.Response('', 403)
              : http.Response(page, 200)));
      try {
        await expectLater(
            service.resolve(videoUrl), throwsA(isA<TikTokSongException>()));
      } finally {
        service.close();
      }
    }
  });

  test('original embed sound can use its dedicated music page identity',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') {
        return jsonResponse({
          'html':
              '<a href="https://www.tiktok.com/music/original-77">original sound</a>'
        });
      }
      if (request.url.path.startsWith('/music/')) {
        return http.Response(
            '<script id="SIGI_STATE">${jsonEncode({
                  'MusicModule': {
                    '77': {'id': '77', 'title': 'Song', 'authorName': 'Artist'}
                  }
                })}</script>',
            200);
      }
      return http.Response('', 403);
    }));
    addTearDown(service.close);
    expect((await service.resolve(videoUrl)).query, 'Song Artist');
  });
  test('linked base recording retains the sped up sound version clue',
      () async {
    final service = TikTokSongService(client: MockClient((request) async {
      if (request.url.path == '/oembed') return http.Response('', 403);
      if (request.url.host == 'itunes.apple.com') {
        return jsonResponse({
          'results': [
            {'kind': 'song', 'trackName': 'golden hour', 'artistName': 'JVKE'}
          ]
        });
      }
      return http.Response(
          musicPage({
            'title': 'golden hour (sped up)',
            'original': true,
            'tt2dsp': {
              'tt_to_dsp_song_infos': [
                {'Platform': 1, 'SongId': '1680872835'}
              ]
            }
          }),
          200);
    }));
    addTearDown(service.close);
    expect(
        (await service.resolve(videoUrl)).query, 'golden hour (Sped Up) JVKE');
  });
}
