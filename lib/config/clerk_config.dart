import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ClerkConfig {
  static const _placeholder = 'YOUR_PUBLISHABLE_KEY';

  static String get publishableKey {
    const fromDefine = String.fromEnvironment('CLERK_PUBLISHABLE_KEY');
    final trimmedDefine = fromDefine.trim();
    if (trimmedDefine.isNotEmpty && trimmedDefine != _placeholder) {
      return trimmedDefine;
    }
    // Dart-define not set; fall back to local .env (development only).
    String fromDotEnv = '';
    try {
      fromDotEnv = dotenv.maybeGet('CLERK_PUBLISHABLE_KEY')?.trim() ?? '';
    } catch (_) {
      // dotenv not initialized — .env absent or not bundled in release IPA.
    }
    if (fromDotEnv.isEmpty || fromDotEnv == _placeholder) {
      throw FlutterError(
        'Missing Clerk publishable key. Pass --dart-define=CLERK_PUBLISHABLE_KEY=pk_test_... '
        'or define CLERK_PUBLISHABLE_KEY in a local .env file.',
      );
    }
    return fromDotEnv;
  }

  static const signInPath = '/auth';
}
