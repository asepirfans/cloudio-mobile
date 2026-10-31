import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player_visual.dart';
import 'sleep_timer_sheet.dart';

import '../controllers/player_controller.dart';
import '../controllers/playlist_controller.dart';
import '../controllers/download_controller.dart';
import '../controllers/theme_controller.dart';
import '../services/playback_diagnostics.dart';
import '../services/offline_storage_service.dart';
import '../models/track.dart';
import '../theme/ambient_palette.dart';
import '../theme/app_theme.dart';
import 'lyrics_card.dart';
import 'playlist_actions.dart';

class PlayerSheet extends StatefulWidget {
  const PlayerSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlayerSheet(),
      ),
    );
  }

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  static const _themeKey = 'cloudio.player_theme.v1';
  PlayerVisualTheme _visual = PlayerVisualTheme.cover;
  bool _themeChosen = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_themeKey);
      if (!mounted || _themeChosen) return;
      setState(() => _visual = PlayerVisualTheme.values.firstWhere(
          (item) => item.name == (saved == 'stage' ? 'cassette' : saved),
          orElse: () => PlayerVisualTheme.cover));
    });
  }

  Future<void> _chooseTheme(Color primaryAccent) async {
    final selected = await showModalBottomSheet<PlayerVisualTheme>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tema player',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 20),
                      for (final theme in PlayerVisualTheme.values)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(theme.icon, color: primaryAccent),
                            title: Text(theme.label),
                            subtitle: Text(
                                switch (theme) {
                                  PlayerVisualTheme.cover =>
                                    'Fokus ke sampul album',
                                  PlayerVisualTheme.vinyl =>
                                    'Berputar mengikuti pemutaran',
                                  PlayerVisualTheme.cassette =>
                                    'Kaset dengan dua gulungan berputar',
                                },
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            trailing: _visual == theme
                                ? Icon(Icons.check_circle_rounded,
                                    color: primaryAccent)
                                : null,
                            onTap: () => Navigator.pop(context, theme)),
                    ]))));
    if (selected == null || !mounted) return;
    setState(() {
      _themeChosen = true;
      _visual = selected;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, selected.name);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    PlaybackDiagnostics.recordUi('fullPlayer', controller);
    final track = controller.currentTrack;
    if (track == null) {
      return const Scaffold(
        body: Center(child: Text('Tidak ada lagu yang diputar')),
      );
    }

    final durationSeconds = controller.duration.inSeconds.toDouble();
    final sliderMax = durationSeconds > 0 ? durationSeconds : 1.0;
    final currentSeconds =
        controller.position.inSeconds.toDouble().clamp(0.0, sliderMax);

    final isLight = Theme.of(context).brightness == Brightness.light;
    final isAmoled = ThemeController.instance.isAmoled;

    return ValueListenableBuilder<int>(
      valueListenable: AmbientPalette.revision,
      builder: (context, _, __) {
        final palette = AmbientPalette.of(track);
        final primaryAccent = palette.accentOf(context);

        return Scaffold(
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: AmbientPalette.backgroundGradient(
                context: context,
                track: track,
                isAmoled: isAmoled,
              ),
            ),
            child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              final wide = constraints.maxWidth > constraints.maxHeight;
              final header = Row(
                children: [
                  _SoftButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: 'Kembali',
                    onTap: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'SEKARANG DIPUTAR',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SoftButton(
                    icon: controller.hasSleepTimer
                        ? Icons.bedtime_rounded
                        : Icons.bedtime_outlined,
                    color: controller.hasSleepTimer ? primaryAccent : null,
                    tooltip: controller.sleepAfterTrack
                        ? 'Sleep timer · setelah lagu ini'
                        : controller.sleepTimerRemaining == null
                            ? 'Sleep timer'
                            : 'Sleep timer · ${SleepTimerSheet.formatRemaining(controller.sleepTimerRemaining!)}',
                    onTap: () => SleepTimerSheet.show(context, controller),
                  ),
                  _SoftButton(
                    icon: Icons.tune_rounded,
                    tooltip: 'Tema player',
                    onTap: () => _chooseTheme(primaryAccent),
                  ),
                  _SoftButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'Opsi lagu',
                    onTap: () => PlaylistActions.showTrackMenu(
                      context,
                      track,
                    ),
                  ),
                ],
              );
              final visual = Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16),
                  child: LayoutBuilder(builder: (context, area) {
                    final artworkSize = math.max(
                        0.0,
                        math.min(
                            380.0, math.min(area.maxWidth, area.maxHeight)));
                    return Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Spotify-style atmospheric ambient glow
                          Container(
                            width: artworkSize * 0.85,
                            height: artworkSize * 0.85,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: palette.primary.withOpacity(isLight ? 0.12 : 0.20),
                                  blurRadius: 55,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          PlayerVisual(
                            theme: _visual,
                            playing: controller.isPlaying,
                            imageUrl: track.artworkUrl,
                            size: artworkSize,
                            accentColor: primaryAccent,
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              );
              final metadata = Padding(
                padding: EdgeInsets.only(top: wide ? 0 : 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.displayTitle,
                                maxLines: wide ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                        height: 1.08,
                                        fontSize: wide ? 20 : 24,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimaryOf(context)),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                track.displayArtist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textSecondaryOf(context),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _DownloadButton(track: track, accentColor: primaryAccent),
                        const SizedBox(width: 2),
                        AnimatedBuilder(
                          animation: PlaylistController.instance,
                          builder: (context, _) {
                            final saved = PlaylistController.instance.playlists
                                .any((list) => list.tracks
                                    .any((item) => item.id == track.id));
                            return _SoftButton(
                              icon: saved
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: saved ? primaryAccent : null,
                              tooltip: saved
                                  ? 'Tersimpan di playlist'
                                  : 'Simpan ke playlist',
                              onTap: () => PlaylistActions.showAddToPlaylist(
                                  context, track),
                            );
                          },
                        ),
                      ],
                    ),
                    if (controller.playbackError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          controller.playbackError!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                    SizedBox(height: wide ? 2 : 12),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: primaryAccent,
                        inactiveTrackColor: isLight
                            ? palette.primary.withOpacity(0.14)
                            : Colors.white.withOpacity(0.18),
                        thumbColor: primaryAccent,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 15,
                        ),
                      ),
                      child: Slider(
                        value: currentSeconds,
                        max: sliderMax,
                        onChanged: (value) => controller.previewSeek(
                          Duration(milliseconds: (value * 1000).round()),
                        ),
                        onChangeEnd: (value) => controller.seek(
                          Duration(seconds: value.round()),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(controller.position),
                            style: TextStyle(
                              color: AppColors.textMutedOf(context),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatDuration(controller.duration),
                            style: TextStyle(
                              color: AppColors.textMutedOf(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              final controls = Padding(
                padding: EdgeInsets.only(
                    top: wide
                        ? 4
                        : compact
                            ? 10
                            : 16),
                child: Column(
                  children: [
                    _PlaybackControls(
                      controller: controller,
                      palette: palette,
                      compact: wide,
                    ),
                    SizedBox(
                        height: wide
                            ? 4
                            : compact
                                ? 10
                                : 16),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Theme.of(context).dividerColor.withOpacity(0.12),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: LyricsCard(
                            key: ValueKey('${track.id}:${track.isKaraoke}'),
                            track: track,
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  AppColors.textSecondaryOf(context),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onPressed: () => _showQueue(context, controller, palette),
                            icon: const Icon(
                              Icons.queue_music_rounded,
                              size: 19,
                            ),
                            label: const Text('Antrean'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  AppColors.textSecondaryOf(context),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onPressed: () => PlaylistActions.showAddToPlaylist(
                              context,
                              track,
                            ),
                            icon: const Icon(
                              Icons.playlist_add_rounded,
                              size: 20,
                            ),
                            label: const Text('Simpan'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 1000 : 520),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        header,
                        if (wide)
                          Expanded(
                              child: Row(children: [
                            visual,
                            const SizedBox(width: 24),
                            Expanded(
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [metadata, controls])),
                          ]))
                        else ...[visual, metadata, controls],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
      },
    );
  }

  void _showQueue(BuildContext context, PlayerController controller, AmbientPalette palette) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primaryAccent = palette.accentOf(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.black12 : AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Antrean berikutnya',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            '${math.max(0, controller.queue.length - controller.currentIndex - 1)} lagu setelah ini',
                            style: TextStyle(
                                color: AppColors.textSecondaryOf(context))))),
                if (controller.isExtendingQueue)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: primaryAccent,
                    backgroundColor: Colors.transparent,
                  ),
                Expanded(
                  child: controller.queue.length == 1 &&
                          controller.isExtendingQueue
                      ? Center(
                          child: Text(
                            'Menyiapkan antrean yang cocok...',
                            style: TextStyle(
                              color: AppColors.textSecondaryOf(context),
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: ValueKey(
                              'upcoming-${controller.currentIndex}-${controller.currentTrack?.id}'),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: controller.queue.length -
                              math.max(controller.currentIndex, 0).toInt(),
                          itemBuilder: (context, index) {
                            final queueIndex = index +
                                math.max(controller.currentIndex, 0).toInt();
                            final item = controller.queue[queueIndex];
                            final isCurrent =
                                queueIndex == controller.currentIndex;
                            return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Material(
                                    color: isCurrent
                                        ? (isLight
                                            ? const Color(0xFFF1F5F9)
                                            : AppColors.elevated)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 8,
                                      ),
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(9),
                                        child: SizedBox.square(
                                          dimension: 52,
                                          child: item.artworkUrl == null
                                              ? ColoredBox(
                                                  color: isLight
                                                      ? const Color(0xFFE2E8F0)
                                                      : AppColors.surface,
                                                  child: Icon(
                                                    Icons.music_note_rounded,
                                                    color: AppColors.textMutedOf(context),
                                                  ),
                                                )
                                              : CachedNetworkImage(
                                                  imageUrl: item.artworkUrl!,
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                      ),
                                      title: Text(
                                        item.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isCurrent
                                              ? primaryAccent
                                              : AppColors.textPrimaryOf(context),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        controller.isManualQueued(item)
                                            ? '${item.displayArtist} · Prioritas'
                                            : isCurrent
                                                ? '${item.displayArtist} · Sedang diputar'
                                                : item.displayArtist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: controller.isManualQueued(item)
                                              ? primaryAccent
                                              : AppColors.textSecondaryOf(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                      trailing: isCurrent
                                          ? Padding(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 12),
                                              child: Icon(
                                                Icons.graphic_eq_rounded,
                                                color: primaryAccent,
                                                size: 18,
                                              ),
                                            )
                                          : IconButton(
                                              tooltip: 'Hapus dari antrean',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: Icon(
                                                Icons.close_rounded,
                                                color: AppColors.textMutedOf(context),
                                                size: 19,
                                              ),
                                              onPressed: () {
                                                controller
                                                    .removeFromQueue(item);
                                              },
                                            ),
                                      onTap: () {
                                        controller.playTrack(item);
                                        Navigator.pop(sheetContext);
                                      },
                                    )));
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final PlayerController controller;
  final AmbientPalette palette;
  final bool compact;
  const _PlaybackControls({
    required this.controller,
    required this.palette,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primaryAccent = palette.accentOf(context);
    final onAccentColor = palette.onAccentOf(context);
    final controlIconColor = isLight ? const Color(0xFF0F172A) : Colors.white;

    return Row(
      children: [
        Expanded(
          child: IconButton(
            tooltip: 'Acak',
            onPressed: controller.toggleShuffle,
            iconSize: 21,
            icon: Icon(
              Icons.shuffle_rounded,
              color: controller.isShuffle
                  ? primaryAccent
                  : AppColors.textMutedOf(context),
            ),
          ),
        ),
        Expanded(
          child: IconButton(
            tooltip: 'Sebelumnya',
            onPressed: controller.previous,
            iconSize: 32,
            icon: Icon(Icons.skip_previous_rounded, color: controlIconColor),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: InkResponse(
            onTap: controller.togglePlayPause,
            radius: 38,
            child: Container(
              width: compact ? 56 : 66,
              height: compact ? 56 : 66,
              decoration: BoxDecoration(
                color: primaryAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryAccent.withOpacity(isLight ? 0.35 : 0.40),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: controller.isBusy
                    ? SizedBox.square(
                        dimension: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: onAccentColor,
                        ),
                      )
                    : Icon(
                        controller.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                        color: onAccentColor,
                      ),
              ),
            ),
          ),
        ),
        Expanded(
          child: IconButton(
            tooltip: 'Berikutnya',
            onPressed: controller.next,
            iconSize: 32,
            icon: Icon(Icons.skip_next_rounded, color: controlIconColor),
          ),
        ),
        Expanded(
          child: IconButton(
            tooltip: 'Ulangi',
            onPressed: controller.toggleRepeat,
            iconSize: 21,
            icon: Icon(
              controller.repeatMode == RepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: controller.repeatMode == RepeatMode.off
                  ? AppColors.textMutedOf(context)
                  : primaryAccent,
            ),
          ),
        ),
      ],
    );
  }
}

class _SoftButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _SoftButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final defaultColor = isLight ? const Color(0xFF0F172A) : Colors.white;

    return Material(
      color: isLight ? Colors.black.withOpacity(0.04) : Colors.white.withOpacity(0.06),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 19, color: color ?? defaultColor),
      ),
    );
  }
}


class _DownloadButton extends StatelessWidget {
  final Track track;
  final Color accentColor;

  const _DownloadButton({required this.track, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        DownloadController.instance,
        OfflineStorageService.instance,
      ]),
      builder: (context, _) {
        final downloads = DownloadController.instance;
        final offline = OfflineStorageService.instance;
        final isDownloaded = offline.isTrackDownloaded(track.id);
        final isDownloading = downloads.isDownloading(track.id);
        final progress = downloads.getProgress(track.id);

        if (isDownloading) {
          return SizedBox.square(
            dimension: 40,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 2.2,
                      color: accentColor,
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return _SoftButton(
          icon: isDownloaded
              ? Icons.check_circle_rounded
              : Icons.arrow_circle_down_rounded,
          color: isDownloaded ? accentColor : AppColors.textMutedOf(context),
          tooltip: isDownloaded
              ? 'Tersimpan offline (ketuk untuk hapus)'
              : 'Unduh lagu offline',
          onTap: () async {
            if (isDownloaded) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.card,
                  title: const Text('Hapus Unduhan?'),
                  content: Text(
                      'Hapus "${track.displayTitle}" dari penyimpanan offline?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.error),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await downloads.removeDownloadedTrack(track.id);
              }
            } else {
              try {
                await downloads.downloadTrack(track);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          '"${track.displayTitle}" berhasil disimpan ke offline.'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  final message = e.toString()
                      .replaceAll('Exception: ', '')
                      .replaceAll('HttpException: ', '')
                      .replaceAll('FormatException: ', '');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal mengunduh: $message'),
                      backgroundColor: AppColors.error,
                      duration: const Duration(seconds: 4),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            }
          },
        );
      },
    );
  }
}
