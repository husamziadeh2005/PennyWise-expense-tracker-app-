import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Where the Node.js API runs.
///
/// The app cannot work without it: every screen after login loads its data
/// from this server. If nothing answers at [baseUrl] the app shows
/// "Cannot reach the server" with a Try again button.
///
/// Override at build time (or let `scripts/dev.sh` do it for you):
///   flutter run --dart-define=API_URL=http://192.168.1.20:3000
///   flutter run --dart-define-from-file=config/dev.json
///
/// Defaults when nothing is passed:
///   * Android emulator -> http://10.0.2.2:3000 (the emulator's alias for your computer)
///   * iOS simulator / macOS / web -> http://localhost:3000
///   * A REAL phone has no sensible default: "localhost" there means the
///     phone itself, so you must pass API_URL (your Mac's Wi-Fi IP or a
///     deployed https URL).
class ApiConfig {
  ApiConfig._();

  static const _fromEnv = String.fromEnvironment('API_URL');

  /// True when API_URL was passed with --dart-define(-from-file).
  static bool get isConfigured => _fromEnv.isNotEmpty;

  static String get baseUrl {
    if (_fromEnv.isNotEmpty) return _fromEnv.replaceAll(RegExp(r'/+$'), '');
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }

  /// Developer hint shown under the error in debug builds only.
  static String get debugHint {
    final buf = StringBuffer('API: $baseUrl\n'
        'Start it with:  cd backend && npm run dev\n'
        'or run everything with:  ./scripts/dev.sh');
    final local = baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1');
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid) && local) {
      buf.write('\nOn a real phone, localhost is the phone itself: '
          'pass --dart-define=API_URL=http://<mac-ip>:3000');
    }
    return buf.toString();
  }
}
