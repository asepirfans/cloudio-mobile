import 'package:cloudio_mobile/services/karaoke_metadata.dart';
import 'package:cloudio_mobile/services/lyrics_service.dart';
import 'package:cloudio_mobile/services/music_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'live karaoke search returns karaoke and original-song lyrics automatically',
      () async {
    final music = MusicService.instance;
    addTearDown(music.dispose);
    final tracks =
        await music.searchKaraoke('Adele Someone Like You', limit: 8);
    expect(tracks, isNotEmpty);
    expect(
        tracks.every((track) =>
            track.isKaraoke && KaraokeMetadata.isKaraoke(track.title)),
        isTrue);
    final lyrics = LyricsService();
    var found = false;
    for (final track in tracks.take(3)) {
      debugPrint('KARAOKE ${track.id} ${track.title} — ${track.artist}');
      final result = await lyrics.getLyrics(track);
      if (result?.hasLyrics == true) {
        expect(result?.syncedLines, isEmpty);
        debugPrint(
            'LYRICS ${result?.source}; lines=${result?.plainText?.split('\n').length}');
        found = true;
        break;
      }
    }
    expect(found, isTrue);
  },
      skip: !const bool.fromEnvironment('CLOUDIO_LIVE_KARAOKE_TEST'),
      timeout: const Timeout(Duration(seconds: 90)));
}
