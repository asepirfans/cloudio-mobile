import 'dart:convert';

/// Application API configuration.
///
/// Supports runtime overrides via compile-time `--dart-define` or
/// `--dart-define-from-file=.env`. Default endpoints are obfuscated
/// so plain-text domains are not exposed in decompiled binaries.
abstract class ApiConfig {
  static const String _envResolverHost =
      String.fromEnvironment('CLOUDIO_RESOLVER_HOST');

  // Obfuscated default fallback endpoint
  static const String _obfuscatedResolver =
      'cmVzb2x2ZXIuY2xvdWRpb2xhYnMubXkuaWQ=';

  static String get resolverHost {
    if (_envResolverHost.isNotEmpty) {
      return _envResolverHost;
    }
    return _defaultResolverHost;
  }

  static final String _defaultResolverHost =
      utf8.decode(base64.decode(_obfuscatedResolver));

  static bool isResolverHost(String host) => host == resolverHost;

  static Uri resolverStreamUri(String videoId, {bool refresh = false}) {
    return Uri.https(resolverHost, '/stream', {
      'id': videoId,
      if (refresh) 'refresh': '1',
    });
  }
}
