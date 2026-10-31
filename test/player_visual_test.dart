import 'package:cloudio_mobile/widgets/player_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [PlayerVisualTheme.vinyl, PlayerVisualTheme.cassette]) {
    testWidgets(
        '${theme.name} pauses with playback, background and reduced motion',
        (tester) async {
      Widget visual({bool playing = true, bool reduced = false}) => MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: PlayerVisual(
                  theme: theme, imageUrl: null, size: 280, playing: playing)));
      double angle() => tester
          .widget<RotationTransition>(find.byType(RotationTransition).first)
          .turns
          .value;
      await tester.pumpWidget(visual());
      await tester.pump(const Duration(seconds: 1));
      expect(angle(), greaterThan(0));
      await tester.pumpWidget(visual(playing: false));
      final paused = angle();
      await tester.pump(const Duration(seconds: 2));
      expect(angle(), paused);
      await tester.pumpWidget(visual());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final background = angle();
      await tester.pump(const Duration(seconds: 2));
      expect(angle(), background);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(angle(), isNot(background));
      await tester.pumpWidget(visual(reduced: true));
      final reduced = angle();
      await tester.pump(const Duration(seconds: 2));
      expect(angle(), reduced);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
