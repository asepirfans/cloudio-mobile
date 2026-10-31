import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

import '../controllers/theme_controller.dart';
import '../models/track.dart';

class AmbientPalette {
  final Color primary;
  final Color secondary;
  final Color accent;

  const AmbientPalette({
    required this.primary,
    required this.secondary,
    required this.accent,
  });

  /// In-memory cache of extracted cover-art palettes
  static final Map<String, AmbientPalette> _cache = {};
  static final Set<String> _extracting = {};

  /// Global revision notifier so player and lyrics screens rebuild when
  /// cover art color extraction completes asynchronously.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Curated Spotify-style atmospheric, moody color schemes (used as fallback or offline)
  static const List<AmbientPalette> _palettePool = [
    // 0. Muted Slate Charcoal
    AmbientPalette(
      primary: Color(0xFF263238),
      secondary: Color(0xFF192227),
      accent: Color(0xFF38BDF8),
    ),
    // 1. Smoked Indigo
    AmbientPalette(
      primary: Color(0xFF2B2A42),
      secondary: Color(0xFF1C1B2E),
      accent: Color(0xFF818CF8),
    ),
    // 2. Warm Espresso Bronze
    AmbientPalette(
      primary: Color(0xFF382920),
      secondary: Color(0xFF241913),
      accent: Color(0xFFF59E0B),
    ),
    // 3. Deep Forest Spruce
    AmbientPalette(
      primary: Color(0xFF1D3328),
      secondary: Color(0xFF13221A),
      accent: Color(0xFF34D399),
    ),
    // 4. Dusty Wine / Maroon
    AmbientPalette(
      primary: Color(0xFF3B1D25),
      secondary: Color(0xFF261217),
      accent: Color(0xFFFB7185),
    ),
    // 5. Midnight Cobalt
    AmbientPalette(
      primary: Color(0xFF1E2D44),
      secondary: Color(0xFF131D2D),
      accent: Color(0xFF60A5FA),
    ),
    // 6. Smoked Plum
    AmbientPalette(
      primary: Color(0xFF35203B),
      secondary: Color(0xFF221426),
      accent: Color(0xFFA78BFA),
    ),
    // 7. Dark Olive Pine
    AmbientPalette(
      primary: Color(0xFF283424),
      secondary: Color(0xFF1A2317),
      accent: Color(0xFF4ADE80),
    ),
    // 8. Deep Teal Obsidian
    AmbientPalette(
      primary: Color(0xFF1A3337),
      secondary: Color(0xFF102124),
      accent: Color(0xFF2DD4BF),
    ),
    // 9. Burnt Umber
    AmbientPalette(
      primary: Color(0xFF3B2A1E),
      secondary: Color(0xFF261B12),
      accent: Color(0xFFFB923C),
    ),
  ];

  /// Calibrates an extracted cover-art color for Spotify's moody, non-neon background
  static AmbientPalette fromColor(Color source) {
    final hsl = HSLColor.fromColor(source);

    // Spotify background tone: Moody, desaturated, mature (never neon)
    final bgSat = hsl.saturation.clamp(0.18, 0.42);
    final bgLight = hsl.lightness.clamp(0.18, 0.28);
    final primary = hsl.withSaturation(bgSat).withLightness(bgLight).toColor();

    // Deeper tone for smooth vertical gradient falloff
    final secLight = (bgLight * 0.72).clamp(0.12, 0.20);
    final secondary =
        hsl.withSaturation(bgSat * 0.85).withLightness(secLight).toColor();

    // Punchy interactive accent (for slider, play buttons, active lyrics)
    final accSat = hsl.saturation.clamp(0.50, 0.85);
    final accLight = hsl.lightness.clamp(0.50, 0.70);
    final accent = hsl.withSaturation(accSat).withLightness(accLight).toColor();

    return AmbientPalette(
      primary: primary,
      secondary: secondary,
      accent: accent,
    );
  }

  /// Stably extracts a calibrated ambient palette from a track's artwork or metadata.
  /// If an artwork URL exists, asynchronous palette extraction is started and cached.
  static AmbientPalette of(Track? track) {
    if (track == null) {
      return _palettePool[0];
    }

    final artworkUrl = track.artworkUrl?.trim();
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      final cached = _cache[artworkUrl];
      if (cached != null) {
        return cached;
      }
      _extractFromArtwork(artworkUrl);
    }

