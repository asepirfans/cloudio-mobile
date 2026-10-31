import 'package:flutter/material.dart';
import 'track.dart';

class TrendingChart {
  final String id;
  final String title;
  final String subtitle;
  final String searchKeyword;
  final String? playlistId;
  final LinearGradient gradient;
  final IconData icon;
  final String badgeText;
  List<Track> cachedTracks;

  TrendingChart({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.searchKeyword,
    this.playlistId,
    required this.gradient,
    required this.icon,
    required this.badgeText,
    this.cachedTracks = const [],
  });

  static List<TrendingChart> getDefaultCharts() => [
        TrendingChart(
          id: 'top-indonesia',
          title: 'Top 50 Indonesia',
          subtitle: 'Daftar lagu resmi terpopuler di Indonesia',
          searchKeyword: 'Top 100 Lagu Teratas Indonesia',
          playlistId: 'VLPL4fGSI1pDJn5ObxTlEPlkkornHXUiKX1z',
          badgeText: 'Indonesia',
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE11D48), Color(0xFF881337)],
          ),
          icon: Icons.trending_up_rounded,
        ),
        TrendingChart(
          id: 'top-global',
          title: 'Top 50 Global',
          subtitle: 'Tangga lagu resmi dunia terpopuler',
          searchKeyword: 'Top 100 Lagu Teratas Dunia',
          playlistId: 'VLPL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i',
          badgeText: 'Global',
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF3730A3)],
          ),
          icon: Icons.public_rounded,
        ),
        TrendingChart(
          id: 'viral-tiktok',
          title: 'Viral Media Sosial',
          subtitle: 'Lagu yang sedang ramai di TikTok dan Reels',
          searchKeyword: 'TikTok Hits Indonesia',
          badgeText: 'Viral Medsos',
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF06B6D4), Color(0xFFC026D3)],
          ),
          icon: Icons.bolt_rounded,
        ),
        TrendingChart(
          id: 'weekly-hot',
          title: 'Populer Minggu Ini',
          subtitle: 'Kompilasi lagu hits mingguan paling dicari',
          searchKeyword: 'Tangga Lagu Indonesia Terbaru',
          badgeText: 'Mingguan',
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF59E0B), Color(0xFFB45309)],
          ),
          icon: Icons.military_tech_rounded,
        ),
      ];
}
