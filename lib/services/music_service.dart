import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';
import '../models/trending_chart.dart';
import 'music_search_filter.dart';
import 'karaoke_metadata.dart';
import 'youtube_music_catalog.dart';
import 'tiktok_playlist_service.dart';
import 'social_song_service.dart';

class HomeSection {
  final String category;
  final String title;
  final String subtitle;
  final List<Track> tracks;

  const HomeSection(this.category, this.title, this.subtitle, this.tracks);
}

class HomeFeed {
  final List<Track> forYou;
  final List<HomeSection> sections;

  const HomeFeed({
    required this.forYou,
    required this.sections,
  });
}

class MusicService {
  static final MusicService instance = MusicService._internal();
  MusicService._internal() : _youtubeMusic = YoutubeMusicCatalog();

  @visibleForTesting
  MusicService.forTesting(YoutubeMusicCatalog catalog)
      : _youtubeMusic = catalog;

  final YoutubeExplode _youtube = YoutubeExplode();
  final YoutubeMusicCatalog _youtubeMusic;
  late final TikTokPlaylistService _tiktokPlaylists =
      TikTokPlaylistService(_youtubeMusic);
  final Random _random = Random();

  static const _moods = <(String, String, String)>[
    ('Santai', 'lagu santai Indonesia', 'Untuk menemani waktu luang'),
    ('Semangat', 'lagu semangat pop', 'Buat menambah energi'),
    ('Galau', 'lagu galau Indonesia', 'Saat ingin larut dalam lagu'),
    ('Fokus', 'musik fokus akustik', 'Teman saat berkonsentrasi'),
    ('Perjalanan', 'lagu perjalanan road trip', 'Musik untuk di jalan'),
    ('Feel good', 'feel good pop songs', 'Lagu yang bikin suasana naik'),
  ];

  static const _discoveries = <(String, String, String)>[
    ('Indie', 'indie pop Indonesia terbaru', 'Temukan suara baru'),
    ('R&B', 'rnb terbaru', 'Pilihan R&B untukmu'),
    ('Pop', 'pop terbaru Indonesia', 'Rilisan pop pilihan'),
    ('K-Pop', 'kpop songs terbaru', 'Pilihan K-Pop terkini'),
    ('Akustik', 'lagu akustik Indonesia', 'Versi yang lebih intim'),
    ('Lagu lama', 'lagu nostalgia Indonesia', 'Putar kembali favorit lama'),
  ];

  static const _globalHeadliners = [
    'Bruno Mars',
    'Sienna Spiro',
    'Dua Lipa',
  ];

  static const _moreGlobalArtists = [
    'The Weeknd',
    'Billie Eilish',
    'Lady Gaga',
    'Sabrina Carpenter',
    'Olivia Rodrigo',
    'Ariana Grande',
    'Taylor Swift',
    'Ed Sheeran',
  ];

  /// Search both catalogs: some uploads exist on YouTube but not YouTube Music.
  Future<List<Track>> search(String query, {int limit = 30}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final searches = await Future.wait<List<Track>>([
      _searchMusicForSearch(cleanQuery, limit),
      _searchYouTube(cleanQuery, limit: limit),
    ]);
    return _mergeUnique(searches, limit: limit);
  }

  /// Resolves a direct YouTube / YouTube Shorts / YouTube Music video link into a playable [Track].
  Future<Track?> resolveYouTubeLink(String url) async {
    final videoId = SocialSongService.extractYouTubeVideoId(url);
    if (videoId == null) return null;
    try {
      final video = await _youtube.videos.get(videoId).timeout(
            const Duration(seconds: 12),
          );
      final songTitle = video.musicData.isNotEmpty
          ? (video.musicData.first.song ?? video.title)
          : video.title;
      final songArtist = video.musicData.isNotEmpty
          ? (video.musicData.first.artist ?? video.author)
          : video.author;
      final album =
          video.musicData.isNotEmpty ? video.musicData.first.album : null;
      final artwork = video.thumbnails.highResUrl.isNotEmpty
          ? video.thumbnails.highResUrl
          : video.thumbnails.mediumResUrl;

      return Track(
        id: 'ytm:${video.id.value}',
        title: songTitle,
        artist: songArtist,
        album: album,
        artworkUrl: artwork,
        duration: video.duration,
        provider: 'ytm',
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to resolve YouTube video ID $videoId directly; searching catalog fallback',
        name: 'MusicService',
        error: error,
        stackTrace: stackTrace,
      );
      final searches = await search(videoId, limit: 1);
      return searches.isNotEmpty ? searches.first : null;
    }
  }

