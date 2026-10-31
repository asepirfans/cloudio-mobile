import '../models/track.dart';
import 'music_search_filter.dart';
import 'tiktok_song_service.dart';

/// Matches public TikTok metadata to music catalog results; no audio recognition.
class TikTokMusicMatcher {
  const TikTokMusicMatcher();

  static final _presentation = RegExp(
      r'\b(?:official\s+(?:music\s+video|audio|lyrics?)|lyrics?|lirik|visualizer)\b',
      caseSensitive: false);
  static final _bracketNoise = RegExp(
      r'[\[(](?:tiktok|tik\s+tok|viral|full\s+version|sound\s+tiktok)[^\])]*[\])]',
      caseSensitive: false);
  static final _versions = <String, RegExp>{
    'sped up':
        RegExp(r'\b(?:sped\s*up|speed\s*up|nightcore)\b', caseSensitive: false),
    'slowed': RegExp(r'\b(?:slowed|slow\s+reverb)\b', caseSensitive: false),
    'remix': RegExp(r'\b(?:remix|dj)\b', caseSensitive: false),
    'cover': RegExp(r'\bcover\b', caseSensitive: false),
    'live': RegExp(r'\blive\b', caseSensitive: false),
    'instrumental': RegExp(r'\binstrumental\b', caseSensitive: false),
    'cello': RegExp(r'\bcello\b', caseSensitive: false),
    'acoustic': RegExp(r'\b(?:acoustic|akustik)\b', caseSensitive: false),
  };

  String cleanTitle(String title) => title
      .replaceAll(_bracketNoise, ' ')
      .replaceAll(_presentation, ' ')
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), ' ')
      .replaceAll(RegExp(r'#\S+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s♬♪♫]+|[\s|–—-]+$'), '')
      .trim();

  List<String> queries(TikTokSong song) {
    final title = cleanTitle(song.title);
    final artist = song.artist?.trim() ?? '';
    return {
      [title, if (artist.isNotEmpty) artist].join(' '),
      song.query,
      title,
    }.where((q) => q.isNotEmpty).take(3).toList();
  }

  Set<String> _words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((w) =>
          w.isNotEmpty &&
          !const {'the', 'a', 'and', 'feat', 'ft', 'version'}.contains(w))
      .toSet();

  Set<String> _versionLabels(String text) => _versions.entries
      .where((entry) => entry.value.hasMatch(text))
      .map((entry) => entry.key)
      .toSet();

  double score(TikTokSong song, Track track) {
    if (MusicSearchFilter.isSpokenContent(track.title, track.artist)) return 0;
    final wanted = _words(cleanTitle(song.title));
    if (wanted.isEmpty) return 0;
    final found = _words('${cleanTitle(track.title)} ${track.artist}');
    final overlap = wanted.intersection(found).length / wanted.length;
    final artist = _words(song.artist ?? '');
    final artistMatch = artist.isEmpty
        ? 0.0
        : artist.intersection(found).length / artist.length;
    final desiredVersions = _versionLabels(song.title);
    final versions = _versionLabels(track.title);
    final missing = desiredVersions.difference(versions).length;
    final extra = versions.difference(desiredVersions).length;
    var value = overlap * (artist.isEmpty ? 1.0 : 0.8) + artistMatch * 0.2;
    value -= missing * 0.18 + extra * 0.12;
    // Matching an artist alone must never produce a plausible song match.
    if (overlap < 0.5) return 0;
    return value.clamp(0.0, 1.0);
  }

  List<Track> rank(TikTokSong song, Iterable<Track> tracks) {
    final unique = <String, Track>{};
    for (final track in tracks) {
      if (score(song, track) < 0.55) continue;
      final old = unique[track.cleanVideoId];
      if (old == null || score(song, track) > score(song, old)) {
        unique[track.cleanVideoId] = track;
      }
    }
    final indexed = unique.values.toList().asMap().entries.toList();
    indexed.sort((a, b) {
      final byScore = score(song, b.value).compareTo(score(song, a.value));
      return byScore == 0 ? a.key.compareTo(b.key) : byScore;
    });
    return indexed.map((entry) => entry.value).toList();
  }

  Future<List<Track>> search(
      TikTokSong song, Future<List<Track>> Function(String) search,
      {bool Function()? isCurrent}) async {
    final gathered = <Track>[];
    for (final query in queries(song)) {
      if (isCurrent != null && !isCurrent()) return [];
      try {
        gathered.addAll(await search(query));
      } catch (_) {/* Try the next query. */}
      final ranked = rank(song, gathered);
      if (ranked.isNotEmpty && score(song, ranked.first) >= 0.95) return ranked;
    }
    return rank(song, gathered);
  }
}
