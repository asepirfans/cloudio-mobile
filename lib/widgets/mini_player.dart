import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../services/playback_diagnostics.dart';
import '../theme/app_theme.dart';
import 'mini_audio_visualizer.dart';
import 'player_sheet.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    PlaybackDiagnostics.recordUi('miniPlayer', controller);
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final duration = controller.duration.inMilliseconds;
    final progress = duration > 0
        ? (controller.position.inMilliseconds / duration).clamp(0.0, 1.0)
        : 0.0;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Material(
        color: isLight ? Colors.white : AppColors.elevated,
        elevation: isLight ? 4 : 0,
        shadowColor: isLight ? Colors.black.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => PlayerSheet.show(context),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox.square(
                    dimension: 44,
                    child: track.artworkUrl == null
                        ? ColoredBox(
                            color: isLight ? const Color(0xFFE2E8F0) : AppColors.card,
                            child: Icon(Icons.album_outlined,
                                color: primaryColor))
                        : CachedNetworkImage(
                            imageUrl: track.artworkUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const Icon(Icons.album_outlined)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isLight ? const Color(0xFF0F172A) : null)),
                      const SizedBox(height: 3),
                      Text(controller.playbackError ?? track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: isLight ? const Color(0xFF64748B) : AppColors.textSecondary)),
                    ])),
                const SizedBox(width: 8),
                MiniAudioVisualizer(
                  isPlaying: controller.isPlaying,
                  color: primaryColor,
                  height: 18,
                  barCount: 4,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: controller.isPlaying ? 'Jeda' : 'Putar',
                  onPressed:
                      controller.isBusy ? null : controller.togglePlayPause,
                  style: IconButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: isLight ? Colors.white : AppColors.accentInk,
                      minimumSize: const Size(44, 44)),
                  icon: controller.isBusy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isLight ? Colors.white : AppColors.accentInk))
                      : Icon(controller.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                ),
                IconButton(
                    tooltip: 'Lagu berikutnya',
                    onPressed: controller.next,
                    icon: Icon(Icons.skip_next_rounded,
                        size: 25,
                        color: isLight ? const Color(0xFF0F172A) : null)),
              ]),
            ),
            LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: isLight ? const Color(0xFFE2E8F0) : AppColors.border,
                valueColor: AlwaysStoppedAnimation(primaryColor)),
          ]),
        ),
      ),
    );
  }
}
