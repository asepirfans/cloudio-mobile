import 'dart:convert';

import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/tiktok_sound_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const postUrl = 'https://www.tiktok.com/@creator/video/123/';
String page(
        {String id = '123',
        bool video = true,
        Map<String, dynamic> music = const {}}) =>
    '<script id="SIGI_STATE">${jsonEncode({
          'ItemModule': {
            id: {
              'id': id,
              'author': {'uniqueId': 'creator'},
              'music': {
                'title': 'Original sound - Creator (Slowed)',
                'playUrl': 'https://sample.tiktokcdn.com/full-song.mp3',
                ...music,
              },
              if (video)
                'video': {
                  'duration': 13,
                  'playAddr': 'https://sample.tiktokcdn.com/denied.mp4',
                  'bitrateInfo': [
                    {
                      'PlayAddr': {
                        'UrlList': ['https://sample.tiktokcdn.com/actual.mp4']
                      }
                    },
                  ]
                }
            }
          }
        })}</script>';

void main() {
  test('separate original audio requires matching creator and post duration',
      () {
    final service = TikTokSoundService();
    addTearDown(service.close);
    const music = {'original': true, 'authorName': 'creator', 'duration': 13};
    final sound = service.parse(page(music: music), '123', Uri.parse(postUrl))!;
    expect(sound.media.first.path, '/full-song.mp3');
    expect(sound.audioOnlyMedia.single, sound.media.first);
    for (final changed in [
      {'original': false},
      {'authorName': 'someone else'},
      {'authorName': ''},
      {'duration': 60},
      {'duration': 0},
    ]) {
      final rejected = service.parse(
          page(music: {...music, ...changed}), '123', Uri.parse(postUrl))!;
      expect(rejected.audioOnlyMedia, isEmpty);
      expect(
          rejected.media.any((uri) => uri.path == '/full-song.mp3'), isFalse);
    }
  });
  test(
      'preserves exact post sound, creator, source and version across save/reload',
      () {
    final service = TikTokSoundService();
    addTearDown(service.close);
    final sound = service.parse(page(), '123', Uri.parse(postUrl))!;
    expect(sound.media.map((uri) => uri.path), ['/denied.mp4', '/actual.mp4']);
    expect(sound.media.any((uri) => uri.path == '/full-song.mp3'), isFalse);
    final track = Track.fromJson(sound.track.toJson());
    expect(track.provider, 'tiktok');
    expect(track.sourceUrl, postUrl);
    expect(track.displayTitle, 'Original sound - Creator (Slowed)');
    expect(track.displayArtist, '@creator');
    expect(track.duration, const Duration(seconds: 13));
    expect(track.copyWith(title: 'Edited').sourceUrl, postUrl);
    expect(service.parse(page(id: '999'), '123', Uri.parse(postUrl)), isNull);
    expect(
        service.parse(page(video: false), '123', Uri.parse(postUrl)), isNull);
  });

  test('skips blocked CDN and HTML impostors; probes only post media',
      () async {
    final visited = <String>[];
    final service = TikTokSoundService(client: MockClient((request) async {
      visited.add(request.url.path);
      if (request.url.host == 'vt.tiktok.com') {
        return http.Response('', 302, headers: {'location': postUrl});
      }
      if (request.url.host == 'www.tiktok.com') {
        return http.Response(page(), 200);
      }
      expect(request.headers['referer'], 'https://www.tiktok.com/');
      expect(request.headers['range'], 'bytes=0-1023');
      if (request.url.path == '/denied.mp4') {
        return http.Response('<html>denied</html>', 200);
      }
      return http.Response.bytes(
          [0, 0, 0, 32, 102, 116, 121, 112, 105, 115, 111, 109], 206);
    }));
    addTearDown(service.close);
    final sound = await service.resolve('https://vt.tiktok.com/share/');
    expect(await service.playbackUrl(sound.track), endsWith('/actual.mp4'));
    expect(visited, isNot(contains('/full-song.mp3')));
    expect(visited.where((path) => path == '/denied.mp4'), hasLength(1));
  });

  test('rejects different posts and CDN redirects outside TikTok', () async {
    final visited = <String>[];
    final service = TikTokSoundService(client: MockClient((request) async {
      visited.add(request.url.host);
      if (request.url.host == 'www.tiktok.com') {
        return http.Response(page(), 200);
      }
      return http.Response('', 302,
          headers: {'location': 'https://evil.test/audio'});
    }));
    addTearDown(service.close);
    final sound = await service.resolve(postUrl);
    await expectLater(
        service.playbackUrl(sound.track), throwsA(isA<Exception>()));
    expect(visited, isNot(contains('evil.test')));
  });
}
