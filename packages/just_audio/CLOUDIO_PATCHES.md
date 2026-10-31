# Cloudio Darwin playback patch

Baseline: just_audio 0.9.46 from pub.dev; upstream MIT license retained.
Android and the upstream Dart player behavior are unchanged, except for a
read-only `cloudioNativeSnapshot()` diagnostic method on Darwin.

Darwin changes:

- `onComplete` checks the ended item's index rather than blindly incrementing
  the mutable current index. AVQueuePlayer's currentItem observation can arrive
  before completion. Do not rewind an ending item while it is still current.
- On currentItem changes, publish the new index, duration and position baseline
  together, after native queue maintenance. The native periodic discontinuity
  observer also reconciles its index with AVQueuePlayer.currentItem.
- The diagnostic snapshot reports both AVQueuePlayer's actual item index and
  the plugin's index, raw item time/duration, and seekable ranges. It does not
  include URLs or headers.

Validation: Cloudio's Dart suite and the physical iPhone probe. To exercise the
reported pair with complete, unclipped playback and catalog durations:

```
flutter build ios --profile --target tool/physical_playback_probe.dart --dart-define=CLOUDIO_PROBE_SHAPE=true
```

The app can record a bounded local diagnostic log when built with
`--dart-define=CLOUDIO_PLAYBACK_DIAGNOSTICS=true`. It is disabled by default.
Cloudio separately reads the MP4 movie header and sets a native playback end
boundary to that media duration. This addresses fragmented AAC assets whose
AVPlayerItem duration is doubled, without using catalog durations as a cutoff.
