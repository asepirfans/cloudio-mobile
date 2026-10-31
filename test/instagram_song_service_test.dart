import 'dart:convert';

import 'package:cloudio_mobile/services/instagram_song_service.dart';
import 'package:cloudio_mobile/services/social_song_service.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String instagramPage(
        {String code = 'Abc_123', String? url, bool original = false}) =>
    '<script type="application/json">${jsonEncode({
          'require': [
            {
              '__bbox': {
                'result': {
                  'data': {
                    'shortcode_media': {
                      'shortcode': code,
                      'video_url':
                          url ?? 'https://video.cdninstagram.com/clip.mp4',
                      'clips_metadata': {
                        'audio_type':
                            original ? 'original_sounds' : 'licensed_music',
                        'music_info': {
                          'music_asset_info': {
                            'title': 'Golden Hour',
                            'display_artist': 'JVKE'
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          ]
        })}</script>';

void main() {
  test('accepts shared Reels/posts and strips tracking, not lookalike hosts',
      () {
    expect(
        InstagramSongService.extractLink(
                'Lihat (https://www.instagram.com/reel/Abc_123/?igsh=secret).')
            ?.toString(),
        'https://www.instagram.com/reel/Abc_123/');
    for (final path in [
      'reels/Abc_123',
      'p/Abc_123',
      'tv/Abc_123',
      'share/reel/abc'
    ]) {
      expect(InstagramSongService.extractLink('https://instagram.com/$path/'),
          isNotNull);
    }
    for (final url in [
      'https://instagram.com.evil.test/reel/Abc_123/',
      'https://evil.test/instagram.com/reel/Abc_123/',
      'https://instagram.com:444/reel/Abc_123/',
      'https://instagram.com/profile/',
      'https://instagram.com/stories/person/123/',
      'https://instagram.com/reels/audio/123/',
    ]) {
      expect(InstagramSongService.extractLink(url), isNull, reason: url);
    }
  });

  test('reads exact shortcode Relay media and licensed music only', () {
    final service = InstagramSongService();
    addTearDown(service.close);
    final post = service.parsePost(instagramPage(), 'Abc_123');
    expect(post.media.single.host, 'video.cdninstagram.com');
    expect(post.song?.query, 'Golden Hour JVKE');
    expect(post.song?.isHint, isFalse);
    expect(service.parsePost(instagramPage(original: true), 'Abc_123').song,
        isNull);
    expect(service.parsePost(instagramPage(code: 'Other'), 'Abc_123').media,
        isEmpty);
    expect(service.parsePost(instagramPage(code: 'Other'), 'Abc_123').song,
        isNull);
    expect(
        service
            .parsePost(
                instagramPage(url: 'https://fbcdn.net.evil.test/a'), 'Abc_123')
            .media,
        isEmpty);
  });

  test(
      'current public product payload supports video_versions without captions as titles',
      () {
    final service = InstagramSongService();
    addTearDown(service.close);
    final html = '<script data-sjs>${jsonEncode({
          'require': [
            {
              '__bbox': {
                'result': {
                  'data': {
                    'xig_polaris_media': {
                      'if_not_gated_logged_out': {
                        'code': 'Abc_123',
                        'video_versions': [
                          {'url': 'https://video.fbcdn.net/video.mp4'}
                        ],
                        'caption': {'text': 'Great music from another artist'},
                      }
                    }
                  }
                }
              }
            }
          ]
        })}</script>';
    final post = service.parsePost(html, 'Abc_123');
    expect(post.media.single.host, 'video.fbcdn.net');
    expect(post.song, isNull);
  });

  test('OpenGraph needs a matching canonical post and a trusted media host',
      () {
    final service = InstagramSongService();
    addTearDown(service.close);
    const html =
        '<meta property="og:url" content="https://www.instagram.com/reel/Abc_123/">'
        '<meta content="https://video.fbcdn.net/a.mp4?x=1&amp;y=2" property="og:video">'
        '<meta property="og:description" content="An arbitrary caption is not a song">';
    final result = service.parsePost(html, 'Abc_123');
    expect(result.media.single.queryParameters, {'x': '1', 'y': '2'});
    expect(result.song, isNull);
    expect(service.parsePost(html, 'Other').media, isEmpty);
    expect(
        service
            .parsePost(html.replaceAll('og:url', 'og:title'), 'Abc_123')
            .media,
        isEmpty);
  });

  test('embed fallback resolves the same post and metadata reuses its response',
      () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return request.url.path.endsWith('/embed/')
          ? http.Response(instagramPage(), 200)
          : http.Response('', 403);
    });
    final service = SocialSongService(client: client);
    addTearDown(service.close);
    const url = 'https://instagram.com/reel/Abc_123/';
    expect(await service.resolveMedia(url), hasLength(1));
    expect((await service.resolveSong(url)).artist, 'JVKE');
    expect(paths, ['/reel/Abc_123/', '/p/Abc_123/embed/']);
    service.clearMediaCache();
    await service.resolveMedia(url);
    expect(paths, hasLength(4));
  });

  test('Instagram share redirects bind to the resolved post', () async {
    final service = InstagramSongService(client: MockClient((request) async {
      if (request.url.path.startsWith('/share/')) {
        return http.Response('', 302, headers: {'location': '/reel/Abc_123/'});
      }
      return http.Response(instagramPage(), 200);
    }));
    addTearDown(service.close);
    expect(
        (await service.resolvePost('https://instagram.com/share/reel/xyz/'))
            .media,
        hasLength(1));
  });

  test('login, foreign and different-post redirects never contribute audio',
      () async {
    for (final target in [
      'https://instagram.com/accounts/login/',
      'https://evil.test/reel/Abc_123/',
      'https://instagram.com/reel/Other/',
    ]) {
      final visited = <Uri>[];
      final service = InstagramSongService(client: MockClient((request) async {
        visited.add(request.url);
        return request.url.path.contains('Other')
            ? http.Response(instagramPage(code: 'Other'), 200)
            : http.Response('', 302, headers: {'location': target});
      }));
      addTearDown(service.close);
      await expectLater(
          service.resolvePost('https://instagram.com/reel/Abc_123/'),
          throwsA(isA<TikTokSongException>()));
      expect(
          visited.any((uri) =>
              uri.host == 'evil.test' || uri.path.contains('/accounts/')),
          isFalse);
    }
  });
}
