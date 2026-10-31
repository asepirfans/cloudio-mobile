import 'dart:math';
import 'dart:async';
import 'dart:typed_data';

import 'package:cloudio_mobile/services/audio_timeline.dart';
import 'package:cloudio_mobile/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Uint8List movie(int scale, int ticks, {bool version1 = false}) {
  final data = ByteData(version1 ? 56 : 44);
  data.setUint32(0, data.lengthInBytes);
  data.setUint32(4, 0x6d6f6f76); // moov
  data.setUint32(8, data.lengthInBytes - 8);
  data.setUint32(12, 0x6d766864); // mvhd
  data.setUint8(16, version1 ? 1 : 0);
  data.setUint32(version1 ? 36 : 28, scale);
  if (version1) {
    data.setUint64(40, ticks);
  } else {
    data.setUint32(32, ticks);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('fetches only the MP4 header and reuses its media duration', () async {
    var requests = 0;
    await http.runWithClient(() async {
      final uri = Uri.https(
          ApiConfig.resolverHost, '/stream', {'id': 'header-fixture'});
      for (var i = 0; i < 2; i++) {
        expect(await AudioTimeline.read(uri), const Duration(seconds: 234));
      }
    },
        () => MockClient((request) async {
              requests++;
              expect(request.headers['Range'], 'bytes=0-16383');
              return http.Response.bytes(movie(1000, 234000), 206);
            }));
    expect(requests, 1);
  });

  test(
      'a preloaded MP4 retries a failed header instead of accepting doubled native duration',
      () async {
    var calls = 0;
    await http.runWithClient(() async {
      final duration = await AudioTimeline.read(Uri.https(
          ApiConfig.resolverHost, '/stream', {'id': 'retry-preload'}));
      expect(duration, const Duration(microseconds: 190705487));
    },
        () => MockClient((request) async {
              calls++;
              if (calls == 1) {
                return http.Response('temporary gateway failure', 503);
              }
              expect(request.headers['Range'], 'bytes=0-65535');
              return http.Response.bytes(movie(44100, 8410112), 206);
            }));
    expect(calls, 2);
  });

  test(
      'complete media header is accepted before a range response stops sending',
      () async {
    var cancelled = false;
    late StreamController<List<int>> stream;
    stream = StreamController<List<int>>(
      onListen: () {
        final header = movie(1000, 234000);
        stream.add(header.sublist(0, 20));
        stream.add(header.sublist(20));
      },
      onCancel: () => cancelled = true,
    );
    addTearDown(stream.close);
    await http.runWithClient(() async {
      expect(
          await AudioTimeline.read(Uri.https(
              ApiConfig.resolverHost,
              '/stream',
              {'id': 'open-range'})).timeout(const Duration(milliseconds: 500)),
          const Duration(seconds: 234));
    },
        () => MockClient.streaming(
            (_, __) async => http.StreamedResponse(stream.stream, 206)));
    expect(cancelled, isTrue);
  });

  test(
      'known media duration survives signed URL changes and concurrent requests share the probe',
      () async {
    var calls = 0;
    final response = Completer<http.Response>();
    await http.runWithClient(() async {
      final uri = Uri.https(
          ApiConfig.resolverHost, '/stream', {'id': 'shared-duration'});
      final first = AudioTimeline.read(uri, mediaId: 'ytm:duration-fixture');
      final second = AudioTimeline.read(uri, mediaId: 'ytm:duration-fixture');
      response.complete(http.Response.bytes(movie(1000, 191000), 206));
      expect(await first, const Duration(seconds: 191));
      expect(await second, const Duration(seconds: 191));
      expect(
          await AudioTimeline.read(
              uri.replace(
                  queryParameters: {'id': 'shared-duration', 'refresh': '1'}),
              mediaId: 'ytm:duration-fixture'),
          const Duration(seconds: 191));
      expect(
          await AudioTimeline.read(Uri.https('example.test', '/audio'),
              mediaId: 'ytm:duration-fixture'),
          isNull);
    },
        () => MockClient((_) {
              calls++;
              return response.future;
            }));
    expect(calls, 1);
  });

  test('larger retry can find a movie header beyond the first range', () async {
    var calls = 0;
    final padding = ByteData(20000)
      ..setUint32(0, 20000)
      ..setUint32(4, 0x66726565);
    final file = Uint8List.fromList(
        [...padding.buffer.asUint8List(), ...movie(1000, 191000)]);
    await http.runWithClient(() async {
      expect(
          await AudioTimeline.read(Uri.https(
              ApiConfig.resolverHost, '/stream', {'id': 'large-header'})),
          const Duration(seconds: 191));
    },
        () => MockClient((request) async {
              calls++;
              return http.Response.bytes(
                  calls == 1 ? file.sublist(0, 16384) : file, 206);
            }));
    expect(calls, 2);
  });

  test('HTTP failure leaves the stream playable without a guessed boundary',
      () async {
    await http.runWithClient(() async {
      expect(
          await AudioTimeline.read(Uri.https(ApiConfig.resolverHost,
              '/stream', {'id': 'failed-fixture'})),
          isNull);
    }, () => MockClient((_) async => http.Response('unavailable', 503)));
  });

  test('local fixtures and unrelated hosts do not trigger a header request',
      () async {
    await http.runWithClient(() async {
      expect(await AudioTimeline.read(Uri.file('/tmp/fixture.wav')), isNull);
      expect(await AudioTimeline.read(Uri.https('example.test', '/audio')),
          isNull);
    }, () => MockClient((_) async => throw StateError('Unexpected request')));
  });

  test('fragmented AAC movie duration matches Shape of You media header', () {
    expect(AudioTimeline.parseMp4Duration(movie(44100, 10306728)),
        const Duration(microseconds: 233712653));
  });

  test('reads version 1 timestamps without truncating the 64 bit duration', () {
    expect(
        AudioTimeline.parseMp4Duration(
            movie(1000000, 5000000000, version1: true)),
        const Duration(seconds: 5000));
  });

  test('a partial moov can still contain a complete mvhd', () {
    final bytes = movie(1000, 234000);
    ByteData.sublistView(bytes).setUint32(0, 64000);
    expect(AudioTimeline.parseMp4Duration(bytes), const Duration(seconds: 234));
  });

  test('unknown, zero and unbounded timelines remain unclipped', () {
    for (final bytes in [
      movie(0, 1),
      movie(1000, 0),
      movie(1000, 0xffffffff),
      movie(1, 0xffffffffffffff, version1: true)
    ]) {
      expect(AudioTimeline.parseMp4Duration(bytes), isNull);
    }
  });

  test('truncated or unrelated response data never becomes a media boundary',
      () {
    final bytes = movie(1000, 234000);
    for (var length = 0; length < 36; length++) {
      expect(
          AudioTimeline.parseMp4Duration(
              Uint8List.sublistView(bytes, 0, length)),
          isNull);
    }
    final random = Random(42);
    for (var length = 0; length < 256; length++) {
      expect(
          AudioTimeline.parseMp4Duration(Uint8List.fromList(
              List.generate(length, (_) => random.nextInt(256)))),
          isNull);
    }
  });
}
