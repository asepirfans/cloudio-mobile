import 'dart:developer' as developer;

import '../models/track.dart';
import 'youtube_music_catalog.dart';

/// Discovers community-curated playlists, not an official TikTok chart.
/// Personalization only reorders songs that are actually in these playlists.
class TikTokPlaylistService {
  TikTokPlaylistService(this._catalog, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final YoutubeMusicCatalog _catalog;
  final DateTime Function() _now;
  List<Track> _cached = [];
  DateTime? _cachedAt;
  DateTime? _retryAfter;
  Future<List<Track>>? _pending;

  Future<List<Track>> songs({
    List<Track> recentlyPlayed = const [],
    List<Track> savedTracks = const [],
    List<String> favoriteArtists = const [],
    int limit = 20,
  }) async {
    if (limit <= 0) return [];
    final pool = await _pool();
    final affinity = <String, int>{};
    void add(String artist, int weight) {
      final key = _key(artist);
      if (key.isNotEmpty) {
        affinity.update(key, (value) => value + weight, ifAbsent: () => weight);
      }
    }

    for (final artist in favoriteArtists) {
      add(artist, 3);
    }
    for (final track in savedTracks.take(40)) {
      add(track.displayArtist, 2);
    }
    for (final track in recentlyPlayed.take(24)) {
      add(track.displayArtist, 1);
    }
    // Keep playlist order as a tie-breaker, including for new users.
    final ranked = pool.asMap().entries.toList()
      ..sort((a, b) {
        final score = (affinity[_key(b.value.displayArtist)] ?? 0)
            .compareTo(affinity[_key(a.value.displayArtist)] ?? 0);
        return score != 0 ? score : a.key.compareTo(b.key);
      });
    final selected = <Track>[];
    final deferred = <Track>[];
    final artists = <String, int>{};
    for (final entry in ranked) {
      final artist = _key(entry.value.displayArtist);
      if ((artists[artist] ?? 0) >= 2) {
        deferred.add(entry.value);
      } else {
        artists.update(artist, (value) => value + 1, ifAbsent: () => 1);
        selected.add(entry.value);
      }
    }
    return [...selected, ...deferred].take(limit).toList();
  }

  Future<List<Track>> _pool() async {
    final now = _now();
    if (_cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(hours: 6)) {
      return _cached;
    }
    if (_retryAfter != null && now.isBefore(_retryAfter!)) {
      return _usableCache(now);
    }
    return _pending ??= _discover().whenComplete(() => _pending = null);
  }

  List<Track> _usableCache(DateTime now) => _cachedAt != null &&
          now.difference(_cachedAt!) < const Duration(hours: 24)
      ? _cached
      : [];

  Future<List<T>> _safe<T>(Future<List<T>> Function() operation) async {
    try {
      return await operation();
    } catch (error) {
      developer.log('TikTok playlist source unavailable',
          name: 'TikTokPlaylist', error: error);
      return [];
    }
  }

  Future<List<Track>> _discover() async {
    final year = _now().year;
    final searches = await Future.wait([
      _safe(() => _catalog.searchPlaylists('TikTok Indonesia $year')),
      _safe(() => _catalog.searchPlaylists('TikTok hits $year')),
    ]);
    final ids = <String>{};
    final playlists = <CatalogPlaylist>[];
    for (final group in searches) {
      var count = 0;
      for (final playlist in group) {
        if (!RegExp(r'tik\s*tok', caseSensitive: false)
            .hasMatch(playlist.title)) continue;
        if (!ids.add(playlist.browseId)) continue;
        playlists.add(playlist);
        if (++count >= 2) break;
      }
    }
    final groups = await Future.wait([
      for (final playlist in playlists)
        _safe(() => _catalog.playlistTracks(playlist.browseId, limit: 30)),
    ]);
    final pool = <Track>[];
    final seenIds = <String>{};
    final seenSongs = <String>{};
    // Interleave playlists so one curator cannot fill the whole category.
    for (var row = 0; row < 30; row++) {
      for (final group in groups) {
        if (row >= group.length) continue;
        final track = group[row];
        if (track.duration != null &&
            track.duration! > const Duration(minutes: 12)) continue;
        final song = '${_key(track.displayTitle)}:${_key(track.displayArtist)}';
        if (seenIds.contains(track.cleanVideoId) || seenSongs.contains(song)) {
          continue;
        }
        seenIds.add(track.cleanVideoId);
        seenSongs.add(song);
        pool.add(track);
      }
    }
    if (pool.isNotEmpty) {
      _cached = List.unmodifiable(pool);
      _cachedAt = _now();
      _retryAfter = null;
      return _cached;
    }
    _retryAfter = _now().add(const Duration(minutes: 5));
    return _usableCache(_now());
  }

  String _key(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s*(- topic|official|vevo)\s*$'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}
