import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/player_controller.dart';
import '../controllers/theme_controller.dart';
import '../models/track.dart';
import '../services/lyrics_service.dart';
import '../theme/ambient_palette.dart';
import '../theme/app_theme.dart';

class LyricsPage extends StatefulWidget {
  final Track track;
  final LyricsData initialLyrics;

  const LyricsPage({
    super.key,
    required this.track,
    required this.initialLyrics,
  });

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final ScrollController _scrollController = ScrollController();
  late Track _track;
  late Future<LyricsData?> _lyrics;
  bool _autoFollow = true;
  bool _photoMode = false;
  bool _browsing = false;
  Timer? _resumeFollow;
  int _lastActive = -2;
  List<GlobalKey> _lineKeys = [];
  int _offsetMs = 0;
  bool _offsetLoaded = false;

  // Teleprompter (Manual auto-scroll with speed adjustment)
  bool _teleprompterActive = false;
  double _scrollSpeed = 1.0;
  Timer? _teleprompterTimer;
  bool _userDragging = false;

  @override
  void initState() {
    super.initState();
    _track = widget.track;
    _lyrics = Future.value(widget.initialLyrics);
    _loadOffset(initial: widget.initialLyrics);
  }

  Future<void> _loadOffset({LyricsData? initial}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'lyrics_offset_${_track.id}';
      if (prefs.containsKey(key)) {
        final val = prefs.getInt(key) ?? 0;
        if (mounted) {
          setState(() {
            _offsetMs = val;
            _offsetLoaded = true;
          });
        }
        return;
      }
    } catch (_) {}

