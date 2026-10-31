import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  dark,
  light,
  warm,
  amoled,
  system,
}

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  static const _prefKey = 'cloudio_theme_mode';

  AppThemeMode _mode = AppThemeMode.dark;
  AppThemeMode get mode => _mode;

  bool get isLight => _mode == AppThemeMode.light;
  bool get isDark => _mode == AppThemeMode.dark;
  bool get isWarm => _mode == AppThemeMode.warm;
  bool get isAmoled => _mode == AppThemeMode.amoled;
  bool get isSystem => _mode == AppThemeMode.system;

  ThemeMode get flutterThemeMode {
    switch (_mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
      case AppThemeMode.warm:
      case AppThemeMode.amoled:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        _mode = AppThemeMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => AppThemeMode.dark,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(AppThemeMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newMode.name);
    } catch (_) {}
  }

  String get modeLabel {
    switch (_mode) {
      case AppThemeMode.dark:
        return 'Gelap (Midnight Navy)';
      case AppThemeMode.light:
        return 'Terang (Daylight)';
      case AppThemeMode.warm:
        return 'Hangat (Warm Cokelat)';
      case AppThemeMode.amoled:
        return 'Hitam Pekat (AMOLED)';
      case AppThemeMode.system:
        return 'Mengikuti Sistem';
    }
  }

  IconData get modeIcon {
    switch (_mode) {
      case AppThemeMode.dark:
        return Icons.dark_mode_rounded;
      case AppThemeMode.light:
        return Icons.light_mode_rounded;
      case AppThemeMode.warm:
        return Icons.coffee_rounded;
      case AppThemeMode.amoled:
        return Icons.brightness_2_rounded;
      case AppThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }
}
