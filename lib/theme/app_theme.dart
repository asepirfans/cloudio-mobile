import 'package:flutter/material.dart';
import '../controllers/theme_controller.dart';

/// Fixed dark-theme tokens. Used by [AppTheme.darkTheme] and as the dark
/// branch of [AppColors].
class DarkPalette {
  static const Color background = Color(0xFF0B1420);
  static const Color surface = Color(0xFF0B1420);
  static const Color card = Color(0xFF142234);
  static const Color elevated = Color(0xFF1D3148);
  static const Color border = Color(0xFF26384B);
  static const Color borderSubtle = Color(0xFF26384B);
  static const Color accent = Color(0xFFA4D5F5);
  static const Color accentHover = Color(0xFFC8E7FB);
  static const Color accentDim = Color(0xFF1D3148);
  static const Color accentInk = Color(0xFF102A3D);
  static const Color violet = Color(0xFFA4D5F5);
  static const Color textPrimary = Color(0xFFF1F6FA);
  static const Color textSecondary = Color(0xFF9CAFC0);
  static const Color textMuted = Color(0xFF9CAFC0);
  static const Color textDisabled = Color(0xFF56708C);
  static const Color error = Color(0xFFF87171);
  static const Color success = Color(0xFF4ADE80);
}

/// Fixed light-theme tokens: bright surfaces with dark, high-contrast text.
class LightPalette {
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color elevated = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFE2E8F0);
  static const Color accent = Color(0xFF0369A1);
  static const Color accentHover = Color(0xFF0284C7);
  static const Color accentDim = Color(0xFFE0F2FE);
  static const Color accentInk = Color(0xFFFFFFFF);
  static const Color violet = Color(0xFF0369A1);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFF94A3B8);
  static const Color error = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);
}

/// Fixed warm chocolate/brown tokens: rich roasted coffee and warm cocoa surfaces
/// with golden caramel accents and warm cream typography.
class WarmPalette {
  static const Color background = Color(0xFF1E140F);
  static const Color surface = Color(0xFF1E140F);
  static const Color card = Color(0xFF2B1D16);
  static const Color elevated = Color(0xFF3B2A21);
  static const Color border = Color(0xFF4D382D);
  static const Color borderSubtle = Color(0xFF443127);
  static const Color accent = Color(0xFFE08D4E);
  static const Color accentHover = Color(0xFFEA9E63);
  static const Color accentDim = Color(0xFF3D271D);
  static const Color accentInk = Color(0xFF23140C);
  static const Color violet = Color(0xFFE08D4E);
  static const Color textPrimary = Color(0xFFFAF3EC);
  static const Color textSecondary = Color(0xFFC7B199);
  static const Color textMuted = Color(0xFF9E8776);
  static const Color textDisabled = Color(0xFF6B584B);
  static const Color error = Color(0xFFF87171);
  static const Color success = Color(0xFF4ADE80);
}

/// Brightness and theme-aware color tokens. The active mode is synced from
/// [ThemeController], supporting Dark (Midnight Navy), Light (Daylight), and Warm (Cokelat).
class AppColors {
  static Brightness brightness = Brightness.dark;
  static AppThemeMode currentMode = AppThemeMode.dark;

  static bool get isLight => currentMode == AppThemeMode.light || brightness == Brightness.light;
  static bool get isWarm => currentMode == AppThemeMode.warm;
  static bool get isDark => currentMode == AppThemeMode.dark;

  static Color get background => isWarm
      ? WarmPalette.background
      : (isLight ? LightPalette.background : DarkPalette.background);
  static Color get surface => isWarm
      ? WarmPalette.surface
      : (isLight ? LightPalette.surface : DarkPalette.surface);
  static Color get card => isWarm
      ? WarmPalette.card
      : (isLight ? LightPalette.card : DarkPalette.card);
  static Color get elevated => isWarm
      ? WarmPalette.elevated
      : (isLight ? LightPalette.elevated : DarkPalette.elevated);
  static Color get border => isWarm
      ? WarmPalette.border
      : (isLight ? LightPalette.border : DarkPalette.border);
  static Color get borderSubtle => isWarm
      ? WarmPalette.borderSubtle
      : (isLight ? LightPalette.borderSubtle : DarkPalette.borderSubtle);

