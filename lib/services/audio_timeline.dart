import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Reads the MP4 movie timeline, independent of AVPlayer's DASH estimate.
class AudioTimeline {
  static final Map<String, Duration> _cache = {};
  static final Map<String, Duration> _mediaCache = {};
  static final Map<String, Future<Duration?>> _pending = {};

  static Future<Duration?> read(Uri uri, {String? mediaId}) async {
    if (uri.scheme == 'file') {
      try {
        final file = File(uri.toFilePath());
        if (file.existsSync()) {
          final raf = file.openSync();
          try {
            final len = file.lengthSync();
            final headerBytes = raf.readSync(math.min(65536, len));
            final duration = parseMp4Duration(headerBytes);
            if (duration != null) return duration;
          } finally {
            raf.closeSync();
          }
        }
      } catch (_) {}
      return null;
    }
    if (uri.scheme != 'https' ||
        !(ApiConfig.isResolverHost(uri.host) ||
            uri.host.endsWith('.googlevideo.com'))) return null;
    final key = uri.toString();
    final cached =
        _cache[key] ?? (mediaId == null ? null : _mediaCache[mediaId]);
    if (cached != null) return cached;
    final duration =
        await (_pending[key] ??= _readWithRetry(uri).whenComplete(() {
      _pending.remove(key);
    }));
    if (duration != null) {
      _remember(_cache, key, duration);
      if (mediaId != null) _remember(_mediaCache, mediaId, duration);
    }
    return duration;
  }

  static void _remember(
      Map<String, Duration> cache, String key, Duration value) {
    if (!cache.containsKey(key) && cache.length >= 64) {
      cache.remove(cache.keys.first);
    }
    cache[key] = value;
  }

  static Future<Duration?> _readWithRetry(Uri uri) async {
    // A cold gateway or partial range response can fail the first read. Never
    // permanently accept that transient failure for a preloaded queue item.
    for (final byteLimit in [16384, 65536]) {
      final duration = await _readHeader(uri, byteLimit);
      if (duration != null) return duration;
    }
    return null;
  }

  static Future<Duration?> _readHeader(Uri uri, int byteLimit) async {
    final client = http.Client();
    try {
      return await (() async {
        final request = http.Request('GET', uri)
          ..headers['Range'] = 'bytes=0-${byteLimit - 1}'
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
        final response = await client.send(request);
        if (response.statusCode != 200 && response.statusCode != 206) {
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          final remaining = byteLimit - bytes.length;
          bytes.add(
              chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
          // The timeline is usable as soon as mvhd is complete. Waiting for the
          // response to finish can time out even though its header arrived.
          final duration = parseMp4Duration(bytes.toBytes());
          if (duration != null) return duration;
          if (bytes.length >= byteLimit) break;
        }
        return null;
      })()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Duration? parseMp4Duration(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    Duration? scan(int start, int end, {bool movie = false}) {
      var offset = start;
      while (offset + 8 <= end) {
        var size = data.getUint32(offset);
        final type = data.getUint32(offset + 4);
        var header = 8;
        if (size == 1) {
          if (offset + 16 > end) return null;
          size = data.getUint64(offset + 8);
          header = 16;
        }
        if (size < header) return null;
        final body = offset + header;
        final availableEnd = math.min(offset + size, end);
        if (!movie && type == 0x6d6f6f76) {
          // moov
          final duration = scan(body, availableEnd, movie: true);
          if (duration != null) return duration;
        } else if (movie && type == 0x6d766864 && body < availableEnd) {
          // mvhd
          final version = data.getUint8(body);
          if (version != 0 && version != 1) return null;
          final scaleOffset = body + (version == 1 ? 20 : 12);
          final durationOffset = scaleOffset + 4;
          if (durationOffset + (version == 1 ? 8 : 4) > availableEnd) {
            return null;
          }
          final scale = data.getUint32(scaleOffset);
          final ticks = version == 1
              ? data.getUint64(durationOffset)
              : data.getUint32(durationOffset);
          if (scale == 0 || ticks == 0 || ticks == 0xffffffff) return null;
          final micros = (ticks * 1000000) ~/ scale;
          if (micros <= 0 || micros > const Duration(days: 7).inMicroseconds) {
            return null;
          }
          return Duration(microseconds: micros);
        }
        if (size > end - offset) return null;
        offset += size;
      }
      return null;
    }

    return scan(0, bytes.length);
  }
}
