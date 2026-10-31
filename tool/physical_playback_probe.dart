import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/cloudio_audio_handler.dart';
import 'package:cloudio_mobile/services/audio_resolver.dart';
import 'package:cloudio_mobile/services/lyrics_service.dart';
import 'package:cloudio_mobile/services/player_session_store.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:cloudio_mobile/widgets/player_sheet.dart';
import 'package:cloudio_mobile/widgets/mini_player.dart';

// End a real decoded stream naturally after a short excerpt. No seek or
// manual Next is used, so AVQueuePlayer's completion path is exercised.
class NaturalEndPlayer extends AudioPlayer {
  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) {
    if (source is ConcatenatingAudioSource &&
        source.children.first is UriAudioSource) {
      final child = source.children.first as UriAudioSource;
      source.children[0] = ClippingAudioSource(
          child: child, end: const Duration(seconds: 12), tag: child.tag);
    }
    return super.setAudioSource(source,
        preload: preload,
        initialIndex: initialIndex,
        initialPosition: initialPosition);
  }
}

final _navigatorKey = GlobalKey<NavigatorState>();

final _sheetKey = GlobalKey();
final _miniKey = GlobalKey();

List<Widget> renderedWidgets(GlobalKey key) {
  final widgets = <Widget>[];
  void visit(Element element) {
    widgets.add(element.widget);
    element.visitChildren(visit);
  }

  final context = key.currentContext;
  if (context is Element) visit(context);
  return widgets;
}

final _report = File('${Directory.systemTemp.path}/cloudio-physical-probe.txt');

