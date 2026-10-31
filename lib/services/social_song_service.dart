import 'package:http/http.dart' as http;

import 'instagram_song_service.dart';
import 'tiktok_song_service.dart';

class SocialSongService {
  SocialSongService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  late final _tiktok = TikTokSongService(client: _client);
  late final _instagram = InstagramSongService(client: _client);

  static final _youtubeRegex = RegExp(
    r'''(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch\?(?:[^\s<>"']*&)?v=|shorts/|embed/)|youtu\.be/)([a-zA-Z0-9_-]{11})''',
    caseSensitive: false,
  );

  static bool isYouTubeLink(String text) => _youtubeRegex.hasMatch(text);

  static String? extractYouTubeVideoId(String text) {
    final match = _youtubeRegex.firstMatch(text);
    return match?.group(1);
  }

  static Uri? extractYouTubeLink(String text) {
    final id = extractYouTubeVideoId(text);
    return id != null ? Uri.parse('https://www.youtube.com/watch?v=$id') : null;
  }

  static Uri? extractLink(String text, {bool includeInstagram = false}) =>
      extractYouTubeLink(text) ??
      TikTokSongService.extractLink(text) ??
      (includeInstagram ? InstagramSongService.extractLink(text) : null);

  static String platform(String text) {
    if (isYouTubeLink(text)) return 'YouTube';
    if (InstagramSongService.extractLink(text) != null) return 'Instagram';
    return 'TikTok';
  }

  static bool isMediaHost(String input, Uri uri) =>
      platform(input) == 'Instagram'
          ? InstagramSongService.isMediaHost(uri)
          : TikTokSongService.isAudioHost(uri);

  Future<List<Uri>> resolveMedia(String input) async =>
      platform(input) == 'Instagram'
          ? (await _instagram.resolvePost(input)).media
          : _tiktok.resolveAudioUrls(input);

  Future<TikTokSong> resolveSong(String input) async {
    if (platform(input) != 'Instagram') return _tiktok.resolve(input);
    final song = (await _instagram.resolvePost(input)).song;
    if (song != null) return song;
    throw const TikTokSongException(
        'Audio belum dikenali dan judul musik Instagram tidak tersedia. '
        'Coba Kenali lagu atau isi judul lagunya.');
  }

  void clearMediaCache() => _instagram.clearCache();
  void close() => _client.close();
}
