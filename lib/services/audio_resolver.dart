import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../config/api_config.dart';

class CachedStreamUrl {
  final String url;
  final DateTime expiresAt;

  const CachedStreamUrl(this.url, this.expiresAt);

  bool get isExpired =>
      DateTime.now().add(const Duration(minutes: 2)).isAfter(expiresAt);
}

/// Resolves YouTube audio locally, with Cloudio gateway fallback.
class AudioResolverService {
  static final AudioResolverService instance = AudioResolverService._internal();
  AudioResolverService._internal();

  @visibleForTesting
  AudioResolverService.forTesting(
    Future<StreamManifest> Function(String) manifestLoader, {
    List<Future<StreamManifest> Function(String)> fallbackLoaders = const [],
  }) : _testLoaders = [manifestLoader, ...fallbackLoaders];

  List<Future<StreamManifest> Function(String)>? _testLoaders;
  final Map<String, Future<String>> _pending = {};
  final Map<String, int> _revisions = {};

  // Client update for upstream issue #386; avoid the restricted watch page.
  static const _streamClient = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, CachedStreamUrl> _cache = {};

  bool get _usesDarwinPlayer =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _prefersOpus =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// Apple platforms prefer AAC/M4A while Android and web prefer Opus/WebM.
  /// [compatibilityFallback] selects the smallest progressive MP4 and is only
  /// used after the native player rejects an audio-only stream.
  Future<String> resolveStreamUrl(
    String videoId, {
    bool forceRefresh = false,
    bool compatibilityFallback = false,
    bool gatewayOnly = false,
  }) async {
    final cleanId = videoId.startsWith('ytm:') ? videoId.substring(4) : videoId;
    final strategy = gatewayOnly
        ? 'gateway'
        : compatibilityFallback
            ? 'progressive-mp4'
            : _usesDarwinPlayer
                ? 'aac'
                : _prefersOpus
                    ? 'opus'
                    : 'audio';
    final cacheKey = '$strategy:$cleanId';

    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired) {
        developer.log(
          'Using cached $strategy URL for $cleanId',
          name: 'AudioResolver',
        );
        return cached.url;
      }
    }

    final pendingKey = '$cacheKey:${_revisions[cleanId] ?? 0}:$forceRefresh';
    final active = _pending[pendingKey];
    if (active != null) return active;
    final revision = _revisions[cleanId] ?? 0;
    late final Future<String> operation;
    operation = _resolve(cleanId,
            compatibilityFallback: compatibilityFallback,
            gatewayOnly: gatewayOnly,
            forceRefresh: forceRefresh)
        .then((url) {
      if ((_revisions[cleanId] ?? 0) == revision) {
        final uri = Uri.parse(url);
        _cache[cacheKey] = CachedStreamUrl(
            url,
            ApiConfig.isResolverHost(uri.host)
                ? DateTime.now().add(const Duration(minutes: 5))
                : _expiryFor(uri));
        // Keep discovery/preloading from growing the cache forever.
        _cache.removeWhere((_, entry) => entry.isExpired);
        while (_cache.length > 100) {
          _cache.remove(_cache.keys.first);
        }
      }
      return url;
    }).whenComplete(() {
      if (identical(_pending[pendingKey], operation)) {
        _pending.remove(pendingKey);
      }
    });
    _pending[pendingKey] = operation;
    return operation;
  }

  Future<String> _resolve(
    String videoId, {
    required bool compatibilityFallback,
    required bool gatewayOnly,
    required bool forceRefresh,
  }) async {
    if (gatewayOnly) {
      return ApiConfig.resolverStreamUri(videoId, refresh: forceRefresh)
          .toString();
    }
    final deadline = DateTime.now().add(const Duration(seconds: 7));
    final loaders = _testLoaders ??
        [
          for (final client in [
            _streamClient,
            YoutubeApiClient.ios,
            YoutubeApiClient.safari,
            YoutubeApiClient.android,
          ])
            (String id) => _yt.videos.streamsClient
                .getManifest(id, ytClients: [client], requireWatchPage: false),
        ];
    StreamInfo? progressiveFallback;
    if (!gatewayOnly) {
      for (var index = 0; index < loaders.length; index++) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        StreamManifest? manifest;
        try {
          manifest = await loaders[index](videoId).timeout(
              remaining < const Duration(milliseconds: 2500)
                  ? remaining
                  : const Duration(milliseconds: 2500));
          final selected = compatibilityFallback
              ? _selectProgressiveMp4(manifest, videoId)
              : _selectAudioOnly(manifest, videoId);
          return selected.url.toString();
        } catch (_) {
          if (manifest != null &&
              !compatibilityFallback &&
              _usesDarwinPlayer) {
            try {
              progressiveFallback ??=
                  _selectProgressiveMp4(manifest, videoId);
            } catch (_) {}
          }
          developer.log('Stream strategy $index failed for $videoId',
              name: 'AudioResolver');
        }
      }
    }
    if (progressiveFallback != null) {
      return progressiveFallback.url.toString();
    }
    return ApiConfig.resolverStreamUri(videoId, refresh: forceRefresh)
        .toString();
  }

  StreamInfo _selectAudioOnly(StreamManifest manifest, String videoId) {
    final streams = manifest.audioOnly
        .where((stream) => _hasUsableUrl(stream, videoId))
        .toList();
    if (streams.isEmpty) {
      throw StateError('No audio-only stream is available for $videoId');
    }

    if (_usesDarwinPlayer) {
      final aac = streams
          .where(
            (stream) =>
                stream.container == StreamContainer.mp4 &&
                stream.audioCodec.toLowerCase().contains('mp4a'),
          )
          .toList();
      if (aac.isNotEmpty) return _closestTo128Kbps(aac);

      throw StateError('No AAC audio-only stream is available for $videoId');
    }

    if (_prefersOpus) {
      final opus = streams
          .where(
            (stream) =>
                stream.container == StreamContainer.webM &&
                stream.audioCodec.toLowerCase().contains('opus'),
          )
          .toList();
      if (opus.isNotEmpty) return _closestTo128Kbps(opus);
    }

    final mp4 = streams
        .where((stream) =>
            stream.container == StreamContainer.mp4 &&
            stream.audioCodec.toLowerCase().contains('mp4a'))
        .toList();
    return _closestTo128Kbps(mp4.isNotEmpty ? mp4 : streams);
  }

  StreamInfo _selectProgressiveMp4(
    StreamManifest manifest,
    String videoId,
  ) {
    final usable = manifest.muxed
        .where((stream) => _hasUsableUrl(stream, videoId));
    var streams = usable
        .where(
          (stream) =>
              stream.container == StreamContainer.mp4 &&
              stream.videoCodec.toLowerCase().contains('avc') &&
              stream.audioCodec.toLowerCase().contains('mp4a'),
        )
        .toList();
    if (streams.isEmpty) {
      streams = usable
          .where((stream) =>
              stream.container == StreamContainer.mp4 &&
              (!_usesDarwinPlayer ||
                  stream.audioCodec.toLowerCase().contains('mp4a')))
          .toList();
    }
    if (streams.isEmpty) {
      throw StateError('No progressive MP4 fallback is available for $videoId');
    }
    streams.sort(
      (first, second) => first.bitrate.bitsPerSecond.compareTo(
        second.bitrate.bitsPerSecond,
      ),
    );
    return streams.first;
  }

  StreamInfo _closestTo128Kbps(List<StreamInfo> streams) {
    const target = 128000;
    streams.sort(
      (first, second) => (first.bitrate.bitsPerSecond - target).abs().compareTo(
            (second.bitrate.bitsPerSecond - target).abs(),
          ),
    );
    return streams.first;
  }

  bool _hasUsableUrl(StreamInfo stream, String videoId) {
    try {
      _validateCanonicalUrl(stream.url, videoId);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _validateCanonicalUrl(Uri uri, String videoId) {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('Invalid stream URL for $videoId');
    }
    // Browser devtools URLs often point to only one requested byte range.
    // just_audio must receive the canonical manifest URL and issue ranges itself.
    if (uri.queryParameters.containsKey('range')) {
      throw StateError('Chunk-only stream URL returned for $videoId');
    }
    final expires = int.tryParse(uri.queryParameters['expire'] ?? '');
    if (expires != null &&
        DateTime.fromMillisecondsSinceEpoch(expires * 1000)
            .isBefore(DateTime.now().add(const Duration(minutes: 2)))) {
      throw StateError('Stream URL is already expiring for $videoId');
    }
  }

  DateTime _expiryFor(Uri uri) {
    final seconds = int.tryParse(uri.queryParameters['expire'] ?? '');
    if (seconds != null) {
      final signedExpiry = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      final safeExpiry = signedExpiry.subtract(const Duration(minutes: 10));
      return safeExpiry.isAfter(DateTime.now()) ? safeExpiry : signedExpiry;
    }
    return DateTime.now().add(const Duration(minutes: 45));
  }

  void invalidate(String videoId) {
    final cleanId = videoId.startsWith('ytm:') ? videoId.substring(4) : videoId;
    _revisions[cleanId] = (_revisions[cleanId] ?? 0) + 1;
    _cache.removeWhere((key, _) => key.endsWith(':$cleanId'));
  }

  void dispose() {
    _yt.close();
  }
}
