import 'package:cloudio_mobile/services/music_search_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool song({
    required String title,
    String author = 'Uploader',
    String description = '',
    Duration? duration = const Duration(minutes: 3),
    bool isLive = false,
    bool hasMusicMetadata = false,
  }) =>
      MusicSearchFilter.isYouTubeSong(
        title: title,
        author: author,
        description: description,
        duration: duration,
        isLive: isLive,
        hasMusicMetadata: hasMusicMetadata,
      );

  test('rejects explicitly labeled and hidden podcasts', () {
    expect(
      song(
          title: 'WAWANCANDA DEDDY CORBUZIER - GAJI 700RB',
          author: 'Abdel Achrian',
          hasMusicMetadata: true),
      isFalse,
    );
    expect(
        song(title: 'Raditya Dika Standup', hasMusicMetadata: true), isFalse);
    expect(song(title: 'Cerita Malam - Podcast Episode 12'), isFalse);
    expect(
      song(
        title: 'Cerita Malam',
        description: 'Dengarkan episode terbaru podcast kami.',
      ),
      isFalse,
    );
    expect(song(title: 'Artis Terkenal Berbincang Hari Ini'), isFalse);
    expect(
      song(title: 'Joe Rogan - Elon Musk', author: 'Clips'),
      isFalse,
    );
  });

  test('keeps music releases and independent uploads', () {
    expect(
      song(title: 'Sectro B Robstee', hasMusicMetadata: true),
      isTrue,
    );
    expect(
      song(title: 'Robstee - Sectro B', author: 'Robstee'),
      isTrue,
    );
    expect(song(title: 'Lagu Baru (Official Audio)'), isTrue);
    expect(song(title: 'Lagu Baru', author: 'Robstee - Topic'), isTrue);
  });

  test('rejects news even when it has music-like labels or metadata', () {
    expect(song(title: 'Berita musik terbaru (Official Audio)'), isFalse);
    expect(song(title: 'Kabar hari ini', author: 'CNN Indonesia'), isFalse);
    expect(
      song(
        title: 'Dunia hari ini',
        author: 'Uploader Music',
        description: 'Liputan terkini dari seluruh dunia',
        hasMusicMetadata: true,
      ),
      isFalse,
    );
    expect(
      song(title: 'Podcast musisi (Official Audio)', hasMusicMetadata: true),
      isFalse,
    );
  });

  test('requires music evidence for otherwise unclassified videos', () {
    expect(song(title: 'Cerita Malam Hari'), isFalse);
    expect(song(title: 'Joe Rogan - Elon Musk'), isFalse);
    expect(song(title: 'Cerita Malam (Audio)'), isFalse);
    expect(song(title: 'Cerita Malam (Official Video)'), isFalse);
    expect(
      song(title: 'Cerita Malam', description: 'Listen to our latest upload'),
      isFalse,
    );
    expect(song(title: 'Robstee - Sectro B (Official Music Video)'), isTrue);
    expect(song(title: 'Robstee - Sectro B (Cover)'), isTrue);
    expect(song(title: 'Sectro B', author: 'RobsteeVEVO'), isTrue);
  });

  test('keeps recorded DJ mixes and long dance music sets', () {
    expect(
      song(
        title: 'TULUS, TENXI, NAYKILLA, HINDIA LIVE SET MIX | '
            'HIPDUT, BREAKBEAT (BKB), BASSLINE BOUNCE MIX',
        author: 'motomovth and Dynamic Pro',
        duration: const Duration(minutes: 36, seconds: 19),
      ),
      isTrue,
    );
    expect(
      song(title: 'DJ Tiesto Live Set', duration: const Duration(hours: 2)),
      isTrue,
    );
    expect(
      song(title: 'Techno Mix', duration: const Duration(hours: 1)),
      isTrue,
    );
    expect(song(title: 'DJ Hipdut Mix'), isTrue);
  });

  test('DJ labels never override spoken content or stream exclusions', () {
    for (final title in [
      'DJ Mix Podcast Episode 1',
      'Berita DJ Techno Mix',
      'DJ Interview Live Set',
      'DJ Mix Livestream',
      'DJ Mix Radio 24/7',
    ]) {
      expect(song(title: title, duration: const Duration(hours: 1)), isFalse,
          reason: title);
    }
    expect(
      song(title: 'DJ Mix', description: 'Podcast bersama DJ terkenal'),
      isFalse,
    );
    expect(song(title: 'DJ Mix', author: 'CNN Indonesia'), isFalse);
    expect(song(title: 'DJ Mix', isLive: true), isFalse);
    expect(song(title: 'DJ Mix', duration: null), isFalse);
    expect(
      song(title: 'Mix Hari Ini', duration: const Duration(hours: 1)),
      isFalse,
    );
    expect(
      song(
          title: 'Cerita Malam',
          author: 'DJ Channel',
          duration: const Duration(hours: 1)),
      isFalse,
    );
  });

  test('rejects live streams and unclassified long-form results', () {
    expect(song(title: 'Lagu baru', duration: null), isFalse);
    expect(
      song(title: 'Lagu baru', duration: const Duration(seconds: 30)),
      isFalse,
    );
    expect(
      song(
          title: 'Lagu baru',
          duration: const Duration(minutes: 15, seconds: 1)),
      isFalse,
    );
    expect(
      song(title: 'Robstee - Sectro B', author: 'Robstee', isLive: true),
      isFalse,
    );
    expect(
      song(
        title: 'Robstee - Sectro B',
        duration: const Duration(minutes: 46),
      ),
      isFalse,
    );
  });
}
