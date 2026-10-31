import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/download_controller.dart';
import '../controllers/player_controller.dart';
import '../controllers/playlist_controller.dart';
import '../models/track.dart';
import '../services/offline_storage_service.dart';
import '../theme/app_theme.dart';

class PlaylistActions {
  static Future<void> showTrackMenu(
    BuildContext context,
    Track track, {
    Future<void> Function()? onRemove,
  }) async {
    final isDownloaded =
        OfflineStorageService.instance.isTrackDownloaded(track.id);
    final isDownloading =
        DownloadController.instance.isDownloading(track.id);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                track.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                track.displayArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.accent,
                ),
                title: const Text('Tambahkan ke antrean'),
                subtitle: Text(
                  'Diputar sebelum rekomendasi otomatis',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, 'queue'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Simpan ke playlist'),
                onTap: () => Navigator.pop(sheetContext, 'playlist'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isDownloaded
                      ? Icons.check_circle_rounded
                      : Icons.arrow_circle_down_rounded,
                  color: isDownloaded
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                title: Text(isDownloaded
                    ? 'Hapus dari unduhan'
                    : 'Unduh lagu offline'),
                subtitle: isDownloading
                    ? Text(
                        'Sedang mengunduh...',
                        style: TextStyle(color: AppColors.accent, fontSize: 11),
                      )
                    : null,
                onTap: () => Navigator.pop(
                    sheetContext, isDownloaded ? 'remove_download' : 'download'),
              ),
              if (onRemove != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.remove_circle_outline_rounded,
                    color: AppColors.textMuted,
                  ),
                  title: const Text('Hapus dari playlist'),
                  onTap: () => Navigator.pop(sheetContext, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted || action == null) return;
    if (action == 'remove') {
      await onRemove?.call();
      return;
    }
    if (action == 'playlist') {
      await showAddToPlaylist(context, track);
      return;
    }
    if (action == 'download') {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mulai mengunduh "${track.displayTitle}"...'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await DownloadController.instance.downloadTrack(track);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('"${track.displayTitle}" berhasil disimpan ke offline.'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          final msg = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('HttpException: ', '')
              .replaceAll('FormatException: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal mengunduh: $msg'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }
    if (action == 'remove_download') {
      await DownloadController.instance.removeDownloadedTrack(track.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('"${track.displayTitle}" dihapus dari unduhan offline.'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final added = await context.read<PlayerController>().addToQueue(track);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Ditambahkan ke antrean prioritas'
              : 'Lagu sudah ada di antrean',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> showAddToPlaylist(
    BuildContext context,
    Track track,
  ) async {
    final rootContext = context;
    final controller = context.read<PlaylistController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Consumer<PlaylistController>(
          builder: (context, playlists, _) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Simpan ke playlist',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const SizedBox(height: 16),
                Row(children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.square(
                          dimension: 52,
                          child: track.artworkUrl == null
                              ? ColoredBox(
                                  color: AppColors.elevated,
                                  child: const Icon(Icons.music_note_rounded))
                              : CachedNetworkImage(
                                  imageUrl: track.artworkUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.music_note_rounded)))),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(track.displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ])),
                ]),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(Icons.add_rounded, color: AppColors.accent),
                  ),
                  title: const Text(
                    'Playlist baru',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    final name = await _askPlaylistName(context);
                    if (name == null) return;
                    final playlist = await controller.createPlaylist(name);
                    await controller.addTrack(playlist.id, track);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (rootContext.mounted) {
                      _showSavedMessage(rootContext, playlist.name);
                    }
                  },
                ),
                if (playlists.playlists.isNotEmpty) const Divider(height: 20),
                if (playlists.playlists.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                          'Buat playlist pertamamu untuk menyimpan lagu ini.',
                          style: TextStyle(color: AppColors.textSecondary))),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .42),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists.playlists[index];
                      final saved =
                          playlist.tracks.any((item) => item.id == track.id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.elevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          saved
                              ? 'Sudah tersimpan · ${playlist.tracks.length} lagu'
                              : '${playlist.tracks.length} lagu',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Icon(
                            saved
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: saved
                                ? AppColors.accent
                                : AppColors.textSecondary),
                        onTap: () async {
                          final added =
                              await controller.addTrack(playlist.id, track);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (rootContext.mounted) {
                            _showSavedMessage(
                              rootContext,
                              added
                                  ? 'Disimpan ke ${playlist.name}'
                                  : 'Lagu sudah ada di ${playlist.name}',
                              exactMessage: true,
                            );
                          }
                        },
                      );
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

  static Future<String?> _askPlaylistName(BuildContext context) async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Playlist baru',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nama playlist'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) Navigator.pop(dialogContext, name);
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    textController.dispose();
    return result;
  }

  static void _showSavedMessage(
    BuildContext context,
    String value, {
    bool exactMessage = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(exactMessage ? value : 'Disimpan ke $value'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
