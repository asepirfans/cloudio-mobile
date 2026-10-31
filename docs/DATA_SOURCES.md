# Data sources, attribution and rights

This inventory describes the implementation in this repository. Links were reviewed on 2026-10-18. Provider availability and terms may change. References describe provenance; they do not establish permission for every use.

## Lyrics

**Primary: [LRCLIB](https://lrclib.net/), [API documentation](https://lrclib.net/docs), [server repository](https://github.com/tranxuanthang/lrclib).**

`lib/services/lyrics_service.dart` requests `/api/get` and `/api/search` using song metadata. It prefers synchronized lyrics when appropriate and may display plain lyrics. Karaoke results look up the underlying song; an unsuitable timing track is not advertised as synchronized karaoke. The UI displays the lyric source.

**Fallback: [YouTube Music](https://music.youtube.com/).** `lib/services/youtube_music_catalog.dart` looks up the lyrics browse panel through an unofficial client; source attribution is returned to the lyric UI.

LRCLIB's MIT license applies to its server software. It is not a blanket grant of copyright in songs, translations or lyric contributions. YouTube Music's availability likewise does not grant permission to redistribute its lyrics. No downloaded lyric catalog is included in Cloudio releases. Displaying fetched lyrics may still require appropriate rights and compliance with provider terms; obtain those permissions where necessary.

## Music catalog, artwork and playback

- [YouTube](https://www.youtube.com/) and [YouTube Music](https://music.youtube.com/) supply catalog metadata, artwork and regular playback media.
- [`youtube_explode_dart` 3.0.5](https://pub.dev/packages/youtube_explode_dart/versions/3.0.5) supplies on-device lookup/resolution. The package is software, not a content-rights grant or an official YouTube API agreement.
- The custom YouTube Music catalog client uses unofficial endpoints; it is not the official YouTube Data API.
- The app provides on-device stream resolution with automatic multi-strategy playback recovery when encountering format or network limits.
- The app does not bundle a music library in APK/IPA files. Runtime streaming and local caching are still uses of provider content, subject to rights and terms.

## TikTok and Instagram

Public post HTML/metadata and provider-hosted media are read by `tiktok_song_service.dart`, `tiktok_sound_service.dart`, `instagram_song_service.dart`, and `social_media_http.dart`.

TikTok playback is tied to the requested post identifier. Separate original audio is eligible only when the original flag, creator name and duration match, and the resulting audio-only file passes duration checks. A named song is not automatically substituted for a post edit. The application downloads temporary input, copies the compressed audio into a local audio-only file, and removes the input. Matching MP3-only input may be copied directly. Limits: 32 MiB video / 64 MiB matched separate audio, cache of 32 files / 128 MiB. This is a temporary cache, not a permanent download library.

Instagram integration attempts recognition on accessible public media; private, login-restricted, expired or unsupported posts may fail. These are unofficial integrations with no affiliation or guarantee of continued access. A public link or TikTok's `original` metadata does not prove that a creator holds every music right.

## Audio recognition

- Pure Dart fingerprint code is vendored from [`shazam_identifier` 1.0.0](https://pub.dev/packages/shazam_identifier/versions/1.0.0), Copyright 2026 Shashwat, MIT. Immutable archive: <https://pub.dev/api/archives/shazam_identifier-1.0.0.tar.gz>.
- Included files and provenance: [fingerprint README](../lib/services/fingerprint/README.md), [original license](../lib/services/fingerprint/LICENSE), [bundled copy](../assets/licenses/shazam_identifier.txt).
- Cloudio performs recording, bounded PCM decoding and fingerprint generation locally. The matching request sends a signature for at most 12 seconds of 16 kHz mono PCM and its duration to an unofficial endpoint on `amp.shazam.com`. The raw microphone recording is not sent by that matching request.
- This is **not** an integration with the official [Apple ShazamKit SDK](https://developer.apple.com/documentation/shazamkit). The MIT fingerprint implementation does not grant access rights to Shazam's service, catalog or marks. An approved recognition provider / official SDK and its terms should be evaluated for production distribution.

## Software and typeface

See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), [THIRD_PARTY_LICENSES.txt](../THIRD_PARTY_LICENSES.txt), and the resolved versions in `pubspec.lock`. Instrument Sans is bundled with its [SIL OFL 1.1 text](../assets/fonts/OFL.txt). The patched `just_audio` package retains its [upstream license](../packages/just_audio/LICENSE) and [patch notes](../packages/just_audio/CLOUDIO_PATCHES.md).

## Provider terms and rights

- [YouTube Terms of Service](https://www.youtube.com/static?template=terms) — permissions, restrictions on downloading, automated access, and content use.
- [YouTube API Services Developer Policies](https://developers.google.com/youtube/terms/developer-policies) — relevant when adopting an official API integration; referencing these policies does not mean the current unofficial client is approved.
- [TikTok Intellectual Property Policy](https://www.tiktok.com/legal/page/global/copyright-policy/en).
- [Instagram Terms of Use](https://help.instagram.com/581066165581870/).
- [Apple ShazamKit documentation](https://developer.apple.com/documentation/shazamkit).

Cloudio's MIT license covers its original code only. Rights in recordings, compositions, lyrics, artwork, performances and trademarks remain with their respective holders. Attribution and an “educational” or preview label do not replace permission. There is no claim that this build has cleared content rights, passed a legal compliance review, or been approved by these platforms or app stores.

For a public/commercial service, obtain the necessary content and service permissions and review the integrations, or replace them with licensed providers and approved playback/recognition APIs. Do not use this documentation as a guarantee that the current implementation is legally unrestricted.

## Rights reports

Use the repository's [issue tracker](https://github.com/asepirfans/cloudio-mobile/issues) to identify a problematic repository file or attribution. Provide the file URL, the rights holder and the concern; avoid publishing private legal documents or credentials. Maintainers should review the claim and remove or correct repository material where appropriate. This project does not operate YouTube, TikTok, Instagram, LRCLIB or Shazam; provider-hosted content also has the provider's own reporting process.
