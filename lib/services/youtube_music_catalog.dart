import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'music_search_filter.dart';

class CatalogPlaylist {
  final String browseId;
  final String title;

  const CatalogPlaylist({required this.browseId, required this.title});
}

/// Small, anonymous YouTube Music catalog client.
///
/// Discovery uses the same WEB_REMIX InnerTube surface as music.youtube.com.
/// Playback stays in [AudioResolverService], using the returned YouTube video ID.
class YoutubeMusicCatalog {
  YoutubeMusicCatalog({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _host = 'music.youtube.com';
  static const _clientVersion = '1.20241010.01.00';
  static const _songSearchParams = 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D';

  Map<String, String> get _headers => const {
        'Content-Type': 'application/json',
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
        'X-Youtube-Client-Name': '67',
        'X-Youtube-Client-Version': _clientVersion,
      };

  Map<String, dynamic> get _context => const {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': _clientVersion,
          'hl': 'id',
          'gl': 'ID',
        },
      };

  Future<List<Track>> searchSongs(
    String query, {
    int limit = 30,
  }) async {
    final data = await _post(
      'search',
      {
        'context': _context,
        'query': query.trim(),
        'params': _songSearchParams,
      },
    );

    final tracks = <Track>[];
    final seen = <String>{};
    for (final renderer in _findObjects(
      data,
      'musicResponsiveListItemRenderer',
    )) {
      final track = _trackFromSearchRenderer(renderer);
      if (track == null || !seen.add(track.cleanVideoId)) continue;
      tracks.add(track);
      if (tracks.length >= limit) break;
    }
    return tracks;
  }

  /// Community playlists; search rank is relevance, not a TikTok chart.
  Future<List<CatalogPlaylist>> searchPlaylists(String query,
      {int limit = 8}) async {
    if (limit <= 0) return [];
    final data = await _post(
        'search',
        {
          'context': _context,
          'query': query.trim(),
          'params': 'EgeKAQQoAEAB',
        },
        timeout: const Duration(seconds: 8));
    final playlists = <CatalogPlaylist>[];
    final seen = <String>{};
    for (final renderer
        in _findObjects(data, 'musicResponsiveListItemRenderer')) {
      final browse =
          _map(_map(renderer['navigationEndpoint'])?['browseEndpoint']);
      final id = _string(browse?['browseId']);
      final columns = _list(renderer['flexColumns']);
      final title = columns.isEmpty
          ? null
          : _text(_runsFromColumn(columns.first).firstOrNull?['text']);
      if (id == null ||
          !id.startsWith('VL') ||
          title == null ||
          !seen.add(id)) {
        continue;
      }
      playlists.add(CatalogPlaylist(browseId: id, title: title));
      if (playlists.length >= limit) break;
    }
    return playlists;
  }

  Future<List<Track>> playlistTracks(String browseId, {int limit = 30}) async {
    if (!browseId.startsWith('VL') || limit <= 0) return [];
    final data = await _post(
        'browse',
        {
          'context': _context,
          'browseId': browseId,
        },
        timeout: const Duration(seconds: 8));
    final tracks = <Track>[];
    final seen = <String>{};
    // Only playlist shelves: never include recommendations elsewhere on the page.
    for (final shelf in _findObjects(data, 'musicPlaylistShelfRenderer')) {
      for (final renderer in _findObjects(
          shelf['contents'], 'musicResponsiveListItemRenderer')) {
        if (renderer['isPlayable'] == false) continue;
        final track = _trackFromSearchRenderer(renderer);
        if (track == null || !seen.add(track.cleanVideoId)) continue;
        tracks.add(track);
        if (tracks.length >= limit) return tracks;
      }
    }
    return tracks;
  }

  Future<List<Track>> radio(
    String videoId, {
    int limit = 30,
  }) async {
    final cleanId = videoId.startsWith('ytm:') ? videoId.substring(4) : videoId;
    final data = await _post(
      'next',
      {
        'context': _context,
        'videoId': cleanId,
        'playlistId': 'RDAMVM$cleanId',
        'params': 'wAEB',
      },
    );

    final tracks = <Track>[];
    final seen = <String>{};
    for (final renderer in _findObjects(data, 'playlistPanelVideoRenderer')) {
      final track = _trackFromRadioRenderer(renderer);
      if (track == null || !seen.add(track.cleanVideoId)) continue;
      tracks.add(track);
      if (tracks.length >= limit) break;
    }
    return tracks;
  }

  Future<String?> lyrics(String videoId) async {
    final cleanId = videoId.startsWith('ytm:') ? videoId.substring(4) : videoId;
    final next = await _post('next', {'context': _context, 'videoId': cleanId},
        timeout: const Duration(seconds: 6));
    String? browseId;
    for (final tab in _findObjects(next, 'tabRenderer')) {
      if (tab['disabled'] == true) continue;
      for (final endpoint in _findObjects(tab, 'browseEndpoint')) {
        final id = _string(endpoint['browseId']);
        if (id != null && id.startsWith('MPLYt')) browseId = id;
      }
    }
    if (browseId == null) return null;
    final page = await _post(
        'browse', {'context': _context, 'browseId': browseId},
        timeout: const Duration(seconds: 6));
    for (final shelf in _findObjects(page, 'musicDescriptionShelfRenderer')) {
      final description = _map(shelf['description']);
      final text = description?['simpleText'] ??
          _runs(description?['runs']).map((run) => run['text'] ?? '').join();
      if (text is String && text.trim().isNotEmpty) return text.trim();
    }
    return null;
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final response = await _client
        .post(
          Uri.https(_host, '/youtubei/v1/$endpoint', {
            'prettyPrint': 'false',
          }),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'YouTube Music returned ${response.statusCode}',
        response.request?.url,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid YouTube Music response');
    }
    return decoded;
  }

  Track? _trackFromSearchRenderer(Map<String, dynamic> renderer) {
    // The songs-only request is the first filter. Reject explicit non-music
    // watch types as well, in case a mixed shelf appears in the response.
    const musicTypes = {
      'MUSIC_VIDEO_TYPE_ATV',
      'MUSIC_VIDEO_TYPE_OMV',
      'MUSIC_VIDEO_TYPE_UGC',
    };
    for (final config in _findObjects(
      renderer,
      'watchEndpointMusicSupportedConfigs',
    )) {
      final type = _string(
        _map(config['watchEndpointMusicConfig'])?['musicVideoType'],
      );
      if (type != null && !musicTypes.contains(type)) return null;
    }
    for (final config in _findObjects(
      renderer,
      'browseEndpointContextMusicConfig',
    )) {
      final type = _string(config['pageType']);
      if (type != null &&
          (type.contains('PODCAST') || type.contains('EPISODE'))) return null;
    }
    final columns = _list(renderer['flexColumns']);
    if (columns.isEmpty) return null;
    final titleRuns = _runsFromColumn(columns.first);
    final metadataRuns = columns.length > 1
        ? _runsFromColumn(columns[1])
        : const <Map<String, dynamic>>[];
    final videoId = _string(
          _map(renderer['playlistItemData'])?['videoId'],
        ) ??
        _videoIdFromRuns(titleRuns);
    final title = _text(titleRuns.isEmpty ? null : titleRuns.first['text']);
    final artist = _runForPageType(metadataRuns, 'MUSIC_PAGE_TYPE_ARTIST') ??
        _firstMeaningfulText(metadataRuns);
    if (videoId == null || title == null || artist == null) return null;
    final fixedDuration = _list(renderer['fixedColumns'])
        .map((column) =>
            _map(_map(column)?['musicResponsiveListItemFixedColumnRenderer']))
        .map((column) =>
            _durationFromRuns(_runs(_map(column?['text'])?['runs'])))
        .whereType<Duration>();
    final duration =
        _durationFromRuns(metadataRuns) ?? fixedDuration.firstOrNull;
    // Even a songs-only shelf can contain spoken uploads. Apply the same
    // duration and spoken-content rules as the general YouTube search.
    if (!MusicSearchFilter.isYouTubeSong(
      title: title,
      author: artist,
      description: metadataRuns.map((run) => run['text'] ?? '').join(' '),
      duration: duration,
      isLive: false,
      hasMusicMetadata: true,
    )) return null;

    return Track(
      id: 'ytm:$videoId',
      title: title,
      artist: artist,
      album: _runForPageType(metadataRuns, 'MUSIC_PAGE_TYPE_ALBUM'),
      artworkUrl: _thumbnail(renderer),
      duration: duration,
      provider: 'ytm',
    );
  }

  Track? _trackFromRadioRenderer(Map<String, dynamic> renderer) {
    final videoId = _string(renderer['videoId']);
    final titleRuns = _runs(_map(renderer['title'])?['runs']);
    final bylineRuns = _runs(_map(renderer['longBylineText'])?['runs']);
    final title = _text(titleRuns.isEmpty ? null : titleRuns.first['text']);
    final artist = _runForPageType(bylineRuns, 'MUSIC_PAGE_TYPE_ARTIST') ??
        _firstMeaningfulText(bylineRuns);
    if (videoId == null || title == null || artist == null) return null;

    return Track(
      id: 'ytm:$videoId',
      title: title,
      artist: artist,
      album: _runForPageType(bylineRuns, 'MUSIC_PAGE_TYPE_ALBUM'),
      artworkUrl: _thumbnail(renderer),
      duration: _durationFromText(
        _text(
          _runs(_map(renderer['lengthText'])?['runs']).firstOrNull?['text'],
        ),
      ),
      provider: 'ytm',
    );
  }

  Iterable<Map<String, dynamic>> _findObjects(
    dynamic node,
    String key,
  ) sync* {
    if (node is Map) {
      final value = node[key];
      if (value is Map) {
        yield Map<String, dynamic>.from(value);
      }
      for (final child in node.values) {
        yield* _findObjects(child, key);
      }
    } else if (node is List) {
      for (final child in node) {
        yield* _findObjects(child, key);
      }
    }
  }

  List<dynamic> _list(dynamic value) => value is List ? value : const [];

  Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  List<Map<String, dynamic>> _runs(dynamic value) =>
      _list(value).whereType<Map>().map(Map<String, dynamic>.from).toList();

  List<Map<String, dynamic>> _runsFromColumn(dynamic column) {
    final renderer = _map(
      _map(column)?['musicResponsiveListItemFlexColumnRenderer'],
    );
    return _runs(_map(renderer?['text'])?['runs']);
  }

  String? _videoIdFromRuns(List<Map<String, dynamic>> runs) {
    for (final run in runs) {
      final endpoint = _map(run['navigationEndpoint']);
      final watch = _map(endpoint?['watchEndpoint']);
      final id = _string(watch?['videoId']);
      if (id != null) return id;
    }
    return null;
  }

  String? _runForPageType(
    List<Map<String, dynamic>> runs,
    String pageType,
  ) {
    for (final run in runs) {
      final endpoint = _map(run['navigationEndpoint']);
      final browse = _map(endpoint?['browseEndpoint']);
      final configs = _map(
        browse?['browseEndpointContextSupportedConfigs'],
      );
      final musicConfig = _map(configs?['browseEndpointContextMusicConfig']);
      if (musicConfig?['pageType'] == pageType) {
        return _text(run['text']);
      }
    }
    return null;
  }

  String? _firstMeaningfulText(List<Map<String, dynamic>> runs) {
    for (final run in runs) {
      final value = _text(run['text']);
      if (value != null && value != '•' && _durationFromText(value) == null) {
        return value;
      }
    }
    return null;
  }

  Duration? _durationFromRuns(List<Map<String, dynamic>> runs) {
    for (final run in runs.reversed) {
      final duration = _durationFromText(_text(run['text']));
      if (duration != null) return duration;
    }
    return null;
  }

  Duration? _durationFromText(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(RegExp(r'[:.]'));
    if (parts.length < 2 || parts.length > 3) return null;
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((part) => part == null)) return null;
    if (numbers.last! > 59) return null;
    var seconds = 0;
    for (final number in numbers) {
      seconds = seconds * 60 + number!;
    }
    return Duration(seconds: seconds);
  }

  String? _thumbnail(Map<String, dynamic> renderer) {
    final thumbnail = _map(renderer['thumbnail']);
    final musicThumbnail = _map(thumbnail?['musicThumbnailRenderer']);
    final thumbnails = _list(
      _map(musicThumbnail?['thumbnail'])?['thumbnails'] ??
          thumbnail?['thumbnails'],
    );
    if (thumbnails.isEmpty) return null;
    final largest = _map(thumbnails.last);
    final url = _string(largest?['url']);
    return url?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
  }

  String? _string(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  String? _text(dynamic value) => _string(value);

  void close() => _client.close();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
