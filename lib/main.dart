import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';

import 'controllers/player_controller.dart';
import 'controllers/playlist_controller.dart';
import 'controllers/search_history_controller.dart';
import 'controllers/listening_history_controller.dart';
import 'controllers/download_controller.dart';
import 'controllers/theme_controller.dart';
import 'services/cloudio_audio_handler.dart';
import 'services/playback_diagnostics.dart';
import 'services/offline_storage_service.dart';
import 'theme/app_theme.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/cloudio_splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Cloudio music fingerprint'],
        await rootBundle.loadString('assets/licenses/shazam_identifier.txt'));
  });

  // Set system UI overlay style to dark
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  try {
    await AudioService.init(
      builder: () => CloudioAudioHandler(PlayerController.instance),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.cloudiolabs.cloudio_mobile.channel.audio',
        androidNotificationChannelName: 'Cloudio Audio Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('AudioService init warning: $e');
  }

  await OfflineStorageService.instance.init();
  await ThemeController.instance.init();
  await PlayerController.instance.ensureInitialized();
  await PlaybackDiagnostics.start(PlayerController.instance);
  runApp(const CloudioApp());
}

class CloudioApp extends StatelessWidget {
  const CloudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(
          value: PlayerController.instance,
        ),
        ChangeNotifierProvider<PlaylistController>.value(
          value: PlaylistController.instance,
        ),
        ChangeNotifierProvider<SearchHistoryController>.value(
          value: SearchHistoryController.instance,
        ),
        ChangeNotifierProvider<ListeningHistoryController>.value(
          value: ListeningHistoryController.instance,
        ),
        ChangeNotifierProvider<OfflineStorageService>.value(
          value: OfflineStorageService.instance,
        ),
        ChangeNotifierProvider<DownloadController>.value(
          value: DownloadController.instance,
        ),
        ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController.instance,
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeCtrl, _) {
            final darkThemeData = themeCtrl.isWarm
                ? AppTheme.warmTheme
                : (themeCtrl.isAmoled
                    ? AppTheme.amoledTheme
                    : AppTheme.darkTheme);
            return MaterialApp(
              title: 'Cloudio',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: darkThemeData,
              themeMode: themeCtrl.flutterThemeMode,
            builder: (context, child) =>
                ThemeBrightnessSync(child: child ?? const SizedBox.shrink()),
            home: const CloudioSplashScreen(
              nextScreenBuilder: _buildMainScreen,
            ),
          );
        },
      ),
    );
  }
}

Widget _buildMainScreen(BuildContext context) => const MainNavigationScreen();
