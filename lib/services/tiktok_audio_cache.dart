import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'tiktok_song_service.dart';
import 'tiktok_sound_service.dart';

/// A bounded download followed by compressed-audio remux, never video playback.
class TikTokAudioCache {
  TikTokAudioCache({http.Client? client, this.diagnostics})
      : _client = client ?? http.Client();
  final void Function(String)? diagnostics;
  final http.Client _client;
  static const _channel =
      MethodChannel('com.cloudiolabs.cloudio/tiktok_audio_cache');
  static final _pending = <String, Future<String>>{};
  static const maxDownloadBytes = 32 * 1024 * 1024;
  static const maxAudioDownloadBytes = 64 * 1024 * 1024;

  static String _key(Track track) {
    final match = RegExp(r'^tiktok:(\d+)$').firstMatch(track.id);
    if (!track.isTikTokSound || match == null || track.sourceUrl == null) {
      throw const TikTokSongException('Sumber sound TikTok tidak valid.');
    }
    return match.group(1)!;
  }

  Future<String> playbackUrl(Track track, TikTokSoundService source,
      {int attempt = 0}) {
    final key = _key(track);
    if (attempt > 1) {
      throw const TikTokSongException(
          'Audio lokal belum dapat diputar. Coba lagi nanti.');
    }
    return _pending.putIfAbsent(key, () async {
      try {
        if (attempt == 1) {
          await _channel.invokeMethod<void>('remove', {'id': key});
        }
        final path = await _channel.invokeMethod<String>('lookup', {'id': key});
        if (path != null && await File(path).exists()) {
          diagnostics?.call('cache-hit');
          return Uri.file(path).toString();
        }
        return await _prepare(track, key, source, refresh: attempt == 1);
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<String> _prepare(Track track, String key, TikTokSoundService source,
      {required bool refresh}) async {
    final directory = await _channel.invokeMethod<String>('directory');
    if (directory == null) {
      throw const TikTokSongException('Cache audio belum tersedia.');
    }
    final sound = await source.resolve(track.sourceUrl!, refresh: refresh);
    if (sound.track.id != track.id) {
      throw const TikTokSongException('Identitas sound TikTok berubah.');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    for (final uri in sound.media) {
      if (DateTime.now().isAfter(deadline)) break;
      final input = File(
          '$directory/download-$key-${DateTime.now().microsecondsSinceEpoch}.part');
      try {
        final audioOnly = sound.audioOnlyMedia.contains(uri);
        await _download(uri, input, deadline,
            limit: audioOnly ? maxAudioDownloadBytes : maxDownloadBytes);
        diagnostics?.call('downloaded bytes=${await input.length()}');
        final path = await _channel.invokeMethod<String>('extract', {
          'id': key,
          'inputPath': input.path,
        }).timeout(const Duration(seconds: 20));
        if (path != null && await File(path).exists()) {
          if (audioOnly) {
            final metadata = await info(track);
            final duration = metadata?['durationMs'];
            final expected = sound.track.duration?.inMilliseconds;
            if (metadata?['audioTracks'] != 1 ||
                metadata?['videoTracks'] != 0 ||
                duration is! num ||
                expected == null ||
                (duration - expected).abs() > 1500) {
              await _channel.invokeMethod<void>('remove', {'id': key});
              throw const FormatException('Original audio duration mismatch');
            }
          }
          return Uri.file(path).toString();
        }
      } catch (error) {
        diagnostics?.call(error is PlatformException
            ? 'native ${error.code} ${error.details}'
            : error is FormatException
                ? 'media ${error.message}'
                : 'prepare ${error.runtimeType}');
        // Another rendition can have accessible media or a supported audio codec.
      } finally {
        if (await input.exists()) await input.delete();
      }
    }
    throw const TikTokSongException(
        'Sound belum dapat disiapkan sebagai audio. Coba lagi nanti.');
  }

  Future<void> _download(Uri uri, File file, DateTime deadline,
      {required int limit}) async {
    Duration remaining() {
      final value = deadline.difference(DateTime.now());
      if (value <= Duration.zero) {
        throw TimeoutException('TikTok download expired');
      }
      return value < const Duration(seconds: 15)
          ? value
          : const Duration(seconds: 15);
    }

    for (var hop = 0; hop < 5; hop++) {
      if (!TikTokSongService.isAudioHost(uri)) {
        throw const FormatException('Untrusted media');
      }
      final response = await _client
          .send(http.Request('GET', uri)
            ..followRedirects = false
            ..headers.addAll(
                {...TikTokSoundService.playbackHeaders, 'Range': 'bytes=0-'}))
          .timeout(remaining());
      if (response.isRedirect) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null) throw const FormatException('Missing redirect');
        uri = uri.resolve(location);
        continue;
      }
      int? rangeLength;
      var completeRange = false;
      if (response.statusCode == 206) {
        final range = RegExp(r'^bytes 0-(\d+)/(\d+)$')
            .firstMatch(response.headers['content-range'] ?? '');
        if (range != null) {
          rangeLength = int.parse(range.group(2)!);
          completeRange = int.parse(range.group(1)!) + 1 == rangeLength;
        }
      }
      if ((response.statusCode != 200 && !completeRange) ||
          (response.contentLength ?? rangeLength ?? 0) > limit ||
          (response.headers['content-type'] ?? '').contains('text/html')) {
        await response.stream.listen((_) {}).cancel();
        throw FormatException(
            'Media status=${response.statusCode} bytes=${response.contentLength} type=${response.headers['content-type']}');
      }
      final output = await file.open(mode: FileMode.write);
      final iterator = StreamIterator(response.stream);
      var length = 0;
      try {
        while (await iterator.moveNext().timeout(remaining())) {
          length += iterator.current.length;
          if (length > limit) {
            throw const FormatException('Media too large');
          }
          await output.writeFrom(iterator.current);
        }
        if (length == 0 ||
            ((response.contentLength ?? rangeLength) != null &&
                length != (response.contentLength ?? rangeLength))) {
          throw const FormatException('Incomplete media');
        }
      } finally {
        await iterator.cancel();
        await output.close();
      }
      return;
    }
    throw const FormatException('Too many media redirects');
  }

  Future<Map<String, dynamic>?> info(Track track) =>
      _channel.invokeMapMethod<String, dynamic>('info', {'id': _key(track)});
  void close() => _client.close();
}
