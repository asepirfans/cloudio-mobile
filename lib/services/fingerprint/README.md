Fingerprint implementation vendored from shazam_identifier 1.0.0 (MIT,
Copyright 2026 Shashwat), fetched from the immutable pub.dev package archive:
https://pub.dev/api/archives/shazam_identifier-1.0.0.tar.gz

Only the pure Dart signature generator and CRC32 are included. Its microphone
service, HTTP client, logging and external Muzo enrichment are not included.
Cloudio owns recording, decoding, cancellation and catalog matching separately.
The generator runs in an isolate and receives at most 12 seconds of 16 kHz mono
16-bit little-endian PCM. Signature matching uses an unofficial remote Shazam
endpoint and may change independently of this library.
