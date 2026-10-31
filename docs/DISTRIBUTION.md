# Distribution and signing

Cloudio release assets contain application code and bundled licenses, not a downloadable music/lyrics catalog. The project is a development preview; the current provider integrations have not been approved by their providers or app stores. See [data sources and terms](DATA_SOURCES.md).

## Android APK

```bash
flutter pub get
flutter build apk --release --dart-define=CLOUDIO_PLAYBACK_DIAGNOSTICS=false
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. The universal APK supports the ABIs enabled by Flutter's build. Minimum Android SDK is API 23 (Android 6.0).

The current `android/app/build.gradle` release configuration signs with the local Android **debug/development key**. This is a release-mode preview APK, not a production-signed Play Store build. A production release needs a controlled release signing key and an appropriate signing configuration; never commit that key or its password. A future APK signed with a different certificate cannot update the installed preview in place without migration/reinstallation.

Install the APK using Android's normal install flow, allowing installation from your chosen source if required. No Android physical-device runtime coverage is claimed by the current build report.

## Development-signed iOS IPA

Requirements: macOS, Flutter, CocoaPods, Xcode, a valid signing identity, and a provisioning profile that includes the target device.

```bash
flutter pub get
cd ios
pod install
cd ..
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build ipa --release \
  --export-method development --dart-define=CLOUDIO_PLAYBACK_DIAGNOSTICS=false
```

Select your team/bundle identifier in `ios/Runner.xcworkspace`. Output: archive under `build/ios/archive/`, exported IPA under `build/ios/ipa/`.

A development-signed package works only with its valid profile, registered devices and certificate/entitlement constraints. It can expire and is not an App Store package. It contains provisioning metadata, so the personal development-signed package is kept local rather than attached to the public release. Certificates/private keys and pairing records are never release assets.

## Public unsigned iOS IPA

The public `*-ios-unsigned.ipa` asset is a release-mode arm64 application in an IPA container, with embedded provisioning profiles and existing code signatures removed. It requires a compatible signing/sideload workflow and **your own valid Apple signing credentials/profile** before installation. An unsigned IPA cannot be installed directly by tapping it on an iPhone. Signing tools must sign nested frameworks and the main application correctly.

This is not TestFlight, App Store distribution or a promise that every signing method/device will work. For reproducible iOS development, building from source with Xcode and your own team is the supported path. Preserve the bundled license notices when repackaging.

## Release checklist

1. Build `lib/main.dart`; keep playback diagnostics disabled.
2. Run the offline test suite and record the result and known limitations.
3. Generate `THIRD_PARTY_LICENSES.txt` after resolving dependencies.
4. Keep source, licenses and docs in Git; attach APK/IPA to GitHub Releases instead of committing binaries.
5. Exclude device pairing records, profiles, private keys, local logs and downloaded media/lyric fixtures from source publication.
6. Generate `SHA256SUMS.txt` from the exact release files and verify it after download.
7. Describe APK signing and IPA signing requirements explicitly in the release notes.

Store distribution, production signing, provider approvals and content-rights clearance are separate tasks and have not been completed by creating a GitHub release.
