class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Duration? duration;
  final String? sourceUrl;
  final bool isKaraoke;
  final String? karaokeQuery;
  final String provider; // "ytm", "youtube", "tiktok", or "direct"

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.sourceUrl,
    this.isKaraoke = false,
    this.karaokeQuery,
    this.artworkUrl,
    this.duration,
    this.provider = "ytm",
  });

  bool get isTikTokSound => provider == 'tiktok';

  String get cleanVideoId {
    if (id.startsWith("ytm:")) {
      return id.substring(4);
    }
    return id;
  }

  String get displayTitle {
    if (isTikTokSound) return title.trim();
    final parts = _titleParts(title);
    final channelArtist = _cleanArtistName(artist);
    var value = title;

    if (parts.length >= 2) {
      final channelKey = _key(channelArtist);
      final firstKey = _key(parts.first);
      final lastKey = _key(parts.last);

      if (channelKey.isNotEmpty && !_isGenericArtist(channelArtist)) {
        if (_sameLabel(firstKey, channelKey)) {
          value = parts.sublist(1).join(' - ');
        } else if (_sameLabel(lastKey, channelKey)) {
          value = parts.sublist(0, parts.length - 1).join(' - ');
        }
      } else if (_looksLikeSongFirstFormat(title)) {
        value = parts.first;
      } else {
        value = parts.last;
      }
    }

    value = _stripTitleNoise(value);
    return _cleanTitleCase(value.isEmpty ? title : value);
  }

  String get displayArtist {
    if (isTikTokSound) return artist.trim();
    final channelArtist = _cleanArtistName(artist);
    if (channelArtist.isNotEmpty && !_isGenericArtist(channelArtist)) {
      return _cleanArtistCase(channelArtist);
    }

    final parts = _titleParts(title);
    if (parts.length >= 2) {
      final candidate =
          _looksLikeSongFirstFormat(title) ? parts.last : parts.first;
      final cleaned = _cleanArtistName(_stripTitleNoise(candidate));
      if (cleaned.isNotEmpty) return _cleanArtistCase(cleaned);
    }
    return _cleanArtistCase(
      channelArtist.isEmpty ? artist.trim() : channelArtist,
    );
  }

  static List<String> _titleParts(String value) => value
      .split(RegExp(r'\s+(?:-|–|—)\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  static String _cleanArtistName(String value) => value
      .replaceAll(RegExp(r'\s*-\s*topic\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+official\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'vevo\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isGenericArtist(String value) {
    final normalized = _key(value);
    const genericMarkers = [
      'records',
      'record',
      'music',
      'entertainment',
      'indolirik',
      'lyrics',
      'lyric',
      'channel',
      'media',
      'production',
    ];
    return normalized.isEmpty ||
        genericMarkers.any((marker) => normalized.contains(marker));
  }

  static bool _looksLikeSongFirstFormat(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('| lirik') ||
        normalized.contains('| lyric') ||
        normalized.contains('[cover') ||
        normalized.contains('(cover');
  }

  static String _stripTitleNoise(String value) {
    final noise = RegExp(
      r'\b(?:official|music\s*video|video|audio|lyric|lyrics|lirik|visualizer|live|cover|karaoke|instrumental|remix|remastered|slowed|reverb|sped\s*up|nightcore)\b',
      caseSensitive: false,
    );
    return value
        .replaceAllMapped(
          RegExp(r'\s*[\(\[]([^\)\]]*)[\)\]]\s*'),
          (match) =>
              noise.hasMatch(match.group(1) ?? '') ? ' ' : match.group(0) ?? '',
        )
        .replaceAll(RegExp(r'\s*\|[\s\S]*$'), ' ')
        .replaceAll(
          RegExp(
            r'\s*(?:-|–|—|:)?\s*(?:official\s*)?(?:music\s*)?(?:video|audio|lyric|lyrics|lirik|visualizer)\s*$',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\s*(?:-|–|—|:)?\s*(?:live|cover|karaoke|instrumental|remix|remastered|slowed(?:\s+and\s+reverb)?|sped\s*up|nightcore)\b.*$',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s+(?:-|–|—|:)\s*$'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanTitleCase(String value) {
    final letters = value.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty || value != value.toUpperCase()) return value.trim();
    return value
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ')
        .trim();
  }

  static String _cleanArtistCase(String value) {
    final letters = value.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return value.trim();
    if (letters.length <= 5 && value == value.toUpperCase()) {
      return value.trim();
    }
    final uppercaseCount = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
    if (uppercaseCount * 2 <= letters.length) return value.trim();

    const connectors = {'and', 'dan', 'feat', 'ft', 'x'};
    return value
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty || connectors.contains(word)) return word;
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ')
        .trim();
  }

  static String _key(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _sameLabel(String first, String second) =>
      first.isNotEmpty &&
      second.isNotEmpty &&
      (first == second || first.contains(second) || second.contains(first));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'durationMs': duration?.inMilliseconds,
        'provider': provider,
        if (isKaraoke) 'isKaraoke': true,
        if (karaokeQuery != null) 'karaokeQuery': karaokeQuery,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        sourceUrl: json['sourceUrl'] as String?,
        isKaraoke: json['isKaraoke'] == true,
        karaokeQuery: json['karaokeQuery'] as String?,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        artworkUrl: json['artworkUrl'] as String?,
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        provider: (json['provider'] as String?) ?? "ytm",
      );

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    Duration? duration,
    String? provider,
    String? sourceUrl,
    bool? isKaraoke,
    String? karaokeQuery,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      duration: duration ?? this.duration,
      provider: provider ?? this.provider,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      isKaraoke: isKaraoke ?? this.isKaraoke,
      karaokeQuery: karaokeQuery ?? this.karaokeQuery,
    );
  }
}
