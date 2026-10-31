import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../services/tiktok_song_service.dart';
import '../services/social_song_service.dart';
import '../services/tiktok_sound_service.dart';
import '../services/instagram_song_service.dart';
import '../services/music_recognition_service.dart';
import '../widgets/music_recognition_sheet.dart';
import '../services/tiktok_music_matcher.dart';
import '../controllers/player_controller.dart';
import '../controllers/search_history_controller.dart';
import '../controllers/playlist_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';
import '../widgets/playlist_actions.dart';
import 'search_entity_page.dart';

class SearchScreen extends StatefulWidget {
  final bool isActive;
  final List<String>? initialSuggestions;
  final TikTokSoundService? soundService;
  final Future<List<Track>> Function(String)? karaokeSearch;

  const SearchScreen(
      {super.key,
      this.isActive = true,
      this.initialSuggestions,
      this.soundService,
      this.karaokeSearch});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MusicService _musicService = MusicService.instance;
  final SocialSongService _social = SocialSongService();
  late final TikTokSoundService _tiktokSounds =
      widget.soundService ?? TikTokSoundService();
  bool _showingTikTokSound = false;
  late MusicRecognitionService _recognition =
      MusicRecognitionService(posts: _social);
  bool _detectedFromAudio = false;
  String? _searchError;
  String? _detectedSong;
  bool _songIsHint = false;
  bool _readingSocialLink = false;

  Timer? _debounceTimer;
  bool _isLoading = false;
  List<Track> _searchResults = [];
  String _searchedQuery = '';
  int _searchVersion = 0;
  String _filter = 'Semua';
  bool _karaokeMode = false;
  SearchEntityType? _entityType;
  String? _entityName;
  String? _entityArtist;
  List<Track> _entityInitialTracks = [];

