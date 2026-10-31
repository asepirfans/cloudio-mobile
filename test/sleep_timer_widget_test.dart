import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/theme/app_theme.dart';
import 'package:cloudio_mobile/widgets/sleep_timer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_autoplay_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('InstrumentSans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader
          .addFont(rootBundle.load('assets/fonts/InstrumentSans-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
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
    ('sleep-timer', const Size(390, 844), 1.0),
    ('sleep-timer-small', const Size(320, 640), 1.4),
    ('sleep-timer-landscape', const Size(844, 390), 1.0)
  ]) {
    testWidgets('${spec.$1} can set, inspect and cancel a timer',
        (tester) async {
      tester.view.physicalSize = spec.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late PlayerController player;
      await tester.runAsync(() async {
        player = PlayerController.forTesting(
            player: fixture.CompletionPlayer(),
            resolveTrack: (_) async => 'https://example.test/audio.m4a',
            buildQueue: (_) async => []);
        await player.playTrack(fixture.first, newQueue: [fixture.first]);
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(spec.$3)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => Center(
                        child: TextButton(
                            onPressed: () =>
                                SleepTimerSheet.show(context, player),
                            child: const Text('Timer'))))),
          )));
      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('15 menit'));
      await tester.tap(find.text('15 menit'));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pumpAndSettle();
      expect(player.sleepTimerDuration, const Duration(minutes: 15));
      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sisa '), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CLOUDIO_CAPTURE_UI')) {
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tool/ui_previews/${spec.$1}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('Matikan timer'));
      await tester.tap(find.text('Matikan timer'));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pumpAndSettle();
      expect(player.hasSleepTimer, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
    });
  }
}
