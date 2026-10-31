import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'youtube_music_catalog.dart';
import 'karaoke_metadata.dart';
import 'offline_storage_service.dart';
import '../config/api_config.dart';

class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);
}

class LyricsData {
  final List<LyricLine> syncedLines;
  final String? plainText;
  final bool instrumental;
  final String? source;
  final int? lrcDurationSeconds;
  final int suggestedOffsetMs;

  const LyricsData({
    required this.syncedLines,
    required this.plainText,
    required this.instrumental,
    this.source,
    this.lrcDurationSeconds,
    this.suggestedOffsetMs = 0,
  });

  bool get hasLyrics =>
      syncedLines.isNotEmpty ||
      (plainText != null && plainText!.trim().isNotEmpty);

  int activeLineAt(Duration position, {int offsetMs = 0}) {
    final effectivePosition = position - Duration(milliseconds: offsetMs);
    if (effectivePosition.isNegative) return -1;
    var active = -1;
    for (var index = 0; index < syncedLines.length; index++) {
      if (syncedLines[index].time > effectivePosition) break;
      active = index;
    }
    return active;
  }
}

class LyricsException implements Exception {
  final String message;

  const LyricsException(this.message);

  @override
  String toString() => message;
}

class LyricsService {
  LyricsService({http.Client? client, YoutubeMusicCatalog? youtubeMusic})
      : _client = client ?? http.Client(),
        _youtubeMusic = youtubeMusic ?? YoutubeMusicCatalog(client: client);

  final YoutubeMusicCatalog _youtubeMusic;

  static final LyricsService instance = LyricsService();

  final http.Client _client;
  final Map<String, Future<LyricsData?>> _cache = {};
  DateTime? _retryAfter;
  Future<void> _requestQueue = Future<void>.value();

  static final _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Cloudio/1.0.0 (https://${ApiConfig.resolverHost})',
  };

  Future<LyricsData?> getLyrics(Track track) {
    final key = track.isKaraoke ? 'karaoke:${track.id}' : track.id;
    return _cache.putIfAbsent(key, () async {
      try {
        final result = await _load(track);
        if (result == null) _cache.remove(key);
        return result;
      } catch (_) {
        _cache.remove(key);
        rethrow;
      }
    });
  }

  void clearCachedLyrics(String trackId) {
    _cache.remove(trackId);
    _cache.remove('karaoke:$trackId');
  }

  Future<void> saveCustomLyrics(Track track, List<LyricLine> syncedLines,
      {String? plainText}) async {
    final payload = {
      'syncedLines': syncedLines
          .map((l) => {'timeMs': l.time.inMilliseconds, 'text': l.text})
          .toList(),
      'plainText': plainText ?? syncedLines.map((l) => l.text).join('\n'),
      'instrumental': false,
      'source': 'Lirik Kustom (Tap to Sync)',
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await OfflineStorageService.instance
        .saveCustomLyrics(track.id, jsonEncode(payload));
    clearCachedLyrics(track.id);
  }

  Future<void> removeCustomLyrics(String trackId) async {
    await OfflineStorageService.instance.deleteCustomLyrics(trackId);
    clearCachedLyrics(trackId);
  }

  Future<LyricsData?> _load(Track track) async {
    // 1. Check local offline storage
    final localRaw = OfflineStorageService.instance.getLocalLyrics(track.id);
    if (localRaw != null && localRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(localRaw);
        if (decoded is Map<String, dynamic>) {
          final lines = (decoded['syncedLines'] as List? ?? [])
              .map((item) => LyricLine(
                    Duration(milliseconds: (item['timeMs'] as int?) ?? 0),
                    (item['text'] as String?) ?? '',
                  ))
              .toList();
          return LyricsData(
            syncedLines: lines,
            plainText: decoded['plainText'] as String?,
            instrumental: decoded['instrumental'] == true,
            source: decoded['source'] as String? ?? 'Offline Storage',
          );
        }
      } catch (_) {}
    }

    if (track.isTikTokSound) return null;
    if (track.isKaraoke) return _loadKaraoke(track);
    LyricsData? primary;
    Object? failure;
    try {
      primary = await _loadLrclib(track);
      if (primary != null &&
          (primary.syncedLines.isNotEmpty || primary.instrumental)) {
        return primary;
      }
    } catch (error) {
      failure = error;
    }

    // Fallback 1: Kugou Music (synced lyrics provider)
    LyricsData? secondary;
    try {
      secondary = await _loadKugou(track);
      if (secondary != null && secondary.syncedLines.isNotEmpty) {
        return secondary;
      }
    } catch (_) {}

    // Fallback 2: YouTube Music (plain text)
    try {
      final text = await _youtubeMusic.lyrics(track.cleanVideoId);
      if (text != null && text.trim().isNotEmpty) {
        if (primary?.hasLyrics == true) return primary;
        if (secondary?.hasLyrics == true) return secondary;
        return LyricsData(
            syncedLines: const [],
            plainText: text,
            instrumental: false,
            source: 'YouTube Music');
      }
    } catch (error) {
      failure ??= error;
    }
    if (primary?.hasLyrics == true) {
      return primary;
    }
    if (secondary?.hasLyrics == true) {
      return secondary;
    }
    if (failure != null) {
      throw const LyricsException('Lirik gagal dimuat. Coba lagi nanti.');
    }
    return null;
  }

