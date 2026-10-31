import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final IconData moreIcon;

  const TrackTile({
    super.key,
    required this.track,
    this.isCurrent = false,
    this.isPlaying = false,
    required this.onTap,
    this.onMore,
    this.moreIcon = Icons.more_horiz_rounded,
  });

  String _formatDuration(Duration? d) {
    if (d == null || d == Duration.zero) return '';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 50,
                  height: 50,
                  color: AppColors.surface,
                  child: track.artworkUrl != null
                      ? CachedNetworkImage(
                          imageUrl: track.artworkUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: AppColors.card,
                            child: Icon(Icons.music_note,
                                color: AppColors.textMuted, size: 20),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: AppColors.card,
                            child: Icon(Icons.music_note,
                                color: AppColors.textMuted, size: 20),
                          ),
                        )
                      : Icon(Icons.music_note,
                          color: AppColors.textMuted, size: 20),
                ),
              ),
              const SizedBox(width: 13),

              // Title and Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? AppColors.accentOf(context)
                            : AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.isTikTokSound
                          ? '${track.displayArtist} · TikTok'
                          : track.isKaraoke
                              ? '${track.displayArtist} · Karaoke'
                              : track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isCurrent
                            ? AppColors.accentOf(context).withOpacity(0.8)
                            : AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),

              // Equalizer icon if playing or duration
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(
                    isPlaying ? Icons.graphic_eq : Icons.pause,
                    color: AppColors.accentOf(context),
                    size: 18,
                  ),
                )
              else if (track.duration != null)
                Text(
                  _formatDuration(track.duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMutedOf(context),
                  ),
                ),

              if (onMore != null)
                IconButton(
                  tooltip: 'Opsi lagu',
                  icon:
                      Icon(moreIcon, color: AppColors.textSecondaryOf(context), size: 20),
                  onPressed: onMore,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
