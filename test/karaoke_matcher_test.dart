import 'package:flutter_test/flutter_test.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/music_service.dart';

void main() {
  test('Smart karaoke matcher verifies artist and duration compatibility', () async {
    final service = MusicService.instance;

    const track = Track(
      id: 'test-hati',
      title: 'Hati-Hati di Jalan',
      artist: 'Tulus',
      duration: Duration(minutes: 4, seconds: 2),
    );

    final match = await service.findMatchingKaraokeTrack(track);
    expect(match, isNotNull);
    expect(match!.isKaraoke, isTrue);
    expect(
      match.displayTitle.toLowerCase().contains('tulus') ||
          match.displayArtist.toLowerCase().contains('tulus'),
      isTrue,
    );
  });

  test('Smart karaoke matcher rejects tracks if artist does not match', () async {
    final service = MusicService.instance;

    // A song title that has famous songs by other artists, but test artist doesn't have a karaoke version
    const fakeTrack = Track(
      id: 'test-fake',
      title: 'Love Bomb',
      artist: 'NonExistentArtistXYZ123',
      duration: Duration(minutes: 3, seconds: 24),
    );

    final match = await service.findMatchingKaraokeTrack(fakeTrack);
    // MUST be null, not fromis_9 or anyone else!
    expect(match, isNull);
  });
}
