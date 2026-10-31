# TikTok audio cache validation — 2026-10-18

The production TikTok player now receives a local file URI, not a video stream.
On a cache miss, download the post media once (32 MiB video maximum), copy its
compressed audio into an audio-only container and delete the temporary video.
On iOS this uses an audio-only AVMutableComposition and
AVAssetExportPresetPassthrough. Android uses MediaExtractor/MediaMuxer without a
MediaCodec decode/encode pass. MP3 audio-only sources can be copied directly.

Long original posts may advertise separate audio, preferred only when the
original flag, music author/post creator name and duration match. These audio
downloads have a separate 64 MiB limit. The resulting native audio-only file
must match the post duration within 1.5 seconds or it is deleted and rejected.
Native handlers also reject video-bearing inputs over 32 MiB even though the
absolute audio input limit is 64 MiB. Reused/named music and other-length edits
remain excluded. This fixes the 41-minute post `7679996088232709394`: its
accessible MP4 is 355,685,765 bytes, while its original MP3 is 39,368,560 bytes.

Long-post regression verification:
- Link: `https://vt.tiktok.com/ZSgM5WsL9/`, title `suara asli - GEN Z DUTCH`.
- Physical iPhone: cold preparation downloaded 39,368,560 bytes (the separate
  MP3, not the 355 MB video); output audioTracks=1/videoTracks=0, duration
  2,460,499 ms, playing=true, position=3,001 ms, error=null, radioCalls=0.
- Fresh cache and source instances with HTTP forbidden resolved the local file.
  Previous session/history preferences were restored. Report:
  `tool/tiktok_long_sound_physical_report.txt`.
- Service/cache/player/session suite: 32 tests passed; final cache suite: six
  passed, adding the streamed 33 MiB audio-versus-video boundary regression.
  These runs overlap; 33 distinct cases in total. Parser checks reject reused
  authors, missing authors, non-original music and mismatched durations. Cache
  checks remove duration-mismatched originals before playback.
- Targeted analyzer: no issues. Android compileReleaseKotlin succeeded; no
  Android runtime test was performed.
- Updated normal `lib/main.dart` iOS release built successfully (49.4 seconds
  in Xcode), installed on the same iPhone 12, and launched successfully.

Cache lookup precedes any TikTok page/CDN request. Concurrent preparations of the
same post share one future. Completed audio is bounded to 32 files / 128 MiB;
abandoned download/export files older than ten minutes are removed. A deleted
or broken cached file can be refreshed once, with no fallback to video playback.
The cache is temporary and can be cleared by the OS.

Important fixes discovered during testing:
- TikTok's accessible CDN required `Range: bytes=0-`; the full response was HTTP
  206 with a complete Content-Range. Partial ranges, oversize responses and
  redirects outside TikTok media hosts are rejected.
- AVFoundation did not recognize the downloaded MP4 under its `.part` filename.
  The native handler now stages it with a container-appropriate extension.
- Downloading writes chunks directly to disk, with backpressure, instead of
  passing multi-megabyte byte arrays over the Flutter method channel.

Checks:
- Initial cache/service/player/session run: 29 tests passed.
- Final cache suite: 4 tests passed, covering complete 206 responses, partial
  ranges, foreign redirects, oversize media, failed extraction cleanup, request
  coalescing and warm cache without HTTP (three cases overlap the initial run).
- Targeted analyzer: no issues.
- Android debug APK built; an additional offline compileReleaseKotlin succeeded.
  Android runtime behavior was not tested on a device.
- Host AVFoundation inspection/remux: source audio=1/video=1, output
  audio=1/video=0, passthrough export completed without an error.
- Physical iPhone 12 / iOS 26.6.1: source download 1,427,899 bytes, cached M4A
  58,692 bytes, audioTracks=1, videoTracks=0, native duration=13,976 ms.
  Playback advanced to 3,348 ms, playing=true, error=null, no YouTube radio.
- A fresh cache/source instance with all HTTP requests forbidden returned the
  existing local file URI. Previous player-session/history preferences were
  restored after the probe. Report: `tool/tiktok_audio_cache_physical_report.txt`.
- ProcessInfo thermalState was 0 (nominal) at that observation. This is a coarse
  OS thermal-pressure state, not a measured surface temperature or a comparison
  of sustained power/temperature before and after. No numerical heat reduction
  is claimed. Initial preparation still needs network/disk work; repeated
  playback avoids the former video stream and extraction.

API references:
- https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough
- https://developer.android.com/reference/android/media/MediaMuxer

Final `lib/main.dart` iOS release build succeeded (48.3 seconds in Xcode), was
installed on the same iPhone 12, and CoreDevice confirmed successful launch.
