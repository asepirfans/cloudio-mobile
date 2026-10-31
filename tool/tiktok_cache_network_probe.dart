import 'dart:io';
import 'package:cloudio_mobile/services/tiktok_sound_service.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final source = TikTokSoundService();
  final client = http.Client();
  try {
    final input = args.where((arg) => !arg.startsWith('--')).firstOrNull ??
        'https://vt.tiktok.com/ZSgMSnYvm/';
    final sound = await source.resolve(input);
    stdout.writeln(
        'post=${sound.track.id} seconds=${sound.track.duration?.inSeconds} candidates=${sound.media.length}');
    for (var i = 0; i < sound.media.length; i++) {
      var uri = sound.media[i];
      for (var hop = 0; hop < 5; hop++) {
        if (!TikTokSongService.isAudioHost(uri)) break;
        final response = await client
            .send(http.Request('GET', uri)
              ..followRedirects = false
              ..headers.addAll({
                ...TikTokSoundService.playbackHeaders,
                'Range': args.contains('--range') ? 'bytes=0-65535' : 'bytes=0-'
              }))
            .timeout(const Duration(seconds: 15));
        if (response.isRedirect) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null) break;
          uri = uri.resolve(location);
          continue;
        }
        if (args.contains('--save-fixture') &&
            response.statusCode == 206 &&
            (response.contentLength ?? 0) > 0 &&
            response.contentLength! <= 32 * 1024 * 1024) {
          await File('/private/tmp/cloudio-tiktok-cache-input.mp4')
              .writeAsBytes(await response.stream.toBytes());
          stdout
              .writeln('Saved bounded local MP4 fixture for native inspection');
          break;
        }
        final chunks = await response.stream
            .take(1)
            .toList()
            .timeout(const Duration(seconds: 15));
        final prefix = chunks.isEmpty ? <int>[] : chunks.first;
        stdout.writeln(
            'candidate=$i status=${response.statusCode} bytes=${response.contentLength} range=${response.headers['content-range']} type=${response.headers['content-type']} prefix=${prefix.take(12).toList()}');
        break;
      }
    }
  } finally {
    source.close();
    client.close();
  }
}
