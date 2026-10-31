import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/cloudio_audio_handler.dart';
import 'package:cloudio_mobile/services/player_session_store.dart';
import 'package:cloudio_mobile/widgets/mini_player.dart';
import 'package:cloudio_mobile/widgets/player_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'physical_playback_probe.dart' show renderedWidgets;

final report = File('${Directory.systemTemp.path}/cloudio-natural-queue.txt');
final sheetKey = GlobalKey();
final miniKey = GlobalKey();
final navigatorKey = GlobalKey<NavigatorState>();
void log(String value) =>
    report.writeAsStringSync('$value\n', mode: FileMode.append, flush: true);

String fixture(int index) {
  const rate = 8000, seconds = 5;
  const samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    final bytes = ascii.encode(value);
    for (var i = 0; i < bytes.length; i++) {
      data.setUint8(offset + i, bytes[i]);
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
        44 + i * 2,
        (math.sin(2 * math.pi * (220 + index * 20) * i / rate) * 500).round(),
        Endian.little);
  }
  final file = File('${Directory.systemTemp.path}/cloudio-auto-$index.wav');
  file.writeAsBytesSync(data.buffer.asUint8List(), flush: true);
  return file.uri.toString();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  report.writeAsStringSync(
      'NATURAL AUTO-NEXT: 12 local 5s fixtures, no seek, no manual Next\n',
      flush: true);
  final prefs = await SharedPreferences.getInstance();
  const keys = [PlayerSessionStore.storageKey, 'cloudio.listening_history.v1'];
  final saved = {for (final key in keys) key: prefs.getString(key)};
  final tracks = List.generate(
      12,
      (i) => Track(
          id: 'fixture:$i',
          title: 'Auto song ${i + 1}',
          artist: 'Native fixture',
          duration: const Duration(seconds: 5)));
  final urls = {
    for (var i = 0; i < tracks.length; i++) tracks[i].id: fixture(i)
  };
  // ignore: invalid_use_of_visible_for_testing_member
  final player = PlayerController.forTesting(
      resolveTrack: (track) async => urls[track.id]!,
      buildQueue: (_) async => []);
  final handler =
      await AudioService.init(builder: () => CloudioAudioHandler(player));
  await player.ensureInitialized();
  final status = ValueNotifier('Testing natural auto-next');
  Widget statusApp() => MaterialApp(
      home: Scaffold(
          body: Center(
              child: ValueListenableBuilder(
                  valueListenable: status,
                  builder: (_, value, __) => Text(value)))));
  runApp(ChangeNotifierProvider.value(
      value: player,
      child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Stack(children: [
            PlayerSheet(key: sheetKey),
            Positioned(
                bottom: 4,
                left: 8,
                right: 8,
                child: Material(child: MiniPlayer(key: miniKey)))
          ]))));
  try {
    // Fixed start only: every subsequent change must come from natural completion.
    await player.playTrack(tracks.first, newQueue: tracks);
    await WidgetsBinding.instance.endOfFrame;
    VoidCallback? open;
    void visit(Element element) {
      if (element.widget is TextButton) {
        var found = false;
        void label(Element child) {
          if (child.widget is Text &&
              (child.widget as Text).data == 'Antrean') {
            found = true;
          }
          child.visitChildren(label);
        }

        element.visitChildren(label);
        if (found) open = (element.widget as TextButton).onPressed;
      }
      element.visitChildren(visit);
    }

    (sheetKey.currentContext as Element).visitChildren(visit);
    if (open == null) throw StateError('Queue button unavailable');
    open!();
    var previous = -1;
    var enteredAt = DateTime.now();
    final deadline = DateTime.now().add(const Duration(seconds: 85));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final current = player.currentIndex;
      if (current != previous) {
        final elapsed = DateTime.now().difference(enteredAt).inMilliseconds;
        if (current != previous + 1) {
          throw StateError('Skipped queue index: $previous -> $current');
        }
        if (previous >= 0 && elapsed < 4300) {
          throw StateError(
              'Premature native advance $previous -> $current after ${elapsed}ms');
        }
        enteredAt = DateTime.now();
        previous = current;
        log('AUTO index=$current native=${player.player.currentIndex} title=${player.currentTrack?.title} position=${player.position.inMilliseconds} elapsedPreviousMs=$elapsed');
      }
      if (player.player.position < const Duration(milliseconds: 800)) continue;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        continue;
      }
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(milliseconds: 500), onTimeout: () {});
      if (player.currentIndex != current ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        continue;
      }
      final title = tracks[current].displayTitle;
      final widgets = renderedWidgets(sheetKey);
      if (!widgets.whereType<Text>().any((text) => text.data == title)) {
        throw StateError('Stale full player title at $current');
      }
      final slider = widgets.whereType<Slider>().first;
      if (slider.max != 5 ||
          (slider.value - player.position.inSeconds).abs() > 1) {
        throw StateError(
            'Stale seekbar at $current: ${slider.value}/${slider.max}');
      }
      if (!renderedWidgets(miniKey)
          .whereType<Text>()
          .any((text) => text.data == title)) {
        throw StateError('Stale mini-player at $current');
      }
      final activeRows = renderedWidgets(navigatorKey)
          .whereType<ListTile>()
          .where((tile) => tile.trailing is Padding)
          .toList();
      if (activeRows.length != 1 ||
          (activeRows.single.title as Text).data != title) {
        throw StateError('Stale queue highlight at $current');
      }
      if (handler.mediaItem.value?.id != tracks[current].id ||
          handler.playbackState.value.queueIndex != current) {
        throw StateError('Stale system queue at $current');
      }
      if (current == tracks.length - 1 &&
          player.player.position >= const Duration(seconds: 2)) {
        status.value = 'PASS: 11 natural auto-next transitions';
        log('PASS: all 12 tracks in order; title, seekbar, open queue and system metadata followed every natural auto-next');
        break;
      }
    }
    if (previous != tracks.length - 1) {
      throw StateError('Natural queue did not reach final item');
    }
  } catch (error) {
    status.value = 'FAIL: $error';
    log('FAIL: $error');
  } finally {
    runApp(statusApp());
    await WidgetsBinding.instance.endOfFrame;
    await player.pause();
    player.dispose();
    await player.pause();
    for (final entry in saved.entries) {
      if (entry.value == null) {
        await prefs.remove(entry.key);
      } else {
        await prefs.setString(entry.key, entry.value!);
      }
    }
    log('RESTORED original session and history');
  }
}
