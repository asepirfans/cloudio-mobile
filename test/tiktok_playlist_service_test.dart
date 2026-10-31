import 'dart:async';

import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/music_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudio_mobile/services/tiktok_playlist_service.dart';
import 'package:cloudio_mobile/services/youtube_music_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Track song(String id, String artist, {String? title}) => Track(
    id: 'ytm:$id',
    title: title ?? id,
    artist: artist,
    duration: const Duration(minutes: 3));

class PlaylistCatalog extends YoutubeMusicCatalog {
  int searches = 0;
  final browsed = <String>[];
  bool offline = false;
  Completer<void>? gate;
  final entries = <String, List<Track>>{
    'VLlocal': [
      song('one', 'First'),
      song('two', 'Favorite'),
      song('three', 'Favorite'),
      song('four', 'Favorite')
    ],
    'VLglobal': [
      song('one-copy', 'First', title: 'one'),
      song('five', 'Other')
    ],
  };

  @override
  Future<List<CatalogPlaylist>> searchPlaylists(String query,
      {int limit = 8}) async {
    searches++;
    if (offline) throw StateError('offline');
    if (gate != null) await gate!.future;
    return [
      const CatalogPlaylist(browseId: 'VLunrelated', title: 'Daily pop'),
      CatalogPlaylist(
          browseId: query.contains('Indonesia') ? 'VLlocal' : 'VLglobal',
          title: 'TikTok picks'),
    ];
  }

  @override
  Future<List<Track>> playlistTracks(String browseId, {int limit = 30}) async {
    browsed.add(browseId);
    if (offline) throw StateError('offline');
    return entries[browseId] ?? [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('home TikTok shelves use playlist songs instead of keyword song search',
      () async {
    SharedPreferences.setMockInitialValues({});
    final catalog = FeedCatalog();
    final music = MusicService.forTesting(catalog);
    addTearDown(music.dispose);
    final feed = await music.getHomeFeed(favoriteArtists: ['Favorite']);
    final shelves = feed.sections.where((s) => s.category == 'TikTok');
    expect(shelves, isNotEmpty);
    expect(shelves.first.title, 'Pilihan TikTok');
    expect(shelves.expand((s) => s.tracks).first.cleanVideoId, 'two');
    expect(catalog.songQueries.any((q) => q.toLowerCase().contains('tiktok')),
        isFalse);
    expect(
        shelves
            .expand((s) => s.tracks)
            .any((t) => t.cleanVideoId == 'unrelated'),
        isFalse);
  });

  test('only TikTok playlists contribute; versions deduplicate across curators',
      () async {
    final catalog = PlaylistCatalog();
    addTearDown(catalog.close);
    final tracks = await TikTokPlaylistService(catalog).songs();
    expect(catalog.browsed, ['VLlocal', 'VLglobal']);
    expect(tracks.map((t) => t.cleanVideoId),
        ['one', 'two', 'five', 'three', 'four']);
  });

  test(
      'preferences reorder the cached pool without adding unrelated songs or crowding out artists',
      () async {
    final catalog = PlaylistCatalog();
    addTearDown(catalog.close);
    final service = TikTokPlaylistService(catalog);
    await service.songs();
    final personalized =
        await service.songs(savedTracks: [song('saved', 'Favorite')], limit: 4);
    expect(personalized.map((t) => t.cleanVideoId),
        ['two', 'three', 'one', 'five']);
    expect(catalog.searches, 2);
    expect(personalized.any((t) => t.cleanVideoId == 'saved'), isFalse);
  });

  test(
      'concurrent requests share discovery and a temporary outage uses bounded stale data',
      () async {
    final catalog = PlaylistCatalog()..gate = Completer<void>();
    addTearDown(catalog.close);
    var now = DateTime.utc(2026, 10, 18);
    final service = TikTokPlaylistService(catalog, now: () => now);
    final first = service.songs();
    final second = service.songs();
    catalog.gate!.complete();
    expect(await first, await second);
    expect(catalog.searches, 2);
    catalog.offline = true;
    now = now.add(const Duration(hours: 7));
    expect(await service.songs(), isNotEmpty);
    expect(catalog.searches, 4);
    await service.songs();
    expect(catalog.searches, 4);
    now = now.add(const Duration(hours: 18));
    expect(await service.songs(), isEmpty);
  });

  test('one failed playlist does not discard the remaining source', () async {
    final catalog = PartialCatalog();
    addTearDown(catalog.close);
    expect(
        (await TikTokPlaylistService(catalog).songs())
            .map((t) => t.cleanVideoId),
        ['five']);
  });
}

class PartialCatalog extends PlaylistCatalog {
  @override
  Future<List<Track>> playlistTracks(String browseId, {int limit = 30}) async {
    if (browseId == 'VLlocal') throw StateError('removed playlist');
    return [song('five', 'Other')];
  }
}

class FeedCatalog extends PlaylistCatalog {
  final songQueries = <String>[];
  @override
  Future<List<Track>> searchSongs(String query, {int limit = 30}) async {
    songQueries.add(query);
    return [song('unrelated', query)];
  }
}
