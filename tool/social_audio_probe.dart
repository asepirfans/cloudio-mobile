import 'dart:io';

import 'package:cloudio_mobile/services/social_song_service.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';

/// Read-only network probe; does not print signed media URLs or tracking data.
Future<void> main(List<String> args) async {
  if (args.length != 1 || SocialSongService.extractLink(args.single) == null) {
    throw ArgumentError('Supply a public TikTok or Instagram post link');
  }
  final service = SocialSongService();
  try {
    final media = await service.resolveMedia(args.single);
    stdout.writeln(
        '${SocialSongService.platform(args.single)} media candidates: ${media.length}');
    stdout.writeln(
        'Media hosts: ${media.map((uri) => uri.host).toSet().join(", ")}');
    try {
      final song = await service.resolveSong(args.single);
      stdout.writeln('Metadata: ${song.query}; caption hint: ${song.isHint}');
    } on TikTokSongException catch (error) {
      stdout.writeln(error.message);
    }
  } on TikTokSongException catch (error) {
    stdout.writeln(error.message);
  } finally {
    service.close();
  }
}
