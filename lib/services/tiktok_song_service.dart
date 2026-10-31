import 'dart:convert';

import 'package:http/http.dart' as http;

import 'social_media_http.dart';

class TikTokSong {
  const TikTokSong(this.title, {this.artist, this.isHint = false});
  final String title;
  final String? artist;

  /// Explicit caption labels are clues, not confirmed sound metadata.
  final bool isHint;
  String get query => [title, if (artist != null) artist!].join(' ');
}

class TikTokSongException implements Exception {
  const TikTokSongException(this.message);
  final String message;
}

/// Reads public sound metadata. This does not fingerprint the video's audio.
class TikTokSongService {
  TikTokSongService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final Map<String, TikTokSong> _cache = {};
  final Map<String, Future<TikTokSong>> _pending = {};
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Accept-Language': 'id,en;q=0.9'
  };
  static final _link = RegExp(
    r'''https?://(?:www\.|m\.|vm\.|vt\.)?tiktok\.com/[^\s<>"']+''',
    caseSensitive: false,
  );

  static Uri? extractLink(String text) {
    final match = _link.firstMatch(text);
    if (match == null) return null;
    final value = match.group(0)!.replaceAll(RegExp(r'[\)\]\}.,;!?]+$'), '');
    final uri = Uri.tryParse(value);
    return uri != null && _isTikTok(uri) ? uri.replace(scheme: 'https') : null;
  }

  static bool _isTikTok(Uri uri) =>
      const [
        'tiktok.com',
        'www.tiktok.com',
        'm.tiktok.com',
        'vm.tiktok.com',
        'vt.tiktok.com'
      ].contains(uri.host.toLowerCase()) &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443 || uri.port == 80) &&
      (uri.scheme == 'https' || uri.scheme == 'http');

  static bool isAudioHost(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      const [
        'tiktokcdn.com',
        'tiktokcdn-us.com',
        'tiktokcdn-eu.com',
        'tiktokcdn-eu2.com',
        'tiktokv.com',
        'tiktok.com',
        'byteoversea.com',
        'ibytedtos.com',
        'muscdn.com'
      ].any((host) => uri.host == host || uri.host.endsWith('.$host'));

  /// Only the requested post's actual music/video media, never recommendations.
  Future<Uri?> resolveAudioUrl(String input) async {
    final urls = await resolveAudioUrls(input);
    return urls.isEmpty ? null : urls.first;
  }

  Future<List<Uri>> resolveAudioUrls(String input) async {
    final uri = extractLink(input);
    if (uri == null) return [];
    final page = await readSocialMedia(_client, uri,
        allowed: _isTikTok, headers: _headers);
    if (page == null) return [];
    final match = RegExp(r'/(?:video|photo)/(\d+)').firstMatch(page.uri.path);
    if (match == null) return [];
    final requestedId =
        RegExp(r'/(?:video|photo)/(\d+)').firstMatch(uri.path)?.group(1);
    if (requestedId != null && requestedId != match.group(1)) return [];
    return parseAudioUrls(socialPageText(page.bytes), match.group(1)!);
  }

  Uri? parseAudioUrl(String html, String postId) {
    final urls = parseAudioUrls(html, postId);
    return urls.isEmpty ? null : urls.first;
  }

  List<Uri> parseAudioUrls(String html, String postId) {
    final urls = <Uri>{};
    void collect(dynamic value) {
      if (value is String) {
        final uri = Uri.tryParse(_decode(value));
        if (uri != null && isAudioHost(uri)) urls.add(uri);
      } else if (value is List) {
        for (final candidate in value) {
          collect(candidate);
        }
      } else if (value is Map) {
        collect(value['UrlList'] ?? value['url_list'] ?? value['urlList']);
      }
    }

    for (final script
        in RegExp(r'<script\b([^>]*)>([\s\S]*?)</script>', caseSensitive: false)
            .allMatches(html)) {
      final id = _attribute(script.group(1)!, 'id');
      if (id != '__UNIVERSAL_DATA_FOR_REHYDRATION__' && id != 'SIGI_STATE') {
        continue;
      }
      try {
        final data = jsonDecode(script.group(2)!);
        if (data is! Map) continue;
        final scope = data['__DEFAULT_SCOPE__'];
        final detail = scope is Map
            ? scope['webapp.video-detail'] ?? scope['webapp.photo-detail']
            : null;
        final info = detail is Map ? detail['itemInfo'] : null;
        final modules = data['ItemModule'];
        final item = info is Map
            ? info['itemStruct']
            : modules is Map
                ? modules[postId]
                : null;
        if (item is! Map || item['id']?.toString() != postId) continue;
        final music = item['music'];
        final video = item['video'];
        // The video's soundtrack includes edits; the named music can differ.
        if (video is Map) {
          collect(video['playAddr']);
          final bitrates = video['bitrateInfo'];
          if (bitrates is List) {
            for (final bitrate in bitrates.whereType<Map>()) {
              collect(bitrate['PlayAddr']);
            }
          }
        }
        if (music is Map) collect(music['playUrl']);
      } catch (_) {/* Try the other supported payload. */}
    }
    // Keep the music fallback even if a post has many video renditions.
    final candidates = urls.toList();
    return candidates.length <= 3
        ? candidates
        : [candidates.first, candidates[1], candidates.last];
  }

  Future<TikTokSong> resolve(String input) async {
    final link = extractLink(input);
    if (link == null) {
      throw const TikTokSongException('Tempel link video TikTok yang valid.');
    }
    final key = link.replace(query: '', fragment: '').toString();
    final cached = _cache[key];
    if (cached != null) return cached;
    return _pending.putIfAbsent(key, () async {
      try {
        final song = await _resolve(key).timeout(
          const Duration(seconds: 35),
          onTimeout: () => throw const TikTokSongException(
            'TikTok terlalu lama merespons. Coba lagi atau isi judul lagunya.',
          ),
        );
        if (_cache.length >= 40) _cache.remove(_cache.keys.first);
        _cache[key] = song;
        return song;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<TikTokSong> _resolve(String input) async {
    var uri = extractLink(input);
    if (uri == null) {
      throw const TikTokSongException('Tempel link video TikTok yang valid.');
    }
    try {
      String? page;
      // Short share links need their canonical video URL before oEmbed.
      if (!RegExp(r'/@[^/]+/(?:video|photo)/\d+|/music/[^/]+')
          .hasMatch(uri.path)) {
        for (var hop = 0; hop < 5; hop++) {
          final request = http.Request('GET', uri!)
            ..headers.addAll(_headers)
            ..followRedirects = false;
          final response = await _client
              .send(request)
              .then(http.Response.fromStream)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode >= 300 && response.statusCode < 400) {
            final location = response.headers['location'];
            if (location == null) break;
            final next = uri.resolve(location);
            if (!_isTikTok(next)) {
              throw const TikTokSongException(
                  'Link tidak mengarah ke video TikTok publik.');
            }
            uri = next.replace(scheme: 'https');
            if (uri.path.contains('/video/') ||
                uri.path.contains('/photo/') ||
                uri.path.contains('/music/')) {
              break;
            }
          } else {
            if (response.statusCode == 200) page = response.body;
            break;
          }
        }
      }
      if (!RegExp(r'/@[^/]+/(?:video|photo)/\d+|/music/[^/]+')
          .hasMatch(uri!.path)) {
        throw const TikTokSongException(
            'Gunakan link video TikTok publik, bukan link profil.');
      }

      TikTokSong? embedded;
      Uri? soundLink;
      // TikTok oEmbed accepts photo post IDs through its video URL format.
      final embedUri = uri.path.contains('/photo/')
          ? uri.replace(path: uri.path.replaceFirst('/photo/', '/video/'))
          : uri;
      Future<void> readEmbed() async {
        try {
          final response = await _client
              .get(
                Uri.https(
                    'www.tiktok.com', '/oembed', {'url': embedUri.toString()}),
                headers: _headers,
              )
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data is Map && data['html'] is String) {
              final song = _fromEmbed(data['html'] as String);
              embedded = song;
              soundLink = _soundLinkFromEmbed(data['html'] as String);
            }
          }
        } catch (_) {
          // Try the public page if embeds are unavailable or sound is unnamed.
        }
      }

      // Read both in parallel: oEmbed often exposes only an uploader's sound
      // label, while the public page can link to the actual song and artist.
      await Future.wait([
        readEmbed(),
        if (page == null)
          () async {
            page = await _readPublicPage(uri!);
          }(),
      ]);
      final song =
          page == null ? null : await _fromPage(page!, _postIdentity(uri));
      if (song != null && !song.isHint) return song;
      if (embedded != null) return embedded!;
      if (soundLink != null && soundLink!.path != uri.path) {
        final soundPage = await _readPublicPage(soundLink!);
        if (soundPage != null) {
          final linked = await _fromPage(soundPage, _postIdentity(soundLink!));
          if (linked != null) return linked;
        }
      }
      if (song != null) return song;
      if (soundLink != null) {
        throw const TikTokSongException(
          'Sound TikTok terbaca, tetapi judul lagu aslinya tidak tersedia. Sound original ini perlu pengenalan audio; coba cari judul atau potongan liriknya.',
        );
      }
      if (page == null) {
        throw const TikTokSongException(
            'Video TikTok tidak dapat dibuka. Coba link video publik lainnya.');
      }
      throw const TikTokSongException(
        'Judul lagu belum terbaca dari TikTok. Jika sound-nya original atau video privat, coba cari judul lagunya langsung.',
      );
    } on TikTokSongException {
      rethrow;
    } catch (_) {
      throw const TikTokSongException(
          'Gagal membaca link TikTok. Periksa koneksi lalu coba lagi.');
    }
  }

  static String _postIdentity(Uri uri) =>
      RegExp(r'/(?:video|photo)/(\d+)').firstMatch(uri.path)?.group(1) ??
      uri.pathSegments.where((part) => part.isNotEmpty).last;

  Future<String?> _readPublicPage(Uri uri) async {
    try {
      final page = await readSocialMedia(_client, uri,
          allowed: _isTikTok, headers: _headers);
      if (page == null || _postIdentity(page.uri) != _postIdentity(uri)) {
        return null;
      }
      return socialPageText(page.bytes);
    } catch (_) {
      return null;
    }
  }

  TikTokSong? _fromEmbed(String html) {
    for (final anchor
        in RegExp(r'<a\b([^>]*)>([\s\S]*?)</a>', caseSensitive: false)
            .allMatches(html)) {
      final attrs = anchor.group(1)!;
      final href = _attribute(attrs, 'href');
      final uri = href == null ? null : Uri.tryParse(_decode(href));
      if (uri == null || !_isTikTok(uri) || !uri.path.startsWith('/music/')) {
        continue;
      }
      final title = _clean(_attribute(attrs, 'title') ?? anchor.group(2)!);
      if (_isNamedSound(title)) return TikTokSong(title);
    }
    return null;
  }

  Uri? _soundLinkFromEmbed(String html) {
    for (final anchor
        in RegExp(r'<a\b([^>]*)>', caseSensitive: false).allMatches(html)) {
      final href = _attribute(anchor.group(1)!, 'href');
      final uri = href == null ? null : Uri.tryParse(_decode(href));
      if (uri != null && _isTikTok(uri) && uri.path.startsWith('/music/')) {
        return uri;
      }
    }
    return null;
  }

  Future<TikTokSong?> _fromPage(String html, String videoId) async {
    for (final script
        in RegExp(r'<script\b([^>]*)>([\s\S]*?)</script>', caseSensitive: false)
            .allMatches(html)) {
      final id = _attribute(script.group(1)!, 'id');
      if (id != '__UNIVERSAL_DATA_FOR_REHYDRATION__' && id != 'SIGI_STATE') {
        continue;
      }
      try {
        final data = jsonDecode(script.group(2)!);
        if (data is! Map) continue;
        final scope = data['__DEFAULT_SCOPE__'];
        final detail = scope is Map
            ? scope['webapp.video-detail'] ?? scope['webapp.photo-detail']
            : null;
        final info = detail is Map ? detail['itemInfo'] : null;
        final modules = data['ItemModule'];
        // Ignore recommended videos: only inspect the requested video's sound.
        final item = info is Map
            ? info['itemStruct']
            : modules is Map
                ? modules[videoId]
                : null;
        // Some returned pages contain a different video (removed/private link).
        // Never use that video's music as the answer.
        if (item is Map &&
            item['id'] != null &&
            item['id'].toString() != videoId) continue;
        var song = await _findMusic(item);
        if (song != null) return song;
        if (item is Map) {
          final hint = _captionHint(item['desc']);
          if (hint != null) return hint;
        }
        final soundId = RegExp(r'(\d+)$').firstMatch(videoId)?.group(1);
        final soundDetail = scope is Map ? scope['webapp.music-detail'] : null;
        final musicInfo = soundDetail is Map ? soundDetail['musicInfo'] : null;
        final soundModules = data['MusicModule'];
        final music = musicInfo is Map
            ? musicInfo['music']
            : soundModules is Map
                ? soundModules[soundId]
                : null;
        if (music is Map &&
            soundId != null &&
            music['id']?.toString() == soundId) {
          song = await _findMusic({'music': music});
          if (song != null) return song;
        }
      } catch (_) {
        // An unavailable or malformed page should yield an actionable message.
      }
    }
    return null;
  }

  Future<TikTokSong?> _findMusic(dynamic node) async {
    if (node is Map) {
      final music = node['music'];
      if (music is Map) {
        final title =
            music['title'] is String ? _clean(music['title'] as String) : '';
        // A creator can rename original audio. Prefer linked catalog identity
        // even when that creator label looks like an ordinary song title.
        final referenced = await _fromMusicReferences(music);
        if (referenced != null) return _withSoundVersion(referenced, title);
        if (_isNamedSound(title)) {
          final author = music['authorName'];
          final artist = music['original'] != true &&
                  author is String &&
                  author.trim().isNotEmpty
              ? _clean(author)
              : null;
          return TikTokSong(title, artist: artist);
        }
      }
    }
    return null;
  }

  TikTokSong _withSoundVersion(TikTokSong song, String soundTitle) {
    final versions = {
      'Sped Up': RegExp(r'\b(?:sped\s*up|speed\s*up|nightcore)\b',
          caseSensitive: false),
      'Slowed': RegExp(r'\bslowed\b', caseSensitive: false),
      'Remix': RegExp(r'\bremix\b', caseSensitive: false),
      'Cello Version': RegExp(r'\bcello\b', caseSensitive: false),
    };
    final extra = versions.entries
        .where((entry) =>
            entry.value.hasMatch(soundTitle) &&
            !entry.value.hasMatch(song.title))
        .map((entry) => entry.key)
        .toList();
    return extra.isEmpty
        ? song
        : TikTokSong('${song.title} (${extra.join(', ')})',
            artist: song.artist);
  }

  TikTokSong? _captionHint(dynamic caption) {
    if (caption is! String) return null;
    final match = RegExp(
      r'(?:^|\n)\s*(?:judul\s+lagu|song(?:\s+title)?|music)\s*:\s*([^\n#]+)',
      caseSensitive: false,
    ).firstMatch(caption);
    final title = match == null ? '' : _clean(match.group(1)!);
    if (!_isNamedSound(title) || title.length < 3 || title.length > 120) {
      return null;
    }
    return TikTokSong(title, isHint: true);
  }

  Future<TikTokSong?> _fromMusicReferences(Map music) async {
    final dsp = music['tt2dsp'];
    final references = dsp is Map ? dsp['tt_to_dsp_song_infos'] : null;
    if (references is! List) return null;
    // Use only public song IDs; embedded service tokens are never forwarded.
    for (final reference in references.whereType<Map>().take(4)) {
      final id = reference['SongId']?.toString() ?? '';
      try {
        if (reference['Platform'] == 1 && RegExp(r'^\d+$').hasMatch(id)) {
          final response = await _client
              .get(Uri.https('itunes.apple.com', '/lookup', {
                'id': id,
                'entity': 'song',
                'country': 'US',
              }))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) continue;
          final data = jsonDecode(response.body);
          final results = data is Map ? data['results'] : null;
          if (results is! List) continue;
          for (final track in results.whereType<Map>()) {
            if (track['kind'] == 'song' && track['trackName'] is String) {
              return TikTokSong(_clean(track['trackName'] as String),
                  artist: track['artistName'] is String
                      ? _clean(track['artistName'] as String)
                      : null);
            }
          }
        } else if (reference['Platform'] == 3 &&
            RegExp(r'^[a-zA-Z0-9]{22}$').hasMatch(id)) {
          final response = await _client
              .get(Uri.https('open.spotify.com', '/oembed', {
                'url': 'https://open.spotify.com/track/$id',
              }))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) continue;
          final data = jsonDecode(response.body);
          if (data is Map && data['title'] is String) {
            final title = _clean(data['title'] as String);
            if (_isNamedSound(title)) return TikTokSong(title);
          }
        }
      } catch (_) {
        // A regional store lookup may fail; try the next linked music service.
      }
    }
    return null;
  }

  bool _isNamedSound(String title) =>
      title.isNotEmpty &&
      !RegExp(r'^(?:original\s+(?:sound|audio)|suara\s+asli|sonido\s+original|som\s+original)',
              caseSensitive: false)
          .hasMatch(title);

  String? _attribute(String attributes, String name) =>
      RegExp('\\b$name\\s*=\\s*["\']([^"\']*)["\']', caseSensitive: false)
          .firstMatch(attributes)
          ?.group(1);

  String _clean(String value) =>
      _decode(value.replaceAll(RegExp(r'<[^>]*>'), ' '))
          .replaceAll(RegExp(r'^[\s♬♪♫]+'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  String _decode(String text) {
    var result = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    result =
        result.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|\d+);'), (match) {
      final value = match.group(1)!;
      final code = int.tryParse(
          value.startsWith('x') ? value.substring(1) : value,
          radix: value.startsWith('x') ? 16 : 10);
      return code != null && code <= 0x10ffff
          ? String.fromCharCode(code)
          : match.group(0)!;
    });
    return result;
  }

  void close() => _client.close();
}
