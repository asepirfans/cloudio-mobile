# Social music search validation — 2026-10-18

## Implemented

- Search accepts TikTok and Instagram links through one paste button.
- TikTok tries up to three post-bound media candidates, prioritizing the actual
  video soundtrack, then music as fallback. Failed CDN requests, decoding and
  unmatched audio can move on to another candidate. Both common URL-list forms
  and bitrate renditions are supported. Trailing slashes no longer hide post
  metadata, and redirected posts cannot substitute a different identity.
- Instagram reads exact-shortcode public JSON (including Relay/product payloads),
  named licensed music, and canonical-bound OpenGraph media. It tries the embed
  page when media/metadata is absent. Short share redirects are supported.
- Media downloads are bounded at 12 MiB with a total download deadline and a
  redirect limit. HTML reads use a 3 MiB limit. Only platform CDN URLs may supply
  recognition media. Login/private data and arbitrary captions are not treated
  as recognized songs.
- Existing native audio decoding and fingerprint generation are reused; no new
  package, API key, account login, backend deployment, or native decoder change.

## Automated checks

The six focused service/controller suites passed (43 tests); the additional
current Instagram product payload test was then run with its full suite (7
passing tests, bringing distinct focused cases to 44).

```sh
flutter test --no-pub --reporter expanded \
  test/music_recognition_test.dart \
  test/instagram_song_service_test.dart \
  test/social_media_http_test.dart \
  test/tiktok_song_service_test.dart \
  test/tiktok_music_matcher_test.dart \
  test/music_recognition_controller_test.dart
```

Two search layout tests passed: 390 logical pixels, and 320 logical pixels with
1.4x text. Their screenshots were inspected. The small layout uses an icon with
an accessible TikTok/Instagram paste tooltip so the heading remains visible.

```sh
flutter test --no-pub --reporter expanded \
  --dart-define=CLOUDIO_CAPTURE_UI=true \
  test/ui_layout_test.dart --name '^search'
```

Targeted Flutter analysis of the modified implementation and tests passed.

## Real network checks and limits

1. `https://vt.tiktok.com/ZSbwo7d1r/`: resolver returned three media candidates
   from TikTok CDN hosts. Metadata returned `golden hour (Cello Version) — JVKE`.
   This verifies extraction/metadata; it does not establish successful native
   decoding or fingerprint recognition of that live post.
2. The existing PCM recognition fixture was sent through the production
   fingerprint matcher and returned `I Will Survive — Gloria Gaynor`.
3. `https://www.instagram.com/reel/Chunk8-jurw/` and its embed returned HTTP 200
   with a generic Instagram page, containing neither `video_url` nor
   `video_versions`. A diagnostic anonymous public query also returned HTML
   instead of media JSON. No login or account cookies were used. Cloudio returns
   an actionable unavailable-media error for this case.

**Instagram recognition is verified with controlled media/HTTP fixtures only.
Successful recognition of a real Instagram link remains unverified.** Public
visibility does not guarantee that Instagram will expose media to an anonymous
client. Restricted links need another input such as audible microphone
recognition or a separate extraction service; no such service was deployed here.
The existing unofficial Shazam matching endpoint may change independently.

The original recognition-only change was later built and installed on the user's
iPhone. A subsequent actual TikTok soundtrack route was added and verified on
that device; see `tool/tiktok_sound_physical_report.txt` and
`tool/tiktok_sound_validation.md`. The Instagram limitation above is unchanged.
Existing unrelated workspace edits were preserved.