  static Color get accent => isWarm
      ? WarmPalette.accent
      : (isLight ? LightPalette.accent : DarkPalette.accent);
  static Color get accentHover => isWarm
      ? WarmPalette.accentHover
      : (isLight ? LightPalette.accentHover : DarkPalette.accentHover);
  static Color get accentDim => isWarm
      ? WarmPalette.accentDim
      : (isLight ? LightPalette.accentDim : DarkPalette.accentDim);
  static Color get accentInk => isWarm
      ? WarmPalette.accentInk
      : (isLight ? LightPalette.accentInk : DarkPalette.accentInk);
  static Color get violet => isWarm
      ? WarmPalette.violet
      : (isLight ? LightPalette.violet : DarkPalette.violet);

  static Color get textPrimary => isWarm
      ? WarmPalette.textPrimary
      : (isLight ? LightPalette.textPrimary : DarkPalette.textPrimary);
  static Color get textSecondary => isWarm
      ? WarmPalette.textSecondary
      : (isLight ? LightPalette.textSecondary : DarkPalette.textSecondary);
  static Color get textMuted => isWarm
      ? WarmPalette.textMuted
      : (isLight ? LightPalette.textMuted : DarkPalette.textMuted);
  static Color get textDisabled => isWarm
      ? WarmPalette.textDisabled
      : (isLight ? LightPalette.textDisabled : DarkPalette.textDisabled);

  static Color get error => isLight ? LightPalette.error : DarkPalette.error;
  static Color get success => isLight ? LightPalette.success : DarkPalette.success;

