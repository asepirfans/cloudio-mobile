import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../controllers/player_controller.dart';

/// Opt-in, bounded device log. No stream URLs, tokens or account data.
class PlaybackDiagnostics {
  static final Map<String, Object?> _rendered = {};

  static void recordUi(String surface, PlayerController controller) {
    if (!const bool.fromEnvironment('CLOUDIO_PLAYBACK_DIAGNOSTICS')) return;
    _rendered[surface] = {
      'trackId': controller.currentTrack?.id,
      'positionMs': controller.position.inMilliseconds,
      'durationMs': controller.duration.inMilliseconds,
      'time': DateTime.now().toIso8601String(),
    };
  }

  static Future<void> start(PlayerController controller) async {
    if (kIsWeb || !const bool.fromEnvironment('CLOUDIO_PLAYBACK_DIAGNOSTICS')) {
      return;
    }
    final directory = Directory.systemTemp;
    final file = File('${directory.path}/cloudio-playback-diagnostics.jsonl');
    var capturing = false;
    Timer.periodic(const Duration(seconds: 1), (_) async {
      if (capturing) return;
      capturing = true;
      try {
        final native = await controller.player.cloudioNativeSnapshot();
        final sample = {
          'time': DateTime.now().toIso8601String(),
          'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
          ...controller.playbackDiagnosticState,
          'native': native,
          'rendered': _rendered,
        };
        if (await file.exists() && await file.length() > 2 * 1024 * 1024) {
          await file.writeAsString('');
        }
        await file.writeAsString('${jsonEncode(sample)}\n',
            mode: FileMode.append, flush: true);
      } catch (_) {
        // Diagnostics must never interrupt playback.
      } finally {
        capturing = false;
      }
    });
  }
}
