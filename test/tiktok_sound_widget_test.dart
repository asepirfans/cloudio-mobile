import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/controllers/playlist_controller.dart';
import 'package:cloudio_mobile/controllers/search_history_controller.dart';
import 'package:cloudio_mobile/screens/search_screen.dart';
import 'package:cloudio_mobile/services/tiktok_sound_service.dart';
import 'package:cloudio_mobile/theme/app_theme.dart';
import 'package:cloudio_mobile/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_autoplay_test.dart' as playback;
import 'tiktok_sound_service_test.dart' as fixture;

void main() {
  testWidgets(
      'TikTok link offers the actual clip and a separate full song action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (_) async => <String, dynamic>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('InstrumentSans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/InstrumentSans-$weight.ttf'));
    }
    await font.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final native = playback.CompletionPlayer();
    var radioCalls = 0;
    final player = PlayerController.forTesting(
        player: native,
        resolveTrack: (track) async {
          expect(track.provider, 'tiktok');
          return 'https://sample.tiktokcdn.com/actual.mp4';
        },
        buildQueue: (_) async {
          radioCalls++;
          return [];
        });
    final service = TikTokSoundService(
        client:
            MockClient((request) async => http.Response(fixture.page(), 200)));
    final key = GlobalKey();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: PlaylistController.instance),
          ChangeNotifierProvider.value(value: SearchHistoryController.instance),
        ],
        child: RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.darkTheme,
                home: SearchScreen(
                    initialSuggestions: const [],
                    soundService: service,
                    karaokeSearch: (query) async => [
                          Track(
                              id: 'ytm:karaoke',
                              title: '$query (Karaoke)',
                              artist: 'Backing Studio',
                              isKaraoke: true)
                        ])))));
    await tester.enterText(find.byType(TextField), fixture.postUrl);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Sound asli TikTok · Cuplikan'), findsOneWidget);
    expect(find.text('Original sound - Creator (Slowed)'), findsOneWidget);
    expect(find.text('Cari lagu lengkap'), findsOneWidget);
    expect(find.text('0:13'), findsOneWidget);
    expect(find.textContaining('Kandidat terdekat'), findsNothing);
    if (const bool.fromEnvironment('CLOUDIO_CAPTURE_UI')) {
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('tool/ui_previews/tiktok-sound.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Original sound - Creator (Slowed)'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(player.currentTrack?.provider, 'tiktok');
    expect(radioCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Karaoke'));
    await tester.enterText(find.byType(TextField), 'Adele Someone Like You');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(TrackTile),
            matching: find.text('Adele Someone Like You')),
        findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Karaoke'))
            .selected,
        isTrue);
    expect(find.text('Sound asli TikTok · Cuplikan'), findsNothing);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CLOUDIO_CAPTURE_UI')) {
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('tool/ui_previews/karaoke-search.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)));
  });
}
