import 'dart:io';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Supply a public TikTok post link');
  final reader = TikTokSongService();
  try {
    final audio = await reader
        .resolveAudioUrl(args.single)
        .timeout(const Duration(seconds: 20));
    stdout.writeln(
        'Public audio available: ${audio != null}; host: ${audio?.host ?? "unavailable"}');
  } finally {
    reader.close();
  }
}
