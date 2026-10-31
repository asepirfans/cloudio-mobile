import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/cloudio_audio_handler.dart';
import 'package:cloudio_mobile/services/player_session_store.dart';
import 'package:cloudio_mobile/services/tiktok_sound_service.dart';
import 'package:cloudio_mobile/services/tiktok_audio_cache.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output =
      File('${Directory.systemTemp.path}/cloudio-tiktok-sound-probe.txt');
  void log(String value) {
    output.writeAsStringSync('$value\n', mode: FileMode.append, flush: true);
  }

  output.writeAsStringSync('TikTok actual soundtrack physical probe\n',
      flush: true);
  final prefs = await SharedPreferences.getInstance();
  final keys = [PlayerSessionStore.storageKey, 'cloudio.listening_history.v1'];
  final saved = {for (final key in keys) key: prefs.getString(key)};
  var radioCalls = 0;
  final service = TikTokSoundService();
  final cache = TikTokAudioCache(diagnostics: (event) => log('CACHE $event'));
  // ignore: invalid_use_of_visible_for_testing_member
  final player = PlayerController.forTesting(
      tikTokCache: cache,
      tikTokSounds: service,
      buildQueue: (_) async {
        radioCalls++;
        return [];
      });
  final status = ValueNotifier('Memeriksa sound TikTok…');
  runApp(MaterialApp(
      home: Scaffold(
          body: Center(
              child: ValueListenableBuilder(
                  valueListenable: status,
                  builder: (_, value, __) =>
                      Text(value, textAlign: TextAlign.center))))));
  try {
    await AudioService.init(builder: () => CloudioAudioHandler(player));
    await player.ensureInitialized();
    final sound = await service.resolve(const String.fromEnvironment(
        'CLOUDIO_TIKTOK_PROBE_URL',
        defaultValue: 'https://vt.tiktok.com/ZSgMSnYvm/'));
    final track = Track.fromJson(sound.track.toJson());
    log('post=${track.id} title=${track.title} seconds=${track.duration?.inSeconds} candidates=${sound.media.length}');
    await player.playTrack(track,
        newQueue: [track]).timeout(const Duration(seconds: 70));
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline) &&
        player.position < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    log('playing=${player.isPlaying} positionMs=${player.position.inMilliseconds} durationMs=${player.duration.inMilliseconds} error=${player.playbackError} radioCalls=$radioCalls queue=${player.queue.length}');
    if (!player.isPlaying ||
        player.position < const Duration(seconds: 3) ||
        player.duration <= Duration.zero ||
        player.playbackError != null ||
        radioCalls != 0 ||
        player.currentTrack?.provider != 'tiktok') {
      throw StateError('Actual TikTok playback did not meet checks');
    }
    log('PASS: actual TikTok post playback advanced; no YouTube radio request');
    final info = await cache.info(track);
    log('LOCAL audioTracks=${info?['audioTracks']} videoTracks=${info?['videoTracks']} bytes=${info?['bytes']} durationMs=${info?['durationMs']} thermalState=${info?['thermalState']}');
    if (info?['audioTracks'] != 1 || info?['videoTracks'] != 0) {
      throw StateError('Cached media is not audio-only');
    }
    final offline = TikTokAudioCache(client: _NoNetwork());
    final offlineSource = TikTokSoundService(client: _NoNetwork());
    final cachedUri = await offline.playbackUrl(track, offlineSource);
    if (Uri.parse(cachedUri).scheme != 'file') {
      throw StateError('Replay did not use a local file');
    }
    log('PASS: fresh cache service resolves file URI with all HTTP disabled');
    offline.close();
    offlineSource.close();
    status.value = 'Sound TikTok berhasil diputar.';
  } catch (error) {
    log('FAIL: $error');
    status.value = 'Pengujian gagal: $error';
  } finally {
    await player.pause();
    player.dispose();
    service.close();
    cache.close();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (final key in keys) {
      final value = saved[key];
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    }
    log('Previous player session restored');
  }
}

class _NoNetwork extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw StateError('Network forbidden for warm cache check');
}
