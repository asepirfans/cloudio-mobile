import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/cloudio_audio_handler.dart';
import 'package:cloudio_mobile/services/audio_resolver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Standalone native regression harness.
  // ignore: invalid_use_of_visible_for_testing_member
  final player = PlayerController.forTesting(buildQueue: (_) async => []);
  await AudioService.init(builder: () => CloudioAudioHandler(player));
  await player.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Native autoplay probe')))));
  player.player.playerStateStream.listen((state) {
    debugPrint(
        'PROBE state=${state.processingState} playing=${state.playing} track=${player.currentTrack?.cleanVideoId} busy=${player.isBusy} position=${player.player.position.inMilliseconds} duration=${player.player.duration?.inMilliseconds}');
  });
  try {
    const first = Track(
        id: 'ytm:K3ahuED9v88',
        title: 'golden hour (Cello Version)',
        artist: 'JVKE');
    const second =
        Track(id: 'ytm:8NXfWci2muY', title: 'DJ Set', artist: 'motomovth');
    await player.playTrack(first,
        newQueue: [first, second]).timeout(const Duration(seconds: 45));
    final duration = player.player.duration!;
    await player.seek(duration - const Duration(seconds: 3));
    debugPrint('PROBE seek complete at ${player.player.position}');
    for (var tick = 0; tick < 90; tick++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (tick % 5 == 0) {
        debugPrint(
            'PROBE tick=$tick track=${player.currentTrack?.cleanVideoId} position=${player.player.position.inMilliseconds} state=${player.player.processingState} busy=${player.isBusy} error=${player.playbackError}');
      }
      if (player.currentTrack?.id == second.id &&
          player.player.playing &&
          player.player.position.inSeconds >= 2) {
        debugPrint('PROBE PASS: native audio advanced to the next queued song');
        await player.pause();
        return;
      }
    }
    debugPrint('PROBE FAIL: no native autoplay transition within 90 seconds');
  } catch (error) {
    debugPrint(
        'PROBE ERROR: ${error.toString().replaceAll(RegExp(r'https?://\S+'), '[URL]')}');
  }
  await player.pause();
  AudioResolverService.instance.dispose();
}
