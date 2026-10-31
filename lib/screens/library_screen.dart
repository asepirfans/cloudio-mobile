import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../controllers/playlist_controller.dart';
import '../controllers/listening_history_controller.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/offline_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/playlist_actions.dart';
import '../widgets/theme_selection_sheet.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistController>();
    final history = context.watch<ListeningHistoryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Musik kamu'),
        actions: [
          IconButton(
            tooltip: 'Tema Aplikasi',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => ThemeSelectionSheet.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !playlists.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      children: [
                        ListenableBuilder(
                          listenable: OfflineStorageService.instance,
                          builder: (context, _) {
                            final offline = OfflineStorageService.instance;
                            return _OfflineDownloadCard(
                              latest: offline.downloadedTracks.isEmpty
                                  ? null
                                  : offline.downloadedTracks.first,
                              count: offline.downloadedTracks.length,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const _OfflineTracksPage(),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        _ListeningHistoryCard(
                          latest:
                              history.items.isEmpty ? null : history.items.first,
                          count: history.items.length,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const _ListeningHistoryPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Playlist kamu',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Disimpan di perangkat ini',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _createPlaylist(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.accentInk,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Buat',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (playlists.playlists.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyLibrary(
                      onCreate: () => _createPlaylist(context),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    sliver: SliverList.separated(
                      itemCount: playlists.playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final playlist = playlists.playlists[index];
                        return _PlaylistCard(
                          playlist: playlist,
                          onTap: () => _openPlaylist(context, playlist.id),
                          onPlay: playlist.tracks.isEmpty
                              ? null
                              : () =>
                                  context.read<PlayerController>().playTrack(
                                        playlist.tracks.first,
                                        newQueue: playlist.tracks,
                                      ),
                          onDelete: () => _confirmDelete(context, playlist),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final input = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Playlist baru',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: input,
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
              final value = input.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null && context.mounted) {
      await context.read<PlaylistController>().createPlaylist(name);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Hapus playlist?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '“${playlist.name}” akan dihapus dari perangkat ini.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Hapus',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<PlaylistController>().deletePlaylist(playlist.id);
    }
  }

  void _openPlaylist(BuildContext context, String playlistId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: Consumer2<PlaylistController, PlayerController>(
          builder: (context, playlists, player, _) {
            final playlist = playlists.playlists
                .where((item) => item.id == playlistId)
                .firstOrNull;
            if (playlist == null) return const SizedBox.shrink();

            return SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Kembali',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox.square(
                        dimension: 160,
                        child: playlist.tracks.firstOrNull?.artworkUrl == null
                            ? ColoredBox(
                                color: AppColors.card,
                                child: Icon(
                                  Icons.queue_music_rounded,
                                  color: AppColors.accent,
                                  size: 54,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: playlist.tracks.first.artworkUrl!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Playlist · ${playlist.tracks.length} lagu',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        FilledButton.icon(
                          onPressed: playlist.tracks.isEmpty
                              ? null
                              : () => player.playTrack(
                                    playlist.tracks.first,
                                    newQueue: playlist.tracks,
                                  ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.accentInk,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Putar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: playlist.tracks.isEmpty
                              ? null
                              : () {
                                  final shuffled = [...playlist.tracks]
                                    ..shuffle();
                                  player.playTrack(
                                    shuffled.first,
                                    newQueue: shuffled,
                                  );
                                },
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Acak'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: playlist.tracks.isEmpty
                        ? Center(
                            child: Text(
                              'Belum ada lagu di playlist ini',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 24),
                            itemCount: playlist.tracks.length,
                            itemBuilder: (context, index) {
                              final track = playlist.tracks[index];
                              final isCurrent =
                                  player.currentTrack?.id == track.id;
                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                leading: SizedBox(
                                  width: 20,
                                  child: Center(
                                    child: isCurrent
                                        ? Icon(
                                            Icons.graphic_eq_rounded,
                                            color: AppColors.accent,
                                            size: 18,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                ),
                                title: Text(
                                  track.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? AppColors.accentOf(context)
                                        : AppColors.textPrimaryOf(context),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  track.displayArtist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textMutedOf(context),
                                    fontSize: 11.5,
                                  ),
                                ),
                                onTap: () => player.playTrack(
                                  track,
                                  newQueue: playlist.tracks,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.more_horiz_rounded),
                                  onPressed: () =>
                                      PlaylistActions.showTrackMenu(
                                    context,
                                    track,
                                    onRemove: () => playlists.removeTrack(
                                      playlist.id,
                                      track.id,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OfflineDownloadCard extends StatelessWidget {
  final Track? latest;
  final int count;
  final VoidCallback onTap;

  const _OfflineDownloadCard({
    required this.latest,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox.square(
                    dimension: 58,
                    child: ColoredBox(
                      color: AppColors.elevated,
                      child: Icon(
                        Icons.download_done_rounded,
                        color: AppColors.accent,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Lagu Offline',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '5 GB Max',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        count == 0
                            ? 'Belum ada lagu yang diunduh ke perangkat'
                            : '$count lagu terunduh • Siap diputar tanpa internet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      );
}

class _OfflineTracksPage extends StatelessWidget {
  const _OfflineTracksPage();

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineStorageService.instance,
      builder: (context, _) {
        final offline = OfflineStorageService.instance;
        final player = context.watch<PlayerController>();
        final tracks = offline.downloadedTracks;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Lagu Offline'),
            actions: [
              if (tracks.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: AppColors.card,
                        title: const Text('Hapus semua unduhan?'),
                        content: const Text(
                          'Semua file lagu yang tersimpan di perangkat ini akan dihapus.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('Batal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.error),
                            child: const Text('Hapus'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await offline.clearAll();
                  },
                  child: const Text('Hapus semua'),
                ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: FutureBuilder<int>(
                  future: offline.getTotalStorageUsed(),
                  builder: (context, snapshot) {
                    final used = snapshot.data ?? 0;
                    final ratio = (used / OfflineStorageService.maxQuotaBytes)
                        .clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Penyimpanan Perangkat',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${_formatBytes(used)} / 5.0 GB',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 6,
                                backgroundColor: AppColors.elevated,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.accent),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mode offline terisolasi di perangkat ini. Lagu dapat diputar tanpa internet.',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (tracks.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: FilledButton.icon(
                      onPressed: () {
                        final shuffled = List<Track>.from(tracks)..shuffle();
                        player.playTrack(shuffled.first, newQueue: shuffled);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.accentInk,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      label: const Text('Putar Acak Lagu Offline'),
                    ),
                  ),
                ),
              if (tracks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 54, color: AppColors.textMuted),
                          const SizedBox(height: 14),
                          const Text(
                            'Belum ada lagu offline',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Buka lagu apa saja dan ketuk tombol "Unduh" untuk menyimpannya ke perangkat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = tracks[index];
                        final localArt = offline.getLocalArtworkPath(track.id);
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: SizedBox.square(
                              dimension: 48,
                              child: localArt != null
                                  ? Image.file(File(localArt), fit: BoxFit.cover)
                                  : (track.artworkUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: track.artworkUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : ColoredBox(
                                          color: AppColors.card,
                                          child: const Icon(Icons.music_note_rounded),
                                        )),
                            ),
                          ),
                          title: Text(
                            track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            track.displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => player.playTrack(track, newQueue: tracks),
                          trailing: IconButton(
                            tooltip: 'Hapus dari offline',
                            onPressed: () => offline.deleteTrack(track.id),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.textMuted,
                              size: 20,
                            ),
                          ),
                        );
                      },
                      childCount: tracks.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ListeningHistoryCard extends StatelessWidget {
  final Track? latest;
  final int count;
  final VoidCallback onTap;

  const _ListeningHistoryCard({
    required this.latest,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox.square(
                    dimension: 58,
                    child: latest?.artworkUrl == null
                        ? ColoredBox(
                            color: AppColors.elevated,
                            child: Icon(
                              Icons.history_rounded,
                              color: AppColors.accent,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: latest!.artworkUrl!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Baru didengarkan',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        count == 0
                            ? 'Lagu yang kamu putar akan muncul di sini'
                            : '$count lagu • Terakhir: ${latest!.displayTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      );
}

class _ListeningHistoryPage extends StatelessWidget {
  const _ListeningHistoryPage();

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ListeningHistoryController>();
    final player = context.watch<PlayerController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Baru didengarkan'),
        actions: [
          if (history.items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: AppColors.card,
                    title: const Text('Hapus riwayat putar?'),
                    content: const Text(
                      'Daftar lagu yang pernah diputar di perangkat ini akan dikosongkan.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Batal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await history.clear();
              },
              child: const Text('Hapus semua'),
            ),
        ],
      ),
      body: !history.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : history.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Belum ada lagu yang diputar. Pilih lagu dulu, nanti muncul di sini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: history.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final track = history.items[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: SizedBox.square(
                          dimension: 48,
                          child: track.artworkUrl == null
                              ? ColoredBox(
                                  color: AppColors.card,
                                  child: const Icon(Icons.music_note_rounded),
                                )
                              : CachedNetworkImage(
                                  imageUrl: track.artworkUrl!,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      title: Text(
                        track.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        track.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => player.playTrack(track, newQueue: [track]),
                      trailing: IconButton(
                        tooltip: 'Hapus dari riwayat',
                        onPressed: () => history.remove(track.id),
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.textMuted,
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback onDelete;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final artwork =
        playlist.tracks.isEmpty ? null : playlist.tracks.first.artworkUrl;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox.square(
                  dimension: 58,
                  child: artwork == null
                      ? ColoredBox(
                          color: AppColors.elevated,
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: AppColors.textMuted,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: artwork, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${playlist.tracks.length} lagu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onPlay != null)
                IconButton(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              PopupMenuButton<String>(
                tooltip: 'Opsi playlist',
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Hapus playlist'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyLibrary({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 110),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              Icons.library_music_outlined,
              color: AppColors.accent,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Koleksi masih kosong',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            'Buat playlist lalu simpan lagu favoritmu. Semua data tetap berada di perangkat ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Buat playlist'),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
