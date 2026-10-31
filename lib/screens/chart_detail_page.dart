import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../models/track.dart';
import '../models/trending_chart.dart';
import '../services/music_service.dart';
import '../theme/app_theme.dart';
import '../widgets/playlist_actions.dart';

class ChartDetailPage extends StatefulWidget {
  final TrendingChart chart;

  const ChartDetailPage({super.key, required this.chart});

  @override
  State<ChartDetailPage> createState() => _ChartDetailPageState();
}

class _ChartDetailPageState extends State<ChartDetailPage> {
  List<Track> _tracks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tracks = widget.chart.cachedTracks;
    if (_tracks.length >= 20) {
      _isLoading = false;
    } else {
      unawaited(_loadTracks(forceRefresh: true));
    }
  }

  Future<void> _loadTracks({bool forceRefresh = false}) async {
    if (_tracks.length < 20) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final results = await MusicService.instance.getChartTracks(
        widget.chart,
        limit: 50,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _tracks = results;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat tangga lagu.';
        _isLoading = false;
      });
    }
  }

  void _playAll({bool shuffled = false}) {
    if (_tracks.isEmpty) return;
    final queue = [..._tracks];
    if (shuffled) queue.shuffle();
    context.read<PlayerController>().playTrack(queue.first, newQueue: queue);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => _loadTracks(forceRefresh: true),
        color: AppColors.accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: AppColors.background,
              leading: IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Dynamic Chart Gradient
                    DecoratedBox(
                      decoration: BoxDecoration(gradient: widget.chart.gradient),
                    ),
                    // Ambient dark gradient fade to background
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black38,
                            AppColors.background,
                          ],
                          stops: const [0.0, 0.65, 1.0],
                        ),
                      ),
                    ),
                    // Header Content
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(widget.chart.icon,
                                    size: 14, color: Colors.white),
                                const SizedBox(width: 5),
                                Text(
                                  widget.chart.badgeText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.chart.title,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.chart.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary.withOpacity(0.8),
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _tracks.isEmpty
                                ? 'Memuat peringkat...'
                                : '${_tracks.length} lagu populer teratas',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Action Buttons Row (Play All & Shuffle)
            if (_tracks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _playAll(shuffled: false),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 24),
                          label: const Text(
                            'Putar Semua',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _playAll(shuffled: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: BorderSide(color: AppColors.borderSubtle),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        label: const Text(
                          'Acak',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Loading State
            if (_isLoading && _tracks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            // Error State
            else if (_error != null && _tracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: AppColors.textMuted, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style:
                              TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loadTracks,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              )
            // Ranked Song List
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = _tracks[index];
                      final isCurrent = player.currentTrack?.id == track.id;
                      final rank = index + 1;

                      return _RankedTrackTile(
                        rank: rank,
                        track: track,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && player.isPlaying,
                        onTap: () {
                          player.playTrack(track, newQueue: _tracks);
                        },
                        onMore: () {
                          PlaylistActions.showTrackMenu(context, track);
                        },
                      );
                    },
                    childCount: _tracks.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankedTrackTile extends StatelessWidget {
  final int rank;
  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _RankedTrackTile({
    required this.rank,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onMore,
  });

  Color _rankColor() {
    if (rank == 1) return const Color(0xFFFFD700); // Gold
    if (rank == 2) return const Color(0xFFC0C0C0); // Silver
    if (rank == 3) return const Color(0xFFCD7F32); // Bronze
    return AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final rankColor = _rankColor();

    return Material(
      color: isCurrent
          ? AppColors.card.withOpacity(0.7)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Rank badge
              SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      color: rank <= 3 ? rankColor : AppColors.textSecondary,
                      fontSize: rank <= 3 ? 17 : 14,
                      fontWeight:
                          rank <= 3 ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Album artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 50,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      track.artworkUrl == null
                          ? ColoredBox(
                              color: AppColors.elevated,
                              child: Icon(Icons.music_note_rounded,
                                  color: AppColors.textMuted),
                            )
                          : CachedNetworkImage(
                              imageUrl: track.artworkUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => ColoredBox(
                                color: AppColors.elevated,
                                child: Icon(Icons.music_note_rounded,
                                    color: AppColors.textMuted),
                              ),
                            ),
                      if (isCurrent)
                        ColoredBox(
                          color: Colors.black54,
                          child: Icon(
                            isPlaying
                                ? Icons.graphic_eq_rounded
                                : Icons.pause_rounded,
                            color: AppColors.accent,
                            size: 24,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Track Title & Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? AppColors.accentOf(context)
                            : AppColors.textPrimaryOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // More options
              IconButton(
                icon: Icon(Icons.more_vert_rounded,
                    color: AppColors.textMuted, size: 20),
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
