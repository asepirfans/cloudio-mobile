# Third-party notices

Cloudio's MIT license does not override licenses for dependencies, vendored code, fonts, media or trademarks. Keep the notices below and original license texts when redistributing. The generated [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt) contains the license files found in the resolved Dart/Flutter package set, including development dependencies. It is a dependency inventory, not a media license or a complete legal clearance for external services.

## Vendored code and font

| Material | Origin | License / retained notice |
| --- | --- | --- |
| Music fingerprint generator and CRC32 | `shazam_identifier` 1.0.0, Shashwat | MIT; [provenance](lib/services/fingerprint/README.md), [license](lib/services/fingerprint/LICENSE), [app asset copy](assets/licenses/shazam_identifier.txt) |
| Patched `just_audio` 0.9.46 | Ryan Heise and project contributors | MIT, with additional upstream notices including ExoPlayer Apache 2.0; [complete original license](packages/just_audio/LICENSE), [changes](packages/just_audio/CLOUDIO_PATCHES.md) |
| Instrument Sans | The Instrument Sans Project Authors | SIL Open Font License 1.1; [license](assets/fonts/OFL.txt), [upstream](https://github.com/Instrument/instrument-sans) |

## Main runtime dependencies

Versions are resolved by `pubspec.lock`; use the complete license text rather than treating this summary as a replacement.

| Package | Purpose | License family |
| --- | --- | --- |
| [Flutter](https://flutter.dev/) / Dart | Application framework and runtime | BSD-style licenses and additional bundled notices |
| [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) | YouTube lookup and stream resolution | BSD-3-Clause |
| [just_audio](https://pub.dev/packages/just_audio) | Native audio playback | MIT; additional upstream notices retained |
| [audio_service](https://pub.dev/packages/audio_service), [audio_session](https://pub.dev/packages/audio_session), [just_audio_background](https://pub.dev/packages/just_audio_background) | Background playback, system controls and session handling | MIT |
| [record](https://pub.dev/packages/record) | Microphone recording | BSD-3-Clause |
| [provider](https://pub.dev/packages/provider) | State management | MIT |
| [cached_network_image](https://pub.dev/packages/cached_network_image) | Image loading/cache | MIT |
| [http](https://pub.dev/packages/http), [shared_preferences](https://pub.dev/packages/shared_preferences) | Network access and local preferences | BSD-3-Clause |
| [uuid](https://pub.dev/packages/uuid), [cupertino_icons](https://pub.dev/packages/cupertino_icons) | Identifiers and icon assets | MIT |
| [google_fonts](https://pub.dev/packages/google_fonts) | Declared font utility dependency | Apache-2.0; font files have their own licenses |

Flutter builds also include platform/transitive dependencies. Their corresponding package licenses are included in the generated inventory and Flutter's bundled license notices. Android/native platform dependencies can have additional notices in their own distributions; retain them when building or redistributing. Regenerate the inventory after dependency changes:

```bash
flutter pub get
python3 tool/generate_third_party_licenses.py
```

## Services and content

LRCLIB and YouTube Music supply lyrics; YouTube/YouTube Music supply regular catalog/audio/artwork; TikTok/Instagram supply requested public post media/metadata; an unofficial Shazam service supplies recognition matches. These references are attribution and implementation disclosure, not endorsement or a content redistribution grant. See [data sources and provider terms](docs/DATA_SOURCES.md).
