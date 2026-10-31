/// Filters general YouTube video results before they enter Cloudio's song list.
/// Search results do not expose a reliable music category, so uncertain videos
/// are excluded rather than presenting spoken content as a track.
class MusicSearchFilter {
  const MusicSearchFilter._();

  static final RegExp _spokenTitle = RegExp(
    r'\b(?:podcast|podkast|podkes|pod|talk\s?show|interview|wawancara|'
    r'obrolan|ngobrol|conversation|audiobook|audio\s?book|webinar|'
    r'seminar|ceramah|kajian|full\s?episode|episode\s?\d+|'
    r'eps?\.?\s?\d+|q\s?&\s?a|reaction|review|berita|news|'
    r'breaking\s+news|buletin|bulletin|reportase|liputan|'
    r'konferensi\s+pers|press\s+conference|current\s+affairs|'
    r'tutorial|dokumenter|documentary|vlog|wawancanda|'
    r'standup|stand[-\s]+up\s+comedy|komedi|comedy|gosip|gossip)\b',
    caseSensitive: false,
  );
  static final RegExp _spokenDescription = RegExp(
    r'\b(?:podcast|podkast|podkes|episode|talk\s?show|interview|'
    r'wawancara|audiobook|audio\s?book|webinar|ceramah|kajian|'
    r'berita|news|reportase|liputan|buletin|bulletin)\b',
    caseSensitive: false,
  );
  static final RegExp _musicTitle = RegExp(
    r'\b(?:official\s+(?:music\s+video|audio|lyric(?:s)?|visuali[sz]er)|'
    r'music\s+video|video\s+klip|lyric(?:s)?|lirik|visuali[sz]er|song|lagu|'
    r'remix|cover|acoustic|akustik|instrumental|karaoke|backing\s+track|minus\s*one|feat\.?|ft\.?|'
    r'live\s?performance)\b',
    caseSensitive: false,
  );
  static final RegExp _musicChannel = RegExp(
    r'(?:-\s*topic\s*$|vevo\s*$|\brecords\b|\bmusic\b|\bmusik\b)',
    caseSensitive: false,
  );
  static final RegExp _musicDescription = RegExp(
    r'(?:provided to youtube by|stream the song|'
    r'official music video|official audio|song by)',
    caseSensitive: false,
  );
  static final RegExp _mixOrSet = RegExp(
    r'\b(?:mix|mixtape|set)\b',
    caseSensitive: false,
  );
  static final RegExp _djMusic = RegExp(
    r'\b(?:dj|disc\s+jockey|hipdut|breakbeat|bkb|bassline|edm|'
    r'house|techno|trance|dubstep|drum\s*(?:and|&)\s*bass|'
    r'dnb|hardstyle|electro|tropical\s+house|amapiano)\b',
    caseSensitive: false,
  );
  static final RegExp _newsChannel = RegExp(
    r'\b(?:cnn|cnbc|bbc|kompas\s*(?:tv|com)|metrotv|metro\s+tv|'
    r'tvone|tv\s+one|tribun(?:news)?|detik(?:com)?|'
    r'fox\s+news|al\s+jazeera)\b',
    caseSensitive: false,
  );

  static bool isSpokenContent(
    String title,
    String author, {
    String description = '',
  }) {
    if (_spokenTitle.hasMatch('$title $author') ||
        _newsChannel.hasMatch(author)) return true;
    return _spokenDescription.hasMatch(description);
  }

  static bool isYouTubeSong({
    required String title,
    required String author,
    required String description,
    required Duration? duration,
    required bool isLive,
    bool hasMusicMetadata = false,
  }) {
    if (isLive || duration == null || duration.inSeconds < 45) {
      return false;
    }
    if (isSpokenContent(title, author, description: description)) {
      return false;
    }
    final normalizedTitle = title.toLowerCase();
    if (normalizedTitle.contains('live stream') ||
        normalizedTitle.contains('livestream') ||
        normalizedTitle.contains('radio 24/7')) {
      return false;
    }

    // Recorded DJ mixes and sets are music even when longer than one song.
    // Require both a mix/set label and a DJ or dance-music cue in the title;
    // a generic "mix" label or channel name alone is not sufficient.
    final isDjMix = _mixOrSet.hasMatch(title) && _djMusic.hasMatch(title);
    if (duration > const Duration(minutes: 15) && !isDjMix) return false;

    if (isDjMix ||
        hasMusicMetadata ||
        _musicTitle.hasMatch(title) ||
        _musicChannel.hasMatch(author) ||
        _musicDescription.hasMatch(description)) {
      return true;
    }

    // Independent songs commonly use "Artist - Title" without music labels.
    // Limit this shortcut to compact names and single-song lengths.
    final parts = title.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length == 2 &&
        duration.inMinutes <= 10 &&
        parts.every((part) =>
            part.trim().isNotEmpty &&
            part.trim().split(RegExp(r'\s+')).length <= 7)) {
      final channel = _key(author)
          .replaceAll(RegExp(r'\b(?:official|topic|vevo)\b'), '')
          .trim();
      if (channel.isNotEmpty && parts.any((part) => _key(part) == channel)) {
        return true;
      }
    }

    // Matching the query alone says nothing about whether a video is music.
    return false;
  }

  static String _key(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}
