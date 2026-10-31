import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudio_mobile/services/music_recognition_service.dart';
import 'package:cloudio_mobile/services/audio_sample_decoder.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'instagram_song_service_test.dart' show instagramPage;

Uint8List pcm([int seconds = 1]) => Uint8List(32000 * seconds);
Map<String, Object> match({bool found = true}) => {
      'matches': found ? [{}] : [],
      'track': {
        'title': 'Güneş',
        'subtitle': 'Artist',
        'images': {'coverart': 'https://example.test/art.jpg'}
      },
    };
String post(
        {String id = '123',
        String audio = 'https://sample.tiktokcdn.com/music.mp3'}) =>
    '<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__">${jsonEncode({
          '__DEFAULT_SCOPE__': {
            'webapp.video-detail': {
              'itemInfo': {
                'itemStruct': {
                  'id': id,
                  'music': {'playUrl': audio}
                }
              }
            }
          }
        })}</script>';

void main() {
  test(
      'only a local fingerprint is transmitted and an acoustic match is required',
      () async {
    var calls = 0;
    final service = MusicRecognitionService(client: MockClient((request) async {
      calls++;
      expect(request.url.host, 'amp.shazam.com');
      final body = jsonDecode(request.body) as Map;
      expect(body.keys, ['signature']);
      expect(body['signature']['uri'],
          startsWith('data:audio/vnd.shazam.sig;base64,'));
      expect(body['signature']['samplems'], 1000);
      return http.Response.bytes(
          utf8.encode(jsonEncode(match(found: calls == 1))), 200);
    }));
    addTearDown(service.close);
    expect((await service.recognizePcm(pcm()))?.title, 'Güneş');
    expect(await service.recognizePcm(pcm()), isNull);
  });

  test('short samples fail locally and requests are capped at twelve seconds',
      () async {
    var calls = 0;
    final service = MusicRecognitionService(client: MockClient((request) async {
      calls++;
      expect(jsonDecode(request.body)['signature']['samplems'], 12000);
      return http.Response.bytes(utf8.encode(jsonEncode(match())), 200);
    }));
    addTearDown(service.close);
    await expectLater(service.recognizePcm(Uint8List(100)),
        throwsA(isA<MusicRecognitionException>()));
    expect(calls, 0);
    await service.recognizePcm(pcm(13));
    expect(calls, 1);
  });

  test('closing while matching ignores a late response', () async {
    final pending = Completer<http.Response>();
    final sent = Completer<void>();
    final service = MusicRecognitionService(client: MockClient((_) {
      sent.complete();
      return pending.future;
    }));
    final recognizing = service.recognizePcm(pcm());
    await sent.future;
    service.close();
    pending
        .complete(http.Response.bytes(utf8.encode(jsonEncode(match())), 200));
    expect(await recognizing, isNull);
  });

  test(
      'TikTok original audio is decoded locally and matched without song metadata',
      () async {
    var decodes = 0;
    final service = MusicRecognitionService(decoder: (bytes) async {
      decodes++;
      expect(bytes, [73, 68, 51]);
      return pcm();
    }, client: MockClient((request) async {
      if (request.url.host == 'vt.tiktok.com') {
        return http.Response('', 302,
            headers: {'location': 'https://www.tiktok.com/@creator/video/123'});
      }
      if (request.url.host == 'www.tiktok.com') {
        return http.Response(post(), 200);
      }
      if (request.url.host == 'sample.tiktokcdn.com') {
        return http.Response.bytes([73, 68, 51], 200);
      }
      return http.Response.bytes(utf8.encode(jsonEncode(match())), 200);
    }));
    addTearDown(service.close);
    expect(
        (await service.recognizeTikTok('https://vt.tiktok.com/abc/'))?.artist,
        'Artist');
    expect(decodes, 1);
  });

  test(
      'a different post or a non-TikTok audio host cannot supply the recognition audio',
      () {
    final reader = TikTokSongService();
    addTearDown(reader.close);
    expect(reader.parseAudioUrl(post(id: '999'), '123'), isNull);
    expect(reader.parseAudioUrl(post(audio: 'http://127.0.0.1/audio'), '123'),
        isNull);
    expect(
        reader.parseAudioUrl(
            post(audio: 'https://tiktokcdn.com.evil.test/audio'), '123'),
        isNull);
    expect(reader.parseAudioUrl(post(), '123')?.host, 'sample.tiktokcdn.com');
  });

  test('Instagram audio is decoded locally and sent only as a fingerprint',
      () async {
    final visited = <String>[];
    final service = MusicRecognitionService(
        decoder: (bytes) async => pcm(),
        client: MockClient((request) async {
          visited.add(request.url.host);
          if (request.url.host == 'instagram.com') {
            return http.Response(instagramPage(), 200);
          }
          if (request.url.host == 'video.cdninstagram.com') {
            expect(request.headers['referer'], 'https://www.instagram.com/');
            return http.Response.bytes([1, 2, 3], 200);
          }
          expect(request.url.host, 'amp.shazam.com');
          expect(jsonDecode(request.body).keys, ['signature']);
          return http.Response.bytes(utf8.encode(jsonEncode(match())), 200);
        }));
    addTearDown(service.close);
    expect(
        (await service
                .recognizeSocialLink('https://instagram.com/reel/Abc_123/'))
            ?.artist,
        'Artist');
    expect(
        visited, ['instagram.com', 'video.cdninstagram.com', 'amp.shazam.com']);
  });

  test('TikTok retries actual video media then music after failed CDN/codec',
      () async {
    for (final failure in ['cdn', 'codec', 'no-match']) {
      var fingerprints = 0;
      final visited = <String>[];
      final page = '<script id="SIGI_STATE">${jsonEncode({
            'ItemModule': {
              '123': {
                'id': '123',
                'video': {
                  'playAddr': {
                    'UrlList': ['https://sample.tiktokcdn.com/video.mp4']
                  }
                },
                'music': {
                  'playUrl': {
                    'urlList': ['https://sample.tiktokcdn.com/music.mp3']
                  }
                }
              }
            }
          })}</script>';
      final service = MusicRecognitionService(decoder: (bytes) async {
        if (bytes.first == 1 && failure == 'codec') {
          throw const FormatException();
        }
        return pcm();
      }, client: MockClient((request) async {
        if (request.url.host == 'www.tiktok.com') {
          return http.Response(page, 200);
        }
        if (request.url.host == 'sample.tiktokcdn.com') {
          visited.add(request.url.path);
          final video = request.url.path == '/video.mp4';
          return http.Response.bytes(
              [video ? 1 : 2], video && failure == 'cdn' ? 403 : 200);
        }
        fingerprints++;
        return http.Response.bytes(
            utf8.encode(jsonEncode(
                match(found: failure != 'no-match' || fingerprints == 2))),
            200);
      }));
      addTearDown(service.close);
      expect(
          (await service
                  .recognizeTikTok('https://www.tiktok.com/@creator/video/123'))
              ?.artist,
          'Artist');
      expect(visited, ['/video.mp4', '/music.mp3']);
    }
  });

  test('media redirects to an untrusted host cannot reach decoder or matcher',
      () async {
    final visited = <String>[];
    final service = MusicRecognitionService(
        decoder: (_) async => fail('must not decode'),
        client: MockClient((request) async {
          visited.add(request.url.host);
          if (request.url.host == 'www.tiktok.com') {
            return http.Response(post(), 200);
          }
          return http.Response('', 302,
              headers: {'location': 'https://evil.test/audio'});
        }));
    addTearDown(service.close);
    expect(
        await service
            .recognizeTikTok('https://www.tiktok.com/@creator/video/123'),
        isNull);
    expect(visited, ['www.tiktok.com', 'sample.tiktokcdn.com']);
  });

  test('local stereo resampling preserves timing and caps the sample length',
      () {
    final input = ByteData(48000 * 2 * 2);
    for (var frame = 0; frame < 48000; frame++) {
      input.setInt16(frame * 4, 1000, Endian.little);
      input.setInt16(frame * 4 + 2, 3000, Endian.little);
    }
    final result = resampleRecognitionAudio({
      'pcm': input.buffer.asUint8List(),
      'sampleRate': 48000,
      'channels': 2
    });
    expect(result.length, 32000);
    expect(ByteData.sublistView(result).getInt16(0, Endian.little), 2000);
    expect(
        () => resampleRecognitionAudio(
            {'pcm': pcm(), 'sampleRate': 0, 'channels': 0}),
        throwsFormatException);
  });
}
