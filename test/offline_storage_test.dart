import 'dart:io';

import 'package:cloudio_mobile/controllers/download_controller.dart';
import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/offline_storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDocDir;
  late Directory testTempDir;

  setUpAll(() {
    testDocDir = Directory.systemTemp.createTempSync('cloudio_offline_doc_');
    testTempDir = Directory.systemTemp.createTempSync('cloudio_offline_temp_');

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return testDocDir.path;
        }
        if (methodCall.method == 'getTemporaryDirectory') {
          return testTempDir.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    try {
      if (testDocDir.existsSync()) testDocDir.deleteSync(recursive: true);
      if (testTempDir.existsSync()) testTempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('OfflineStorageService initializes and enforces 5GB quota', () async {
    final storage = OfflineStorageService.instance;
    await storage.init();

    expect(storage.isInitialized, isTrue);
    expect(OfflineStorageService.maxQuotaBytes, 5 * 1024 * 1024 * 1024);

    final remaining = await storage.getRemainingQuota();
    expect(remaining, greaterThan(0));
    expect(await storage.hasEnoughQuota(1024 * 1024), isTrue);
  });

  test('OfflineStorageService can save, query, and delete a track', () async {
    final storage = OfflineStorageService.instance;
    await storage.init();

    const track = Track(
      id: 'ytm:test_offline_1',
      title: 'Lagu Offline Test',
      artist: 'Artis Lokal',
      duration: Duration(minutes: 3, seconds: 30),
    );

    // Create a mock audio file
    final tempAudio = File('${testTempDir.path}/mock_song.m4a');
    await tempAudio.writeAsBytes(List.filled(1024 * 50, 42)); // 50 KB mock audio

    await storage.saveDownloadedTrack(
      track: track,
      tempAudioFile: tempAudio,
      rawLyricsJson: '{"instrumental":false,"plainText":"Test lyric line"}',
    );

    expect(storage.isTrackDownloaded(track.id), isTrue);
    expect(storage.trackCount, greaterThanOrEqualTo(1));
    expect(storage.downloadedTracks.any((t) => t.id == track.id), isTrue);

    final audioPath = storage.getLocalAudioPathSync(track.id);
    expect(audioPath, isNotNull);
    expect(File(audioPath!).existsSync(), isTrue);

    final lyrics = storage.getLocalLyrics(track.id);
    expect(lyrics, contains('Test lyric line'));

    final totalUsed = await storage.getTotalStorageUsed();
    expect(totalUsed, greaterThanOrEqualTo(1024 * 50));

    // Delete track
    await storage.deleteTrack(track.id);
    expect(storage.isTrackDownloaded(track.id), isFalse);
    expect(File(audioPath).existsSync(), isFalse);
  });

  test('DownloadController reflects correct download status for offline tracks', () {
    final controller = DownloadController.instance;
    expect(controller.getStatus('non_existent'), DownloadStatus.idle);
    expect(controller.isDownloading('non_existent'), isFalse);
    expect(controller.getProgress('non_existent'), 0.0);
  });

  test('DownloadController rethrows and marks error on invalid stream', () async {
    final controller = DownloadController.instance;
    const invalidTrack = Track(
      id: 'invalid_track_id',
      title: 'Invalid',
      artist: 'Artist',
      sourceUrl: 'http://invalid-url-that-does-not-exist.test/audio.mp3',
      provider: 'direct',
    );

    expect(
      () async => await controller.downloadTrack(invalidTrack),
      throwsA(isA<Exception>()),
    );
  });
}
