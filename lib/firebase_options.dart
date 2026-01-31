import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for Firebase.');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase is not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDbecypyatwPDHrJzaf8jcPRw_E3sxnbBc',
    appId: '1:40275920926:android:ea51c2b4e64728c687060f',
    messagingSenderId: '40275920926',
    projectId: 'echo-3de52',
    storageBucket: 'echo-3de52.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCvgh2SmNZenh0DDlTJ8uo0F7S8j_wndKE',
    appId: '1:40275920926:ios:d08d80a41806e18d87060f',
    messagingSenderId: '40275920926',
    projectId: 'echo-3de52',
    storageBucket: 'echo-3de52.firebasestorage.app',
    iosBundleId: 'com.echo.echo',
  );
}
