import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cloudio_mobile/controllers/listening_history_controller.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/controllers/playlist_controller.dart';
import 'package:cloudio_mobile/controllers/search_history_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/screens/home_screen.dart';
import 'package:cloudio_mobile/screens/main_navigation_screen.dart';
import 'package:cloudio_mobile/screens/library_screen.dart';
import 'package:cloudio_mobile/screens/search_screen.dart';
import 'package:cloudio_mobile/services/music_service.dart';
import 'package:cloudio_mobile/theme/ambient_palette.dart';
import 'package:cloudio_mobile/theme/app_theme.dart';
import 'package:cloudio_mobile/widgets/player_sheet.dart';
import 'package:cloudio_mobile/widgets/player_visual.dart';
import 'package:cloudio_mobile/widgets/lyrics_page.dart';
import 'package:cloudio_mobile/services/lyrics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_autoplay_test.dart' as fixture;

const tracks = [
  Track(
      id: 'preview:1',
      title: 'Shape of You',
      artist: 'Ed Sheeran',
      duration: Duration(seconds: 234),
      artworkUrl: 'https://i.ytimg.com/vi/xTvyyoF_LZY/hqdefault.jpg'),
  Track(
      id: 'preview:2',
      title: 'Rude',
      artist: 'MAGIC!',
      duration: Duration(seconds: 225),
      artworkUrl: 'https://i.ytimg.com/vi/3WzamI8QD2s/hqdefault.jpg'),
  Track(
      id: 'preview:3',
      title: 'Talking to the Moon',
      artist: 'Bruno Mars',
      duration: Duration(seconds: 218),
      artworkUrl: 'https://i.ytimg.com/vi/QyN7J1eB1fU/hqdefault.jpg'),
  Track(
      id: 'preview:4',
      title: 'Die With A Smile',
      artist: 'Lady Gaga, Bruno Mars',
      duration: Duration(seconds: 252),
      artworkUrl: 'https://i.ytimg.com/vi/DlFXDl_ROAM/hqdefault.jpg'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('InstrumentSans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader
          .addFont(rootBundle.load('assets/fonts/InstrumentSans-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (_) async => <String, dynamic>{});
  });

  for (final spec in [
    ('home', 390.0, 1.0),
    ('home-small', 320.0, 1.0),
    ('home-large-text', 390.0, 1.4),
    ('search', 390.0, 1.0),
    ('search-small', 320.0, 1.4),
    ('library', 390.0, 1.0),
    ('home-light', 390.0, 1.0),
    ('library-light', 390.0, 1.0),
    ('search-light', 390.0, 1.0),
    ('player', 390.0, 1.0),
    ('player-light', 390.0, 1.0),
    ('player-small', 320.0, 1.4),
    ('player-short', 320.0, 1.4),
    ('player-landscape', 844.0, 1.0),
    ('player-landscape-text', 844.0, 1.4),
    ('player-legacy', 390.0, 1.0),
    ('player-vinyl', 390.0, 1.0),
    ('player-cassette', 390.0, 1.0),
    ('player-queue', 320.0, 1.4),
    ('player-save', 320.0, 1.4),
    ('lyrics', 390.0, 1.0),
    ('lyrics-small', 320.0, 1.4),
    ('lyrics-light', 390.0, 1.0),
  ]) {
    testWidgets('${spec.$1} stays usable with persistent playback controls',
        (tester) async {
      tester.view.physicalSize = Size(
          spec.$2,
          spec.$1.startsWith('player-landscape')
              ? 390
              : spec.$1 == 'player-short'
                  ? 640
                  : 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (spec.$1 == 'player-legacy') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cloudio.player_theme.v1', 'stage');
      }
      if (spec.$1 == 'player-vinyl' || spec.$1 == 'player-cassette') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cloudio.player_theme.v1',
            spec.$1 == 'player-vinyl' ? 'vinyl' : 'cassette');
      }
      late PlayerController player;
      await tester.runAsync(() async {
        for (var i = 0; i < tracks.length; i++) {
          // Synthetic artwork keeps clean clones independent of downloaded
          // album images and avoids distributing third-party image fixtures.
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          const colors = [
            Color(0xFFA4D5F5),
            Color(0xFF1D3148),
            Color(0xFF56708C),
            Color(0xFFC8E7FB)
          ];
          canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 128),
              Paint()..color = colors[i % colors.length]);
          final picture = recorder.endRecording();
          final image = await picture.toImage(128, 128);
          picture.dispose();
          final key = await CachedNetworkImageProvider(tracks[i].artworkUrl!)
              .obtainKey(ImageConfiguration.empty);
          PaintingBinding.instance.imageCache.putIfAbsent(
              key,
              () => OneFrameImageStreamCompleter(
                  Future.value(ImageInfo(image: image))));
        }
        await PlaylistController.instance.ensureLoaded();
        await ListeningHistoryController.instance.ensureLoaded();
        if (PlaylistController.instance.playlists.isEmpty) {
          final saved =
              await PlaylistController.instance.createPlaylist('Langit sore');
          for (final track in tracks) {
            await PlaylistController.instance.addTrack(saved.id, track);
          }
          await PlaylistController.instance.createPlaylist('Di perjalanan');
        }
        final native = fixture.CompletionPlayer();
        player = PlayerController.forTesting(
            player: native,
            resolveTrack: (_) async => 'https://example.test/audio.m4a',
            buildQueue: (_) async => []);
        await player
            .playTrack(tracks.last, newQueue: [tracks.last, tracks.first]);
        native.nativeDuration = const Duration(seconds: 252);
        native.nativePosition = const Duration(seconds: 81);
        player.checkPlaybackEnd();
      });
      final key = GlobalKey();
      final Widget page = spec.$1.startsWith('lyrics')
          ? LyricsPage(
              track: tracks.last,
              initialLyrics: LyricsData(
                  syncedLines: List.generate(
                      30,
                      (i) => LyricLine(
                          Duration(seconds: i * 10), 'Baris lirik ke $i')),
                  plainText: null,
                  instrumental: false))
          : spec.$1.startsWith('player')
              ? const PlayerSheet()
              : spec.$1.startsWith('search')
                  ? const SearchScreen(initialSuggestions: [
                      'Pop Indonesia',
                      'Akustik',
                      'R&B',
                      'Indie',
                      'Lagu lama'
                    ])
                  : spec.$1.startsWith('library')
                      ? const LibraryScreen()
                      : const HomeScreen(
                          initialFeed: HomeFeed(forYou: tracks, sections: [
                          HomeSection('Santai', 'Pelan-pelan saja',
                              'Musik untuk jeda sebentar', tracks)
                        ]));
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<PlaylistController>.value(
                value: PlaylistController.instance),
            ChangeNotifierProvider<ListeningHistoryController>.value(
                value: ListeningHistoryController.instance),
            ChangeNotifierProvider<SearchHistoryController>.value(
                value: SearchHistoryController.instance),
          ],
          child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: spec.$1.contains('light')
                      ? AppTheme.lightTheme
                      : AppTheme.darkTheme,
                  builder: (context, child) =>
                      ThemeBrightnessSync(child: child!),
                  home: Builder(
                      builder: (context) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                                padding:
                                    const EdgeInsets.only(top: 44, bottom: 24),
                                textScaler: TextScaler.linear(spec.$3)),
                            child: Padding(
                                padding: EdgeInsets.zero,
                                child: spec.$1.startsWith('player') ||
                                        spec.$1.startsWith('lyrics')
                                    ? page
                                    : CloudioShell(
                                        body: page,
                                        selectedIndex:
                                            spec.$1.startsWith('search')
                                                ? 1
                                                : spec.$1.startsWith('library')
                                                    ? 2
                                                    : 0,
                                        onDestinationSelected: (_) {},
                                      )),
                          ))))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Die With A Smile'), findsWidgets);
      if (spec.$1.startsWith('player')) {
        expect(find.byType(SingleChildScrollView), findsNothing);
        final before = tester.getTopLeft(find.text('Die With A Smile'));
        await tester.drag(find.byType(PlayerVisual), const Offset(0, -90));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getTopLeft(find.text('Die With A Smile')), before);
        final save = tester.getRect(find.text('Simpan'));
        expect(save.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height - 24));
        if (spec.$1 == 'player-legacy') {
          expect(tester.widget<PlayerVisual>(find.byType(PlayerVisual)).theme,
              PlayerVisualTheme.cassette);
        }
      }
      if (spec.$1 == 'player-queue' || spec.$1 == 'player-save') {
        await tester
            .tap(find.text(spec.$1 == 'player-queue' ? 'Antrean' : 'Simpan'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        if (spec.$1 == 'player-save') {
          expect(find.textContaining('Sudah tersimpan'), findsOneWidget);
        }
      }
      if (spec.$1 == 'player-vinyl' || spec.$1 == 'player-cassette') {
        expect(
            tester.widget<PlayerVisual>(find.byType(PlayerVisual)).theme,
            spec.$1 == 'player-vinyl'
                ? PlayerVisualTheme.vinyl
                : PlayerVisualTheme.cassette);
        await tester.tap(find.byTooltip('Tema player'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Sampul'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
            (await SharedPreferences.getInstance())
                .getString('cloudio.player_theme.v1'),
            'cover');
        // Restore theme for the preview.
        await tester.tap(find.byTooltip('Tema player'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester
            .tap(find.text(spec.$1 == 'player-vinyl' ? 'Piringan' : 'Kaset'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      if (spec.$1 == 'lyrics') {
        await tester.pumpAndSettle();
        final expectedAccent = AmbientPalette.of(tracks.last)
            .accentOf(tester.element(find.byType(LyricsPage)));
        final scroll = tester.state<ScrollableState>(find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
        final before = scroll.position.pixels;
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        final auto = tester.widget<Material>(find
            .ancestor(of: find.text('Auto'), matching: find.byType(Material))
            .first);
        expect(auto.color, expectedAccent);
        expect(find.textContaining('Tetap mengikuti'), findsNothing);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, closeTo(before, 2));
        await tester.tap(find.text('Manual'));
        await tester.pump();
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pump(const Duration(seconds: 3));
        final manual = tester.widget<Material>(find
            .ancestor(of: find.text('Manual'), matching: find.byType(Material))
            .first);
        expect(manual.color, expectedAccent);
        // Verify in manual mode, no line has active accent color
        expect(
            DefaultTextStyle.of(tester.element(find.text('Baris lirik ke 20')))
                .style
                .color,
            isNot(expectedAccent));
        // Verify tapping a line in manual mode does NOT seek the player
        final posBefore = player.position;
        await tester.tap(find.text('Baris lirik ke 10'), warnIfMissed: false);
        await tester.pump();
        expect(player.position, posBefore);
        // Verify setting icon opens the teleprompter sheet
        await tester.tap(find.byTooltip('Pengaturan auto-scroll'));
        await tester.pumpAndSettle();
        expect(find.text('Pengaturan Auto-Scroll'), findsOneWidget);
        expect(find.text('Mulai Gulir Otomatis'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('CLOUDIO_CAPTURE_UI')) {
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('tool/ui_previews/lyrics-manual.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpAndSettle();
        final manualOffset = scroll.position.pixels;
        await tester.runAsync(() => player.seek(const Duration(seconds: 200)));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(scroll.position.pixels, manualOffset);
        await tester.tap(find.text('Auto'));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(player.position.inSeconds, 200);
        final viewport = tester.getRect(find.byType(ListView));
        expect(
            DefaultTextStyle.of(tester.element(find.text('Baris lirik ke 20')))
                .style
                .color,
            expectedAccent);
        final active = tester.getRect(find.text('Baris lirik ke 20'));
        expect(active.top, greaterThanOrEqualTo(viewport.top));
        expect(active.bottom, lessThanOrEqualTo(viewport.bottom));
      }
      if (const bool.fromEnvironment('CLOUDIO_CAPTURE_UI')) {
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('tool/ui_previews').create(recursive: true);
          await File('tool/ui_previews/${spec.$1}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (spec.$1 == 'home') {
        await tester.tap(find.text('Santai'));
        await tester.pump();
        expect(find.text('Mulai dari sini'), findsNothing);
        expect(find.text('Pelan-pelan saja'), findsOneWidget);
      }
      if (spec.$1.startsWith('search')) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        tester.view.resetViewInsets();
        await tester.pump();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
      await tester.pump();
    });
  }
}