  List<String> _quickTags = [];
  bool _loadingSuggestions = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialSuggestions != null) {
      _quickTags = widget.initialSuggestions!;
      _loadingSuggestions = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestions());
    }
  }

  Future<void> _loadSuggestions() async {
    final playlists = context.read<PlaylistController>();
    await playlists.ensureLoaded();
    final savedArtists = playlists.playlists
        .expand((playlist) => playlist.tracks)
        .map((track) => track.displayArtist)
        .toSet()
        .toList();
    try {
      final tags = await _musicService.getSearchSuggestions(
        savedArtists: savedArtists,
      );
      if (!mounted) return;
      setState(() {
        _quickTags = tags;
        _loadingSuggestions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quickTags = savedArtists.take(8).toList();
        _loadingSuggestions = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    // Invalidate during debounce so an old request cannot replace new input.
    _searchVersion++;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchedQuery = '';
        _isLoading = false;
        _searchError = null;
        _detectedSong = null;
        _readingSocialLink = false;
      });
      return;
    }

    setState(() {});

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query,
      {RecognizedMusic? recognized, bool findFullSong = false}) async {
    _debounceTimer?.cancel();
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;
    if (InstagramSongService.extractLink(cleanQuery) != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Link Instagram tidak didukung karena proteksi login Instagram. Gunakan link YouTube atau TikTok, atau fitur Kenali Lagu.'),
      ));
      return;
    }
    final requestVersion = ++_searchVersion;
    _recognition.close();
    _social.clearMediaCache();
    _recognition = MusicRecognitionService(posts: _social);
    final recognition = _recognition;
    setState(() {
      _isLoading = true;
      _searchedQuery = cleanQuery;
      _filter = 'Semua';
      _searchResults = [];
      _searchError = null;
      _detectedSong = null;
      _showingTikTokSound = false;
      _songIsHint = false;
      _detectedFromAudio = recognized != null;
      _readingSocialLink = SocialSongService.extractLink(cleanQuery) != null;
      _filter = _readingSocialLink || recognized != null || _karaokeMode
          ? 'Lagu'
          : 'Semua';
    });

    try {
      List<Track> results;
      if (SocialSongService.isYouTubeLink(cleanQuery)) {
        final track = await _musicService.resolveYouTubeLink(cleanQuery);
        if (!mounted || requestVersion != _searchVersion) return;
        if (track != null) {
          setState(() {
            _searchResults = [track];
            _showingTikTokSound = false;
            _songIsHint = false;
            _detectedSong = '${track.displayTitle} - ${track.displayArtist}';
            _readingSocialLink = true;
            _isLoading = false;
          });
          return;
        }
      }
      if (TikTokSongService.extractLink(cleanQuery) != null && !findFullSong) {
        final sound = await _tiktokSounds.resolve(cleanQuery);
        if (!mounted || requestVersion != _searchVersion) return;
        setState(() {
          _searchResults = [sound.track];
          _showingTikTokSound = true;
          _detectedSong = sound.track.title;
          _isLoading = false;
        });
        return;
      }
      if (_readingSocialLink || recognized != null) {
        TikTokSong song;
        RecognizedMusic? acoustic = recognized;
        if (acoustic == null) {
          try {
            acoustic = await recognition
                .recognizeSocialLink(cleanQuery)
                .timeout(const Duration(seconds: 45));
          } catch (_) {
            recognition.close();
          }
        }
        if (!mounted || requestVersion != _searchVersion) return;
        if (acoustic != null) {
          song = TikTokSong(acoustic.title, artist: acoustic.artist);
        } else {
          song = await _social.resolveSong(cleanQuery);
        }
        if (!mounted || requestVersion != _searchVersion) return;
        setState(() {
          _detectedSong = song.query;
          _songIsHint = song.isHint;
          _detectedFromAudio = acoustic != null;
        });
        results = await const TikTokMusicMatcher().search(
          song,
          (query) => _musicService.search(query),
          isCurrent: () => mounted && requestVersion == _searchVersion,
        );
      } else {
        results = _karaokeMode
            ? await (widget.karaokeSearch?.call(cleanQuery) ??
                _musicService.searchKaraoke(cleanQuery))
            : await _musicService.search(cleanQuery);
      }
      if (mounted && requestVersion == _searchVersion) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (!mounted || requestVersion != _searchVersion) return;
      setState(() {
        _searchError = error is TikTokSongException
            ? error.message
            : 'Pencarian gagal. Periksa koneksi lalu coba lagi.';
        _isLoading = false;
      });
    }
  }

  void _selectSearchMode(bool karaoke) {
    if (_karaokeMode == karaoke) return;
    _debounceTimer?.cancel();
    ++_searchVersion;
    _recognition.close();
    setState(() {
      _karaokeMode = karaoke;
      _searchResults = [];
      _searchError = null;
      _detectedSong = null;
      _isLoading = false;
    });
    final query = _searchController.text.trim();
    if (SocialSongService.extractLink(query) != null) {
      _searchController.clear();
      setState(() => _searchedQuery = '');
    } else if (query.isNotEmpty) {
      unawaited(_performSearch(query));
    }
  }

  Future<void> _listenForMusic() async {
    _debounceTimer?.cancel();
    ++_searchVersion;
    _recognition.close();
    setState(() => _isLoading = false);
    final match = await MusicRecognitionSheet.show(
        context, context.read<PlayerController>());
    if (!mounted || match == null) return;
    final query = '${match.title} ${match.artist}';
    _searchController.text = query;
    await _performSearch(query, recognized: match);
  }

  Future<void> _pasteSocialLink() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = clipboard?.text ?? '';
    if (InstagramSongService.extractLink(text) != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Link Instagram tidak didukung karena proteksi login Instagram. Gunakan link YouTube atau TikTok, atau fitur Kenali Lagu.'),
      ));
      return;
    }
    final link = SocialSongService.extractLink(text);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copy link YouTube atau TikTok, lalu tempel di sini.'),
      ));
      return;
    }
    _searchController.text = link.toString();
    await _performSearch(link.toString());
  }

  Future<void> _correctSocialSong() async {
    final query = await showDialog<String>(
      context: context,
      builder: (_) => _TikTokSongEditor(initialQuery: _detectedSong ?? ''),
    );
    if (!mounted || query == null || query.isEmpty) return;
    _searchController.text = query;
    await _performSearch(query);
  }

  void _playWithSmartQueue(Track track, PlayerController player) {
    unawaited(context.read<SearchHistoryController>().add(track));
    unawaited(player.playTrack(track, newQueue: [track]));
  }

  void _openEntity(String name, Track representative, String kind) {
    final isArtist = kind == 'Artis';
    final artist = representative.displayArtist;
    final initial = _searchResults.where((track) {
      if (isArtist) {
        return track.displayArtist.toLowerCase() == name.toLowerCase();
      }
      return track.album?.toLowerCase() == name.toLowerCase() &&
          track.displayArtist.toLowerCase() == artist.toLowerCase();
    }).toList();
    setState(() {
      _entityType = isArtist ? SearchEntityType.artist : SearchEntityType.album;
      _entityName = name;
      _entityArtist = artist;
      _entityInitialTracks = initial;
    });
  }

  void _closeEntity() {
    setState(() {
      _entityType = null;
      _entityName = null;
      _entityArtist = null;
      _entityInitialTracks = [];
    });
  }

  @override
  void dispose() {
    _recognition.close();
    _social.close();
    _tiktokSounds.close();
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_entityType != null) {
      return PopScope(
        canPop: !widget.isActive,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && widget.isActive) _closeEntity();
        },
        child: SearchEntityPage(
          key: ValueKey('$_entityType:$_entityName:$_entityArtist'),
          type: _entityType!,
          name: _entityName!,
          artist: _entityArtist!,
          initialTracks: _entityInitialTracks,
          onBack: _closeEntity,
        ),
      );
    }
    final compactActions = MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(14) > 17;
    final player = context.watch<PlayerController>();
    final history = context.watch<SearchHistoryController>();
    final artists = <String, Track>{};
    final albums = <(String, String), Track>{};
    for (final track in _searchResults) {
      artists.putIfAbsent(track.displayArtist, () => track);
      final album = track.album?.trim();
      if (album != null && album.isNotEmpty) {
        albums.putIfAbsent((album, track.displayArtist), () => track);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari musik'),
        actions: [
          IconButton(
              tooltip: 'Kenali lagu',
              onPressed: _listenForMusic,
              icon: const Icon(Icons.mic_none_rounded)),
          if (compactActions)
            IconButton(
              tooltip: 'Tempel link YouTube atau TikTok',
              onPressed: _pasteSocialLink,
              icon: const Icon(Icons.link_rounded),
            )
          else
            Tooltip(
              message: 'Tempel link YouTube atau TikTok',
              child: TextButton.icon(
                onPressed: _pasteSocialLink,
                icon: const Icon(Icons.link_rounded, size: 19),
                label: const Text('Tempel link'),
              ),
            )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(126),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(children: [
              Container(
                height: 54,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: _performSearch,
                  style: TextStyle(
                      color: AppColors.textPrimaryOf(context), fontSize: 15),
                  decoration: InputDecoration(
                    hintText: compactActions
                        ? (_karaokeMode
                            ? 'Judul lagu atau artis'
                            : 'Lagu, artis, atau link')
                        : (_karaokeMode
                            ? 'Cari versi karaoke lagu…'
                            : 'Lagu, artis, link YouTube / TikTok / IG'),
                    hintStyle: TextStyle(
                        color: AppColors.textMutedOf(context), fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AppColors.textMutedOf(context), size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: AppColors.textSecondaryOf(context),
                                size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Theme(
                data: Theme.of(context).copyWith(
                  splashColor: AppColors.accent.withOpacity(0.16),
                  highlightColor: AppColors.accent.withOpacity(0.12),
                  hoverColor: AppColors.accent.withOpacity(0.08),
                  focusColor: AppColors.accent.withOpacity(0.12),
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                        secondary: AppColors.accent,
                        onSecondary: AppColors.accentInk,
                        secondaryContainer: AppColors.accentDim,
                        onSecondaryContainer: AppColors.accent,
                      ),
                  chipTheme: Theme.of(context).chipTheme.copyWith(
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        pressElevation: 0,
                      ),
                ),
                child: Row(children: [
                  ChoiceChip(
                      label: const Text('Musik'),
                      selected: !_karaokeMode,
                      selectedColor: AppColors.accent,
                      backgroundColor: AppColors.accentDim,
                      checkmarkColor: AppColors.accentInk,
                      side: BorderSide.none,
                      labelStyle: TextStyle(
                          color: !_karaokeMode
                              ? AppColors.accentInk
                              : AppColors.accent),
                      onSelected: (_) => _selectSearchMode(false)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                      label: const Text('Karaoke'),
                      selected: _karaokeMode,
                      selectedColor: AppColors.accent,
                      backgroundColor: AppColors.accentDim,
                      checkmarkColor: AppColors.accentInk,
                      side: BorderSide.none,
                      labelStyle: TextStyle(
                          color: _karaokeMode
                              ? AppColors.accentInk
                              : AppColors.accent),
                      avatar: Icon(Icons.mic_rounded,
                          size: 16,
                          color: _karaokeMode
                              ? AppColors.accentInk
                              : AppColors.accent),
                      onSelected: (_) => _selectSearchMode(true)),
                ]),
              ),
            ]),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
                if (_readingSocialLink) ...[
                  const SizedBox(height: 16),
                  Text(
                      _detectedSong == null
                          ? (SocialSongService.isYouTubeLink(_searchedQuery)
                              ? 'Memuat video YouTube…'
                              : 'Membaca sound TikTok…')
                          : 'Mencari lagu di Cloudio…',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ]),
            )
          : _searchResults.isNotEmpty
              ? ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 28),
                  children: [
                    if (_detectedSong != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _showingTikTokSound
                                    ? 'Sound asli TikTok · Cuplikan'
                                    : (SocialSongService.isYouTubeLink(_searchedQuery)
                                        ? 'Video YouTube · Audio resmi'
                                        : '${_detectedFromAudio ? "Dikenali dari audio" : _songIsHint ? "Petunjuk dari caption" : "Musik ${SocialSongService.platform(_searchedQuery)}"}: $_detectedSong'),
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                                _showingTikTokSound
                                    ? 'Putar audio dari post ini, sesuai durasi aslinya.'
                                    : (SocialSongService.isYouTubeLink(_searchedQuery)
                                        ? 'Audio diambil langsung dari YouTube.'
                                        : 'Kandidat terdekat di urutan pertama.'),
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                            TextButton.icon(
                              onPressed: _showingTikTokSound
                                  ? () => _performSearch(_searchedQuery,
                                      findFullSong: true)
                                  : _correctSocialSong,
                              icon: const Icon(Icons.tune_rounded, size: 16),
                              label: Text(_showingTikTokSound
                                  ? 'Cari lagu lengkap'
                                  : (SocialSongService.isYouTubeLink(_searchedQuery)
                                      ? 'Cari lagu serupa'
                                      : 'Cari versi lain')),
                            ),
                          ],
                        ),
                      ),
                    if (!_showingTikTokSound && !_karaokeMode)
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: albums.isEmpty ? 3 : 4,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final filters = [
                              'Semua',
                              'Lagu',
                              'Artis',
                              if (albums.isNotEmpty) 'Album',
                            ];
                            final filter = filters[index];
                            return ChoiceChip(
                              label: Text(filter),
                              selected: _filter == filter,
                              showCheckmark: false,
                              side: BorderSide.none,
                              selectedColor: AppColors.accent,
                              backgroundColor: AppColors.card,
                              labelStyle: TextStyle(
                                color: _filter == filter
                                    ? AppColors.background
                                    : AppColors.textSecondary,
                                fontSize: 12,
                              ),
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            );
                          },
                        ),
                      ),
                    if (_filter == 'Semua' && artists.isNotEmpty)
                      _resultGroupTitle('Artis'),
                    if (_filter == 'Semua' && artists.isNotEmpty)
                      _entityTile(artists.keys.first, artists.values.first,
                          'Artis', true),
                    if (_filter == 'Artis') ...[
                      _resultGroupTitle('Artis'),
                      for (final entry in artists.entries)
                        _entityTile(entry.key, entry.value, 'Artis', true),
                    ] else if (_filter == 'Album') ...[
                      _resultGroupTitle('Album'),
                      for (final entry in albums.entries)
                        _entityTile(entry.key.$1, entry.value, 'Album', false),
                    ] else ...[
                      _resultGroupTitle(_showingTikTokSound
                          ? 'Sound TikTok'
                          : (SocialSongService.isYouTubeLink(_searchedQuery)
                              ? 'Video YouTube'
                              : (_karaokeMode ? 'Karaoke' : 'Lagu'))),
                      for (final track in _searchResults)
                        TrackTile(
                          track: track,
                          isCurrent: player.currentTrack?.id == track.id,
                          isPlaying: player.isPlaying,
                          onTap: () => _playWithSmartQueue(track, player),
                          onMore: () =>
                              PlaylistActions.showTrackMenu(context, track),
                        ),
                    ],
                  ],
                )
              : SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_searchedQuery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24.0),
                          child: Center(
                            child: Text(
                              _searchError ??
                                  (_detectedSong != null
                                      ? '$_detectedSong belum punya hasil yang cukup cocok. Coba koreksi judul atau versinya.'
                                      : (_karaokeMode
                                          ? 'Versi karaoke belum ditemukan. Coba judul lagu dan artisnya.'
                                          : 'Tidak ada hasil di Cloudio. Coba kata lain atau periksa koneksi.')),
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        ),
                      if (_searchedQuery.isNotEmpty && _readingSocialLink)
                        Wrap(spacing: 8, children: [
                          TextButton.icon(
                            onPressed: () => _performSearch(_searchedQuery),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Coba lagi'),
                          ),
                          if (TikTokSongService.extractLink(_searchedQuery) !=
                              null)
                            TextButton.icon(
                              onPressed: () => _performSearch(_searchedQuery,
                                  findFullSong: true),
                              icon: const Icon(Icons.search_rounded, size: 18),
                              label: const Text('Cari lagu lengkap'),
                            ),
                          TextButton.icon(
                            onPressed: _correctSocialSong,
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('Isi judul lagu'),
                          ),
                        ]),
                      if (_searchedQuery.isEmpty) ...[
                        if (history.items.isNotEmpty) ...[
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Terakhir dicari',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: history.clear,
                                child: const Text(
                                  'Hapus semua',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...history.items.map(
                            (track) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(14),
                                child: ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox.square(
                                      dimension: 42,
                                      child: track.artworkUrl == null
                                          ? ColoredBox(
                                              color: AppColors.elevated,
                                              child: Icon(
                                                Icons.music_note_rounded,
                                                color: AppColors.textMuted,
                                              ),
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    track.displayArtist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Hapus lagu dari riwayat',
                                    onPressed: () => history.remove(track.id),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: AppColors.textMuted,
                                      size: 17,
                                    ),
                                  ),
                                  onTap: () =>
                                      _playWithSmartQueue(track, player),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (_loadingSuggestions || _quickTags.isNotEmpty) ...[
                          Text(
                            'Jelajahi musik',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_loadingSuggestions)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _quickTags.map((tag) {
                              return ActionChip(
                                label: Text(
                                  tag,
                                  style: TextStyle(
                                      color: AppColors.textPrimaryOf(context),
                                      fontSize: 13),
                                ),
                                backgroundColor: Theme.of(context).cardColor,
                                side: BorderSide(
                                    color: Theme.of(context)
                                        .dividerColor
                                        .withOpacity(0.2)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                onPressed: () {
                                  _searchController.text = tag;
                                  _performSearch(tag);
                                },
                              );
                            }).toList(),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _resultGroupTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 7),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      );

  Widget _entityTile(String name, Track track, String kind, bool circular) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(circular ? 28 : 8),
        child: SizedBox.square(
          dimension: 52,
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
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(kind),
      onTap: () {
        _openEntity(name, track, kind);
      },
    );
  }
}

class _TikTokSongEditor extends StatefulWidget {
  const _TikTokSongEditor({required this.initialQuery});
  final String initialQuery;
  @override
  State<_TikTokSongEditor> createState() => _TikTokSongEditorState();
}

class _TikTokSongEditorState extends State<_TikTokSongEditor> {
  late final _editor = TextEditingController(text: widget.initialQuery);
  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _submit() {
    if (_editor.text.trim().isNotEmpty) {
      Navigator.pop(context, _editor.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cari lagu atau versi lain'),
        content: TextField(
          controller: _editor,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Judul + artis, boleh tambah remix / sped up'),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          TextButton(onPressed: _submit, child: const Text('Cari')),
        ],
      );
}
