import 'package:cloudio_mobile/services/tiktok_playlist_service.dart';
import 'package:cloudio_mobile/services/youtube_music_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public TikTok community playlists provide playable catalog songs',
      () async {
    final catalog = YoutubeMusicCatalog();
    addTearDown(catalog.close);
    final tracks = await TikTokPlaylistService(catalog).songs();
    expect(tracks.length, greaterThanOrEqualTo(10));
    expect(
        tracks.every((t) =>
            t.id.startsWith('ytm:') &&
            t.title.isNotEmpty &&
            t.artist.isNotEmpty),
        isTrue);
    expect(tracks.any((t) => t.duration != null), isTrue);
    for (final track in tracks.take(5)) {
      debugPrint(
          '${track.displayTitle} — ${track.displayArtist} (${track.duration})');
    }
  },
      timeout: const Timeout(Duration(seconds: 45)),
      skip: !const bool.fromEnvironment('CLOUDIO_LIVE_TIKTOK_PLAYLIST_TEST'));
}
