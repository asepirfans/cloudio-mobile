/// Label-based karaoke selection and original-song lookup hints.
class KaraokeMetadata {
  static final _marker = RegExp(
      r'\b(?:karaoke|no\s+vocals?|without\s+vocals?|minus\s*one|'
      r'backing\s+track|tanpa\s+vokal|instrumental\s+(?:version|cover))\b',
      caseSensitive: false);
  static final _vocal = RegExp(
      r'\b(?:with\s+(?:lead\s+)?vocals?|vocal\s+guide|guide\s+vocals?|'
      r'dengan\s+vokal|original\s+vocals?)\b',
      caseSensitive: false);

  static bool isKaraoke(String title) =>
      _marker.hasMatch(title) && !_vocal.hasMatch(title);

  static String songQuery(String title) => title
      .replaceAll(
          RegExp(
              r'[\[(][^\])]*(?:karaoke|no\s+vocal|without\s+vocal|minus\s*one|backing\s+track|key|nada|instrumental)[^\])]*[\])]',
              caseSensitive: false),
          ' ')
      .replaceAll(_marker, ' ')
      .replaceAll(
          RegExp(r'\b(?:version|official|lyrics?|lirik|audio|video|hd|4k|hq)\b',
              caseSensitive: false),
          ' ')
      .replaceAll(
          RegExp(r'\b(?:original|lower|higher|female|male)\s+key\b',
              caseSensitive: false),
          ' ')
      .replaceAll(RegExp(r'[|()[\]]'), ' ')
      .replaceAll(RegExp(r'\s*[-–—]\s*$|^\s*[-–—]\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String cleanArtist(String artist) => artist
      .replaceAll(RegExp(r'\s*[-–—]\s*topic\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bvevo\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\b(?:feat|ft)\.?\s+.*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
