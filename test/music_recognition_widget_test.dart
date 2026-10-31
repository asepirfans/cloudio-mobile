import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloudio_mobile/controllers/music_recognition_controller.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/widgets/music_recognition_sheet.dart';
import 'package:cloudio_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_recognition_controller_test.dart' as fakes;
import 'player_autoplay_test.dart' as playback;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('InstrumentSans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/InstrumentSans-$weight.ttf'));
    }
    await font.load();
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
    ('recognition', const Size(390, 844), 1.0),
    ('recognition-small', const Size(320, 640), 1.4),
    ('recognition-landscape', const Size(844, 390), 1.0)
  ]) {
    testWidgets('${spec.$1} only records after an explicit tap and can cancel',
        (tester) async {
      tester.view.physicalSize = spec.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late PlayerController player;
      await tester.runAsync(() async {
        player =
            PlayerController.forTesting(player: playback.CompletionPlayer());
        await player.ensureInitialized();
      });
      final recorder = fakes.FakeRecorder();
      final service = fakes.FakeRecognizer();
      final recognition =
          MusicRecognitionController(recorder: recorder, service: service);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
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
                          onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (_) => MusicRecognitionSheet(
                                  player: player, controller: recognition)),
                          child: const Text('Kenali'),
                        )))),
          )));
      await tester.tap(find.text('Kenali'));
      await tester.pumpAndSettle();
      expect(recorder.permissionRequests, 0);
      expect(recorder.starts, 0);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CLOUDIO_CAPTURE_UI')) {
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tool/ui_previews/${spec.$1}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('Dengarkan'));
      await tester.tap(find.text('Dengarkan'));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      expect(recorder.starts, 1);
      expect(find.text('Mendengarkan…'), findsOneWidget);
      await tester.ensureVisible(find.text('Batal'));
      await tester.tap(find.text('Batal'));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      expect(recognition.phase, RecognitionPhase.ready);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        player.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    });
  }
}
