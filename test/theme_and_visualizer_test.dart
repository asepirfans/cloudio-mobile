import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudio_mobile/controllers/listening_history_controller.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/controllers/playlist_controller.dart';
import 'package:cloudio_mobile/controllers/theme_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/screens/home_screen.dart';
import 'package:cloudio_mobile/services/music_service.dart';
import 'package:flutter/services.dart';
import 'package:cloudio_mobile/widgets/mini_audio_visualizer.dart';
import 'package:cloudio_mobile/widgets/theme_selection_sheet.dart';
import 'package:cloudio_mobile/theme/app_theme.dart';
import 'package:cloudio_mobile/theme/ambient_palette.dart';
import 'player_autoplay_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.setThemeMode(AppThemeMode.dark);
    AmbientPalette.clearCache();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (_) async => <String, dynamic>{});
  });

  group('ThemeController', () {

    test('initializes default to dark mode', () async {
      final controller = ThemeController.instance;
      await controller.init();

      expect(controller.mode, AppThemeMode.dark);
      expect(controller.isDark, isTrue);
      expect(controller.isLight, isFalse);
      expect(controller.isAmoled, isFalse);
      expect(controller.flutterThemeMode, ThemeMode.dark);
    });

    test('can switch to light and warm modes and persist', () async {
      final controller = ThemeController.instance;
      await controller.init();

      await controller.setThemeMode(AppThemeMode.light);
      expect(controller.mode, AppThemeMode.light);
      expect(controller.isLight, isTrue);
      expect(controller.flutterThemeMode, ThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloudio_theme_mode'), 'light');

      await controller.setThemeMode(AppThemeMode.warm);
      expect(controller.mode, AppThemeMode.warm);
      expect(controller.isWarm, isTrue);
      expect(controller.flutterThemeMode, ThemeMode.dark);
      expect(prefs.getString('cloudio_theme_mode'), 'warm');

      await controller.setThemeMode(AppThemeMode.dark);
      expect(controller.mode, AppThemeMode.dark);
      expect(controller.isDark, isTrue);
      expect(controller.flutterThemeMode, ThemeMode.dark);
      expect(prefs.getString('cloudio_theme_mode'), 'dark');
    });
  });

  group('MiniAudioVisualizer Widget', () {
    testWidgets('renders bars when playing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniAudioVisualizer(
                isPlaying: true,
                barCount: 4,
                height: 18,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MiniAudioVisualizer), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders bars when paused', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniAudioVisualizer(
                isPlaying: false,
                barCount: 4,
                height: 18,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MiniAudioVisualizer), findsOneWidget);
    });
  });

  group('ThemeSelectionSheet Widget', () {
    testWidgets('renders all three theme options (Dark, Light, Warm) and switches selection', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await ThemeController.instance.init();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController.instance,
          child: const MaterialApp(
            home: Scaffold(
              body: ThemeSelectionSheet(),
            ),
          ),
        ),
      );

      expect(find.text('Tema Tampilan'), findsOneWidget);
      expect(find.text('Gelap (Midnight Navy)'), findsOneWidget);
      expect(find.text('Terang (Daylight)'), findsOneWidget);
      expect(find.text('Hangat (Warm Cokelat)'), findsOneWidget);

      await tester.tap(find.text('Hangat (Warm Cokelat)'));
      await tester.pumpAndSettle();

      expect(ThemeController.instance.isWarm, isTrue);
    });
  });

  group('Light Mode Text Contrast', () {
    testWidgets('AppColors produces dark text in Light Theme and light text in Dark Theme', (tester) async {
      Color? lightPrimary;
      Color? lightSecondary;
      Color? lightMuted;
      Color? darkPrimary;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: Builder(
            builder: (context) {
              lightPrimary = AppColors.textPrimaryOf(context);
              lightSecondary = AppColors.textSecondaryOf(context);
              lightMuted = AppColors.textMutedOf(context);
              return const Scaffold(body: Text('Light'));
            },
          ),
        ),
      );

      // Verify text in Light mode is DARK
      expect(lightPrimary, const Color(0xFF0F172A));
      expect(lightSecondary, const Color(0xFF475569));
      expect(lightMuted, const Color(0xFF64748B));

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('dark_app'),
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              darkPrimary = AppColors.textPrimaryOf(context);
              return const Scaffold(body: Text('Dark'));
            },
          ),
        ),
      );
      await tester.pump();

      // Verify text in Dark mode is LIGHT
      expect(darkPrimary, AppColors.textPrimary);
    });

    testWidgets('HomeScreen renders with dark text in Light Theme', (tester) async {
      const feed = HomeFeed(
        forYou: [
          Track(
            id: 'feed-light-1',
            title: 'Lagu Terang',
            artist: 'Musisi Hebat',
            duration: Duration(minutes: 3),
          ),
        ],
        sections: [],
      );

      final player = PlayerController.forTesting(
        player: fixture.CompletionPlayer(),
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => [],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: player),
            ChangeNotifierProvider.value(value: PlaylistController.instance),
            ChangeNotifierProvider.value(value: ListeningHistoryController.instance),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: RepaintBoundary(
                child: HomeScreen(initialFeed: feed),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tangga Lagu & Trending'), findsOneWidget);
      expect(find.text('Lagu Terang'), findsOneWidget);
      expect(find.text('Musisi Hebat'), findsOneWidget);

      await tester.runAsync(() async {
        final boundary = tester.renderObject(find.byType(RepaintBoundary).first)
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        File('/Users/samjin/.gemini/antigravity-ide/brain/6b29c38e-b172-4903-bf80-c723e39a3631/light_theme_verified.png')
            .writeAsBytesSync(byteData!.buffer.asUint8List());
      });

      player.dispose();
    });

    testWidgets('HomeScreen renders with warm chocolate styling in Warm Theme', (tester) async {
      await ThemeController.instance.setThemeMode(AppThemeMode.warm);

      const feed = HomeFeed(
        forYou: [
          Track(
            id: 'feed-warm-1',
            title: 'Kopi Kenangan',
            artist: 'Senja Akustik',
            duration: Duration(minutes: 3),
          ),
        ],
        sections: [],
      );

      final player = PlayerController.forTesting(
        player: fixture.CompletionPlayer(),
        resolveTrack: (_) async => 'https://example.test/audio.m4a',
        buildQueue: (_) async => [],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: player),
            ChangeNotifierProvider.value(value: PlaylistController.instance),
            ChangeNotifierProvider.value(value: ListeningHistoryController.instance),
            ChangeNotifierProvider.value(value: ThemeController.instance),
          ],
          child: MaterialApp(
            theme: AppTheme.warmTheme,
            home: const Scaffold(
              body: RepaintBoundary(
                child: HomeScreen(initialFeed: feed),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tangga Lagu & Trending'), findsOneWidget);
      expect(find.text('Kopi Kenangan'), findsOneWidget);

      await tester.runAsync(() async {
        final boundary = tester.renderObject(find.byType(RepaintBoundary).first)
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        File('/Users/samjin/.gemini/antigravity-ide/brain/6b29c38e-b172-4903-bf80-c723e39a3631/warm_theme_verified.png')
            .writeAsBytesSync(byteData!.buffer.asUint8List());
      });

      player.dispose();
    });

    testWidgets('ThemeSelectionSheet renders 3 options clearly', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ThemeController.instance,
          child: const MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                child: Center(
                  child: ThemeSelectionSheet(),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tema Tampilan'), findsOneWidget);
      expect(find.text('Gelap (Midnight Navy)'), findsOneWidget);
      expect(find.text('Terang (Daylight)'), findsOneWidget);
      expect(find.text('Hangat (Warm Cokelat)'), findsOneWidget);

      await tester.runAsync(() async {
        final boundary = tester.renderObject(find.byType(RepaintBoundary).first)
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        File('/Users/samjin/.gemini/antigravity-ide/brain/6b29c38e-b172-4903-bf80-c723e39a3631/theme_sheet_verified.png')
            .writeAsBytesSync(byteData!.buffer.asUint8List());
      });
    });

    test('AmbientPalette calibrates vibrant colors to calm, moody, non-neon tones', () {
      const neonRed = Color(0xFFFF0055);
      final palette = AmbientPalette.fromColor(neonRed);

      final hsl = HSLColor.fromColor(palette.primary);
      expect(hsl.saturation, lessThanOrEqualTo(0.45));
      expect(hsl.lightness, lessThanOrEqualTo(0.28));
      expect(hsl.lightness, greaterThanOrEqualTo(0.18));

      final secHsl = HSLColor.fromColor(palette.secondary);
      expect(secHsl.lightness, lessThan(hsl.lightness));

      final accHsl = HSLColor.fromColor(palette.accent);
      expect(accHsl.saturation, greaterThanOrEqualTo(0.50));
    });

    testWidgets('AmbientPalette backgroundGradient produces calm, Spotify-like dark gradient without neon flash', (tester) async {
      const coverColor = Color(0xFF6B21A8); // Deep purple cover
      final palette = AmbientPalette.fromColor(coverColor);
      const artwork = 'https://example.com/cover-purple.jpg';
      AmbientPalette.setCachedPalette(artwork, palette);

      const track = Track(
        id: 'track-cover-1',
        title: 'Midnight Echoes',
        artist: 'The Mood',
        duration: Duration(minutes: 3, seconds: 45),
        artworkUrl: artwork,
      );

      final resolved = AmbientPalette.of(track);
      expect(resolved.primary, palette.primary);

      LinearGradient? gradient;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              gradient = AmbientPalette.backgroundGradient(
                context: context,
                track: track,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(gradient, isNotNull);
      expect(gradient!.colors.length, 3);
      // Top color is a soft moody vignette of the cover art
      expect(gradient!.colors[0], Color.lerp(palette.primary, const Color(0xFF12141C), 0.35));
      // Middle is deep charcoal, not a 65% neon flash!
      expect(gradient!.colors[1], Color.lerp(palette.secondary, const Color(0xFF0F1117), 0.82));
      // Bottom is deep near-black background
      expect(gradient!.colors[2], const Color(0xFF090B10));
    });

    testWidgets('AmbientPalette backgroundGradient in Warm and Light themes', (tester) async {
      const coverColor = Color(0xFF0D9488); // Teal cover
      final palette = AmbientPalette.fromColor(coverColor);
      const artwork = 'https://example.com/cover-teal.jpg';
      AmbientPalette.setCachedPalette(artwork, palette);

      const track = Track(
        id: 'track-cover-2',
        title: 'Ocean Breeze',
        artist: 'Calm Wave',
        duration: Duration(minutes: 4),
        artworkUrl: artwork,
      );

      LinearGradient? warmGradient;
      LinearGradient? lightGradient;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              warmGradient = AmbientPalette.backgroundGradient(
                context: context,
                track: track,
                isWarm: true,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(warmGradient!.colors.last, const Color(0xFF1E140F)); // Warm cocoa base

      await ThemeController.instance.setThemeMode(AppThemeMode.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          home: Builder(
            builder: (context) {
              lightGradient = AmbientPalette.backgroundGradient(
                context: context,
                track: track,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(lightGradient!.colors.last, const Color(0xFFF8FAFC)); // Clean light base
    });
  });
}

