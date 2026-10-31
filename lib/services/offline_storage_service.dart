import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

class OfflineStorageException implements Exception {
  final String message;
  const OfflineStorageException(this.message);

  @override
  String toString() => message;
}

/// Manages offline tracks, local file persistence, and the 5 GB quota limit.
class OfflineStorageService extends ChangeNotifier {
  static final OfflineStorageService instance = OfflineStorageService._internal();
  OfflineStorageService._internal();

  /// Maximum allowed offline storage quota: 5 GB
  static const int maxQuotaBytes = 5 * 1024 * 1024 * 1024; // 5 GB

  Directory? _baseDir;
  Directory? _audioDir;
  Directory? _artworkDir;
  Directory? _lyricsDir;
  File? _indexFile;

  final Map<String, Track> _downloadedTracks = {};
  final Map<String, int> _trackFileSizes = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  List<Track> get downloadedTracks => _downloadedTracks.values.toList().reversed.toList();
  int get trackCount => _downloadedTracks.length;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _baseDir = Directory('${appDocDir.path}/cloudio_offline');
      if (!await _baseDir!.exists()) {
        await _baseDir!.create(recursive: true);
      }

      _audioDir = Directory('${_baseDir!.path}/audio');
      if (!await _audioDir!.exists()) await _audioDir!.create(recursive: true);

      _artworkDir = Directory('${_baseDir!.path}/artwork');
      if (!await _artworkDir!.exists()) await _artworkDir!.create(recursive: true);

      _lyricsDir = Directory('${_baseDir!.path}/lyrics');
      if (!await _lyricsDir!.exists()) await _lyricsDir!.create(recursive: true);