  Future<List<Track>> searchKaraoke(
    String query, {
    String? artist,
    int limit = 30,
  }) async {
    final clean = KaraokeMetadata.songQuery(query);
    if (clean.isEmpty) return [];

    final cleanArt = artist != null ? KaraokeMetadata.cleanArtist(artist) : '';
    final requested = cleanArt.isNotEmpty &&
            !clean.toLowerCase().contains(cleanArt.toLowerCase())
        ? '$clean $cleanArt karaoke'
        : '$clean karaoke';

    final results = await Future.wait<List<Track>>([
      _searchMusicForSearch(requested, limit * 2),
      _searchYouTube(requested, limit: limit * 2, karaokeOnly: true),
    ]);
    final seen = <String>{};
    return results
        .expand((items) => items)
        .where((track) =>
            KaraokeMetadata.isKaraoke(track.title) &&
            seen.add(track.cleanVideoId))
        .take(limit)
        .map((track) => track.copyWith(isKaraoke: true, karaokeQuery: clean))
        .toList();
  }

  /// Finds the best matching karaoke / minus-one track for an existing track.
  /// Strictly verifies artist match, title match, and duration compatibility.
  Future<Track?> findMatchingKaraokeTrack(Track originalTrack) async {
    final cleanTitle = KaraokeMetadata.songQuery(originalTrack.displayTitle);
    if (cleanTitle.isEmpty) return null;

    final cleanArt = KaraokeMetadata.cleanArtist(originalTrack.displayArtist);

    // 1. Search with title and artist
    var candidates = await searchKaraoke(
      cleanTitle,
      artist: cleanArt,
      limit: 15,
    );

    // 2. Fallback search if empty
    if (candidates.isEmpty) {
      final altQuery = cleanArt.isNotEmpty
          ? '$cleanTitle $cleanArt minus one'
          : '$cleanTitle minus one';
      final altResults =
          await _searchYouTube(altQuery, limit: 10, karaokeOnly: true);
      candidates = altResults
          .where((t) => KaraokeMetadata.isKaraoke(t.title))
          .map((t) => t.copyWith(isKaraoke: true, karaokeQuery: cleanTitle))
          .toList();
    }

    if (candidates.isEmpty) return null;

    final originalDurationSec = originalTrack.duration?.inSeconds ?? 0;
    final lowerTitle = cleanTitle.toLowerCase();
    final lowerArtist = cleanArt.toLowerCase();
    final artistTokens = lowerArtist
        .split(RegExp(r'\s+'))
        .where((t) =>
            t.length > 2 &&
            !{'the', 'and', 'official', 'vevo', 'music', 'records', 'band'}.contains(t))
        .toList();

    Track? bestTrack;
    int highestScore = -1;

    for (final candidate in candidates) {
      final candTitle = candidate.displayTitle.toLowerCase();
      final candArtist = candidate.displayArtist.toLowerCase();
      int score = 0;

      // Title check
      if (candTitle.contains(lowerTitle)) {
        score += 35;
      } else {
        final words =
            lowerTitle.split(RegExp(r'\s+')).where((w) => w.length > 2);
        int matched = 0;
        for (final w in words) {
          if (candTitle.contains(w)) matched++;
        }
        if (words.isNotEmpty && matched == words.length) {
          score += 25;
        } else if (matched > 0) {
          score += 10;
        }
      }

      // Artist check - MUST match original artist if artist tokens are present
      bool artistMatched = false;
      if (artistTokens.isNotEmpty) {
        for (final token in artistTokens) {
          if (candTitle.contains(token) || candArtist.contains(token)) {
            score += 45;
            artistMatched = true;
            break;
          }
        }
        // If candidate doesn't match the artist at all, reject it to avoid jumping to another song!
        if (!artistMatched) {
          continue;
        }
      }

      // Duration check (tolerance: max 50s delta)
      final candDurationSec = candidate.duration?.inSeconds ?? 0;
      if (originalDurationSec > 0 && candDurationSec > 0) {
        final diff = (originalDurationSec - candDurationSec).abs();
        if (diff <= 15) {
          score += 35;
        } else if (diff <= 35) {
          score += 20;
        } else if (diff > 50) {
          // Significant duration mismatch (e.g. extended version or wrong track)
          continue;
        }
      }

      if (score > highestScore && score >= 40) {
        highestScore = score;
        bestTrack = candidate;
      }
    }

    return bestTrack;
  }

