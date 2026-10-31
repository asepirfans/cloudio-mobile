import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/widgets/mini_player.dart';
import 'package:cloudio_mobile/widgets/player_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_autoplay_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  for (final fullScreen in [false, true]) {
    testWidgets(
        '${fullScreen ? 'full player' : 'mini player'} updates title and progress after a missed native event',
        (tester) async {
      const next = Track(
          id: 'ytm:next',
          title: 'New song',
          artist: 'New artist',
          duration: Duration(minutes: 5));
      late fixture.CompletionPlayer native;
      late PlayerController player;
      await tester.runAsync(() async {
        native = fixture.CompletionPlayer();
        player = PlayerController.forTesting(
            player: native,
            resolveTrack: (_) async => 'https://example.test/audio.m4a',
            buildQueue: (_) async => []);
        await player.playTrack(fixture.first, newQueue: [fixture.first, next]);
        await fixture.until(() =>
            (native.source as ConcatenatingAudioSource).children.length == 2);
      });
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: player,
          child: MaterialApp(
              home: fullScreen
                  ? const PlayerSheet()
                  : const Scaffold(body: MiniPlayer()))));
      expect(find.text(fixture.first.displayTitle), findsOneWidget);
      if (fullScreen) {
        await tester.tap(find.text('Antrean'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      native.transition(notify: false);
      native.nativeDuration = next.duration!;
      native.nativePosition = const Duration(seconds: 7);
      player.checkPlaybackEnd();
      await tester.pump();
      expect(find.text(next.displayTitle), fullScreen ? findsNWidgets(2) : findsOneWidget);
      expect(find.text(fixture.first.displayTitle), findsNothing);
      if (fullScreen) {
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.value, 7);
        expect(slider.max, 300);
        expect(find.text('0:07'), findsOneWidget);
        expect(find.text('5:00'), findsOneWidget);
        final rows = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
        expect(rows, hasLength(1));
        expect((rows.single.title as Text).data, next.displayTitle);
        expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      } else {
        expect(
            tester
                .widget<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator))
                .value,
            closeTo(7 / 300, 0.0001));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
      // Flush the lyrics widget's delayed request after unmounting the player.
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
    });
  }
}
