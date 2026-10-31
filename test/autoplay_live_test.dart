import 'package:cloudio_mobile/models/track.dart';
import 'package:cloudio_mobile/services/music_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('radio supplies the next song for a single TikTok recording', () async {
    addTearDown(MusicService.instance.dispose);
    final queue = await MusicService.instance.buildSmartQueue(
        const Track(
            id: 'ytm:K3ahuED9v88',
            title: 'golden hour (Cello Version)',
            artist: 'JVKE',
            duration: Duration(minutes: 3)),
        limit: 12);
    debugPrint(
        'Queue count: ${queue.length}; next: ${queue.skip(1).take(3).map((t) => t.title).join(', ')}');
    expect(queue.length, greaterThan(1));
  },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: !const bool.fromEnvironment('CLOUDIO_LIVE_AUTOPLAY_TEST'));
}
