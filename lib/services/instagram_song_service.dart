import 'dart:convert';

import 'package:http/http.dart' as http;

import 'social_media_http.dart';
import 'tiktok_song_service.dart';

class InstagramMusicPost {
  const InstagramMusicPost({this.media = const [], this.song});
  final List<Uri> media;
  final TikTokSong? song;
}

/// Reads only public post data. Never uses cookies or follows login redirects.
class InstagramSongService {
  InstagramSongService({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, InstagramMusicPost>{};
  final _pending = <String, Future<InstagramMusicPost>>{};
  static const headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Accept-Language': 'id,en;q=0.9',
    'Referer': 'https://www.instagram.com/',
  };
  static const crawlerHeaders = {
    'User-Agent':
        'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'id,en;q=0.9',
  };
  static final _link = RegExp(
    r'''https?://(?:www\.|m\.)?instagram\.com/[^\s<>"']+''',
    caseSensitive: false,
  );

  static bool isPageHost(Uri uri) =>
      const ['instagram.com', 'www.instagram.com', 'm.instagram.com']
          .contains(uri.host.toLowerCase()) &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      uri.scheme == 'https';

  static String? shortcode(Uri uri) {
    final parts = uri.pathSegments;
    return parts.length >= 2 &&
            const ['reel', 'reels', 'p', 'tv'].contains(parts[0]) &&
            parts[1] != 'audio' &&
            RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[1])
        ? parts[1]
        : null;
  }

