import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Bounds both redirects and response bodies, including chunked responses.
Future<({Uri uri, Uint8List bytes})?> readSocialMedia(
  http.Client client,
  Uri uri, {
  required bool Function(Uri) allowed,
  required Map<String, String> headers,
  int maxBytes = 3 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  Duration remaining() {
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) throw TimeoutException('Media request expired');
    return value;
  }

  for (var hop = 0; hop < 6; hop++) {
    if (!allowed(uri)) return null;
    final response = await client
        .send(http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll(headers))
        .timeout(remaining());
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.listen((_) {}).cancel();
      final location = response.headers['location'];
      if (location == null) return null;
      uri = uri.resolve(location);
      continue;
    }
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > maxBytes) {
      await response.stream.listen((_) {}).cancel();
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    final iterator = StreamIterator(response.stream);
    try {
      while (await iterator.moveNext().timeout(remaining())) {
        if (bytes.length + iterator.current.length > maxBytes) return null;
        bytes.add(iterator.current);
      }
    } finally {
      await iterator.cancel();
    }
    return (uri: uri, bytes: bytes.takeBytes());
  }
  return null;
}

String socialPageText(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);