      _indexFile = File('${_baseDir!.path}/offline_tracks.json');
      await _loadIndex();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing OfflineStorageService: $e');
    }
  }

  Future<void> _loadIndex() async {
    if (_indexFile == null || !await _indexFile!.exists()) return;
    try {
      final content = await _indexFile!.readAsString();
      if (content.trim().isEmpty) return;
      final data = jsonDecode(content);
      if (data is Map<String, dynamic> && data['tracks'] is List) {
        final list = data['tracks'] as List;
        _downloadedTracks.clear();
        _trackFileSizes.clear();

        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final track = Track.fromJson(item);
            final audioPath = getLocalAudioPathSync(track.id);
            if (audioPath != null && File(audioPath).existsSync()) {
              _downloadedTracks[track.id] = track;
              _trackFileSizes[track.id] = (item['fileSizeBytes'] as int?) ??
                  File(audioPath).lengthSync();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load offline tracks index: $e');
    }
  }

  Future<void> _saveIndex() async {
    if (_indexFile == null) return;
    try {
      final list = <Map<String, dynamic>>[];
      for (final track in _downloadedTracks.values) {
        final map = track.toJson();
        map['fileSizeBytes'] = _trackFileSizes[track.id] ?? 0;
        list.add(map);
      }
      final payload = jsonEncode({
        'version': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'tracks': list,
      });
      await _indexFile!.writeAsString(payload, flush: true);
    } catch (e) {
      debugPrint('Failed to save offline tracks index: $e');
    }
  }

  bool isTrackDownloaded(String trackId) {
    if (!_downloadedTracks.containsKey(trackId)) return false;
    final path = getLocalAudioPathSync(trackId);
    return path != null && File(path).existsSync();
  }

  String? getLocalAudioPathSync(String trackId) {
    if (_audioDir == null) return null;
    final safeId = _sanitizeFilename(trackId);
    final file = File('${_audioDir!.path}/$safeId.m4a');
    return file.path;
  }

  Future<String?> getLocalAudioPath(String trackId) async {
    if (!_isInitialized) await init();
    if (!isTrackDownloaded(trackId)) return null;
    return getLocalAudioPathSync(trackId);
  }

  String? getLocalArtworkPath(String trackId) {
    if (_artworkDir == null) return null;
    final safeId = _sanitizeFilename(trackId);
    final file = File('${_artworkDir!.path}/$safeId.jpg');
    return file.existsSync() ? file.path : null;
  }

  String? getLocalLyrics(String trackId) {
    if (_lyricsDir == null) return null;
    final safeId = _sanitizeFilename(trackId);
    final file = File('${_lyricsDir!.path}/$safeId.json');
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
    return null;
  }

  Future<void> saveCustomLyrics(String trackId, String rawLyricsJson) async {
    if (!_isInitialized) await init();
    if (_lyricsDir == null) return;
    final safeId = _sanitizeFilename(trackId);
    final lyricsFile = File('${_lyricsDir!.path}/$safeId.json');
    await lyricsFile.writeAsString(rawLyricsJson, flush: true);
  }

  Future<void> deleteCustomLyrics(String trackId) async {
    if (!_isInitialized) await init();
    if (_lyricsDir == null) return;
    final safeId = _sanitizeFilename(trackId);
    final lyricsFile = File('${_lyricsDir!.path}/$safeId.json');
    if (await lyricsFile.exists()) {
      await lyricsFile.delete();
    }
  }

  Future<int> getTotalStorageUsed() async {
    if (!_isInitialized) await init();
    var total = 0;
    for (final size in _trackFileSizes.values) {
      total += size;
    }
    return total;
  }

  Future<int> getRemainingQuota() async {
    final used = await getTotalStorageUsed();
    final remaining = maxQuotaBytes - used;
    return remaining < 0 ? 0 : remaining;
  }

  Future<bool> hasEnoughQuota(int anticipatedBytes) async {
    final remaining = await getRemainingQuota();
    return remaining >= anticipatedBytes;
  }

  /// Saves a downloaded track and its accompanying assets into sandbox storage.
  Future<void> saveDownloadedTrack({
    required Track track,
    required File tempAudioFile,
    Uint8List? artworkBytes,
    String? rawLyricsJson,
  }) async {
    if (!_isInitialized) await init();

    final fileSize = await tempAudioFile.length();
    final remaining = await getRemainingQuota();
    if (fileSize > remaining) {
      throw const OfflineStorageException(
        'Kapasitas offline penuh (Maksimal 5 GB). Silakan hapus beberapa lagu untuk melanjutkan.',
      );
    }

    final safeId = _sanitizeFilename(track.id);

    // Save audio file
    final targetAudioFile = File('${_audioDir!.path}/$safeId.m4a');
    if (await targetAudioFile.exists()) {
      await targetAudioFile.delete();
    }
    await tempAudioFile.copy(targetAudioFile.path);

    // Save artwork if present
    if (artworkBytes != null && artworkBytes.isNotEmpty) {
      final artworkFile = File('${_artworkDir!.path}/$safeId.jpg');
      await artworkFile.writeAsBytes(artworkBytes, flush: true);
    }

    // Save lyrics if present
    if (rawLyricsJson != null && rawLyricsJson.isNotEmpty) {
      final lyricsFile = File('${_lyricsDir!.path}/$safeId.json');
      await lyricsFile.writeAsString(rawLyricsJson, flush: true);
    }

    _downloadedTracks[track.id] = track;
    _trackFileSizes[track.id] = fileSize;
    await _saveIndex();
    notifyListeners();
  }

  /// Deletes a downloaded track and all its associated local files.
  Future<void> deleteTrack(String trackId) async {
    if (!_isInitialized) await init();
    final safeId = _sanitizeFilename(trackId);

    try {
      final audioFile = File('${_audioDir!.path}/$safeId.m4a');
      if (await audioFile.exists()) await audioFile.delete();

      final artworkFile = File('${_artworkDir!.path}/$safeId.jpg');
      if (await artworkFile.exists()) await artworkFile.delete();

      final lyricsFile = File('${_lyricsDir!.path}/$safeId.json');
      if (await lyricsFile.exists()) await lyricsFile.delete();
    } catch (e) {
      debugPrint('Error deleting track files: $e');
    }

    _downloadedTracks.remove(trackId);
    _trackFileSizes.remove(trackId);
    await _saveIndex();
    notifyListeners();
  }

  /// Clears all offline tracks from storage.
  Future<void> clearAll() async {
    if (!_isInitialized) await init();
    final ids = _downloadedTracks.keys.toList();
    for (final id in ids) {
      await deleteTrack(id);
    }
  }

  static String _sanitizeFilename(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }
}
