import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../services/audio_resolver.dart';
import '../services/lyrics_service.dart';
import '../services/offline_storage_service.dart';
import '../services/tiktok_audio_cache.dart';
import '../services/tiktok_song_service.dart';
import '../services/tiktok_sound_service.dart';

enum DownloadStatus {
  idle,
  downloading,
  completed,
  error,
}

class DownloadController extends ChangeNotifier {
  static final DownloadController instance = DownloadController._internal();
  DownloadController._internal();

  final http.Client _client = http.Client();
  final Map<String, DownloadStatus> _status = {};
  final Map<String, double> _progress = {};
  final Map<String, String> _errors = {};

  DownloadStatus getStatus(String trackId) {
    if (OfflineStorageService.instance.isTrackDownloaded(trackId)) {
      return DownloadStatus.completed;
    }
    return _status[trackId] ?? DownloadStatus.idle;
  }

  double getProgress(String trackId) => _progress[trackId] ?? 0.0;
  String? getError(String trackId) => _errors[trackId];

  bool isDownloading(String trackId) =>
      _status[trackId] == DownloadStatus.downloading;

  Future<void> downloadTrack(Track track) async {
    if (OfflineStorageService.instance.isTrackDownloaded(track.id)) {
      return;
    }
    if (_status[track.id] == DownloadStatus.downloading) {
      return;
    }

    _status[track.id] = DownloadStatus.downloading;
    _progress[track.id] = 0.0;
    _errors.remove(track.id);
    notifyListeners();

    File? tempAudioFile;
    try {
      // 1. Resolve Audio Stream URL
      String streamUrl = '';
      if (track.isTikTokSound) {
        if (track.sourceUrl != null &&
            track.sourceUrl!.isNotEmpty &&
            TikTokSongService.isAudioHost(Uri.parse(track.sourceUrl!))) {
          streamUrl = track.sourceUrl!;
        } else {
          try {
            streamUrl = await TikTokAudioCache().playbackUrl(
              track,
              TikTokSoundService(),
            );
          } catch (_) {
            streamUrl = track.sourceUrl ?? '';
          }
        }
      } else if (track.provider == 'direct' &&
          track.sourceUrl != null &&
          track.sourceUrl!.isNotEmpty) {
        streamUrl = track.sourceUrl!;
      } else {
        // Try normal resolution first (uses cache if available)
        try {
          streamUrl = await AudioResolverService.instance.resolveStreamUrl(
            track.cleanVideoId,
            forceRefresh: false,
          );
        } catch (_) {
          // Fallback to gateway
          streamUrl = await AudioResolverService.instance.resolveStreamUrl(
            track.cleanVideoId,
            forceRefresh: true,
            gatewayOnly: true,
          );
        }
      }

      if (streamUrl.isEmpty) {
        throw const FormatException('Stream audio tidak ditemukan.');
      }

      // 2. Setup Temporary File
      final tempDir = await getTemporaryDirectory();
      final safeId = track.cleanVideoId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final tempFileName =
          'dl_${safeId}_${DateTime.now().millisecondsSinceEpoch}.tmp';
      tempAudioFile = File('${tempDir.path}/$tempFileName');

      final uri = Uri.parse(streamUrl);
      if (uri.scheme == 'file') {
        final localFile = File(uri.toFilePath());
        if (!await localFile.exists()) {
          throw const FormatException('File audio lokal sumber tidak ditemukan.');
        }
        await localFile.copy(tempAudioFile.path);
      } else {
        // 3. Download Audio with Progress and Headers
        var downloadedBytes = await _downloadFromUrl(streamUrl, tempAudioFile, track);

        // If download failed or was empty, attempt gateway fallback for YouTube tracks
        if (downloadedBytes < 1024 && !track.isTikTokSound && track.provider != 'direct') {
          debugPrint('Direct stream failed for ${track.title}. Retrying with gateway...');
          final gatewayUrl = await AudioResolverService.instance.resolveStreamUrl(
            track.cleanVideoId,
            forceRefresh: true,
            gatewayOnly: true,
          );
          downloadedBytes = await _downloadFromUrl(gatewayUrl, tempAudioFile, track);
        }

        if (downloadedBytes < 1024) {
          throw const FormatException('Data audio yang diunduh tidak lengkap atau kosong.');
        }
      }

      // 4. Download Artwork (best effort)
      Uint8List? artworkBytes;
      if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
        try {
          final artRes = await _client.get(
            Uri.parse(track.artworkUrl!),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
              'Accept': 'image/*,*/*',
            },
          ).timeout(const Duration(seconds: 6));
          if (artRes.statusCode == 200 && artRes.bodyBytes.isNotEmpty) {
            artworkBytes = artRes.bodyBytes;
          }
        } catch (_) {}
      }

      // 5. Download Synced Lyrics (best effort)
      String? rawLyricsJson;
      try {
        final lyrics = await LyricsService.instance
            .getLyrics(track)
            .timeout(const Duration(seconds: 6));
        if (lyrics != null && lyrics.hasLyrics) {
          final mapped = {
            'instrumental': lyrics.instrumental,
            'plainText': lyrics.plainText,
            'source': lyrics.source,
            'syncedLines': lyrics.syncedLines
                .map((line) => {
                      'timeMs': line.time.inMilliseconds,
                      'text': line.text,
                    })
                .toList(),
          };
          rawLyricsJson = jsonEncode(mapped);
        }
      } catch (_) {}

      // 6. Save to Persistent Sandbox Storage
      await OfflineStorageService.instance.saveDownloadedTrack(
        track: track,
        tempAudioFile: tempAudioFile,
        artworkBytes: artworkBytes,
        rawLyricsJson: rawLyricsJson,
      );

      _status[track.id] = DownloadStatus.completed;
      _progress[track.id] = 1.0;
      notifyListeners();
    } catch (e) {
      _status[track.id] = DownloadStatus.error;
      _errors[track.id] = e.toString();
      debugPrint('Error downloading track ${track.title}: $e');
      notifyListeners();
      rethrow;
    } finally {
      if (tempAudioFile != null && await tempAudioFile.exists()) {
        try {
          await tempAudioFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<int> _downloadFromUrl(
    String url,
    File targetFile,
    Track track,
  ) async {
    final sink = targetFile.openWrite();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
      request.headers['Accept'] = '*/*';
      request.headers['Accept-Encoding'] = 'identity';
      request.headers['Connection'] = 'keep-alive';
      if (track.isTikTokSound) {
        request.headers.addAll(TikTokSoundService.playbackHeaders);
      }

      final response = await _client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      var downloadedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          _progress[track.id] = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
          notifyListeners();
        }
      }
      await sink.flush();
      return downloadedBytes;
    } finally {
      await sink.close();
    }
  }

  Future<void> removeDownloadedTrack(String trackId) async {
    await OfflineStorageService.instance.deleteTrack(trackId);
    _status.remove(trackId);
    _progress.remove(trackId);
    _errors.remove(trackId);
    notifyListeners();
  }
}