  Future<List<Track>> _searchMusicForSearch(String query, int limit) async {
    try {
      final tracks = await _youtubeMusic.searchSongs(query, limit: limit);
      return tracks
          .where((track) => !_isNonMusicContent(track.title, track.artist))
          .toList();
    } catch (error, stackTrace) {
      developer.log(
        'YouTube Music search failed for query: $query',
        name: 'MusicService',
        error: error,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  final Map<String, List<Track>> _chartCache = {};

  /// Fetches ranked songs for a curated trending chart with caching.
  Future<List<Track>> getChartTracks(
    TrendingChart chart, {
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _chartCache.containsKey(chart.id) &&
        _chartCache[chart.id]!.length >= 20) {
      return _chartCache[chart.id]!;
    }
    try {
      List<Track> tracks = [];
      final targetLimit = limit < 50 ? 50 : limit;
      if (chart.playlistId != null) {
        final playlistSongs =
            await _youtubeMusic.playlistTracks(chart.playlistId!, limit: targetLimit);
        tracks = playlistSongs
            .where((t) =>
                t.duration == null ||
                t.duration! <= const Duration(minutes: 10))
            .where((t) => !_isNonMusicContent(t.title, t.artist))
            .toList();
      } else if (chart.id == 'viral-tiktok') {
        tracks = await _tiktokPlaylists.songs(limit: targetLimit);
      } else {
        final playlists =
            await _youtubeMusic.searchPlaylists(chart.searchKeyword, limit: 3);
        for (final p in playlists) {
          final pTracks =
              await _youtubeMusic.playlistTracks(p.browseId, limit: targetLimit);
          if (pTracks.isNotEmpty) {
            tracks = pTracks
                .where((t) =>
                    t.duration == null ||
                    t.duration! <= const Duration(minutes: 10))
                .where((t) => !_isNonMusicContent(t.title, t.artist))
                .toList();
            break;
          }
        }
        if (tracks.isEmpty) {
          tracks =
              await _youtubeMusic.searchSongs(chart.searchKeyword, limit: targetLimit);
        }
      }

      if (tracks.isNotEmpty) {
        _chartCache[chart.id] = tracks;
        chart.cachedTracks = tracks;
        return tracks;
      }
    } catch (e, st) {
      developer.log('Failed to fetch chart ${chart.id}', error: e, stackTrace: st);
    }
    return chart.cachedTracks;
  }

  /// Collects tracks belonging to an artist from both search catalogs.
  Future<List<Track>> artistTracks(
    String artist, {
    List<Track> initial = const [],
  }) async {
    final found = await search(artist, limit: 60);
    final matches = [
      ...initial,
      ...found,
    ].where((track) => _isSameArtist(track.displayArtist, artist)).toList();
    return _mergeUnique([matches], limit: 60);
  }

  /// Album data is only shown when the catalog explicitly labels that album.
  Future<List<Track>> albumTracks(
    String album,
    String artist, {
    List<Track> initial = const [],
  }) async {
    final found = await _searchMusicForSearch('$album $artist', 60);
    final normalizedAlbum = _entityKey(album);
    final matches = [
      ...initial,
      ...found,
    ]
        .where((track) =>
            _entityKey(track.album ?? '') == normalizedAlbum &&
            _isSameArtist(track.displayArtist, artist))
        .toList();
    return _mergeUnique([matches], limit: 60);
  }

  String _entityKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Starts with [seed] and asks YouTube Music for its native radio queue.
  /// Standard YouTube related videos are used only as a fallback.
  Future<List<Track>> buildSmartQueue(Track seed, {int limit = 24}) async {
    if (seed.isTikTokSound) return [seed];
    if (seed.isKaraoke) {
      return searchKaraoke(seed.karaokeQuery ?? seed.title, limit: limit);
    }
    try {
      final musicRadio = await _youtubeMusic.radio(
        seed.cleanVideoId,
        limit: limit + 4,
      );
      final queue = <Track>[seed];
      final seenIds = <String>{seed.cleanVideoId};
      final seenSongs = <String>{
        _songIdentity(seed.displayTitle, seed.displayArtist),
      };
      for (final track in musicRadio) {
        if (queue.length >= limit) break;
        if (!_isPreferredRadioCandidate(track)) continue;
        if (!seenIds.add(track.cleanVideoId)) continue;
        if (_isSameSong(
          seed.displayTitle,
          seed.displayArtist,
          track.displayTitle,
          track.displayArtist,
        )) {
          continue;
        }
        if (!seenSongs.add(
          _songIdentity(track.displayTitle, track.displayArtist),
        )) {
          continue;
        }
        queue.add(track);
      }
      // One valid next song is enough to continue. Discarding a short radio
      // response made autoplay stop when the other discovery source failed.
      if (queue.length > 1) return queue;
    } catch (error, stackTrace) {
      developer.log(
        'YouTube Music radio failed; using YouTube related fallback',
        name: 'MusicService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final relatedQueue = <Track>[seed];
    try {
      final video = await _youtube.videos.get(seed.cleanVideoId).timeout(
            const Duration(seconds: 12),
          );
      final related = await _youtube.videos.getRelatedVideos(video).timeout(
            const Duration(seconds: 15),
          );
      final seen = <String>{seed.id};
      final seenSongs = <String>{
        _songIdentity(seed.displayTitle, seed.displayArtist),
      };

      if (related != null) {
        for (final item in related) {
          if (relatedQueue.length >= limit) break;
          if (!_isIndividualSong(item.title, item.duration)) continue;
          final id = 'ytm:${item.id.value}';
          if (!seen.add(id)) continue;
          final songTitle = item.musicData.isNotEmpty
              ? item.musicData.first.song ?? item.title
              : item.title;
          final songArtist = item.musicData.isNotEmpty
              ? item.musicData.first.artist ?? item.author
              : item.author;
          final candidate = Track(
            id: id,
            title: songTitle,
            artist: songArtist,
            album:
                item.musicData.isNotEmpty ? item.musicData.first.album : null,
            artworkUrl: item.thumbnails.mediumResUrl,
            duration: item.duration,
            provider: 'ytm',
          );
          if (!_isPreferredRadioCandidate(candidate)) continue;
          if (_isSameSong(
            seed.displayTitle,
            seed.displayArtist,
            candidate.displayTitle,
            candidate.displayArtist,
          )) {
            continue;
          }
          if (!seenSongs.add(
            _songIdentity(
              candidate.displayTitle,
              candidate.displayArtist,
            ),
          )) {
            continue;
          }
          relatedQueue.add(candidate);
        }
      }

      if (relatedQueue.length > 1) {
        final sameArtist = relatedQueue.skip(1).where(
              (track) => _isSameArtist(
                seed.displayArtist,
                track.displayArtist,
              ),
            );
        final similarArtists = relatedQueue.skip(1).where(
              (track) => !_isSameArtist(
                seed.displayArtist,
                track.displayArtist,
              ),
            );
        return [seed, ...sameArtist, ...similarArtists].take(limit).toList();
      }
    } catch (error, stackTrace) {
      developer.log(
        'YouTube related queue failed for ${seed.id}',
        name: 'MusicService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final fallbackGroups = await Future.wait<List<Track>>([
      search(
        '${seed.displayArtist} official audio',
        limit: limit,
      ),
      search(
        '${seed.displayTitle} ${seed.displayArtist} radio lagu sejenis',
        limit: limit,
      ),
    ]);
    final merged = _mergeUnique([
      relatedQueue,
      ...fallbackGroups,
    ], limit: limit);
    return [
      seed,
      ...merged.where(
        (track) =>
            track.id != seed.id &&
            !_isSameSong(
              seed.displayTitle,
              seed.displayArtist,
              track.displayTitle,
              track.displayArtist,
            ),
      ),
    ].take(limit).toList();
  }

  /// Builds local recommendations from saved songs, listening history, and
  /// playlist genre labels. Radio supplies similarity where genre metadata is
  /// absent from the catalog; this is not the user's private YT Music feed.
  /// This does not access a user's private YouTube Music recommendations.
  Future<HomeFeed> getHomeFeed({
    List<String> favoriteArtists = const [],
    List<Track> savedTracks = const [],
    List<Track> recentlyPlayed = const [],
    List<String> playlistNames = const [],
  }) async {
    final cleanArtists = favoriteArtists
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .take(6)
        .toList();
    final mood = _moods[await _nextIndex('home_mood', _moods.length)];
    final discovery =
        _discoveries[await _nextIndex('home_discovery', _discoveries.length)];
    final recentSeed = _pickDiverseSeed(recentlyPlayed.take(24).toList());
    final savedSeed = _pickDiverseSeed(
      savedTracks,
      avoidingArtist: recentSeed?.displayArtist,
    );
    final artist = recentSeed?.displayArtist ??
        savedSeed?.displayArtist ??
        (cleanArtists.isEmpty
            ? null
            : cleanArtists[_random.nextInt(cleanArtists.length)]);
    final genre = _pickPlaylistGenre(playlistNames);
    final noPreferences = recentSeed == null &&
        savedSeed == null &&
        artist == null &&
        genre == null;
    final globalSongs = _getGlobalSongs();

    final results = await Future.wait<List<Track>>([
      _personalizedSongs(
        recentSeed: recentSeed,
        savedSeed: savedSeed,
        artist: artist,
        genre: genre,
        globalSongs: globalSongs,
      ),
      noPreferences
          ? _searchCatalog('Dua Lipa', limit: 20).then(
              (tracks) => tracks
                  .where((track) => _isCleanArtistSong(track, 'Dua Lipa'))
                  .toList(),
            )
          : _searchCatalog(
              genre == null ? 'lagu $artist terbaru' : '$genre songs terbaru',
              limit: 20,
            ),
      _searchCatalog('lagu Indonesia terbaru populer', limit: 20),
      _searchCatalog('indie pop Indonesia terbaru', limit: 20),
      globalSongs.then(
        (tracks) => tracks.skip(noPreferences ? 8 : 0).take(12).toList(),
      ),
      globalSongs.then(
        (tracks) => tracks.skip(noPreferences ? 16 : 12).take(12).toList(),
      ),
      _searchCatalog(mood.$2, limit: 20),
      _searchCatalog('${mood.$2} terbaru', limit: 20),
      _searchCatalog(discovery.$2, limit: 20),
      _searchCatalog('${discovery.$2} pilihan', limit: 20),
      _tiktokPlaylists.songs(
        recentlyPlayed: recentlyPlayed,
        savedTracks: savedTracks,
        favoriteArtists: cleanArtists,
      ),
    ]);

    // A radio request may fail or contain too few songs; catalog search fills it.
    if (results[0].length < 6 && artist != null) {
      results[0] = _mergeUnique([
        results[0],
        await _searchCatalog('$artist lagu serupa', limit: 12),
      ], limit: 16);
    }

    final seen = <String>{};
    List<Track> distinct(List<Track> tracks) => tracks
        .where((track) {
          return seen.add(
            _songIdentity(track.displayTitle, track.displayArtist),
          );
        })
        .take(10)
        .toList();

    List<List<Track>> shelfRows(int first, int second) {
      final primary = distinct(results[first]);
      final extra = distinct([
        ...results[second],
        ...results[first].skip(primary.length),
      ]);
      return [primary, extra];
    }

    final forYouRows = shelfRows(0, 1);
    final indonesiaRows = shelfRows(2, 3);
    final globalRows = shelfRows(4, 5);
    final moodRows = shelfRows(6, 7);
    final discoveryRows = shelfRows(8, 9);
    // Keep TikTok picks visible even when a song also appears on another shelf.
    final tiktokTracks = results[10];
    final forYou = forYouRows[0];
    final sections = [
      HomeSection(
        'TikTok',
        'Pilihan TikTok',
        'Dari playlist komunitas YouTube Music',
        tiktokTracks.take(10).toList(),
      ),
      HomeSection(
        'TikTok',
        'Sound TikTok lainnya',
        'Dari playlist komunitas YouTube Music',
        tiktokTracks.skip(10).take(10).toList(),
      ),
      HomeSection(
        'Untukmu',
        'Lagi untukmu',
        genre != null
            ? 'Racikan $genre dari playlist dan riwayatmu'
            : artist == null
                ? 'Pilihan lain untuk dijelajahi'
                : 'Terinspirasi dari $artist dan lagu yang kamu dengar',
        forYouRows[1],
      ),
      HomeSection(
        'Indonesia',
        'Hits Indonesia',
        'Lagu Indonesia yang sedang dicari',
        indonesiaRows[0],
      ),
      HomeSection(
        'Indonesia',
        'Indie Indonesia',
        'Suara baru dari musisi lokal',
        indonesiaRows[1],
      ),
      HomeSection(
        'Global',
        'Global',
        'Bruno Mars, Sienna Spiro, Dua Lipa, dan lainnya',
        globalRows[0],
      ),
      HomeSection(
        'Global',
        'Pop dunia',
        'Artis global yang banyak dikenal',
        globalRows[1],
      ),
      HomeSection(
        mood.$1,
        'Untuk suasana ${mood.$1.toLowerCase()}',
        mood.$3,
        moodRows[0],
      ),
      HomeSection(
        mood.$1,
        'Masih dalam suasana ${mood.$1.toLowerCase()}',
        'Lanjutkan dengan pilihan berbeda',
        moodRows[1],
      ),
      HomeSection(
        discovery.$1,
        'Jelajahi ${discovery.$1}',
        discovery.$3,
        discoveryRows[0],
      ),
      HomeSection(
        discovery.$1,
        '${discovery.$1} lainnya',
        'Temukan lebih banyak lagu',
        discoveryRows[1],
      ),
    ]..removeWhere((section) => section.tracks.isEmpty);
    return HomeFeed(forYou: forYou, sections: sections);
  }

  Track? _pickDiverseSeed(List<Track> tracks, {String? avoidingArtist}) {
    final musicTracks = tracks
        .where((track) => !_isNonMusicContent(track.title, track.artist))
        .toList();
    if (musicTracks.isEmpty) return null;
    final candidates = musicTracks
        .where((track) =>
            avoidingArtist == null ||
            !_isSameArtist(track.displayArtist, avoidingArtist))
        .toList();
    final pool = candidates.isEmpty ? musicTracks : candidates;
    // Vary the seed on each refresh instead of repeating the last play.
    return pool[_random.nextInt(pool.length)];
  }

  String? _pickPlaylistGenre(List<String> playlistNames) {
    const genres = <String, List<String>>{
      'pop': ['pop'],
      'indie': ['indie'],
      'R&B': ['r&b', 'rnb', 'soul'],
      'rock': ['rock', 'metal', 'punk'],
      'hip hop': ['hip hop', 'hiphop', 'rap'],
      'jazz': ['jazz'],
      'K-pop': ['k-pop', 'kpop'],
      'dangdut': ['dangdut', 'koplo'],
      'akustik': ['akustik', 'acoustic'],
      'elektronik': ['edm', 'electronic', 'elektronik', 'house'],
      'lo-fi': ['lofi', 'lo-fi'],
    };
    final matches = <String>[];
    for (final name in playlistNames) {
      final normalized = name.toLowerCase();
      for (final entry in genres.entries) {
        if (entry.value.any(normalized.contains)) matches.add(entry.key);
      }
    }
    return matches.isEmpty ? null : matches[_random.nextInt(matches.length)];
  }

  Future<List<Track>> _personalizedSongs({
    required Track? recentSeed,
    required Track? savedSeed,
    required String? artist,
    required String? genre,
    required Future<List<Track>> globalSongs,
  }) async {
    if (recentSeed == null && savedSeed == null && artist == null) {
      if (genre != null) return _searchCatalog('$genre songs', limit: 20);
      return globalSongs.then((tracks) => tracks.take(12).toList());
    }
    final groups = await Future.wait<List<Track>>([
      if (recentSeed != null) _radioForFeed(recentSeed),
      if (savedSeed != null) _radioForFeed(savedSeed),
      if (genre != null) _searchCatalog('$genre songs', limit: 16),
      if (artist != null) _searchCatalog('$artist lagu serupa', limit: 12),
    ]);
    return _mergeUnique(groups, limit: 20);
  }

  Future<List<Track>> _getGlobalSongs() async {
    final rotating = [..._moreGlobalArtists]..shuffle(_random);
    final artists = [
      ..._globalHeadliners,
      ...rotating.take(3),
    ];
    final groups = await Future.wait(
      artists.map((artist) async {
        final candidates = await _searchCatalog(artist, limit: 18);
        return candidates
            .where((track) => _isCleanArtistSong(track, artist))
            .take(5)
            .toList();
      }),
    );
    return _mergeUnique(groups, limit: 24);
  }

  bool _isCleanArtistSong(Track track, String artist) {
    if (!track.displayArtist.toLowerCase().contains(artist.toLowerCase())) {
      return false;
    }
    final title = track.title.toLowerCase();
    const excluded = [
      'cover',
      'karaoke',
      'instrumental',
      'sped up',
      'slowed',
      'nightcore',
      'remix',
      'live at',
      'live in',
      'reaction',
    ];
    if (excluded.any(title.contains)) return false;
    final duration = track.duration;
    return duration == null || _isIndividualSong(track.title, duration);
  }

  Future<List<Track>> _radioForFeed(Track seed) async {
    try {
      final tracks = await _youtubeMusic.radio(seed.cleanVideoId, limit: 18);
      return tracks.where(_isPreferredRadioCandidate).toList();
    } catch (error, stackTrace) {
      developer.log(
        'Home radio failed for ${seed.id}',
        name: 'MusicService',
        error: error,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  Future<List<String>> getSearchSuggestions({
    List<String> savedArtists = const [],
  }) async {
    final tracks = await _searchCatalog('lagu populer terbaru', limit: 30);
    final artists = <String>{};
    for (final artist in savedArtists) {
      if (artist.trim().isNotEmpty) artists.add(artist.trim());
    }
    for (final track in tracks) {
      final artist = track.displayArtist.trim();
      if (artist.isNotEmpty) artists.add(artist);
    }
    final choices = artists.toList()..shuffle(_random);
    if (choices.length > 1) {
      try {
        final preferences = await SharedPreferences.getInstance();
        final previous =
            preferences.getString('cloudio.last_search_suggestion');
        if (choices.first == previous) {
          choices.insert(0, choices.removeAt(1));
        }
        await preferences.setString(
          'cloudio.last_search_suggestion',
          choices.first,
        );
      } catch (_) {
        // Suggestions still work when local storage is unavailable.
      }
    }
    return choices.take(8).toList();
  }

  Future<int> _nextIndex(String key, int count) async {
    var index = _random.nextInt(count);
    try {
      final preferences = await SharedPreferences.getInstance();
      final storageKey = 'cloudio.$key';
      final previous = preferences.getInt(storageKey);
      if (count > 1 && index == previous) {
        index = (index + 1 + _random.nextInt(count - 1)) % count;
      }
      await preferences.setInt(storageKey, index);
    } catch (_) {
      // Use the generated choice if local storage is unavailable.
    }
    return index;
  }

  Future<List<Track>> _searchCatalog(
    String query, {
    required int limit,
  }) async {
    try {
      final tracks = await _youtubeMusic.searchSongs(query, limit: limit);
      if (tracks.isNotEmpty) return tracks;
    } catch (error, stackTrace) {
      developer.log(
        'YouTube Music catalog failed for query: $query',
        name: 'MusicService',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return _searchYouTube(query, limit: limit, officialOnly: true);
  }

  Future<List<Track>> _searchYouTube(
    String query, {
    required int limit,
    bool officialOnly = false,
    bool karaokeOnly = false,
  }) async {
    try {
      final results = await _youtube.search.search(query).timeout(
            const Duration(seconds: 15),
          );
      final tracks = <Track>[];
      for (final video in results) {
        if (tracks.length >= limit) break;
        if (!MusicSearchFilter.isYouTubeSong(
          title: video.title,
          author: video.author,
          description: video.description,
          duration: video.duration,
          isLive: video.isLive,
          hasMusicMetadata: video.musicData.any((data) =>
              (data.song?.trim().isNotEmpty ?? false) &&
              (data.artist?.trim().isNotEmpty ?? false)),
        )) {
          continue;
        }
        if (karaokeOnly && !KaraokeMetadata.isKaraoke(video.title)) continue;
        if (officialOnly && !_isOfficialRelease(video.title, video.author)) {
          continue;
        }
        tracks.add(
          Track(
            id: 'ytm:${video.id.value}',
            title: !karaokeOnly && video.musicData.isNotEmpty
                ? video.musicData.first.song ?? video.title
                : video.title,
            artist: video.musicData.isNotEmpty
                ? video.musicData.first.artist ?? video.author
                : video.author,
            album:
                video.musicData.isNotEmpty ? video.musicData.first.album : null,
            artworkUrl: video.thumbnails.mediumResUrl,
            duration: video.duration,
            provider: 'youtube',
          ),
        );
      }
      return tracks;
    } catch (error, stackTrace) {
      developer.log(
        'YouTube search failed for query: $query',
        name: 'MusicService',
        error: error,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  bool _isNonMusicContent(String title, String author) {
    return MusicSearchFilter.isSpokenContent(title, author);
  }

  bool _isIndividualSong(String title, Duration? duration) {
    if (duration == null ||
        duration.inSeconds < 60 ||
        duration.inSeconds > 600) {
      return false;
    }
    final normalized = title.toLowerCase();
    const excludedPhrases = [
      'full album',
      'album lengkap',
      'kumpulan lagu',
      'kompilasi',
      'nonstop',
      'non stop',
      'playlist',
      'greatest hits',
      'best songs',
      'best of',
      'medley',
      'live stream',
      'livestream',
      'radio 24/7',
      '1 hour',
      '1 jam',
    ];
    return !excludedPhrases.any(normalized.contains);
  }

  bool _isOfficialRelease(String title, String author) {
    final normalizedTitle = title.toLowerCase();
    final normalizedAuthor = author.toLowerCase();
    const officialTitleMarkers = [
      'official music video',
      'official video',
      'official audio',
      'official lyric',
      'official visualizer',
    ];
    const officialChannelMarkers = ['vevo', '- topic', 'official'];
    return officialTitleMarkers.any(normalizedTitle.contains) ||
        officialChannelMarkers.any(normalizedAuthor.contains);
  }

  bool _isPreferredRadioCandidate(Track track) {
    final title = track.title.toLowerCase();
    const alternateVersionMarkers = [
      ' cover',
      'lyrics',
      'lyric video',
      'lirik',
      'karaoke',
      'instrumental',
      'sped up',
      'nightcore',
      'slowed',
      'reverb',
      'remix',
      'live at',
      'live in',
      'live performance',
    ];
    return !_isNonMusicContent(track.title, track.artist) &&
        _isIndividualSong(track.title, track.duration) &&
        !alternateVersionMarkers.any(title.contains);
  }

  String _songIdentity(String title, String artist) {
    final normalizedArtist = artist
        .toLowerCase()
        .replaceAll(RegExp(r'\s*(- topic|official)\s*$'), '')
        .replaceAll('vevo', '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    var normalizedTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(
          RegExp(
            r'\b(?:official|music video|video clip|audio|lyrics?|lirik|visualizer|'
            r'live|cover|karaoke|instrumental|remix|remastered|slowed|reverb|'
            r'sped up|nightcore|performance|session|hd|4k)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (normalizedArtist.isNotEmpty) {
      normalizedTitle = normalizedTitle
          .replaceAll(normalizedArtist, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    return normalizedTitle.isEmpty
        ? '$normalizedArtist|${title.toLowerCase()}'
        : normalizedTitle;
  }

  bool _isSameSong(
    String firstTitle,
    String firstArtist,
    String secondTitle,
    String secondArtist,
  ) {
    final first = _songIdentity(firstTitle, firstArtist);
    final second = _songIdentity(secondTitle, secondArtist);
    if (first == second) return true;

    final firstTokens =
        first.split(' ').where((token) => token.length > 1).toSet();
    final secondTokens =
        second.split(' ').where((token) => token.length > 1).toSet();
    if (firstTokens.isEmpty || secondTokens.isEmpty) return false;

    final shared = firstTokens.intersection(secondTokens).length;
    final shorter = firstTokens.length < secondTokens.length
        ? firstTokens.length
        : secondTokens.length;
    return shorter >= 2 && shared == shorter;
  }

  bool _isSameArtist(String first, String second) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\s*(- topic|official)\s*$'), '')
        .replaceAll('vevo', '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    final firstValue = normalize(first);
    final secondValue = normalize(second);
    if (firstValue.isEmpty || secondValue.isEmpty) return false;
    return firstValue == secondValue ||
        firstValue.contains(secondValue) ||
        secondValue.contains(firstValue);
  }

  List<Track> _mergeUnique(
    List<List<Track>> groups, {
    required int limit,
  }) {
    final result = <Track>[];
    final seenIds = <String>{};
    final seenSongs = <String>{};
    var index = 0;

    while (result.length < limit) {
      var addedInRound = false;
      for (final group in groups) {
        if (index >= group.length) continue;
        final track = group[index];
        final identity = _songIdentity(
          track.displayTitle,
          track.displayArtist,
        );
        if (seenIds.add(track.id) && seenSongs.add(identity)) {
          result.add(track);
        }
        addedInRound = true;
        if (result.length == limit) break;
      }
      if (!addedInRound) break;
      index++;
    }
    return result;
  }

  void dispose() {
    _youtubeMusic.close();
    _youtube.close();
  }
}
