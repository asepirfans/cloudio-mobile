import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/player_controller.dart';
import '../controllers/listening_history_controller.dart';
import '../controllers/playlist_controller.dart';
import '../controllers/theme_controller.dart';
import '../models/track.dart';
import '../models/trending_chart.dart';
import '../services/music_service.dart';
import '../theme/app_theme.dart';
import '../widgets/playlist_actions.dart';
import '../widgets/section_header.dart';
import '../widgets/theme_selection_sheet.dart';
import '../widgets/track_tile.dart';
import 'chart_detail_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialFeed});

  final HomeFeed? initialFeed;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MusicService _musicService = MusicService.instance;
  final List<TrendingChart> _trendingCharts = TrendingChart.getDefaultCharts();
  List<Track> _topIndonesiaTracks = [];
  String _selectedCategory = 'Semua';
  bool _isLoading = true;
  String? _errorMessage;
  List<Track> _forYou = [];
  List<HomeSection> _sections = [];
  PlaylistController? _playlistController;
  ListeningHistoryController? _historyController;
  Timer? _preferenceDebounce;

  @override
  void initState() {
    super.initState();
    final feed = widget.initialFeed;
    if (feed != null) {
      _forYou = feed.forYou;
      _sections = feed.sections;
      _isLoading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFeed());
    }
  }

  Future<void> _loadTrendingPreview() async {
    try {
      final tracks =
          await _musicService.getChartTracks(_trendingCharts.first, limit: 50);
      if (!mounted) return;
      setState(() {
        _topIndonesiaTracks = tracks.take(5).toList();
      });
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<PlaylistController>();
    if (!identical(_playlistController, controller)) {
      _playlistController?.removeListener(_onPreferencesChanged);
      _playlistController = controller..addListener(_onPreferencesChanged);
    }
    final history = context.read<ListeningHistoryController>();
    if (!identical(_historyController, history)) {
      _historyController?.removeListener(_onPreferencesChanged);
      _historyController = history..addListener(_onPreferencesChanged);
    }
  }

  void _onPreferencesChanged() {
    if (_isLoading || widget.initialFeed != null) return;
    _preferenceDebounce?.cancel();
    _preferenceDebounce = Timer(const Duration(milliseconds: 900), _loadFeed);
  }

  @override
  void dispose() {
    _preferenceDebounce?.cancel();
    _playlistController?.removeListener(_onPreferencesChanged);
    _historyController?.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  Future<void> _loadFeed() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    unawaited(_loadTrendingPreview());

    final playlists = context.read<PlaylistController>();
    final history = context.read<ListeningHistoryController>();
    await Future.wait([playlists.ensureLoaded(), history.ensureLoaded()]);
    final artistCounts = <String, int>{};
    final savedTracks = <Track>[];
    final savedIds = <String>{};
    for (final playlist in playlists.playlists) {
      for (final track in playlist.tracks) {
        if (savedIds.add(track.id)) savedTracks.add(track);
        artistCounts.update(
          track.displayArtist,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final favoriteArtists = artistCounts.keys.toList()
      ..sort((a, b) => artistCounts[b]!.compareTo(artistCounts[a]!));

    try {
      final feed = await _musicService.getHomeFeed(
        favoriteArtists: favoriteArtists,
        savedTracks: savedTracks,
        recentlyPlayed: history.items,
        playlistNames: playlists.playlists
            .where((playlist) => playlist.tracks.isNotEmpty)
            .map((playlist) => playlist.name)
            .toList(),
      );
      if (!mounted) return;
      final isEmpty = feed.forYou.isEmpty && feed.sections.isEmpty;
      setState(() {
        _forYou = feed.forYou;
        _sections = feed.sections;
        if (_selectedCategory != 'Semua' &&
            _selectedCategory != 'Trending' &&
            !(_selectedCategory == 'Untukmu' && _forYou.isNotEmpty) &&
            !_sections
                .any((section) => section.category == _selectedCategory)) {
          _selectedCategory = 'Semua';
        }
        _errorMessage = isEmpty
            ? 'Cloudio belum dapat memuat musik. Tarik layar untuk mencoba lagi.'
            : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat rekomendasi Cloudio.';
        _isLoading = false;
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat pagi';
    if (hour < 15) return 'Selamat siang';
    if (hour < 19) return 'Selamat sore';
    return 'Selamat malam';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final topPadding = MediaQuery.paddingOf(context).top;
    final hasFeed = _forYou.isNotEmpty || _sections.isNotEmpty;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFeed,
        color: AppColors.accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HomeHeaderDelegate(
                topPadding: topPadding,
                textScale: MediaQuery.textScalerOf(context).scale(1),
                greeting: _getGreeting(),
                selectedCategory: _selectedCategory,
                categories: {
                  'Semua',
                  'Trending',
                  if (_forYou.isNotEmpty) 'Untukmu',
                  ..._sections.map((section) => section.category),
                }.toList(),
                onCategorySelected: (category) {
                  setState(() => _selectedCategory = category);
                },
              ),
            ),
            if (_isLoading && !hasFeed)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null && !hasFeed)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _HomeError(
                  message: _errorMessage!,
                  onRetry: _loadFeed,
                ),
              )
            else ...[
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_errorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(children: [
                      Expanded(
                          child: Text('Rekomendasi belum diperbarui.',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12))),
                      TextButton(
                          onPressed: _loadFeed, child: const Text('Coba lagi')),
                    ]),
                  ),
                ),
              if ((_selectedCategory == 'Semua' ||
                      _selectedCategory == 'Untukmu') &&
                  _forYou.isNotEmpty)
                SliverToBoxAdapter(
                  child: _FeaturedTrack(
                    track: _forYou.first,
                    onTap: () =>
                        player.playTrack(_forYou.first, newQueue: _forYou),
                  ),
                ),
              if (_selectedCategory == 'Semua' ||
                  _selectedCategory == 'Trending') ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Tangga Lagu & Trending',
                    subtitle: 'Paling banyak didengar saat ini',
                  ),
                ),
                _trendingChartsSection(),
                _trendingPreviewSection(player),
              ],
              if (_selectedCategory == 'Trending') ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Koleksi Tangga Lagu',
                    subtitle: 'Eksplorasi tangga lagu berdasarkan kategori',
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final chart = _trendingCharts[index];
                        return _TrendingCategoryBanner(
                          chart: chart,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChartDetailPage(chart: chart),
                            ),
                          ),
                        );
                      },
                      childCount: _trendingCharts.length,
                    ),
                  ),
                ),
              ],
              if ((_selectedCategory == 'Semua' ||
                      _selectedCategory == 'Untukmu') &&
                  _forYou.isNotEmpty) ...[
                if (_forYou.length > 1) ...[
                  const SliverToBoxAdapter(
                      child: SectionHeader(
                    title: 'Pilihan untukmu',
                    subtitle: 'Pilihan dari musik yang kamu suka',
                  )),
                  _horizontalSection(_forYou.skip(1).toList(), player),
                ],
                if (context
                    .watch<ListeningHistoryController>()
                    .items
                    .isNotEmpty) ...[
                  const SliverToBoxAdapter(
                      child: SectionHeader(title: 'Putar lagi')),
                  SliverToBoxAdapter(
                      child: Column(
                    children: context
                        .read<ListeningHistoryController>()
                        .items
                        .take(3)
                        .map((track) => TrackTile(
                              track: track,
                              isCurrent: player.currentTrack?.id == track.id,
                              isPlaying: player.isPlaying,
                              onTap: () => player.playTrack(track,
                                  newQueue: context
                                      .read<ListeningHistoryController>()
                                      .items),
                              onMore: () =>
                                  PlaylistActions.showTrackMenu(context, track),
                            ))
                        .toList(),
                  )),
                ],
              ],
              for (final section in _sections)
                if (_selectedCategory == 'Semua' ||
                    _selectedCategory == section.category) ...[
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: section.title,
                      subtitle: section.subtitle,
                    ),
                  ),
                  _horizontalSection(section.tracks, player),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _horizontalSection(
    List<Track> tracks,
    PlayerController player,
  ) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 224 +
            (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 2) * 70,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: tracks.length,
          itemBuilder: (context, index) => _TrackCard(
            track: tracks[index],
            isCurrent: player.currentTrack?.id == tracks[index].id,
            isPlaying: player.isPlaying,
            onTap: () => player.playTrack(tracks[index], newQueue: tracks),
            onSave: () => PlaylistActions.showTrackMenu(
              context,
              tracks[index],
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _trendingChartsSection() {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 164.0 + (textScale - 1.0).clamp(0.0, 2.0) * 80.0;
    return SliverToBoxAdapter(
      child: SizedBox(
        height: cardHeight,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: _trendingCharts.length,
          itemBuilder: (context, index) {
            final chart = _trendingCharts[index];
            return _TrendingChartCard(
              chart: chart,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChartDetailPage(chart: chart),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _trendingPreviewSection(PlayerController player) {
    if (_topIndonesiaTracks.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paling Populer Hari Ini',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '5 besar tangga lagu Indonesia',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ChartDetailPage(chart: _trendingCharts.first),
                        ),
                      );
                    },
                    icon: const Text(
                      'Lihat Semua',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    label:
                        const Icon(Icons.arrow_forward_ios_rounded, size: 11),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (int i = 0; i < _topIndonesiaTracks.length && i < 5; i++)
                    _RankedMiniTile(
                      rank: i + 1,
                      track: _topIndonesiaTracks[i],
                      isCurrent:
                          player.currentTrack?.id == _topIndonesiaTracks[i].id,
                      isPlaying: player.isPlaying,
                      onTap: () => player.playTrack(
                        _topIndonesiaTracks[i],
                        newQueue: _topIndonesiaTracks,
                      ),
                      onMore: () => PlaylistActions.showTrackMenu(
                        context,
                        _topIndonesiaTracks[i],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<String> categories;
  final double topPadding;
  final double textScale;
  final String greeting;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  const _HomeHeaderDelegate(
      {required this.topPadding,
      required this.textScale,
      required this.greeting,
      required this.selectedCategory,
      required this.categories,
      required this.onCategorySelected});

  @override
  double get minExtent =>
      topPadding + 108 + (textScale > 1 ? (textScale - 1) * 70 : 0);
  @override
  double get maxExtent => minExtent;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: EdgeInsets.only(top: topPadding + 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      greeting,
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.9,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: ThemeController.instance,
                    builder: (context, _) {
                      final themeCtrl = ThemeController.instance;
                      return InkWell(
                        onTap: () => ThemeSelectionSheet.show(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context)
                                  .dividerColor
                                  .withOpacity(0.15),
                            ),
                          ),
                          child: Icon(
                            themeCtrl.modeIcon,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 22),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = category == selectedCategory;
                    return InkWell(
                        onTap: () => onCategorySelected(category),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: selected
                                          ? AppColors.accentOf(context)
                                          : Colors.transparent,
                                      width: 2))),
                          child: Text(category,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: selected
                                      ? AppColors.accentOf(context)
                                      : AppColors.textSecondaryOf(context),
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                        ));
                  },
                )),
          ]),
        ));
  }

  @override
  bool shouldRebuild(covariant _HomeHeaderDelegate oldDelegate) =>
      oldDelegate.greeting != greeting ||
      oldDelegate.selectedCategory != selectedCategory ||
      oldDelegate.categories.join('|') != categories.join('|') ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.textScale != textScale;
}