    // Stable moody fallback hash while loading or offline
    final key = '${track.id}_${track.title}_${track.artist}';
    var hash = 0;
    for (var i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.codeUnitAt(i)) & 0x7FFFFFFF;
    }

    return _palettePool[hash % _palettePool.length];
  }

  static void _extractFromArtwork(String url) async {
    if (_extracting.contains(url)) return;
    _extracting.add(url);

    try {
      ImageProvider provider;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        provider = CachedNetworkImageProvider(url);
      } else if (url.startsWith('file://') || url.startsWith('/')) {
        provider = FileImage(File(url.replaceFirst('file://', '')));
      } else {
        provider = AssetImage(url);
      }

      final generator = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(64, 64),
        maximumColorCount: 16,
      );

      final selectedColor = generator.mutedColor?.color ??
          generator.darkMutedColor?.color ??
          generator.dominantColor?.color ??
          generator.darkVibrantColor?.color ??
          generator.vibrantColor?.color;

      if (selectedColor != null) {
        final palette = fromColor(selectedColor);
        _cache[url] = palette;
        revision.value++;
      }
    } catch (_) {
      // In offline/test environments, gracefully ignore image decoding failures
    } finally {
      _extracting.remove(url);
    }
  }

  @visibleForTesting
  static void setCachedPalette(String key, AmbientPalette palette) {
    _cache[key] = palette;
  }

  @visibleForTesting
  static void clearCache() {
    _cache.clear();
  }

  /// The dynamic accent color for interactive controls (play button, slider, queue indicators)
  Color accentOf(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    if (isLight) {
      return accent.computeLuminance() > 0.40
          ? Color.lerp(accent, Colors.black, 0.25)!
          : accent;
    }
    return accent;
  }

  /// High-contrast foreground color on top of [accentOf]
  Color onAccentOf(BuildContext context) {
    return accent.computeLuminance() > 0.45
        ? const Color(0xFF0F172A)
        : Colors.white;
  }

  /// Builds a calm, Spotify-like ambient gradient for a player and lyrics background
  static LinearGradient backgroundGradient({
    required BuildContext context,
    required Track? track,
    bool isAmoled = false,
    bool isWarm = false,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light ||
        ThemeController.instance.isLight;
    final palette = of(track);
    final isWarmActive = isWarm || ThemeController.instance.isWarm;

    if (isLight) {
      // Light Mode: Ultra-soft, luminous ambient glow without chromatic glare
      final topSoft = Color.lerp(palette.primary, Colors.white, 0.88)!;
      final softTint = Color.lerp(palette.secondary, Colors.white, 0.94)!;
      const bottomWash = Color(0xFFF8FAFC);
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          topSoft,
          softTint,
          bottomWash,
        ],
        stops: const [0.0, 0.45, 1.0],
      );
    } else if (isWarmActive) {
      // Warm (Cokelat) Mode: Rich espresso & roasted coffee ambient gradient subtly tinted by cover art
      final warmTop =
          Color.lerp(palette.primary, const Color(0xFF2B1D16), 0.70)!;
      final warmMid =
          Color.lerp(palette.secondary, const Color(0xFF241812), 0.85)!;
      const warmBottom = Color(0xFF1E140F);
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          warmTop,
          warmMid,
          warmBottom,
        ],
        stops: const [0.0, 0.45, 1.0],
      );
    } else if (isAmoled) {
      // AMOLED Mode: Subtle top aura flowing into pure pitch black
      final topVignette = Color.lerp(palette.primary, Colors.black, 0.50)!;
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          topVignette,
          Color.lerp(palette.secondary, Colors.black, 0.80)!,
          Colors.black,
        ],
        stops: const [0.0, 0.40, 1.0],
      );
    } else {
      // Dark Mode (Spotify Signature):
      // The cover art color gently tints the top with a deep, moody vignette,
      // and smoothly darkens into deep charcoal/black (#090B10) without any neon flash.
      final topVignette =
          Color.lerp(palette.primary, const Color(0xFF12141C), 0.35)!;
      final midShade =
          Color.lerp(palette.secondary, const Color(0xFF0F1117), 0.82)!;
      const bottomShade = Color(0xFF090B10);
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          topVignette,
          midShade,
          bottomShade,
        ],
        stops: const [0.0, 0.50, 1.0],
      );
    }
  }
}
