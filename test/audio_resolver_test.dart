import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloudio_mobile/services/audio_resolver.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cloudio_mobile/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

StreamManifest manifest(String url) => StreamManifest([audioStream(url)]);

AudioOnlyStreamInfo audioStream(
  String url, {
  int bitrate = 128000,
  String container = 'mp4',
  String audioCodec = 'mp4a.40.2',
}) =>
    AudioOnlyStreamInfo.fromJson({
      'videoId': {'value': '8NXfWci2muY'},
      'tag': 140,
      'url': url,
      'container': {'name': container},
      'size': {'totalBytes': 1000},
      'bitrate': {'bitsPerSecond': bitrate},
      'audioCodec': audioCodec,
      'qualityLabel': 'medium',
      'fragments': [],
      'codec': 'audio/$container',
    });

MuxedStreamInfo muxedStream(
  String url, {
  int bitrate = 500000,
  String audioCodec = 'mp4a.40.2',
  String videoCodec = 'avc1.42001E',
}) =>
    MuxedStreamInfo.fromJson({
      'videoId': {'value': '8NXfWci2muY'},
      'tag': 18,
      'url': url,
      'container': {'name': 'mp4'},
      'size': {'totalBytes': 1000},
      'bitrate': {'bitsPerSecond': bitrate},
      'audioCodec': audioCodec,
      'videoCodec': videoCodec,
      'qualityLabel': '360p',
      'videoQuality': 'medium360',
      'videoResolution': {'width': 640, 'height': 360},
      'framerate': {'framesPerSecond': 30},
      'codec': 'video/mp4',
    });

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test('$platform uses audio-only AAC before progressive MP4', () async {
      debugDefaultTargetPlatformOverride = platform;
      final resolver = AudioResolverService.forTesting((_) async =>
          StreamManifest([
            audioStream('https://audio.example.test/aac', bitrate: 96000),
            audioStream('https://audio.example.test/opus',
                container: 'webm', audioCodec: 'opus'),
            muxedStream('https://audio.example.test/muxed', bitrate: 128000),
          ]));
      addTearDown(resolver.dispose);
      expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
          'https://audio.example.test/aac');
    });

    test('$platform tries next client before progressive fallback', () async {
      debugDefaultTargetPlatformOverride = platform;
      var nextCalls = 0;
      final resolver = AudioResolverService.forTesting(
        (_) async => StreamManifest([
          muxedStream('https://audio.example.test/muxed'),
        ]),
        fallbackLoaders: [
          (_) async {
            nextCalls++;
            return manifest('https://audio.example.test/next-aac');
          },
        ],
      );
      addTearDown(resolver.dispose);
      expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
          'https://audio.example.test/next-aac');
      expect(nextCalls, 1);
    });

    test('$platform can use muxed-only manifest after local clients fail',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      var nextCalls = 0;
      final resolver = AudioResolverService.forTesting(
        (_) async => StreamManifest([
          muxedStream('https://audio.example.test/larger', bitrate: 900000),
          muxedStream('https://audio.example.test/smallest'),
        ]),
        fallbackLoaders: [
          (_) async {
            nextCalls++;
            throw StateError('unavailable');
          },
        ],
      );
      addTearDown(resolver.dispose);
      expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
          'https://audio.example.test/smallest');
      expect(nextCalls, 1);
    });

    test('$platform does not select non-AAC MP4 audio', () async {
      debugDefaultTargetPlatformOverride = platform;
      final resolver = AudioResolverService.forTesting(
        (_) async => StreamManifest([
          audioStream('https://audio.example.test/non-aac', audioCodec: 'opus'),
          muxedStream('https://audio.example.test/non-aac-muxed',
              audioCodec: 'opus'),
        ]),
        fallbackLoaders: [
          (_) async => manifest('https://audio.example.test/aac'),
        ],
      );
      addTearDown(resolver.dispose);
      expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
          'https://audio.example.test/aac');
      expect(
          await resolver.resolveStreamUrl('8NXfWci2muY',
              compatibilityFallback: true),
          contains(ApiConfig.resolverHost));
    });
  }

  for (final invalidUrl in [
    'https://audio.example.test/expired?expire=1',
    'https://audio.example.test/chunk?range=0-1024',
    'http://audio.example.test/insecure',
    'relative-stream',
  ]) {
    test('skips invalid preferred audio URL $invalidUrl within same manifest',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var nextCalls = 0;
      final resolver = AudioResolverService.forTesting(
        (_) async => StreamManifest([
          audioStream(invalidUrl),
          audioStream('https://audio.example.test/valid-aac', bitrate: 96000),
        ]),
        fallbackLoaders: [
          (_) async {
            nextCalls++;
            return manifest('https://audio.example.test/other-client');
          },
        ],
      );
      addTearDown(resolver.dispose);
      expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
          'https://audio.example.test/valid-aac');
      expect(nextCalls, 0);
    });

    test('skips invalid progressive URL $invalidUrl within same manifest',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final resolver = AudioResolverService.forTesting((_) async =>
          StreamManifest([
            muxedStream(invalidUrl, bitrate: 200000),
            muxedStream('https://audio.example.test/valid-progressive'),
          ]));
      addTearDown(resolver.dispose);
      expect(
          await resolver.resolveStreamUrl('8NXfWci2muY',
              compatibilityFallback: true),
          'https://audio.example.test/valid-progressive');
    });
  }

  test('Android prefers valid Opus over AAC even when AAC bitrate is closer',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final resolver = AudioResolverService.forTesting((_) async =>
        StreamManifest([
          audioStream('https://audio.example.test/aac'),
          audioStream('https://audio.example.test/expired-opus?expire=1',
              container: 'webm', audioCodec: 'opus'),
          audioStream('https://audio.example.test/opus',
              bitrate: 160000, container: 'webm', audioCodec: 'opus'),
        ]));
    addTearDown(resolver.dispose);
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/opus');
  });

  test('Android falls back to AAC when all Opus URLs are invalid', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final resolver = AudioResolverService.forTesting((_) async =>
        StreamManifest([
          audioStream('https://audio.example.test/expired-opus?expire=1',
              container: 'webm', audioCodec: 'opus'),
          audioStream('https://audio.example.test/aac', bitrate: 96000),
        ]));
    addTearDown(resolver.dispose);
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/aac');
  });

  test('explicit compatibility fallback bypasses audio-only streams', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var nextCalls = 0;
    final resolver = AudioResolverService.forTesting(
      (_) async => StreamManifest([
        audioStream('https://audio.example.test/aac'),
        muxedStream('https://audio.example.test/non-avc',
            bitrate: 200000, videoCodec: 'av01'),
        muxedStream('https://audio.example.test/avc'),
      ]),
      fallbackLoaders: [
        (_) async {
          nextCalls++;
          return StreamManifest([]);
        },
      ],
    );
    addTearDown(resolver.dispose);
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/aac');
    expect(
        await resolver.resolveStreamUrl('8NXfWci2muY',
            compatibilityFallback: true),
        'https://audio.example.test/avc');
    expect(nextCalls, 0);
  });

  test('Linux prefers AAC over other MP4 audio codecs', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final resolver = AudioResolverService.forTesting((_) async =>
        StreamManifest([
          audioStream('https://audio.example.test/mp4-opus', audioCodec: 'opus'),
          audioStream('https://audio.example.test/aac', bitrate: 96000),
        ]));
    addTearDown(resolver.dispose);
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/aac');
  });

  test('Android does not automatically switch to progressive streams', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final resolver = AudioResolverService.forTesting((_) async =>
        StreamManifest([
          muxedStream('https://audio.example.test/muxed'),
        ]));
    addTearDown(resolver.dispose);
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        contains(ApiConfig.resolverHost));
    expect(
        await resolver.resolveStreamUrl('8NXfWci2muY',
            compatibilityFallback: true),
        'https://audio.example.test/muxed');
  });

  test('expired signed URLs and chunk URLs fall through to another strategy',
      () async {
    final resolver = AudioResolverService.forTesting(
        (_) async => manifest('https://audio.example.test/expired?expire=1'),
        fallbackLoaders: [
          (_) async =>
              manifest('https://audio.example.test/chunk?range=0-1024'),
          (_) async => manifest('https://audio.example.test/valid'),
        ]);
    addTearDown(resolver.dispose);
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/valid');
  });

  test('tries the next client when the first returns no usable format',
      () async {
    var fallbackCalls = 0;
    final resolver = AudioResolverService.forTesting(
        (_) async => StreamManifest([]),
        fallbackLoaders: [
          (_) async {
            fallbackCalls++;
            return manifest('https://audio.example.test/stream');
          }
        ]);
    addTearDown(resolver.dispose);
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/stream');
    expect(fallbackCalls, 1);
  });

  test('concurrent preloads share one lookup', () async {
    var calls = 0;
    final pending = Completer<StreamManifest>();
    final resolver = AudioResolverService.forTesting((_) {
      calls++;
      return pending.future;
    });
    addTearDown(resolver.dispose);
    final first = resolver.resolveStreamUrl('ytm:8NXfWci2muY');
    final second = resolver.resolveStreamUrl('8NXfWci2muY');
    pending.complete(manifest('https://audio.example.test/shared'));
    expect(await first, await second);
    expect(calls, 1);
  });

  test('gateway-only recovery skips all local clients', () async {
    final resolver = AudioResolverService.forTesting(
        (_) async => throw StateError('must not run'));
    addTearDown(resolver.dispose);
    final url = Uri.parse(await resolver.resolveStreamUrl('8NXfWci2muY',
        gatewayOnly: true, forceRefresh: true));
    expect(url.host, ApiConfig.resolverHost);
    expect(url.queryParameters['refresh'], '1');
  });

  test('invalidation prevents an old in-flight lookup from repopulating cache',
      () async {
    var calls = 0;
    final pending = Completer<StreamManifest>();
    final resolver = AudioResolverService.forTesting((_) {
      calls++;
      return calls == 1
          ? pending.future
          : Future.value(manifest('https://audio.example.test/new'));
    });
    addTearDown(resolver.dispose);
    final old = resolver.resolveStreamUrl('8NXfWci2muY');
    resolver.invalidate('8NXfWci2muY');
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/new');
    pending.complete(manifest('https://audio.example.test/old'));
    await old;
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'),
        'https://audio.example.test/new');
    expect(calls, 2);
  });

  test('blocked local extraction falls back to the range-capable gateway',
      () async {
    var calls = 0;
    final resolver = AudioResolverService.forTesting((id) async {
      calls++;
      throw StateError('upstream rejected extraction');
    });
    addTearDown(resolver.dispose);
    final url = Uri.parse(await resolver.resolveStreamUrl('ytm:8NXfWci2muY'));
    expect(url.scheme, 'https');
    expect(url.host, ApiConfig.resolverHost);
    expect(url.path, '/stream');
    expect(url.queryParameters, {'id': '8NXfWci2muY'});
    expect(await resolver.resolveStreamUrl('8NXfWci2muY'), url.toString());
    expect(calls, 1);
    final retry = Uri.parse(await resolver.resolveStreamUrl('8NXfWci2muY',
        forceRefresh: true, compatibilityFallback: true));
    expect(retry.queryParameters, {'id': '8NXfWci2muY', 'refresh': '1'});
    expect(calls, 2);
    resolver.invalidate('ytm:8NXfWci2muY');
    await resolver.resolveStreamUrl('8NXfWci2muY');
    expect(calls, 3);
  });
}
