// Run with Flutter's bundled Dart SDK. Reads only an explicitly supplied PCM
// fixture; never records a microphone or changes the user's playback session.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:cloudio_mobile/services/fingerprint/shazam_signature_generator.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Supply a 16 kHz mono s16le PCM file');
  }
  final bytes = await File(args.single).readAsBytes();
  final watch = Stopwatch()..start();
  final signature = VibraSignature.fromI16(bytes);
  const id = Uuid();
  final client = http.Client();
  try {
    final response = await client
        .post(
            Uri.https('amp.shazam.com',
                '/discovery/v5/en-US/US/android/-/tag/${id.v4()}/${id.v4()}', {
              'sync': 'true',
              'webv3': 'true',
              'sampling': 'true',
              'shazamapiversion': 'v3'
            }),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'com.shazam.android/13.25.0-230413 (Android; SDK 33;)'
            },
            body: jsonEncode({
              'signature': {
                'uri': signature,
                'samplems': bytes.length * 1000 ~/ 32000
              }
            }))
        .timeout(const Duration(seconds: 20));
    final data = jsonDecode(response.body);
    stdout.writeln(jsonEncode({
      'status': response.statusCode,
      'matches': data['matches']?.length,
      'title': data['track']?['title'],
      'artist': data['track']?['subtitle'],
      'elapsedMs': watch.elapsedMilliseconds
    }));
    if (data['matches'] is! List || (data['matches'] as List).isEmpty) {
      exitCode = 1;
    }
  } finally {
    client.close();
  }
}
