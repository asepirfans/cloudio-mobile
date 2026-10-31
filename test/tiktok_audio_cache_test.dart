import 'dart:io';

import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/tiktok_audio_cache.dart';
import 'package:cloudio_mobile/services/tiktok_sound_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const track = Track(
    id: 'tiktok:123',
    title: 'Sound',
    artist: '@creator',
    provider: 'tiktok',
    sourceUrl: 'https://www.tiktok.com/@creator/video/123/');

class Source extends TikTokSoundService {
  Source({this.audioOnly = false});
  final bool audioOnly;
  int calls = 0;
  @override
  Future<TikTokSound> resolve(String input, {bool refresh = false}) async {
    calls++;
    final media = [
      Uri.https('sample.tiktokcdn.com', '/blocked.mp4'),
      Uri.https('sample.tiktokcdn.com', '/actual.mp4')
    ];
    return TikTokSound(
        track: track.copyWith(duration: const Duration(seconds: 41)),
        media: media,
        audioOnlyMedia: audioOnly ? {media.last} : {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.cloudiolabs.cloudio/tiktok_audio_cache');
  late Directory directory;
  late File audio;
  var extracts = 0;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cloudio-audio-test-');
    audio = File('${directory.path}/sound-123.m4a');
    extracts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'directory':
          return directory.path;
        case 'lookup':
          return await audio.exists() ? audio.path : null;
        case 'extract':
          extracts++;
          final input = File((call.arguments as Map)['inputPath'] as String);
          expect(await input.readAsBytes(), [1, 2, 3, 4]);
          await audio.writeAsBytes([5, 6]);
          return audio.path;
        case 'remove':
          if (await audio.exists()) await audio.delete();
          return null;
      }
      return null;
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
      'cold requests coalesce; replay and a fresh service use the local audio without network',
      () async {
    var requests = 0;
    final source = Source();
    addTearDown(source.close);
    final cache = TikTokAudioCache(client: MockClient((request) async {
      requests++;
      expect(request.headers['referer'], 'https://www.tiktok.com/');
      expect(request.headers['range'], 'bytes=0-');
      return request.url.path == '/blocked.mp4'
          ? http.Response('', 403)
          : http.Response.bytes([1, 2, 3, 4], 206,
              headers: {'content-range': 'bytes 0-3/4'});
    }));
    addTearDown(cache.close);
    final paths = await Future.wait(
        [cache.playbackUrl(track, source), cache.playbackUrl(track, source)]);
    expect(paths.toSet().single, Uri.file(audio.path).toString());
    expect(source.calls, 1);
    expect(requests, 2);
    expect(extracts, 1);
    expect(directory.listSync().whereType<File>().map((file) => file.path),
        [audio.path]);
    final warm = TikTokAudioCache(
        client: MockClient(
            (_) async => fail('warm playback must not use network')));
    addTearDown(warm.close);
    expect(await warm.playbackUrl(track, source), paths.first);
    expect(source.calls, 1);
    expect(extracts, 1);
  });

  test(
      'oversized media and failed extraction never fall back to a streaming video',
      () async {
    final source = Source();
    addTearDown(source.close);
    final cache = TikTokAudioCache(
        client: MockClient.streaming((_, __) async => http.StreamedResponse(
            const Stream.empty(), 200,
            contentLength: TikTokAudioCache.maxDownloadBytes + 1)));
    addTearDown(cache.close);
    await expectLater(
        cache.playbackUrl(track, source), throwsA(isA<Exception>()));
    expect(extracts, 0);
    expect(directory.listSync(), isEmpty);
  });

  test('original audio duration is verified and a mismatched cache is removed',
      () async {
    var durationMs = 41000;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'directory':
          return directory.path;
        case 'extract':
          extracts++;
          await audio.writeAsBytes([5, 6]);
          return audio.path;
        case 'info':
          return {'audioTracks': 1, 'videoTracks': 0, 'durationMs': durationMs};
        case 'remove':
          if (await audio.exists()) await audio.delete();
      }
      return null;
    });
    final source = Source(audioOnly: true);
    addTearDown(source.close);
    final cache = TikTokAudioCache(
        client: MockClient((request) async => request.url.path == '/blocked.mp4'
            ? http.Response('', 403)
            : http.Response.bytes([1, 2, 3, 4], 200)));
    addTearDown(cache.close);
    expect(await cache.playbackUrl(track, source),
        Uri.file(audio.path).toString());
    durationMs = 60000;
    await expectLater(cache.playbackUrl(track, source, attempt: 1),
        throwsA(isA<Exception>()));
    expect(await audio.exists(), isFalse);
    expect(extracts, 2);
    expect(directory.listSync(), isEmpty);
  });

  test('33 MiB is allowed for matched audio, but still refused for video',
      () async {
    const bytes = 33 * 1024 * 1024;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'directory':
          return directory.path;
        case 'extract':
          extracts++;
          expect(
              await File((call.arguments as Map)['inputPath'] as String)
                  .length(),
              bytes);
          await audio.writeAsBytes([5, 6]);
          return audio.path;
        case 'info':
          return {'audioTracks': 1, 'videoTracks': 0, 'durationMs': 41000};
        case 'remove':
          if (await audio.exists()) await audio.delete();
      }
      return null;
    });
    final block = Uint8List(1024 * 1024);
    final cache = TikTokAudioCache(
        client: MockClient.streaming((request, _) async => request.url.path ==
                '/blocked.mp4'
            ? http.StreamedResponse(const Stream.empty(), 403)
            : http.StreamedResponse(
                Stream.fromIterable(List.filled(33, block)), 206,
                contentLength: bytes,
                headers: {'content-range': 'bytes 0-${bytes - 1}/$bytes'})));
    addTearDown(cache.close);
    final video = Source();
    final originalAudio = Source(audioOnly: true);
    addTearDown(video.close);
    addTearDown(originalAudio.close);
    await expectLater(
        cache.playbackUrl(track, video), throwsA(isA<Exception>()));
    expect(extracts, 0);
    expect(await cache.playbackUrl(track, originalAudio),
        Uri.file(audio.path).toString());
    expect(extracts, 1);
    expect(directory.listSync().whereType<File>().map((file) => file.path),
        [audio.path]);
  });

  test('partial ranges and foreign redirects cannot become cached audio',
      () async {
    final source = Source();
    addTearDown(source.close);
    for (final redirect in [false, true]) {
      final cache = TikTokAudioCache(client: MockClient((request) async {
        expect(request.url.host, 'sample.tiktokcdn.com');
        return redirect
            ? http.Response('', 302,
                headers: {'location': 'https://evil.test/media'})
            : http.Response.bytes([1, 2], 206,
                headers: {'content-range': 'bytes 0-1/4'});
      }));
      await expectLater(
          cache.playbackUrl(track, source), throwsA(isA<Exception>()));
      cache.close();
    }
    expect(extracts, 0);
    expect(directory.listSync(), isEmpty);
  });

  test('unsupported remux cleans temporary downloads; retries are bounded',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'directory') return directory.path;
      if (call.method == 'extract') {
        throw PlatformException(code: 'unsupported_codec');
      }
      return null;
    });
    final source = Source();
    addTearDown(source.close);
    final cache = TikTokAudioCache(
        client:
            MockClient((_) async => http.Response.bytes([1, 2, 3, 4], 200)));
    addTearDown(cache.close);
    await expectLater(
        cache.playbackUrl(track, source), throwsA(isA<Exception>()));
    expect(directory.listSync(), isEmpty);
    await expectLater(
        Future.sync(() => cache.playbackUrl(track, source, attempt: 2)),
        throwsA(isA<Exception>()));
    expect(source.calls, 1);
  });
}