void reportLog(String message) {
  debugPrint(message);
  _report.writeAsStringSync('$message\n', mode: FileMode.append, flush: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _report.writeAsStringSync('PHYSICAL starting AOT probe\n', flush: true);
  final preferences = await SharedPreferences.getInstance();
  const keys = [PlayerSessionStore.storageKey, 'cloudio.listening_history.v1'];
  final saved = {for (final key in keys) key: preferences.getString(key)};
  const shape = bool.fromEnvironment('CLOUDIO_PROBE_SHAPE');
  // ignore: invalid_use_of_visible_for_testing_member
  final player = PlayerController.forTesting(
      player: shape ? AudioPlayer() : NaturalEndPlayer(),
      buildQueue: (_) async => []);
  reportLog('PHYSICAL initializing media service');
  final handler =
      await AudioService.init(builder: () => CloudioAudioHandler(player));
  await player.ensureInitialized();
  reportLog('PHYSICAL initialized player');
  final status = ValueNotifier('Testing physical playback…');
  Widget statusApp() => MaterialApp(
      home: Scaffold(
          body: Center(
              child: ValueListenableBuilder(
                  valueListenable: status,
                  builder: (_, value, __) =>
                      Text(value, textAlign: TextAlign.center)))));
  runApp(ChangeNotifierProvider.value(
      value: player,
      child: MaterialApp(
          navigatorKey: _navigatorKey,
          home: Stack(children: [
            PlayerSheet(key: _sheetKey),
            Positioned(
                bottom: 4,
                left: 8,
                right: 8,
                child: Material(child: MiniPlayer(key: _miniKey))),
          ]))));
  StreamSubscription? sequence;
  try {
    const first = shape
        ? Track(
            id: 'ytm:xTvyyoF_LZY',
            title: 'Shape of You',
            artist: 'Ed Sheeran',
            duration: Duration(seconds: 234))
        : Track(
            id: 'ytm:K3ahuED9v88',
            title: 'golden hour (Cello Version)',
            artist: 'JVKE');
    const second = shape
        ? Track(
            id: 'ytm:DlFXDl_ROAM',
            title: 'Die With A Smile',
            artist: 'Lady Gaga',
            duration: Duration(seconds: 252))
        : bool.fromEnvironment('CLOUDIO_PROBE_DJ')
            ? Track(id: 'ytm:8NXfWci2muY', title: 'DJ Set', artist: 'motomovth')
            : Track(
                id: 'ytm:LjhCEhWiKXk',
                title: 'Just the Way You Are',
                artist: 'Bruno Mars');
    sequence = player.player.sequenceStateStream.listen((state) {
      reportLog(
          'PHYSICAL sequence=${state?.sequence.length} index=${state?.currentIndex}');
    });
    final nextUri = Uri.parse(await AudioResolverService.instance
        .resolveStreamUrl(second.cleanVideoId));
    reportLog(
        'PHYSICAL source host=${nextUri.host} itag=${nextUri.queryParameters['itag']}');
    await player.playTrack(first, newQueue: [
      first,
      second,
      const Track(id: 'K3ahuED9v88', title: 'Third queued song', artist: 'JVKE')
    ]).timeout(const Duration(seconds: 50));
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline) &&
        (player.player.sequenceState?.sequence.length ?? 0) < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if ((player.player.sequenceState?.sequence.length ?? 0) < 2) {
      throw StateError('Native successor was not prepared');
    }
    final source = player.player.audioSource;
    reportLog('PHYSICAL PASS preload: current + next in native player');
    final duration = player.player.duration;
    if (duration == null || duration < const Duration(seconds: 10)) {
      throw StateError('Native stream duration unavailable');
    }
    await WidgetsBinding.instance.endOfFrame;
    VoidCallback? openQueue;
    void findQueueButton(Element element) {
      final widget = element.widget;
      if (widget is TextButton) {
        var queueLabel = false;
        void scan(Element child) {
          if (child.widget is Text &&
              (child.widget as Text).data == 'Antrean') {
            queueLabel = true;
          }
          child.visitChildren(scan);
        }

        element.visitChildren(scan);
        if (queueLabel) openQueue = widget.onPressed;
      }
      element.visitChildren(findQueueButton);
    }

    (_sheetKey.currentContext as Element).visitChildren(findQueueButton);
    if (openQueue == null) throw StateError('Queue button unavailable');
    openQueue!();
    reportLog('PHYSICAL natural end: queue open, no seek, no manual next');
    final transitionDeadline =
        DateTime.now().add(const Duration(seconds: shape ? 300 : 90));
    var advanced = false;
    var tick = 0;
    while (DateTime.now().isBefore(transitionDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (tick++ % 8 == 0) {
        reportLog(
            'PHYSICAL tick track=${player.currentTrack?.cleanVideoId} playing=${player.isPlaying} state=${player.player.processingState} position=${player.player.position.inMilliseconds} duration=${player.player.duration?.inMilliseconds} buffered=${player.player.bufferedPosition.inMilliseconds} error=${player.playbackError}');
        if (shape) {
          reportLog(
              'PHYSICAL actual native item=${await player.player.cloudioNativeSnapshot()}');
        }
      }
      if (player.currentTrack?.id == second.id &&
          player.isPlaying &&
          player.player.processingState == ProcessingState.ready &&
          player.player.position >= const Duration(seconds: 2)) {
        advanced = true;
        break;
      }
    }
    if (!advanced) {
      throw StateError('Native auto-next did not start second track');
    }
    if (!identical(source, player.player.audioSource)) {
      reportLog(
          'PHYSICAL RECOVERED: auto-next required bounded stream fallback');
    }
    if (handler.mediaItem.value?.id != second.id) {
      throw StateError('System media metadata did not follow auto-next');
    }
    reportLog(
        'PHYSICAL PASS transition: samePlaylist=${identical(source, player.player.audioSource)}, second song playing, media metadata updated');
    await WidgetsBinding.instance.endOfFrame;
    final sheetWidgets = renderedWidgets(_sheetKey);
    final sheetTexts =
        sheetWidgets.whereType<Text>().map((text) => text.data).toList();
    final slider = sheetWidgets.whereType<Slider>().first;
    if (!sheetTexts.contains(second.displayTitle) ||
        sheetTexts.contains(first.displayTitle)) {
      throw StateError('Rendered player title did not follow native track');
    }
    if (slider.value < 1 ||
        slider.value > player.player.position.inSeconds + 2 ||
        slider.max != player.duration.inSeconds.toDouble()) {
      throw StateError(
          'Rendered player seekbar did not follow native timeline: slider=${slider.value}/${slider.max}, controller=${player.position.inMilliseconds}/${player.duration.inMilliseconds}, native=${player.player.position.inMilliseconds}/${player.player.duration?.inMilliseconds}, lifecycle=${WidgetsBinding.instance.lifecycleState}');
    }
    final miniWidgets = renderedWidgets(_miniKey);
    if (!miniWidgets
        .whereType<Text>()
        .any((text) => text.data == second.displayTitle)) {
      throw StateError(
          'Rendered mini-player title did not follow native track');
    }
    final highlighted =
        renderedWidgets(_navigatorKey).whereType<ListTile>().where((tile) {
      final icons = <Icon>[];
      void collect(Widget? widget) {
        if (widget is Icon) icons.add(widget);
        if (widget is Padding) collect(widget.child);
      }

      collect(tile.trailing);
      return icons.any((icon) => icon.icon == Icons.graphic_eq_rounded);
    }).toList();
    if (player.currentIndex != 1 ||
        highlighted.length != 1 ||
        (highlighted.single.title as Text).data != second.displayTitle) {
      throw StateError(
          'Open queue did not move its active row on natural auto-next');
    }
    reportLog(
        'PHYSICAL PASS queue: index=${player.currentIndex}, highlighted=${second.displayTitle}');
    reportLog(
        'PHYSICAL PASS rendered UI: title=${second.displayTitle}, slider=${slider.value}/${slider.max}, mini-player title updated');
    await player.pause();
    status.value = 'Playback PASS\nChecking lyrics…';
    const lyricTrack = Track(
        id: 'ytm:LjhCEhWiKXk',
        title: 'Just the Way You Are',
        artist: 'Bruno Mars',
        duration: Duration(seconds: 220));
    final lyrics = await LyricsService.instance
        .getLyrics(lyricTrack)
        .timeout(const Duration(seconds: 35));
    if (lyrics?.hasLyrics != true) throw StateError('Live lyrics unavailable');
    reportLog(
        'PHYSICAL PASS lyrics: source=${lyrics!.source} lines=${lyrics.syncedLines.length}');
    status.value = 'PASS\nNative preload, auto-next, media metadata, lyrics';
    reportLog('PHYSICAL ALL PASS');
  } catch (error) {
    final message =
        error.toString().replaceAll(RegExp(r'https?://\S+'), '[URL]');
    reportLog('PHYSICAL FAIL $message');
    status.value = 'FAIL\n$message';
  } finally {
    runApp(statusApp());
    await WidgetsBinding.instance.endOfFrame;
    await sequence?.cancel();
    await player.pause();
    // Drain the controller's serialized writes after disposal's final snapshot.
    player.dispose();
    await player.pause();
    for (final entry in saved.entries) {
      if (entry.value == null) {
        await preferences.remove(entry.key);
      } else {
        await preferences.setString(entry.key, entry.value!);
      }
    }
    reportLog(
        'PHYSICAL restored original player session and listening history');
  }
}