  Future<LyricsData?> _loadKaraoke(Track track) async {
    final titleHint = KaraokeMetadata.songQuery(track.title);
    final queryHint = KaraokeMetadata.songQuery(track.karaokeQuery ?? '');
    final evidence = ' ${_normalize('$titleHint $queryHint ${track.artist}')} ';
    final queries = <String>{titleHint, queryHint}..remove('');
    for (final query in queries.take(2)) {
      final response =
          await _get(Uri.https('lrclib.net', '/api/search', {'q': query}));
      if (response.statusCode != 200) {
        throw const LyricsException('Lirik gagal dimuat. Coba lagi nanti.');
      }
      final records = jsonDecode(response.body);
      if (records is! List) continue;
      final matches = <Map<String, dynamic>>[];
      for (final value in records.whereType<Map>()) {
        final record = Map<String, dynamic>.from(value);
        final title = record['trackName'];
        final artist = record['artistName'];
        if (title is! String ||
            artist is! String ||
            record['instrumental'] == true) continue;
        final titleKey = _normalize(title);
        final artistKey = _normalize(artist);
        if (titleKey.isEmpty ||
            artistKey.isEmpty ||
            !evidence.contains(' $titleKey ') ||
            !evidence.contains(' $artistKey ')) continue;
        final lyrics = _lyricsFrom(record, trackDuration: track.duration);
        if (lyrics.hasLyrics) matches.add(record);
      }
      if (matches.isEmpty) continue;
      matches.sort((a, b) {
        final duration = track.duration?.inSeconds;
        if (duration == null) return 0;
        return (((a['duration'] as num?) ?? duration) - duration)
            .abs()
            .compareTo(
                (((b['duration'] as num?) ?? duration) - duration).abs());
      });

      final lyrics = _lyricsFrom(matches.first, trackDuration: track.duration);
      return LyricsData(
          syncedLines: lyrics.syncedLines,
          plainText: lyrics.plainText ??
              lyrics.syncedLines.map((line) => line.text).join('\n'),
          instrumental: false,
          source: 'LRCLIB · Karaoke otomatis',
          lrcDurationSeconds: lyrics.lrcDurationSeconds,
          suggestedOffsetMs: lyrics.suggestedOffsetMs,
      );
    }
    try {
      final kugou = await _loadKugou(track);
      if (kugou != null && kugou.syncedLines.isNotEmpty) {
        return LyricsData(
          syncedLines: kugou.syncedLines,
          plainText: kugou.plainText,
          instrumental: false,
          source: 'Kugou Music · Karaoke otomatis',
          lrcDurationSeconds: kugou.lrcDurationSeconds,
          suggestedOffsetMs: kugou.suggestedOffsetMs,
        );
      }
    } catch (_) {}
    return null;
  }


