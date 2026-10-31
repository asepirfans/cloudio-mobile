import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../theme/app_theme.dart';
import '../widgets/playlist_actions.dart';
import '../widgets/track_tile.dart';

enum SearchEntityType { artist, album }

class SearchEntityPage extends StatefulWidget {
  final SearchEntityType type;
  final String name;
  final String artist;
  final List<Track> initialTracks;
  final VoidCallback onBack;

  const SearchEntityPage({
    super.key,
    required this.type,
    required this.name,
    required this.artist,
    required this.initialTracks,
    required this.onBack,
  });

  @override
  State<SearchEntityPage> createState() => _SearchEntityPageState();
}

class _SearchEntityPageState extends State<SearchEntityPage> {
  List<Track> _tracks = [];
  bool _loading = true;
  bool _failed = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _tracks = widget.initialTracks;
    unawaited(_loadTracks());
  }

  Future<void> _loadTracks() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final tracks = widget.type == SearchEntityType.artist
          ? await MusicService.instance.artistTracks(
              widget.name,
              initial: widget.initialTracks,
            )
          : await MusicService.instance.albumTracks(
              widget.name,
              widget.artist,
              initial: widget.initialTracks,
            );
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _play({bool shuffled = false}) {
    if (_tracks.isEmpty) return;
    final queue = [..._tracks];
    if (shuffled) queue.shuffle();
    unawaited(context.read<PlayerController>().playTrack(
          queue.first,
          newQueue: queue,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final isArtist = widget.type == SearchEntityType.artist;
    final player = context.watch<PlayerController>();
    final artwork = _tracks.firstOrNull?.artworkUrl ??
        widget.initialTracks.firstOrNull?.artworkUrl;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali ke pencarian',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: widget.onBack,
        ),
        title: Text(isArtist ? 'Artis' : 'Album'),
        titleTextStyle: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTracks,
        color: AppColors.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: isArtist ? 1.8 : 1.45,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: AppColors.elevated,
                        child: artwork == null
                            ? Icon(Icons.music_note_rounded,
                                size: 64, color: AppColors.accent)
                            : CachedNetworkImage(
                                imageUrl: artwork,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.music_note_rounded,
                                  size: 64,
                                  color: AppColors.accent,
                                ),
                              ),
                      ),
                      if (isArtist)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xB30E1A2B)],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                widget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 31,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                isArtist
                    ? '${_tracks.length} lagu ditemukan'
                    : '${widget.artist} · ${_tracks.length} lagu ditemukan',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _tracks.isEmpty ? null : () => _play(),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Putar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.accentInk,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _tracks.isEmpty
                        ? null
                        : () => _play(shuffled: true),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Acak'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Text(
                isArtist ? 'Lagu dari artis ini' : 'Lagu dalam album',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Belum bisa memperbarui daftar lagu. Tarik ke bawah untuk mencoba lagi.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            if (!_loading && _tracks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Belum ada lagu dengan metadata yang cocok.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            for (final track in (isArtist && !_showAll
                ? _tracks.take(3)
                : _tracks))
              TrackTile(
                track: track,
                isCurrent: player.currentTrack?.id == track.id,
                isPlaying: player.isPlaying,
                onTap: () => unawaited(player.playTrack(
                  track,
                  newQueue: _tracks,
                )),
                onMore: () => PlaylistActions.showTrackMenu(context, track),
              ),
            if (isArtist && _tracks.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextButton.icon(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  icon: Icon(_showAll
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded),
                  label: Text(_showAll
                      ? 'Tampilkan lebih sedikit'
                      : 'Lihat semua ${_tracks.length} lagu'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
