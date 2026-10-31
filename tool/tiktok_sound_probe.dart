import 'dart:io';
import 'package:cloudio_mobile/services/tiktok_sound_service.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Supply a TikTok post URL');
  final service = TikTokSoundService();
  final client = http.Client();
  try {
    final sound = await service.resolve(args.single);
    stdout.writeln(
        '${sound.track.id}: ${sound.track.title}; creator: ${sound.track.artist}; seconds: ${sound.track.duration?.inSeconds}');
    stdout.writeln('Actual post media candidates: ${sound.media.length}');
    for (var index = 0; index < sound.media.length; index++) {
      var uri = sound.media[index];
      for (var hop = 0; hop < 5; hop++) {
        if (!TikTokSongService.isAudioHost(uri)) break;
        final response = await client
            .send(http.Request('GET', uri)
              ..followRedirects = false
              ..headers.addAll({
                ...TikTokSoundService.playbackHeaders,
                'Range': 'bytes=0-1023'
              }))
            .timeout(const Duration(seconds: 15));
        if (response.isRedirect) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null) break;
          uri = uri.resolve(location);
          continue;
        }
        final prefix =
            await response.stream.first.timeout(const Duration(seconds: 15));
        stdout.writeln(
            'Candidate $index: status ${response.statusCode}; type ${response.headers['content-type']}; prefix ${prefix.take(12).toList()}');
        break;
      }
    }
  } finally {
    client.close();
    service.close();
  }
}
