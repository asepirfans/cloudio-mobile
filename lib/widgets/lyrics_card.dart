import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/lyrics_service.dart';
import '../theme/app_theme.dart';
import 'lyrics_page.dart';

class LyricsCard extends StatefulWidget {
  final Track track;

  const LyricsCard({super.key, required this.track});

  @override
  State<LyricsCard> createState() => _LyricsCardState();
}

class _LyricsCardState extends State<LyricsCard> {
  late Future<LyricsData?> _lyrics;

  @override
  void initState() {
    super.initState();
    _lyrics = LyricsService.instance.getLyrics(widget.track);
  }

  void _retry() {
    LyricsService.instance.clearCachedLyrics(widget.track.id);
    setState(() {
      _lyrics = LyricsService.instance.getLyrics(widget.track);
    });
  }

  void _openLyrics(LyricsData lyrics) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LyricsPage(track: widget.track, initialLyrics: lyrics),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LyricsData?>(
      future: _lyrics,
      builder: (context, snapshot) {
        final lyrics = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        final available = lyrics?.hasLyrics == true;
        final canRetry = !loading && !available && lyrics?.instrumental != true;
        final subtitle = loading
            ? 'Memuat lirik...'
            : snapshot.hasError
                ? 'Gagal memuat • ketuk untuk coba lagi'
                : available
                    ? lyrics!.syncedLines.isNotEmpty
                        ? 'Sinkron • Auto & Manual'
                        : 'Baca bebas • Manual'
                    : lyrics?.instrumental == true
                        ? 'Lagu instrumental tanpa lirik'
                        : 'Belum tersedia • ketuk untuk coba lagi';

        return Tooltip(
          message: subtitle,
          child: Semantics(
            label: 'Lirik, $subtitle',
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: available
                    ? () => _openLyrics(lyrics!)
                    : canRetry
                        ? _retry
                        : null,
                child: SizedBox(
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (loading)
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          canRetry
                              ? Icons.refresh_rounded
                              : Icons.lyrics_rounded,
                          color: available
                              ? AppColors.textPrimaryOf(context)
                              : AppColors.textMutedOf(context),
                          size: 19,
                        ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Lirik',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondaryOf(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
      },
    );
  }
}
