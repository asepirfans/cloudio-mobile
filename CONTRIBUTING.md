# Contributing to Cloudio

Thanks for helping improve Cloudio. Start with an issue for substantial behavior changes so the intended outcome is clear.

1. Use the Flutter/Dart versions documented in the README and run `flutter pub get`.
2. Keep `packages/just_audio` and its license/patch notes when changing native playback.
3. Make a focused change. Run relevant tests and `flutter analyze`; include the commands and outcome in your pull request.
4. For provider integrations, document provenance, service limits, errors and any new data sent off the device. Do not claim an unofficial endpoint is an approved API.
5. Preserve upstream notices. Regenerate `THIRD_PARTY_LICENSES.txt` when dependencies change.

Bug reports should include platform/version, reproduction steps, expected/actual behavior and sanitized errors. Never include tokens, signing keys, provisioning profiles, device pairing records, private posts, raw microphone recordings, downloaded songs, artwork fixtures or complete copyrighted lyrics.

Do not submit credentials or generated APK/IPA/build directories to Git. Attach distribution packages to a release instead. Contributions are provided under the project's MIT license for original code, with third-party code kept under its existing license; contribute only material you are authorized to share.