  static String? _shareCode(Uri uri) {
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (parts.length >= 3 &&
        parts[0] == 'share' &&
        const ['reel', 'reels', 'p', 'tv'].contains(parts[1]) &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[2])) {
      return parts[2];
    }
    return null;
  }

  static Uri? extractLink(String text) {
    final match = _link.firstMatch(text);
    if (match == null) return null;
    final uri = Uri.tryParse(
        match.group(0)!.replaceAll(RegExp(r'[\)\]\}.,;!?]+$'), ''));
    if (uri == null || !isPageHost(uri.replace(scheme: 'https'))) return null;
    final normalized = uri.replace(scheme: 'https');
    // Share links are resolved through redirects, then bound to a shortcode.
    if (shortcode(normalized) == null &&
        !RegExp(r'^/share/(?:reel|reels|p|tv)/[A-Za-z0-9_-]+/?$')
            .hasMatch(normalized.path)) return null;
    return Uri(scheme: 'https', host: normalized.host, path: normalized.path);
  }

  static bool isMediaHost(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      const ['cdninstagram.com', 'fbcdn.net'].any((host) =>
          uri.host.toLowerCase() == host ||
          uri.host.toLowerCase().endsWith('.$host'));

  Future<InstagramMusicPost> resolvePost(String input) async {
    final uri = extractLink(input);
    if (uri == null) {
      throw const TikTokSongException(
          'Tempel link Reel atau post Instagram yang valid.');
    }
    final key = shortcode(uri) ?? _shareCode(uri) ?? uri.toString();
    final cached = _cache[key];
    if (cached != null) return cached;
    return _pending.putIfAbsent(key, () async {
      try {
        final post = await _readPost(uri);
        // Signed media URLs expire; retain only for this lookup/fallback.
        if (_cache.length >= 10) _cache.remove(_cache.keys.first);
        if (post.media.isNotEmpty || post.song != null) _cache[key] = post;
        return post;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<InstagramMusicPost> _readPost(Uri uri) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final isShare = _shareCode(uri) != null;
        final expectedCode = isShare ? null : shortcode(uri);
        final page = await readSocialMedia(_client, uri,
            allowed: (next) =>
                isPageHost(next) &&
                (shortcode(next) != null ||
                    extractLink(next.toString()) != null) &&
                (expectedCode == null || shortcode(next) == expectedCode),
            headers: attempt == 0 ? crawlerHeaders : headers);
        if (page != null) {
          final code = shortcode(page.uri) ?? (isShare ? _shareCode(uri) : null);
          if (code == null ||
              (shortcode(uri) != null && code != shortcode(uri))) break;
          final post = parsePost(socialPageText(page.bytes), code);
          if (post.media.isNotEmpty || post.song != null) return post;
          uri = Uri.https('www.instagram.com', '/p/$code/embed/');
        } else {
          final code = shortcode(uri) ?? (isShare ? _shareCode(uri) : null);
          if (code == null) break;
          uri = Uri.https('www.instagram.com', '/p/$code/embed/');
        }
      } catch (_) {
        final code = shortcode(uri) ?? _shareCode(uri);
        if (code == null) break;
        uri = Uri.https('www.instagram.com', '/p/$code/embed/');
      }
    }
    throw const TikTokSongException(
        'Audio Instagram belum dapat dibaca. Gunakan Reel/post publik; '
        'konten privat atau yang meminta login tidak didukung. '
        'Coba Kenali lagu saat audionya terdengar, atau isi judul lagu.');
  }

  InstagramMusicPost parsePost(String html, String code) {
    final media = <Uri>{};
    TikTokSong? song;
    void addMedia(dynamic value) {
      if (value is! String) return;
      final uri = Uri.tryParse(_decode(value));
      if (uri != null && isMediaHost(uri)) media.add(uri);
    }

    void readItem(Map item) {
      if (item['is_private'] == true) return;
      addMedia(item['video_url']);
      final versions = item['video_versions'];
      if (versions is List) {
        for (final version in versions.whereType<Map>()) {
          addMedia(version['url']);
        }
      }
      final clips = item['clips_metadata'];
      if (clips is Map) {
        final original = clips['original_sound_info'];
        if (original is Map) addMedia(original['progressive_download_url']);
        final music = clips['music_info'];
        final asset = music is Map ? music['music_asset_info'] : null;
        if (asset is Map && clips['audio_type'] != 'original_sounds') {
          final title = asset['title'];
          final artist = asset['display_artist'];
          if (title is String &&
              artist is String &&
              title.trim().isNotEmpty &&
              artist.trim().isNotEmpty &&
              !RegExp(r'original audio|original sound|suara asli',
                      caseSensitive: false)
                  .hasMatch(title)) {
            song ??= TikTokSong(title.trim(), artist: artist.trim());
          }
        }
      }
    }

    // Relay JSON may contain JSON strings nested inside __bbox/result payloads.
    // Only maps carrying the exact requested shortcode can contribute media.
    void walk(dynamic node, int depth) {
      if (depth > 35) return;
      if (node is Map) {
        if (node['shortcode'] == code || node['code'] == code) {
          readItem(node);
          return;
        }
        for (final value in node.values) {
          walk(value, depth + 1);
        }
      } else if (node is List) {
        for (final value in node) {
          walk(value, depth + 1);
        }
      } else if (node is String &&
          (node.startsWith('{') || node.startsWith('['))) {
        try {
          walk(jsonDecode(node), depth + 1);
        } catch (_) {}
      }
    }

    for (final script
        in RegExp(r'<script\b[^>]*>([\s\S]*?)</script>', caseSensitive: false)
            .allMatches(html)) {
      var body = script.group(1)!.trim();
      if (body.startsWith('window._sharedData =')) {
        body = body
            .substring(body.indexOf('=') + 1)
            .trim()
            .replaceFirst(RegExp(r';$'), '');
      }
      try {
        walk(jsonDecode(body), 0);
      } catch (_) {}
    }
    final meta = <String, String>{};
    for (final tag
        in RegExp(r'<meta\b([^>]*)>', caseSensitive: false).allMatches(html)) {
      final attrs = tag.group(1)!;
      final name = _attribute(attrs, 'property') ?? _attribute(attrs, 'name');
      final content = _attribute(attrs, 'content');
      if (name != null && content != null) meta[name] = _decode(content);
    }
    // OpenGraph is page scoped, so require its canonical post identity first.
    final canonical = Uri.tryParse(meta['og:url'] ?? '');
    if (canonical != null &&
        isPageHost(canonical) &&
        shortcode(canonical) == code) {
      addMedia(meta['og:video:secure_url']);
      addMedia(meta['og:video']);
    }
    return InstagramMusicPost(media: media.take(3).toList(), song: song);
  }

  static String? _attribute(String attrs, String name) =>
      RegExp('\\b$name\\s*=\\s*(["\'])([\\s\\S]*?)\\1', caseSensitive: false)
          .firstMatch(attrs)
          ?.group(2);
  static String _decode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  void clearCache() => _cache.clear();
  void close() => _client.close();
}
