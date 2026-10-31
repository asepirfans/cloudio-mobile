import 'package:cloudio_mobile/services/social_song_service.dart';
import 'package:cloudio_mobile/services/instagram_song_service.dart';
import 'package:cloudio_mobile/services/tiktok_song_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YouTube Link Extraction and Recognition', () {
    const validVideoId = 'dQw4w9WgXcQ';
    final sampleUrls = [
      'https://www.youtube.com/watch?v=$validVideoId',
      'https://youtube.com/watch?v=$validVideoId',
      'https://m.youtube.com/watch?v=$validVideoId',
      'https://music.youtube.com/watch?v=$validVideoId',
      'https://youtu.be/$validVideoId',
      'https://www.youtube.com/shorts/$validVideoId',
      'https://youtube.com/shorts/$validVideoId',
      'https://www.youtube.com/embed/$validVideoId',
      'https://youtu.be/$validVideoId?si=random_tracking_123&t=15s',
      'https://www.youtube.com/watch?feature=shared&v=$validVideoId&themeRefresh=1',
      'Check this out: https://youtu.be/$validVideoId! Amazing song.',
    ];

    test('isYouTubeLink correctly detects all YouTube URL variations', () {
      for (final url in sampleUrls) {
        expect(SocialSongService.isYouTubeLink(url), isTrue,
            reason: 'Failed on $url');
      }
      expect(SocialSongService.isYouTubeLink('https://tiktok.com/@user/video/123'),
          isFalse);
      expect(
          SocialSongService.isYouTubeLink('https://instagram.com/reel/abc123/'),
          isFalse);
      expect(SocialSongService.isYouTubeLink('just a random search query'),
          isFalse);
    });

    test('extractYouTubeVideoId extracts exact 11-char video ID', () {
      for (final url in sampleUrls) {
        expect(SocialSongService.extractYouTubeVideoId(url), validVideoId,
            reason: 'Failed on $url');
      }
      expect(SocialSongService.extractYouTubeVideoId('https://not-yt.com'), isNull);
    });

    test('extractYouTubeLink normalizes to canonical watch URL', () {
      final uri = SocialSongService.extractYouTubeLink(
          'https://youtu.be/$validVideoId?si=secret');
      expect(uri?.toString(), 'https://www.youtube.com/watch?v=$validVideoId');
    });

    test('SocialSongService.platform identifies YouTube, Instagram, and TikTok',
        () {
      expect(
          SocialSongService.platform('https://youtu.be/$validVideoId'), 'YouTube');
      expect(
          SocialSongService.platform(
              'https://www.youtube.com/watch?v=$validVideoId'),
          'YouTube');
      expect(
          SocialSongService.platform('https://www.instagram.com/reel/C5WTtLuPrkq/'),
          'Instagram');
      expect(
          SocialSongService.platform('https://www.tiktok.com/@user/video/12345'),
          'TikTok');
    });

    test('SocialSongService.extractLink supports all three platforms seamlessly',
        () {
      // YouTube
      expect(
          SocialSongService.extractLink('https://youtu.be/$validVideoId')?.toString(),
          'https://www.youtube.com/watch?v=$validVideoId');
      // TikTok
      expect(
          TikTokSongService.extractLink(
              'https://vt.tiktok.com/ZSjX12345/'),
          isNotNull);
      expect(
          SocialSongService.extractLink(
              'https://vt.tiktok.com/ZSjX12345/'),
          isNotNull);
      // Instagram
      expect(
          InstagramSongService.extractLink(
              'https://www.instagram.com/reel/C5WTtLuPrkq/'),
          isNotNull);
      expect(
          SocialSongService.extractLink(
              'https://www.instagram.com/reel/C5WTtLuPrkq/',
              includeInstagram: true),
          isNotNull);
      expect(
          SocialSongService.extractLink(
              'https://www.instagram.com/reel/C5WTtLuPrkq/'),
          isNull);
    });
  });
}
