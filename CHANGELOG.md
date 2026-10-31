# Changelog

## 1.0.0-preview.1 — 2026-10-18

First public development preview for Android and iOS.

- Music catalog discovery, playlists, listening history and background playback.
- Microphone music recognition, original TikTok soundtrack playback, and public Instagram song lookup.
- Music / Karaoke search and automatic original-song lyric lookup.
- LRCLIB synchronized/plain lyrics with YouTube Music fallback and source labels.
- Bounded audio-only TikTok cache, including separate original audio for matching long posts.
- Cloud-blue category buttons, including pressed/transition states; selectable player visuals and sleep timer.
- Documentation of data sources, unofficial integrations, provider terms, dependency notices and MIT project-code licensing.

Validation: release APK built and signature verified; development IPA archived/exported successfully; public unsigned IPA packaged and checked for missing provisioning profiles/signatures. Offline suite: 162 passed, 6 opt-in network tests skipped. Root analyzer: no issues (vendored upstream package excluded from root lint style checks). Android physical runtime testing and App Store/Play Store approval are not claimed. Xcode's archive validation still reports the template launch-image asset warning.

Signing: Android preview uses the local debug/development key. Public iOS IPA requires signing before installation; the personal development-signed IPA is kept local for registered devices. Provider/content rights have not been cleared by publishing this preview; see `docs/DATA_SOURCES.md`.