  static bool _isWarmCtx(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor == WarmPalette.background ||
      (currentMode == AppThemeMode.warm &&
          Theme.of(context).brightness == Brightness.dark);

  static bool _isLightCtx(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color textPrimaryOf(BuildContext context) {
    if (_isWarmCtx(context)) return WarmPalette.textPrimary;
    if (_isLightCtx(context)) return LightPalette.textPrimary;
    return DarkPalette.textPrimary;
  }

  static Color textSecondaryOf(BuildContext context) {
    if (_isWarmCtx(context)) return WarmPalette.textSecondary;
    if (_isLightCtx(context)) return LightPalette.textSecondary;
    return DarkPalette.textSecondary;
  }

  static Color textMutedOf(BuildContext context) {
    if (_isWarmCtx(context)) return WarmPalette.textMuted;
    if (_isLightCtx(context)) return LightPalette.textMuted;
    return DarkPalette.textMuted;
  }

  static Color accentOf(BuildContext context) {
    if (_isWarmCtx(context)) return WarmPalette.accent;
    if (_isLightCtx(context)) return LightPalette.accent;
    return DarkPalette.accent;
  }
}

class AppTheme {
  static ThemeData get darkTheme {
    final baseTextTheme =
        ThemeData.dark().textTheme.apply(fontFamily: 'InstrumentSans');

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'InstrumentSans',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DarkPalette.background,
      primaryColor: DarkPalette.accent,
      colorScheme: const ColorScheme.dark(
        primary: DarkPalette.accent,
        surface: DarkPalette.surface,
        onSurface: DarkPalette.textPrimary,
        error: DarkPalette.error,
      ),
      textTheme: baseTextTheme
          .apply(
            bodyColor: DarkPalette.textPrimary,
            displayColor: DarkPalette.textPrimary,
          )
          .copyWith(
            headlineSmall: const TextStyle(
              fontFamily: 'InstrumentSans',
              color: DarkPalette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            titleLarge: const TextStyle(
              fontFamily: 'InstrumentSans',
              color: DarkPalette.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
      splashFactory: InkRipple.splashFactory,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DarkPalette.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: DarkPalette.accent)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DarkPalette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dividerColor: DarkPalette.borderSubtle,
      appBarTheme: const AppBarTheme(
        titleSpacing: 24,
        toolbarHeight: 68,
        backgroundColor: DarkPalette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'InstrumentSans',
          color: DarkPalette.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: DarkPalette.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? DarkPalette.accent
                : DarkPalette.textMuted,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? DarkPalette.textPrimary
                : DarkPalette.textMuted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: DarkPalette.accent,
        inactiveTrackColor: DarkPalette.border,
        thumbColor: DarkPalette.accent,
        overlayColor: Color(0x228CC8FF),
      ),
    );
  }

  static ThemeData get amoledTheme {
    return darkTheme.copyWith(
      scaffoldBackgroundColor: Colors.black,
      cardColor: const Color(0xFF101010),
      colorScheme: darkTheme.colorScheme.copyWith(
        surface: Colors.black,
      ),
      appBarTheme: darkTheme.appBarTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      navigationBarTheme: darkTheme.navigationBarTheme.copyWith(
        backgroundColor: Colors.black,
      ),
    );
  }

  static ThemeData get warmTheme {
    final baseTextTheme =
        ThemeData.dark().textTheme.apply(fontFamily: 'InstrumentSans');

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'InstrumentSans',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: WarmPalette.background,
      primaryColor: WarmPalette.accent,
      cardColor: WarmPalette.card,
      colorScheme: const ColorScheme.dark(
        primary: WarmPalette.accent,
        surface: WarmPalette.surface,
        onSurface: WarmPalette.textPrimary,
        error: WarmPalette.error,
      ),
      textTheme: baseTextTheme
          .apply(
            bodyColor: WarmPalette.textPrimary,
            displayColor: WarmPalette.textPrimary,
          )
          .copyWith(
            headlineSmall: const TextStyle(
              fontFamily: 'InstrumentSans',
              color: WarmPalette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            titleLarge: const TextStyle(
              fontFamily: 'InstrumentSans',
              color: WarmPalette.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
      splashFactory: InkRipple.splashFactory,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WarmPalette.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WarmPalette.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WarmPalette.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WarmPalette.accent)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: WarmPalette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dividerColor: WarmPalette.borderSubtle,
      appBarTheme: const AppBarTheme(
        titleSpacing: 24,
        toolbarHeight: 68,
        backgroundColor: WarmPalette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'InstrumentSans',
          color: WarmPalette.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: WarmPalette.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? WarmPalette.accent
                : WarmPalette.textMuted,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? WarmPalette.textPrimary
                : WarmPalette.textMuted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: WarmPalette.accent,
        inactiveTrackColor: WarmPalette.border,
        thumbColor: WarmPalette.accent,
        overlayColor: Color(0x22E08D4E),
      ),
    );
  }

  static ThemeData get lightTheme {
    final baseTextTheme =
        ThemeData.light().textTheme.apply(fontFamily: 'InstrumentSans');

    const lightBg = Color(0xFFF8FAFC);
    const lightCard = Color(0xFFFFFFFF);
    const lightTextPrimary = Color(0xFF0F172A);
    const lightTextSecondary = Color(0xFF64748B);
    const lightBorder = Color(0xFFE2E8F0);
    const lightAccent = Color(0xFF0284C7);

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'InstrumentSans',
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: lightAccent,
      cardColor: lightCard,
      colorScheme: const ColorScheme.light(
        primary: lightAccent,
        surface: lightBg,
        onSurface: lightTextPrimary,
        error: Color(0xFFDC2626),
      ),
      textTheme: baseTextTheme
          .apply(
            bodyColor: lightTextPrimary,
            displayColor: lightTextPrimary,
          )
          .copyWith(
            headlineSmall: const TextStyle(
              fontFamily: 'InstrumentSans',
              color: lightTextPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            titleLarge: const TextStyle(
              fontFamily: 'InstrumentSans',
              color: lightTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
      splashFactory: InkRipple.splashFactory,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: lightBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: lightBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: lightAccent)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dividerColor: lightBorder,
      appBarTheme: const AppBarTheme(
        titleSpacing: 24,
        toolbarHeight: 68,
        backgroundColor: lightBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'InstrumentSans',
          color: lightTextPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: lightBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? lightAccent
                : lightTextSecondary,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? lightTextPrimary
                : lightTextSecondary,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: lightAccent,
        inactiveTrackColor: lightBorder,
        thumbColor: lightAccent,
        overlayColor: Color(0x220284C7),
      ),
    );
  }
}

/// Keeps [AppColors.brightness] in sync with the resolved app theme
/// (light, dark, AMOLED or system) and forces a full subtree rebuild when it
/// flips, so const widgets that read [AppColors] tokens repaint too.
class ThemeBrightnessSync extends StatefulWidget {
  final Widget child;
  const ThemeBrightnessSync({super.key, required this.child});

  @override
  State<ThemeBrightnessSync> createState() => _ThemeBrightnessSyncState();
}

class _ThemeBrightnessSyncState extends State<ThemeBrightnessSync> {
  Brightness? _last;
  AppThemeMode? _lastMode;

  static void _markAll(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_markAll);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final mode = ThemeController.instance.mode;
    AppColors.brightness = brightness;
    AppColors.currentMode = mode;
    if ((_last != null && _last != brightness) ||
        (_lastMode != null && _lastMode != mode)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) (context as Element).visitChildren(_markAll);
      });
    }
    _last = brightness;
    _lastMode = mode;
    return widget.child;
  }
}
