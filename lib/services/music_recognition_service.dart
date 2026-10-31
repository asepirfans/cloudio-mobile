import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'fingerprint/shazam_signature_generator.dart';
import 'audio_sample_decoder.dart';
import 'tiktok_song_service.dart';
import 'social_song_service.dart';
import 'social_media_http.dart';

class RecognizedMusic {
  final String title;
  final String artist;
  final String? artworkUrl;

  const RecognizedMusic(
      {required this.title, required this.artist, this.artworkUrl});
}

class MusicRecognitionException implements Exception {
  final String message;
  const MusicRecognitionException(this.message);
  @override
  String toString() => message;
}

String generateMusicFingerprint(Uint8List pcm) => VibraSignature.fromI16(pcm);

/// Generates fingerprints locally. Only the signature, never a microphone
/// recording, is sent to the unofficial Shazam matching endpoint.
class MusicRecognitionService {
  MusicRecognitionService(
      {http.Client? client,
      Future<Uint8List> Function(Uint8List)? decoder,
      SocialSongService? posts})
      : _client = client ?? http.Client(),
        _decoder = decoder ?? AudioSampleDecoder.decode,
        _injectedPosts = posts;
  final http.Client _client;
  final Future<Uint8List> Function(Uint8List) _decoder;
  final SocialSongService? _injectedPosts;
  late final SocialSongService _posts =
      _injectedPosts ?? SocialSongService(client: _client);
  bool _closed = false;

  Future<RecognizedMusic?> recognizeTikTok(String input) async {
    if (TikTokSongService.extractLink(input) == null) return null;
    return recognizeSocialLink(input);
  }

  Future<RecognizedMusic?> recognizeSocialLink(String input) async {
    if (SocialSongService.extractLink(input, includeInstagram: true) == null || _closed) return null;
    List<Uri> candidates;
    try {
      candidates =
          await _posts.resolveMedia(input).timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
    for (final uri in candidates.take(3)) {
      if (_closed) return null;
      try {
        final media = await readSocialMedia(_client, uri,
            allowed: (next) => SocialSongService.isMediaHost(input, next),
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': SocialSongService.platform(input) == 'Instagram'
                  ? 'https://www.instagram.com/'
                  : 'https://www.tiktok.com/'
            },
            maxBytes: 12 * 1024 * 1024,
            timeout: const Duration(seconds: 15));
        if (media == null || _closed) continue;
        final pcm =
            await _decoder(media.bytes).timeout(const Duration(seconds: 20));
        if (_closed) return null;
        if (pcm.length < sampleRate * 2 || pcm.length.isOdd) continue;
        final match = await recognizePcm(pcm);
        if (match != null) return match;
      } on MusicRecognitionException {
        // A service/network failure is not a reason to send more fingerprints.
        rethrow;
      } catch (_) {
        // Expired media, an unsupported codec or a failed CDN can use a fallback.
      }
    }
    return null;
  }

  static const sampleRate = 16000;
  static const sampleSeconds = 12;
  static const maxPcmBytes = sampleRate * sampleSeconds * 2;

  Future<RecognizedMusic?> recognizePcm(Uint8List data) async {
    if (_closed) return null;
    if (data.length < sampleRate * 2 || data.length.isOdd) {
      throw const MusicRecognitionException('Audio terlalu pendek. Coba lagi.');
    }
    final pcm = data.length > maxPcmBytes
        ? Uint8List.sublistView(data, 0, maxPcmBytes)
        : data;
    final signature = await compute(generateMusicFingerprint, pcm);
    if (_closed) return null;
    const id = Uuid();
    final uri = Uri.https('amp.shazam.com',
        '/discovery/v5/en-US/US/android/-/tag/${id.v4()}/${id.v4()}', {
      'sync': 'true',
      'webv3': 'true',
      'sampling': 'true',
      'shazamapiversion': 'v3',
    });
    try {
      final response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent':
                  'com.shazam.android/13.25.0-230413 (Android; SDK 33;)'
            },
            body: jsonEncode({
              'signature': {
                'uri': signature,
                'samplems': pcm.length * 1000 ~/ (sampleRate * 2)
              }
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (_closed) return null;
      if (response.statusCode == 429) {
        throw const MusicRecognitionException(
            'Terlalu banyak percobaan. Coba sebentar lagi.');
      }
      if (response.statusCode != 200) {
        throw const MusicRecognitionException(
            'Pengenalan lagu belum tersedia. Coba lagi nanti.');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      // A track object without an acoustic match is not a confirmed result.
      if (decoded['matches'] is! List || (decoded['matches'] as List).isEmpty) {
        return null;
      }
      final track = decoded['track'];
      if (track is! Map) return null;
      final title = track['title'];
      final artist = track['subtitle'];
      if (title is! String ||
          title.trim().isEmpty ||
          artist is! String ||
          artist.trim().isEmpty) return null;
      final images = track['images'];
      final artwork =
          images is Map ? images['coverarthq'] ?? images['coverart'] : null;
      return RecognizedMusic(
          title: title.trim(),
          artist: artist.trim(),
          artworkUrl:
              artwork is String && Uri.tryParse(artwork)?.scheme == 'https'
                  ? artwork
                  : null);
    } on MusicRecognitionException {
      rethrow;
    } catch (_) {
      if (_closed) return null;
      throw const MusicRecognitionException(
          'Gagal mengenali lagu. Periksa koneksi lalu coba lagi.');
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
