import 'package:just_audio/just_audio.dart';

/// Recovers a missing native completion only after the buffered stream has
/// stopped at its actual end. Catalog durations never trigger advancement.
class PlaybackEndGuard {
  int? _generation;
  Duration? _lastPosition;
  DateTime? _stationarySince;
  bool _fired = false;

  void reset() {
    _generation = null;
    _lastPosition = null;
    _stationarySince = null;
    _fired = false;
  }

  bool shouldAdvance(
      {required int generation,
      required bool playing,
      required bool busy,
      required ProcessingState state,
      required Duration position,
      required Duration? duration,
      required Duration bufferedPosition,
      required DateTime now}) {
    if (_generation != generation) {
      reset();
      _generation = generation;
    }
    if (_fired) return false;
    if (!playing ||
        busy ||
        duration == null ||
        duration <= Duration.zero ||
        (state != ProcessingState.ready &&
            state != ProcessingState.buffering) ||
        position < duration - const Duration(milliseconds: 300) ||
        bufferedPosition < duration - const Duration(milliseconds: 300)) {
      _stationarySince = null;
      _lastPosition = null;
      return false;
    }
    if (_lastPosition == null ||
        (position - _lastPosition!).abs() > const Duration(milliseconds: 100)) {
      _stationarySince = now;
    }
    _lastPosition = position;
    _stationarySince ??= now;
    if (now.difference(_stationarySince!) < const Duration(seconds: 3)) {
      return false;
    }
    _fired = true;
    return true;
  }
}
