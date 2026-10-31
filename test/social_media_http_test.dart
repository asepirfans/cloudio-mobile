import 'dart:async';

import 'package:cloudio_mobile/services/social_media_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('chunked oversized pages stop without buffering the entire response',
      () async {
    final client =
        MockClient.streaming((request, body) async => http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
              [5, 6]
            ]),
            200));
    addTearDown(client.close);
    expect(
        await readSocialMedia(client, Uri.https('allowed.test', '/'),
            allowed: (_) => true, headers: {}, maxBytes: 3),
        isNull);
  });

  test('redirects cannot leave the allowed host or run indefinitely', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 302, headers: {'location': '/again'});
    });
    addTearDown(client.close);
    expect(
        await readSocialMedia(client, Uri.https('allowed.test', '/'),
            allowed: (_) => true, headers: {}),
        isNull);
    expect(calls, 6);
    calls = 0;
    final foreign = MockClient((request) async {
      calls++;
      return http.Response('', 302,
          headers: {'location': 'https://other.test/'});
    });
    addTearDown(foreign.close);
    expect(
        await readSocialMedia(foreign, Uri.https('allowed.test', '/'),
            allowed: (uri) => uri.host == 'allowed.test', headers: {}),
        isNull);
    expect(calls, 1);
  });

  test('a stalled chunked response has a total deadline', () async {
    final stream = StreamController<List<int>>();
    final client = MockClient.streaming(
        (request, body) async => http.StreamedResponse(stream.stream, 200));
    addTearDown(client.close);
    await expectLater(
        readSocialMedia(client, Uri.https('allowed.test', '/'),
            allowed: (_) => true,
            headers: {},
            timeout: const Duration(milliseconds: 30)),
        throwsA(isA<TimeoutException>()));
    await stream.close();
  });
}
