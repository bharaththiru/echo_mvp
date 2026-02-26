import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ClerkConfig {
  static const _placeholder = 'YOUR_PUBLISHABLE_KEY';

  static String get publishableKey {
    const fromDefine = String.fromEnvironment('CLERK_PUBLISHABLE_KEY');
    final fromDotEnv = dotenv.maybeGet('CLERK_PUBLISHABLE_KEY')?.trim() ?? '';
    final resolved = fromDefine.trim().isNotEmpty ? fromDefine.trim() : fromDotEnv;
    if (resolved.isEmpty || resolved == _placeholder) {
      throw FlutterError(
        'Missing Clerk publishable key. Pass --dart-define=CLERK_PUBLISHABLE_KEY=pk_test_... '
        'or define CLERK_PUBLISHABLE_KEY in a local .env file.',
      );
    }
    return resolved;
  }

  static const signInPath = '/auth';
}
