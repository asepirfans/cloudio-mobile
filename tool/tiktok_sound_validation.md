# Actual TikTok soundtrack — 2026-10-18

Requested post: https://vt.tiktok.com/ZSgMSnYvm/

Implemented a separate `tiktok` track provider with a stable source post URL.
Pasting a TikTok link now offers the actual post sound. The separate **Cari lagu
lengkap** action retains recognition and YouTube catalog lookup. Saved playlists
and player sessions serialize the post identity/source, never signed CDN URLs.
Playback is online; offline file downloads are not implemented.

The source resolver binds media to the exact post ID. For videos it uses the
video's own play/bitrate/download variants, never the separately named music
recording. It skips inaccessible/non-media CDN responses using bounded Range
probes and validates redirects. Native playback receives TikTok request headers.
Fallback remains within the post's media and cannot invoke the YouTube resolver.
TikTok clips do not automatically start YouTube radio or request YouTube lyrics.

## Validation

- 32 service/player/session/lyrics tests passed, including provider persistence,
  exact soundtrack selection, CDN failover, metadata, and no automatic radio.
- The UI test and soundtrack service suite passed after final label changes
  (4 tests; service cases overlap with the 32 above). The UI verifies a pasted
  link produces a clip, a separate full-song action, duration and TikTok badge,
  and tapping it uses the TikTok provider. Screenshot inspected:
  `tool/ui_previews/tiktok-sound.png`.
- Targeted Flutter analysis passed.
- Host network probe: post `7697931564008672530`, creator `@chewygun_`,
  original-sound label, post metadata duration 13 seconds. Two variants returned
  403; another returned 206 and an actual MP4 header. Signed URLs were not logged.
- Physical iPhone 12 / iOS 26.6.1 AOT probe used the production player,
  actual TikTok source resolver and native AVPlayer. It restored Track from its
  serialized representation before playback. Result: playing=true,
  position=3373 ms, native duration=13977 ms, error=null, radioCalls=0, queue=1.
  Report: `tool/tiktok_sound_physical_report.txt`.
- The probe paused playback and restored previous player-session and listening
  history preferences. The final app target is `lib/main.dart`.

A successful native timeline advance verifies playback; it does not independently
verify what was audible at the user's speakers, background behavior, every
TikTok post, or indefinite availability of platform/CDN URLs.

Final release build (`lib/main.dart`) succeeded and was installed on the same
iPhone 12. CoreDevice confirmed the main application launched successfully.

Follow-up: the player now remuxes/caches local audio instead of streaming the
video. The earlier streaming-only limitation is superseded by
`tool/tiktok_audio_cache_validation.md` and its physical-device report.
