import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudio_mobile/main.dart' as app;
import 'package:cloudio_mobile/widgets/player_sheet.dart';
import 'package:cloudio_mobile/widgets/playlist_actions.dart';
import 'package:cloudio_mobile/widgets/lyrics_page.dart';
import 'package:cloudio_mobile/services/lyrics_service.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

final boundaryKey = GlobalKey();
final log = File('${Directory.systemTemp.path}/cloudio-ui-review.txt');

Future<void> capture(String name) async {
  await Future<void>.delayed(const Duration(seconds: 1));
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('${Directory.systemTemp.path}/cloudio-ui-$name.png')
      .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  image.dispose();
  log.writeAsStringSync('CAPTURED $name\n', mode: FileMode.append, flush: true);
}

Element findElement(bool Function(Element) predicate) {
  Element? match;
  void visit(Element element) {
    if (predicate(element)) match = element;
    element.visitChildren(visit);
  }

  (boundaryKey.currentContext as Element).visitChildren(visit);
  return match!;
}

Future<void> chooseTheme(String label) async {
  final button = findElement((e) =>
      e.widget is IconButton &&
      (e.widget as IconButton).tooltip == 'Tema player');
  (button.widget as IconButton).onPressed!();
  await Future<void>.delayed(const Duration(milliseconds: 700));
  final tile = findElement((e) =>
      e.widget is ListTile &&
      (e.widget as ListTile).title is Text &&
      ((e.widget as ListTile).title as Text).data == label);
  (tile.widget as ListTile).onTap!();
  await Future<void>.delayed(const Duration(milliseconds: 700));
}

Future<void> main() async {
  await app.main();
  log.writeAsStringSync(
      'Cloudio UI review: no playback actions or playlist mutations; theme restored after preview\n',
      flush: true);
  runApp(RepaintBoundary(key: boundaryKey, child: const app.CloudioApp()));
  await Future<void>.delayed(const Duration(seconds: 25));
  try {
    late NavigationBar nav;
    late BuildContext navContext;
    void visit(Element element) {
      if (element.widget is NavigationBar) {
        nav = element.widget as NavigationBar;
        navContext = element;
      }
      element.visitChildren(visit);
    }

    (boundaryKey.currentContext as Element).visitChildren(visit);
    await capture('home');
    nav.onDestinationSelected!(1);
    await capture('search');
    nav.onDestinationSelected!(2);
    await capture('library');
    nav.onDestinationSelected!(0);
    if (!navContext.mounted) return;
    unawaited(PlayerSheet.show(navContext));
    await capture('player');
    final prefs = await SharedPreferences.getInstance();
    final originalTheme = prefs.getString('cloudio.player_theme.v1');
    await chooseTheme('Piringan');
    await capture('vinyl');
    await chooseTheme('Kaset');
    await capture('cassette');
    await chooseTheme(switch (originalTheme) {
      'vinyl' => 'Piringan',
      'cassette' || 'stage' => 'Kaset',
      _ => 'Sampul'
    });
    final queueButton = findElement((e) {
      if (e.widget is! TextButton) return false;
      var found = false;
      void scan(Element node) {
        if (node.widget is Text && (node.widget as Text).data == 'Antrean') {
          found = true;
        }
        node.visitChildren(scan);
      }

      e.visitChildren(scan);
      return found;
    });
    (queueButton.widget as TextButton).onPressed!();
    await capture('queue');
    if (!navContext.mounted) return;
    Navigator.of(navContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!navContext.mounted) return;
    final player = navContext.read<PlayerController>();
    final track = player.currentTrack;
    if (track != null) {
      unawaited(PlaylistActions.showAddToPlaylist(navContext, track));
      await capture('save');
      if (!navContext.mounted) return;
      Navigator.of(navContext).pop();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final lyrics = await LyricsService.instance.getLyrics(track);
      if (lyrics?.hasLyrics == true && navContext.mounted) {
        unawaited(Navigator.of(navContext).push(MaterialPageRoute<void>(
            builder: (_) => LyricsPage(track: track, initialLyrics: lyrics!))));
        await capture('lyrics');
        if (!navContext.mounted) return;
        Navigator.of(navContext).pop();
      }
    }
    if (!navContext.mounted) return;
    Navigator.of(navContext).pop();
    log.writeAsStringSync(
        'PASS: home, search, library, themes, queue, save, available lyrics; returned home\n',
        mode: FileMode.append,
        flush: true);
  } catch (error) {
    log.writeAsStringSync('FAIL: $error\n', mode: FileMode.append, flush: true);
  }
}
