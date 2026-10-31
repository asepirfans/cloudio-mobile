import 'package:cloudio_mobile/services/playback_end_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  final start = DateTime.utc(2026);
  bool tick(PlaybackEndGuard guard, int seconds,
          {int position = 180000,
          int buffered = 180000,
          bool playing = true,
          bool busy = false,
          int generation = 1,
          ProcessingState state = ProcessingState.ready}) =>
      guard.shouldAdvance(
          generation: generation,
          playing: playing,
          busy: busy,
          state: state,
          position: Duration(milliseconds: position),
          duration: const Duration(minutes: 3),
          bufferedPosition: Duration(milliseconds: buffered),
          now: start.add(Duration(seconds: seconds)));
  test(
      'recovers a missing completion once after the fully buffered end is stationary',
      () {
    final guard = PlaybackEndGuard();
    expect(tick(guard, 0), isFalse);
    expect(tick(guard, 2), isFalse);
    expect(tick(guard, 3), isTrue);
    expect(tick(guard, 4), isFalse);
    expect(tick(guard, 5, generation: 2), isFalse);
    expect(tick(guard, 8, generation: 2), isTrue);
  });
  test('does not skip a paused, seeking, loading or midstream stalled song',
      () {
    for (final options in [
      'paused',
      'busy',
      'loading',
      'middle',
      'unbuffered'
    ]) {
      final guard = PlaybackEndGuard();
      for (final seconds in [0, 4, 8]) {
        expect(
            tick(guard, seconds,
                playing: options != 'paused',
                busy: options == 'busy',
                state: options == 'loading'
                    ? ProcessingState.loading
                    : ProcessingState.buffering,
                position: options == 'middle' ? 90000 : 180000,
                buffered: options == 'unbuffered' ? 90000 : 180000),
            isFalse);
      }
    }
  });
  test('ongoing progress near the end resets the stationary window', () {
    final guard = PlaybackEndGuard();
    expect(tick(guard, 0, position: 179750), isFalse);
    expect(tick(guard, 2, position: 180000), isFalse);
    expect(tick(guard, 4), isFalse);
    expect(tick(guard, 5), isTrue);
  });
  test('pausing clears pending recovery', () {
    final guard = PlaybackEndGuard();
    expect(tick(guard, 0), isFalse);
    expect(tick(guard, 2, playing: false), isFalse);
    expect(tick(guard, 4), isFalse);
    expect(tick(guard, 7), isTrue);
  });
}