    final data = initial ?? await _lyrics;
    if (data != null && data.suggestedOffsetMs != 0 && !_offsetLoaded) {
      if (mounted) {
        setState(() {
          _offsetMs = data.suggestedOffsetMs;
          _offsetLoaded = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.watch<PlayerController>().currentTrack;
    if (current == null || current.id == _track.id) return;
    _teleprompterTimer?.cancel();
    _teleprompterActive = false;
    _resumeFollow?.cancel();
    _browsing = false;
    _track = current;
    _lyrics = LyricsService.instance.getLyrics(current);
    _lastActive = -2;
    _lineKeys = [];
    _offsetLoaded = false;
    _offsetMs = 0;
    _loadOffset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _teleprompterTimer?.cancel();
    _resumeFollow?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _setAutoFollow(bool value) {
    _resumeFollow?.cancel();
    _browsing = false;
    if (value) {
      _pauseTeleprompter();
    }
    if (_autoFollow == value) {
      setState(() => _lastActive = -2);
      return;
    }
    setState(() {
      _autoFollow = value;
      _lastActive = -2;
    });
  }

  void _toggleTeleprompter() {
    if (_teleprompterActive) {
      _pauseTeleprompter();
    } else {
      _startTeleprompter();
    }
  }

  void _startTeleprompter() {
    _teleprompterTimer?.cancel();
    _resumeFollow?.cancel();
    setState(() {
      _teleprompterActive = true;
      _autoFollow = false;
    });
    // 60 FPS smooth stepping
    _teleprompterTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_teleprompterActive || _userDragging) return;
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;
      if (current >= maxScroll) {
        _pauseTeleprompter();
        return;
      }
      // Base velocity: ~26 logical pixels per second at 1.0x
      final step = (_scrollSpeed * 26.0) * (16 / 1000.0);
      _scrollController.jumpTo((current + step).clamp(0.0, maxScroll));
    });
  }

  void _pauseTeleprompter() {
    _teleprompterTimer?.cancel();
    _teleprompterTimer = null;
    if (mounted) {
      setState(() {
        _teleprompterActive = false;
      });
    }
  }

  void _setSpeed(double speed) {
    setState(() {
      _scrollSpeed = speed;
    });
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _followLine(int active) {
    if (!_autoFollow || _browsing || active < 0 || active == _lastActive) {
      return;
    }
    _lastActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_autoFollow || _browsing || active >= _lineKeys.length) {
        return;
      }
      final lineContext = _lineKeys[active].currentContext;
      if (lineContext == null) return;
      Scrollable.ensureVisible(
        lineContext,
        alignment: _photoMode ? 0.4 : 0.28,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _formatTime(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    return '${safe.inMinutes}:${(safe.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final isAmoled = ThemeController.instance.isAmoled;

    return ValueListenableBuilder<int>(
      valueListenable: AmbientPalette.revision,
      builder: (context, _, __) {
        final palette = AmbientPalette.of(_track);
        final primaryAccent = palette.accentOf(context);
        final onAccent = palette.onAccentOf(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            decoration: BoxDecoration(
              gradient: AmbientPalette.backgroundGradient(
                context: context,
                track: _track,
                isAmoled: isAmoled,
              ),
            ),
            child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(context, primaryAccent, onAccent),
              Expanded(
                child: FutureBuilder<LyricsData?>(
                  future: _lyrics,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Center(
                        child: CircularProgressIndicator(color: primaryAccent),
                      );
                    }
                    if (snapshot.hasError) {
                      return _emptyState(
                        'Lirik gagal dimuat untuk lagu ini.',
                        primaryAccent: primaryAccent,
                        onRetry: () {
                          LyricsService.instance.clearCachedLyrics(_track.id);
                          setState(() {
                            _lyrics = LyricsService.instance.getLyrics(_track);
                          });
                        },
                      );
                    }
                    final lyrics = snapshot.data;
                    if (lyrics == null || !lyrics.hasLyrics) {
                      return _emptyState(
                        lyrics?.instrumental == true
                            ? 'Lagu instrumental ini tidak punya lirik.'
                            : 'Lirik lagu ini belum tersedia.',
                        primaryAccent: primaryAccent,
                      );
                    }
                    if (!_offsetLoaded && lyrics.suggestedOffsetMs != 0) {
                      _offsetMs = lyrics.suggestedOffsetMs;
                      _offsetLoaded = true;
                    }
                    return Column(
                      children: [
                        if (!_photoMode)
                          _modeSwitch(lyrics.syncedLines.isNotEmpty,
                              primaryAccent, onAccent),
                        Expanded(
                          child: lyrics.syncedLines.isNotEmpty
                              ? _syncedLyrics(lyrics, player, primaryAccent)
                              : _plainLyrics(lyrics),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (_photoMode)
                _photoFooter(primaryAccent)
              else
                _playbackBar(player, primaryAccent, onAccent, palette),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _header(
    BuildContext context,
    Color primaryAccent,
    Color onAccent,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final titleColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subtitleColor =
        isLight ? const Color(0xFF475569) : Colors.white.withOpacity(0.75);
    final chipBackground = isLight
        ? Colors.black.withOpacity(0.05)
        : Colors.white.withOpacity(0.10);
    final iconColor = isLight ? const Color(0xFF0F172A) : Colors.white;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: chipBackground,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: 'Kembali ke lagu',
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 26,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  _track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _teleprompterActive
                  ? const Color(0xFF10B981).withOpacity(0.20)
                  : chipBackground,
              shape: BoxShape.circle,
              border: _teleprompterActive
                  ? Border.all(color: const Color(0xFF10B981), width: 1.5)
                  : null,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Pengaturan auto-scroll',
              onPressed: () =>
                  _openTeleprompterSheet(context, primaryAccent, onAccent),
              icon: _teleprompterActive
                  ? const Icon(
                      Icons.slow_motion_video_rounded,
                      color: Color(0xFF10B981),
                      size: 19,
                    )
                  : Icon(
                      Icons.tune_rounded,
                      color: iconColor,
                      size: 19,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _photoMode
                  ? primaryAccent.withOpacity(0.20)
                  : chipBackground,
              shape: BoxShape.circle,
              border: _photoMode
                  ? Border.all(color: primaryAccent, width: 1.5)
                  : null,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: _photoMode ? 'Tampilkan kontrol' : 'Mode foto',
              onPressed: () => setState(() {
                _photoMode = !_photoMode;
                _lastActive = -2;
              }),
              icon: Icon(
                _photoMode
                    ? Icons.photo_camera_rounded
                    : Icons.photo_camera_outlined,
                color: _photoMode ? primaryAccent : iconColor,
                size: 19,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSwitch(
    bool hasSyncedLyrics,
    Color primaryAccent,
    Color onAccent,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Center(
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.white.withOpacity(0.85)
              : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLight
                ? Colors.black.withOpacity(0.06)
                : Colors.white.withOpacity(0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isLight ? 0.04 : 0.20),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _modeButton(
              label: 'Auto',
              icon: Icons.sync_rounded,
              selected: hasSyncedLyrics && _autoFollow,
              enabled: hasSyncedLyrics,
              accentColor: primaryAccent,
              onAccent: onAccent,
              onTap: () => _setAutoFollow(true),
            ),
            _modeButton(
              label: 'Manual',
              icon: Icons.pan_tool_alt_rounded,
              selected: !hasSyncedLyrics || !_autoFollow,
              enabled: true,
              accentColor: primaryAccent,
              onAccent: onAccent,
              onTap: () => _setAutoFollow(false),
            ),
          ],
        ),
      ),
    );
  }

  void _openTeleprompterSheet(
    BuildContext context,
    Color primaryAccent,
    Color onAccent,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : AppColors.elevated,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isLight
                              ? Colors.black.withOpacity(0.15)
                              : AppColors.textMuted.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(
                          Icons.slow_motion_video_rounded,
                          color: primaryAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pengaturan Auto-Scroll',
                                style: TextStyle(
                                  color: AppColors.textPrimaryOf(context),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Gulir lirik manual otomatis (Teleprompter)',
                                style: TextStyle(
                                  color: AppColors.textSecondaryOf(context),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: AppColors.textSecondaryOf(context)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Material(
                      color: _teleprompterActive
                          ? const Color(0xFF10B981)
                          : primaryAccent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          _toggleTeleprompter();
                          setModalState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _teleprompterActive
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: onAccent,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _teleprompterActive
                                    ? 'Jeda Gulir Otomatis'
                                    : 'Mulai Gulir Otomatis',
                                style: TextStyle(
                                  color: onAccent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Kecepatan Gulir',
                      style: TextStyle(
                        color: AppColors.textSecondaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black.withOpacity(0.06)
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          for (final speed in [0.5, 1.0, 1.5, 2.0])
                            Expanded(
                              child: Material(
                                color: _scrollSpeed == speed
                                    ? primaryAccent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    _setSpeed(speed);
                                    setModalState(() {});
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    child: Center(
                                      child: Text(
                                        '${speed}x',
                                        style: TextStyle(
                                          color: _scrollSpeed == speed
                                              ? onAccent
                                              : AppColors.textPrimaryOf(
                                                  context),
                                          fontSize: 13,
                                          fontWeight: _scrollSpeed == speed
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        _scrollToTop();
                        Navigator.pop(ctx);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimaryOf(context),
                        side: BorderSide(
                          color: isLight
                              ? Colors.black.withOpacity(0.12)
                              : AppColors.borderSubtle,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.first_page_rounded, size: 18),
                      label: const Text('Kembali ke Baris Awal'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required Color accentColor,
    required Color onAccent,
    required VoidCallback onTap,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final unselectedText = isLight
        ? const Color(0xFF334155)
        : Colors.white.withOpacity(0.80);
    final disabledText = isLight
        ? Colors.black.withOpacity(0.25)
        : Colors.white.withOpacity(0.28);

    return Expanded(
      child: Material(
        color: selected ? accentColor : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        elevation: selected ? 1 : 0,
        shadowColor: Colors.black.withOpacity(0.2),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: !enabled
                      ? disabledText
                      : selected
                          ? onAccent
                          : unselectedText,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: !enabled
                        ? disabledText
                        : selected
                            ? onAccent
                            : unselectedText,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _syncedLyrics(
    LyricsData lyrics,
    PlayerController player,
    Color primaryAccent,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;

    if (_lineKeys.length != lyrics.syncedLines.length) {
      _lineKeys = List.generate(lyrics.syncedLines.length, (_) => GlobalKey());
    }
    final active = lyrics.activeLineAt(player.position, offsetMs: _offsetMs);
    _followLine(active);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _userDragging = true;
          _resumeFollow?.cancel();
          _browsing = true;
        } else if (notification is ScrollEndNotification) {
          _userDragging = false;
          if (_browsing) {
            _resumeFollow?.cancel();
            _resumeFollow = Timer(const Duration(milliseconds: 2400), () {
              if (!mounted) return;
              setState(() {
                _browsing = false;
                _lastActive = -2;
              });
            });
          }
        }
        return false;
      },
      child: ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < lyrics.syncedLines.length; index++)
                _buildLyricItem(
                  index: index,
                  active: active,
                  lyrics: lyrics,
                  player: player,
                  primaryAccent: primaryAccent,
                  isLight: isLight,
                  textColor: textColor,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricItem({
    required int index,
    required int active,
    required LyricsData lyrics,
    required PlayerController player,
    required Color primaryAccent,
    required bool isLight,
    required Color textColor,
  }) {
    final isActive = index == active && _autoFollow;
    final isPast = index < active;

    final double fontSize;
    final FontWeight fontWeight;
    final Color lineTextColor;

    if (_autoFollow) {
      if (isActive) {
        fontSize = 28;
        fontWeight = FontWeight.w800;
        lineTextColor = primaryAccent;
      } else {
        fontSize = 22;
        fontWeight = FontWeight.w600;
        lineTextColor = isPast
            ? textColor.withOpacity(0.28)
            : textColor.withOpacity(isLight ? 0.48 : 0.42);
      }
    } else {
      fontSize = 24;
      fontWeight = FontWeight.w600;
      lineTextColor = textColor.withOpacity(isLight ? 0.85 : 0.85);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_autoFollow) return;
        final lineTime = lyrics.syncedLines[index].time;
        final seekTarget = lineTime + Duration(milliseconds: _offsetMs);
        player.seek(seekTarget < Duration.zero ? Duration.zero : seekTarget);
      },
      child: Padding(
        key: _lineKeys[index],
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: isActive ? 14 : 8,
            vertical: isActive ? 10 : 4,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? primaryAccent.withOpacity(isLight ? 0.10 : 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: isActive
                ? Border.all(
                    color: primaryAccent.withOpacity(isLight ? 0.20 : 0.30),
                    width: 1,
                  )
                : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontFamily: 'InstrumentSans',
              color: lineTextColor,
              fontSize: fontSize,
              height: 1.35,
              fontWeight: fontWeight,
              letterSpacing: -0.3,
            ),
            child: Text(lyrics.syncedLines[index].text),
          ),
        ),
      ),
    );
  }

  Widget _plainLyrics(LyricsData lyrics) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _userDragging = true;
        } else if (notification is ScrollEndNotification) {
          _userDragging = false;
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 160),
        child: Text(
          lyrics.plainText!,
          style: TextStyle(
            color: textColor.withOpacity(isLight ? 0.88 : 0.90),
            fontSize: 20,
            height: 1.6,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  Widget _photoFooter(Color primaryAccent) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.white.withOpacity(0.75)
              : AppColors.card.withOpacity(0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isLight
                ? Colors.black.withOpacity(0.08)
                : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(
                dimension: 44,
                child: _track.artworkUrl == null
                    ? ColoredBox(
                        color: isLight
                            ? Colors.black.withOpacity(0.06)
                            : AppColors.elevated,
                        child: Icon(Icons.music_note_rounded,
                            size: 20, color: AppColors.textSecondaryOf(context)),
                      )
                    : CachedNetworkImage(
                        imageUrl: _track.artworkUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: isLight
                              ? Colors.black.withOpacity(0.06)
                              : AppColors.elevated,
                          child: Icon(Icons.music_note_rounded,
                              size: 20,
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _track.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimaryOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _track.displayArtist,
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
          ],
        ),
      ),
    );
  }

  Widget _emptyState(
    String message, {
    Color? primaryAccent,
    VoidCallback? onRetry,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined,
                  color: AppColors.textMutedOf(context), size: 42),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryOf(context)),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: onRetry,
                  style: primaryAccent != null
                      ? TextButton.styleFrom(foregroundColor: primaryAccent)
                      : null,
                  child: const Text('Coba lagi'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _playbackBar(
    PlayerController player,
    Color primaryAccent,
    Color onAccent,
    AmbientPalette palette,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isAmoled = ThemeController.instance.isAmoled;
    final duration = player.duration;
    final maxSeconds =
        duration.inMilliseconds > 0 ? duration.inMilliseconds / 1000.0 : 1.0;
    final currentSeconds =
        (player.position.inMilliseconds / 1000.0).clamp(0.0, maxSeconds);
    final remaining = duration - player.position;

    return Container(
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withOpacity(0.40)
            : (isAmoled
                ? Colors.black.withOpacity(0.60)
                : Colors.black.withOpacity(0.35)),
        border: Border(
          top: BorderSide(
            color: isLight
                ? Colors.black.withOpacity(0.06)
                : Colors.white.withOpacity(0.08),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: primaryAccent,
                  inactiveTrackColor: isLight
                      ? palette.primary.withOpacity(0.16)
                      : Colors.white.withOpacity(0.18),
                  thumbColor: primaryAccent,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 13),
                ),
                child: Slider(
                  value: currentSeconds,
                  max: maxSeconds,
                  onChanged: duration.inMilliseconds > 0
                      ? (value) => player.previewSeek(
                            Duration(milliseconds: (value * 1000).round()),
                          )
                      : null,
                  onChangeEnd: duration.inMilliseconds > 0
                      ? (value) => player.seek(
                            Duration(milliseconds: (value * 1000).round()),
                          )
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(player.position),
                      style: TextStyle(
                        color: AppColors.textSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '-${_formatTime(remaining)}',
                      style: TextStyle(
                        color: AppColors.textSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _controlButton(
                    icon: Icons.shuffle_rounded,
                    tooltip: 'Acak',
                    color: player.isShuffle
                        ? primaryAccent
                        : AppColors.textMutedOf(context),
                    onPressed: player.toggleShuffle,
                  ),
                  _controlButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: 'Sebelumnya',
                    color: AppColors.textPrimaryOf(context),
                    onPressed: player.previous,
                  ),
                  Expanded(
                    child: Center(
                      child: IconButton.filled(
                        tooltip: player.isPlaying ? 'Jeda' : 'Putar',
                        onPressed: player.togglePlayPause,
                        style: IconButton.styleFrom(
                          backgroundColor: primaryAccent,
                          foregroundColor: onAccent,
                          fixedSize: const Size(62, 62),
                        ),
                        icon: player.isBusy
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: onAccent,
                                ),
                              )
                            : Icon(
                                player.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 34,
                              ),
                      ),
                    ),
                  ),
                  _controlButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Berikutnya',
                    color: AppColors.textPrimaryOf(context),
                    onPressed: player.next,
                  ),
                  _controlButton(
                    icon: player.repeatMode == RepeatMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    tooltip: 'Ulangi',
                    color: player.repeatMode == RepeatMode.off
                        ? AppColors.textMutedOf(context)
                        : primaryAccent,
                    onPressed: player.toggleRepeat,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) =>
      Expanded(
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: color ?? AppColors.textPrimary, size: 27),
        ),
      );
}
