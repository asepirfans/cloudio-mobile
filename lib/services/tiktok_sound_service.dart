import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'social_media_http.dart';
import 'tiktok_song_service.dart';

class TikTokSound {
  const TikTokSound(
      {required this.track,
      required this.media,
      this.audioOnlyMedia = const {}});
  final Track track;
  final List<Uri> media;

  /// Original audio advertised for this creator's post with matching duration.
  /// The native result is also checked before it can be played.
  final Set<Uri> audioOnlyMedia;
}

/// Playback of the requested post, independent of recognition/YouTube matching.
class TikTokSoundService {
  TikTokSoundService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, ({DateTime time, TikTokSound sound})>{};
  final _selected = <String, int>{};
  static const playbackHeaders = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://www.tiktok.com/',
  };
  static const _pageHeaders = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Accept-Language': 'id,en;q=0.9',
  };

  Future<TikTokSound> resolve(String input, {bool refresh = false}) async {
    final uri = TikTokSongService.extractLink(input);
    if (uri == null) {
      throw const TikTokSongException('Link TikTok tidak valid.');
    }
    final key = uri.replace(query: '', fragment: '').toString();
    final cached = _cache[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.time) < const Duration(seconds: 90)) {
      return cached.sound;
    }
    final page = await readSocialMedia(_client, uri,
        allowed: (next) =>
            next.scheme == 'https' &&
            TikTokSongService.extractLink(next.toString()) != null,
        headers: _pageHeaders,
        timeout: const Duration(seconds: 18));
    final id = page == null ? null : _postId(page.uri);
    final requestedId = _postId(uri);
    if (id == null || (requestedId != null && id != requestedId)) {
      throw const TikTokSongException(
          'Post TikTok tidak dapat dibaca. Coba link post publik.');
    }
    final sound = parse(socialPageText(page!.bytes), id, page.uri);
    if (sound == null || sound.media.isEmpty) {
      throw const TikTokSongException(
          'Sound asli post ini belum dapat diakses. '
          'Coba lagi atau pilih Cari lagu lengkap.');
    }
    if (_cache.length >= 20) _cache.remove(_cache.keys.first);
    _cache[key] = (time: DateTime.now(), sound: sound);
    return sound;
  }

  static String? _postId(Uri uri) =>
      RegExp(r'/(?:video|photo)/(\d+)').firstMatch(uri.path)?.group(1);

  TikTokSound? parse(String html, String postId, Uri page) {
    for (final script
        in RegExp(r'<script\b([^>]*)>([\s\S]*?)</script>', caseSensitive: false)
            .allMatches(html)) {
      if (!RegExp(
              r'''\bid\s*=\s*["'](?:SIGI_STATE|__UNIVERSAL_DATA_FOR_REHYDRATION__)["']''')
          .hasMatch(script.group(1)!)) continue;
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
        final urls = <Uri>{};
        void collect(dynamic value) {
          if (value is String) {
            final uri = Uri.tryParse(value);
            if (uri != null && TikTokSongService.isAudioHost(uri)) {
              urls.add(uri);
            }
          } else if (value is List) {
            for (final entry in value) {
              collect(entry);
            }
          } else if (value is Map) {
            collect(value['UrlList'] ?? value['urlList'] ?? value['url_list']);
          }
        }

        final video = item['video'];
        final music = item['music'];
        final author = item['author'];
        final audioOnly = <Uri>{};
        if (video is Map) {
          // Long posts can expose a much smaller, separate original audio.
          // A reused/named song or a different-length edit is not equivalent.
          if (music is Map && author is Map && music['original'] == true) {
            final owner = music['authorName'];
            final seconds = video['duration'];
            final musicSeconds = music['duration'];
            final sameCreator = owner is String &&
                owner.trim().isNotEmpty &&
                [
                  author['uniqueId'],
                  author['nickname']
                ].whereType<String>().any((name) =>
                    name.trim().toLowerCase() == owner.trim().toLowerCase());
            if (sameCreator &&
                seconds is num &&
                seconds > 0 &&
                musicSeconds is num &&
                (seconds - musicSeconds).abs() <= 1) {
              collect(music['playUrl']);
              audioOnly.addAll(urls);
            }
          }
          collect(video['playAddr']);
          final bitrates = video['bitrateInfo'];
          if (bitrates is List) {
            for (final bitrate in bitrates.whereType<Map>()) {
              collect(bitrate['PlayAddr']);
            }
          }
          collect(video['downloadAddr']);
        } else if (item['imagePost'] is Map && music is Map) {
          collect(music['playUrl']);
        }
        // Other music URLs may be different edits or longer recordings.
        if (urls.isEmpty) continue;
        final creator =
            author is Map ? author['uniqueId'] ?? author['nickname'] : null;
        final label = music is Map ? music['title'] : null;
        final seconds = video is Map ? video['duration'] : null;
        final cover =
            video is Map ? video['cover'] ?? video['originCover'] : null;
        final canonical =
            Uri(scheme: 'https', host: 'www.tiktok.com', path: page.path);
        return TikTokSound(
            track: Track(
              id: 'tiktok:$postId',
              provider: 'tiktok',
              sourceUrl: canonical.toString(),
              title: label is String && label.trim().isNotEmpty
                  ? label.trim()
                  : 'Sound TikTok',
              artist: creator is String && creator.isNotEmpty
                  ? '@$creator'
                  : 'TikTok',
              album: 'TikTok · Cuplikan',
              artworkUrl:
                  cover is String && Uri.tryParse(cover)?.scheme == 'https'
                      ? cover
                      : null,
              duration: seconds is num && seconds > 0
                  ? Duration(milliseconds: (seconds * 1000).round())
                  : null,
            ),
            media: urls.take(4).toList(),
            audioOnlyMedia: audioOnly);
      } catch (_) {/* Try the other supported payload. */}
    }
    return null;
  }

  Future<String> playbackUrl(Track track, {int attempt = 0}) async {
    if (!track.isTikTokSound || track.sourceUrl == null) {
      throw const TikTokSongException('Sumber sound TikTok tidak tersedia.');
    }
    final sound = await resolve(track.sourceUrl!, refresh: attempt >= 3);
    final start = attempt >= 3
        ? 0
        : attempt > 0
            ? (_selected[track.id] ?? -1) + 1
            : 0;
    for (var index = start; index < sound.media.length; index++) {
      final uri = await _probe(sound.media[index]);
      if (uri == null) continue;
      _selected[track.id] = index;
      return uri.toString();
    }
    throw const TikTokSongException(
        'CDN TikTok belum dapat memutar sound ini. Coba lagi.');
  }

  Future<Uri?> _probe(Uri uri) async {
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      for (var hop = 0; hop < 4; hop++) {
        if (!TikTokSongService.isAudioHost(uri)) return null;
        final response = await _client
            .send(http.Request('GET', uri)
              ..followRedirects = false
              ..headers.addAll({...playbackHeaders, 'Range': 'bytes=0-1023'}))
            .timeout(deadline.difference(DateTime.now()));
        if (response.isRedirect) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null) return null;
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          await response.stream.listen((_) {}).cancel();
          return null;
        }
        final iterator = StreamIterator(response.stream);
        final prefix = <int>[];
        try {
          while (prefix.length < 12 &&
              await iterator
                  .moveNext()
                  .timeout(deadline.difference(DateTime.now()))) {
            prefix.addAll(iterator.current.take(12 - prefix.length));
          }
        } finally {
          await iterator.cancel();
        }
        final mp4 = prefix.length >= 8 &&
            ascii.decode(prefix.sublist(4, 8), allowInvalid: true) == 'ftyp';
        final mp3 = prefix.length >= 3 &&
            ascii.decode(prefix.take(3).toList(), allowInvalid: true) == 'ID3';
        final frame =
            prefix.length >= 2 && prefix[0] == 255 && (prefix[1] & 224) == 224;
        if (mp4 || mp3 || frame) return uri;
        return null;
      }
    } catch (_) {/* Try another post-bound CDN URL. */}
    return null;
  }

  void close() => _client.close();
}
