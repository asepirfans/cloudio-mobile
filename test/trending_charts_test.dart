import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cloudio_mobile/controllers/listening_history_controller.dart';
import 'package:cloudio_mobile/controllers/player_controller.dart';
import 'package:cloudio_mobile/controllers/playlist_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/models/trending_chart.dart';
import 'package:cloudio_mobile/screens/chart_detail_page.dart';
import 'package:cloudio_mobile/screens/home_screen.dart';
import 'package:cloudio_mobile/services/music_service.dart';

import 'player_autoplay_test.dart' as fixture;

void main() {
  test('TrendingChart model provides default charts correctly', () {
    final charts = TrendingChart.getDefaultCharts();
    expect(charts.length, 4);
    expect(charts[0].id, 'top-indonesia');
    expect(charts[0].title, 'Top 50 Indonesia');
    expect(charts[1].id, 'top-global');
    expect(charts[1].title, 'Top 50 Global');
    expect(charts[2].id, 'viral-tiktok');
    expect(charts[3].id, 'weekly-hot');
  });

  testWidgets('ChartDetailPage displays chart hero and play buttons',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final testChart = TrendingChart(
      id: 'top-indonesia',
      title: 'Top 50 Indonesia',
      subtitle: 'Lagu terpopuler dan paling sering diputar di Indonesia',
      searchKeyword: 'lagu indonesia hits',
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE11D48), Color(0xFF881337)],
      ),
      icon: Icons.trending_up_rounded,
      badgeText: 'Indonesia',
      cachedTracks: const [
        Track(
          id: 'track-1',
          title: 'Satu Bulan',
          artist: 'Bernadya',
          duration: Duration(minutes: 3, seconds: 14),
        ),
        Track(
          id: 'track-2',
          title: 'Gala Bunga Matahari',
          artist: 'Sal Priadi',
          duration: Duration(minutes: 3, seconds: 50),
        ),
        Track(
          id: 'track-3',
          title: 'Mati-Matian',
          artist: 'Mahalini',
          duration: Duration(minutes: 4, seconds: 6),
        ),
        Track(
          id: 'track-4',
          title: 'Kekasih Bayangan',
          artist: 'Cakra Khan',
          duration: Duration(minutes: 3, seconds: 45),
        ),
        Track(
          id: 'track-5',
          title: 'Januari',
          artist: 'Glenn Fredly',
          duration: Duration(minutes: 3, seconds: 52),
        ),
      ],
    );

    final player = PlayerController.forTesting(
      player: fixture.CompletionPlayer(),
      resolveTrack: (_) async => 'https://example.test/audio.m4a',
      buildQueue: (_) async => [],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: PlaylistController.instance),
          ChangeNotifierProvider.value(
              value: ListeningHistoryController.instance),
        ],
        child: MaterialApp(
          home: RepaintBoundary(
            child: ChartDetailPage(chart: testChart),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Top 50 Indonesia'), findsOneWidget);
    expect(find.text('Putar Semua'), findsOneWidget);
    expect(find.text('Acak'), findsOneWidget);
    expect(find.text('Satu Bulan'), findsOneWidget);
    expect(find.text('Gala Bunga Matahari'), findsOneWidget);
    expect(find.text('Mati-Matian'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Save screenshot
    await tester.runAsync(() async {
      final boundary = tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      File('/Users/samjin/.gemini/antigravity-ide/brain/6b29c38e-b172-4903-bf80-c723e39a3631/trending_chart_detail.png')
          .writeAsBytesSync(byteData!.buffer.asUint8List());
    });
  });

  testWidgets('HomeScreen renders Tangga Lagu & Trending carousel',
      (tester) async {
    const feed = HomeFeed(
      forYou: [
        Track(
          id: 'feed-1',
          title: 'Lagu Rekomendasi',
          artist: 'Artis Populer',
          duration: Duration(minutes: 3),
        ),
      ],
      sections: [],
    );

    final player = PlayerController.forTesting(
      player: fixture.CompletionPlayer(),
      resolveTrack: (_) async => 'https://example.test/audio.m4a',
      buildQueue: (_) async => [],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: PlaylistController.instance),
          ChangeNotifierProvider.value(
              value: ListeningHistoryController.instance),
        ],
        child: const MaterialApp(
          home: HomeScreen(initialFeed: feed),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Tangga Lagu & Trending'), findsOneWidget);
    expect(find.text('Top 50 Indonesia'), findsOneWidget);
    expect(find.text('Top 50 Global'), findsOneWidget);
    expect(find.text('Trending'), findsOneWidget);
  });
}