  Future<LyricsData?> _loadLrclib(Track track) async {
    final title = track.displayTitle.trim();
    final artist = track.displayArtist.trim();
    if (title.isEmpty || artist.isEmpty) return null;

    final signature = <String, String>{
      'track_name': title,
      'artist_name': artist,
      if (track.album != null && track.album!.trim().isNotEmpty)
        'album_name': track.album!.trim(),
      if (track.duration != null && track.duration!.inSeconds > 0)
        'duration': track.duration!.inSeconds.toString(),
    };
    final exactResponse = await _get(
      Uri.https('lrclib.net', '/api/get', signature),
    );
    if (exactResponse.statusCode == 200) {
      final record = _record(exactResponse.body);
      if (record != null && _matches(record, title, artist, track.duration)) {
        return _lyricsFrom(record, trackDuration: track.duration);
      }
    } else if (exactResponse.statusCode != 404) {
      throw const LyricsException('Lirik gagal dimuat. Coba lagi nanti.');
    }

    // Search without duration when a catalog upload has a different timeline.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final cleanTitle = title
        .replaceAll(
          RegExp(r'\s*[\(\[]\s*(?:feat|ft|with)\.?\s+[^\)\]]+[\)\]]',
              caseSensitive: false),
          '',
        )
        .trim();
    final searchResponse = await _get(Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      'artist_name': artist,
    }));
    if (searchResponse.statusCode != 200) {
      throw const LyricsException('Lirik gagal dimuat. Coba lagi nanti.');
    }
    var decoded = jsonDecode(searchResponse.body);
    if ((decoded is! List || decoded.isEmpty) && cleanTitle != title) {
      final retry = await _get(Uri.https('lrclib.net', '/api/search', {
        'track_name': cleanTitle,
        'artist_name': artist,
      }));
      if (retry.statusCode == 200) {
        final retryDecoded = jsonDecode(retry.body);
        if (retryDecoded is List) decoded = retryDecoded;
      }
    }
    if (decoded is! List) return null;
    final matches = decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _matches(item, title, artist, track.duration))
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final syncedA = (a['syncedLyrics'] as String?)?.isNotEmpty == true;
      final syncedB = (b['syncedLyrics'] as String?)?.isNotEmpty == true;
      if (syncedA != syncedB) return syncedA ? -1 : 1;
      final target = track.duration?.inSeconds;
      if (target == null) return 0;
      final differenceA = ((a['duration'] as num?)?.round() ?? target) - target;
      final differenceB = ((b['duration'] as num?)?.round() ?? target) - target;
      return differenceA.abs().compareTo(differenceB.abs());
    });
    return _lyricsFrom(matches.first, trackDuration: track.duration);
  }

  Future<http.Response> _get(Uri uri) {
    final request = _requestQueue.then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return _request(uri);
    });
    _requestQueue = request.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return request;
  }

  Future<http.Response> _request(Uri uri) async {
    final retryAfter = _retryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      throw const LyricsException(
          'Server lirik sedang sibuk. Coba lagi nanti.');
    }
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 429) {
        final seconds =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
        _retryAfter = DateTime.now().add(Duration(seconds: seconds));
        throw const LyricsException(
            'Server lirik sedang sibuk. Coba lagi nanti.');
      }
      return response;
    } on LyricsException {
      rethrow;
    } catch (_) {
      throw const LyricsException('Periksa koneksi lalu coba muat lirik lagi.');
    }
  }

  Map<String, dynamic>? _record(String body) {
    final value = jsonDecode(body);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  bool _matches(
    Map<String, dynamic> record,
    String title,
    String artist,
    Duration? duration,
  ) {
    final recordTitle = record['trackName'] ?? record['name'];
    final recordArtist = record['artistName'];
    if (recordTitle is! String || recordArtist is! String) return false;
    final titleKey = _normalize(title);
    final cleanTitle = title.replaceAll(
      RegExp(r'\s*[\(\[]\s*(?:feat|ft|with)\.?\s+[^\)\]]+[\)\]]',
          caseSensitive: false),
      '',
    );
    final cleanKey = _normalize(cleanTitle);
    final normRecordTitle = _normalize(recordTitle);
    final artistKey = _normalize(artist);
    final foundArtist = _normalize(recordArtist);
    if (titleKey.isEmpty ||
        artistKey.isEmpty ||
        foundArtist.isEmpty ||
        (normRecordTitle != titleKey && normRecordTitle != cleanKey) ||
        !(foundArtist.contains(artistKey) || artistKey.contains(foundArtist))) {
      return false;
    }
    final seconds = duration?.inSeconds;
    final recordDuration = record['duration'];
    if (seconds != null && seconds > 0 && recordDuration is num) {
      final isSynced = (record['syncedLyrics'] as String?)?.isNotEmpty == true;
      final maxDiff = isSynced ? 20 : 40;
      return (recordDuration - seconds).abs() <= maxDiff;
    }
    return true;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  LyricsData _lyricsFrom(Map<String, dynamic> record,
      {Duration? trackDuration}) {
    final synced = record['syncedLyrics'];
    final plain = record['plainLyrics'];
    final lrcDuration = (record['duration'] as num?)?.round();
    final parsedLines =
        synced is String ? parseLrc(synced) : const <LyricLine>[];

    int suggestedOffset = 0;
    if (trackDuration != null &&
        lrcDuration != null &&
        lrcDuration > 0 &&
        parsedLines.isNotEmpty) {
      final diffSeconds = trackDuration.inSeconds - lrcDuration;
      // In YouTube audio uploads, 2 to 20 seconds difference is typically intro prelude
      if (diffSeconds >= 2 && diffSeconds <= 20) {
        suggestedOffset = diffSeconds * 1000;
      }
    }

    return LyricsData(
      syncedLines: parsedLines,
      plainText:
          plain is String && plain.trim().isNotEmpty ? plain.trim() : null,
      instrumental: record['instrumental'] == true,
      source: 'LRCLIB',
      lrcDurationSeconds: lrcDuration,
      suggestedOffsetMs: suggestedOffset,
    );
  }

  static List<LyricLine> parseLrc(String source) {
    final timestamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final offsetRegex =
        RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
    int headerOffsetMs = 0;
    final offsetMatch = offsetRegex.firstMatch(source);
    if (offsetMatch != null) {
      headerOffsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
    }

    final lines = <LyricLine>[];
    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final matches = timestamp.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;
      final words = rawLine.substring(matches.last.end).trim();
      if (words.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = match.group(3) ?? '0';
        final milliseconds =
            int.parse(fraction.padRight(3, '0').substring(0, 3));
        final totalMs = (minutes * 60 * 1000) +
            (seconds * 1000) +
            milliseconds +
            headerOffsetMs;
        lines.add(
          LyricLine(
            Duration(milliseconds: totalMs.clamp(0, 86400000)),
            words,
          ),
        );
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  Future<LyricsData?> _loadKugou(Track track) async {
    final title = track.displayTitle.trim();
    final artist = track.displayArtist.trim();
    if (title.isEmpty && artist.isEmpty) return null;

    final cleanTitle = title
        .replaceAll(
          RegExp(
              r'\s*[\(\[]\s*(?:feat|ft|with|official|video|audio|lyrics?|lirik)\.?\s*[^\)\]]*[\)\]]',
              caseSensitive: false),
          '',
        )
        .trim();

    final query =
        cleanTitle.isNotEmpty ? '$cleanTitle $artist' : '$title $artist';
    final searchUri = Uri.http('mobilecdn.kugou.com', '/api/v3/search/song', {
      'format': 'json',
      'keyword': query,
      'page': '1',
      'pagesize': '6',
    });

    try {
      final searchRes = await _client.get(
        searchUri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (searchRes.statusCode != 200) return null;
      final data = jsonDecode(searchRes.body);
      if (data is! Map<String, dynamic>) return null;

      final rawList = data['data']?['info'];
      if (rawList is! List || rawList.isEmpty) return null;

      final items = rawList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((item) =>
              _matchesKugou(item, title, cleanTitle, artist, track.duration))
          .toList();

      if (items.isEmpty) return null;

      items.sort((a, b) {
        final target = track.duration?.inSeconds;
        if (target == null) return 0;
        final durA = (a['duration'] as num?)?.round() ?? target;
        final durB = (b['duration'] as num?)?.round() ?? target;
        return (durA - target).abs().compareTo((durB - target).abs());
      });

      for (final item in items.take(3)) {
        final hash = item['hash'] as String?;
        final durationSec = (item['duration'] as num?)?.round() ?? 0;
        if (hash == null || hash.isEmpty) continue;

        final lyricUri = Uri.http('m.kugou.com', '/app/i/krc.php', {
          'cmd': '100',
          'hash': hash,
          'timelength': (durationSec * 1000).toString(),
        });

        final lyricRes = await _client.get(
          lyricUri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
          },
        ).timeout(const Duration(seconds: 4));

        if (lyricRes.statusCode != 200) continue;
        final rawLrc = lyricRes.body;
        if (rawLrc.trim().isEmpty) continue;

        final lines = parseLrc(rawLrc);
        if (lines.length >= 3) {
          int suggestedOffset = 0;
          if (track.duration != null && durationSec > 0) {
            final diff = track.duration!.inSeconds - durationSec;
            if (diff >= 2 && diff <= 20) {
              suggestedOffset = diff * 1000;
            }
          }

          return LyricsData(
            syncedLines: lines,
            plainText: lines.map((l) => l.text).join('\n'),
            instrumental: false,
            source: 'Kugou Music',
            lrcDurationSeconds: durationSec,
            suggestedOffsetMs: suggestedOffset,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  bool _matchesKugou(
    Map<String, dynamic> item,
    String title,
    String cleanTitle,
    String artist,
    Duration? duration,
  ) {
    final songName = item['songname'];
    final singerName = item['singername'];
    if (songName is! String || singerName is! String) return false;

    final normSong = _normalize(songName);
    final normSinger = _normalize(singerName);
    final normTitle = _normalize(title);
    final normCleanTitle = _normalize(cleanTitle);
    final normArtist = _normalize(artist);

    if (normArtist.isNotEmpty &&
        !normSinger.contains(normArtist) &&
        !normArtist.contains(normSinger)) {
      return false;
    }

    final titleMatch = normTitle.isNotEmpty &&
        (normSong.contains(normTitle) ||
            normTitle.contains(normSong) ||
            (normCleanTitle.isNotEmpty &&
                (normSong.contains(normCleanTitle) ||
                    normCleanTitle.contains(normSong))));
    if (!titleMatch) return false;

    final target = duration?.inSeconds;
    final dur = (item['duration'] as num?)?.round();
    if (target != null && target > 0 && dur != null && dur > 0) {
      if ((dur - target).abs() > 35) {
        return false;
      }
    }
    return true;
  }
}