class _FeaturedTrack extends StatelessWidget {
  const _FeaturedTrack({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: isLight
              ? const LinearGradient(
                  colors: [Color(0xFFE0F2FE), Color(0xFFF1F5F9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isLight ? null : AppColors.accent,
          border: isLight
              ? Border.all(color: const Color(0xFFBAE6FD).withOpacity(0.8), width: 1.2)
              : null,
          boxShadow: [
            BoxShadow(
              color: isLight
                  ? const Color(0xFF0284C7).withOpacity(0.08)
                  : AppColors.accent.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isLight
                                  ? Colors.white.withOpacity(0.9)
                                  : AppColors.accentInk.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: isLight
                                  ? Border.all(color: const Color(0xFF0284C7).withOpacity(0.2))
                                  : null,
                            ),
                            child: Text(
                              'Mulai dari sini',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isLight ? const Color(0xFF0369A1) : AppColors.accentInk,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          track.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.6,
                            color: isLight ? const Color(0xFF0F172A) : AppColors.accentInk,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isLight ? const Color(0xFF475569) : AppColors.accentInk.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isLight ? const Color(0xFF0284C7) : AppColors.accentInk,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: (isLight ? const Color(0xFF0284C7) : AppColors.accentInk)
                                      .withOpacity(0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                  color: isLight ? Colors.white : AppColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Putar sekarang',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isLight ? Colors.white : AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox.square(
                      dimension: MediaQuery.sizeOf(context).width < 360 ? 92 : 124,
                      child: track.artworkUrl == null
                          ? ColoredBox(
                              color: isLight ? const Color(0xFFE2E8F0) : AppColors.accentInk,
                              child: Icon(
                                Icons.album_outlined,
                                size: 48,
                                color: isLight ? const Color(0xFF64748B) : AppColors.accent,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: track.artworkUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => ColoredBox(
                                color: isLight ? const Color(0xFFF1F5F9) : AppColors.card,
                                child: const Icon(Icons.album_outlined),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onSave;
  const _TrackCard(
      {required this.track,
      required this.isCurrent,
      required this.isPlaying,
      required this.onTap,
      required this.onSave});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 154,
        child: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            onLongPress: onSave,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.square(
                    dimension: 140,
                    child: Stack(fit: StackFit.expand, children: [
                      track.artworkUrl == null
                          ? ColoredBox(
                              color: AppColors.card,
                              child: Icon(Icons.album_outlined,
                                  color: AppColors.textMuted, size: 34))
                          : CachedNetworkImage(
                              imageUrl: track.artworkUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  ColoredBox(color: AppColors.card)),
                      if (isCurrent)
                        ColoredBox(
                            color: Colors.black45,
                            child: Icon(
                                isPlaying
                                    ? Icons.graphic_eq_rounded
                                    : Icons.pause_rounded,
                                color: AppColors.accent,
                                size: 30)),
                    ]),
                  )),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: Text(track.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isCurrent
                                ? AppColors.accentOf(context)
                                : AppColors.textPrimaryOf(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w600))),
                SizedBox(
                    width: 40,
                    height: 44,
                    child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Opsi lagu',
                        iconSize: 18,
                        onPressed: onSave,
                        icon: Icon(Icons.more_horiz_rounded,
                            color: AppColors.textMutedOf(context)))),
              ]),
              Text(track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textSecondaryOf(context), fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _HomeError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _HomeError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: AppColors.textMuted,
            size: 34,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class _TrendingChartCard extends StatelessWidget {
  final TrendingChart chart;
  final VoidCallback onTap;

  const _TrendingChartCard({
    required this.chart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardWidth = 240.0 + (textScale - 1.0).clamp(0.0, 2.0) * 40.0;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        gradient: chart.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: chart.gradient.colors.first.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          chart.badgeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(chart.icon,
                        color: Colors.white.withOpacity(0.9), size: 20),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        chart.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        chart.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Text(
                      'Lihat 50 Lagu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankedMiniTile extends StatelessWidget {
  final int rank;
  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _RankedMiniTile({
    required this.rank,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onMore,
  });

  Color _rankColor() {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final rankColor = _rankColor();

    return Material(
      color: isCurrent ? AppColors.card.withOpacity(0.6) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Center(
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      color: rankColor,
                      fontSize: rank <= 3 ? 16 : 13,
                      fontWeight:
                          rank <= 3 ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 44,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      track.artworkUrl == null
                          ? ColoredBox(
                              color: AppColors.elevated,
                              child: Icon(Icons.music_note_rounded,
                                  color: AppColors.textMuted, size: 20),
                            )
                          : CachedNetworkImage(
                              imageUrl: track.artworkUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => ColoredBox(
                                color: AppColors.elevated,
                                child: Icon(Icons.music_note_rounded,
                                    color: AppColors.textMuted, size: 20),
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
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondaryOf(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert_rounded,
                    color: AppColors.textMuted, size: 18),
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingCategoryBanner extends StatelessWidget {
  final TrendingChart chart;
  final VoidCallback onTap;

  const _TrendingCategoryBanner({required this.chart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: chart.gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: chart.gradient.colors.first.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(chart.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          chart.badgeText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chart.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        chart.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
