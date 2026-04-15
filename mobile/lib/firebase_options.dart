import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase client config for each supported platform.
///
/// API keys are supplied at build time via `--dart-define` / `--dart-define-from-file`
/// so they do not live in git-tracked Dart source.
class DefaultFirebaseOptions {
  static const String _webApiKey =
      String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const String _androidApiKey =
      String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const String _iosApiKey =
      String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const String _macosApiKey =
      String.fromEnvironment('FIREBASE_MACOS_API_KEY');
  static const String _windowsApiKey =
      String.fromEnvironment('FIREBASE_WINDOWS_API_KEY');

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      _requireApiKey('FIREBASE_WEB_API_KEY', _webApiKey);
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        _requireApiKey('FIREBASE_ANDROID_API_KEY', _androidApiKey);
        return android;
      case TargetPlatform.iOS:
        _requireApiKey('FIREBASE_IOS_API_KEY', _iosApiKey);
        return ios;
      case TargetPlatform.macOS:
        _requireApiKey('FIREBASE_MACOS_API_KEY', _macosApiKey);
        return macos;
      case TargetPlatform.windows:
        _requireApiKey('FIREBASE_WINDOWS_API_KEY', _windowsApiKey);
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static bool get isConfiguredForCurrentPlatform {
    if (kIsWeb) {
      return _webApiKey.isNotEmpty;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidApiKey.isNotEmpty;
      case TargetPlatform.iOS:
        return _iosApiKey.isNotEmpty;
      case TargetPlatform.macOS:
        return _macosApiKey.isNotEmpty;
      case TargetPlatform.windows:
        return _windowsApiKey.isNotEmpty;
      case TargetPlatform.linux:
        return false;
      default:
        return false;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _webApiKey,
    appId: '1:228632083486:web:56f73ba000519b500ec20f',
    messagingSenderId: '228632083486',
    projectId: 'calendarplusplus-a24d5',
    authDomain: 'calendarplusplus-a24d5.firebaseapp.com',
    storageBucket: 'calendarplusplus-a24d5.firebasestorage.app',
    measurementId: 'G-QFVZW4EV1Y',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _androidApiKey,
    appId: '1:228632083486:android:575b10a3b020a2070ec20f',
    messagingSenderId: '228632083486',
    projectId: 'calendarplusplus-a24d5',
    storageBucket: 'calendarplusplus-a24d5.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: _iosApiKey,
    appId: '1:228632083486:ios:0c758c8b84891d380ec20f',
    messagingSenderId: '228632083486',
    projectId: 'calendarplusplus-a24d5',
    storageBucket: 'calendarplusplus-a24d5.firebasestorage.app',
    iosBundleId: 'com.jonathan.calendar',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: _macosApiKey,
    appId: '1:228632083486:ios:14b802ecf66f9b010ec20f',
    messagingSenderId: '228632083486',
    projectId: 'calendarplusplus-a24d5',
    storageBucket: 'calendarplusplus-a24d5.firebasestorage.app',
    iosBundleId: 'com.example.untitled',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: _windowsApiKey,
    appId: '1:228632083486:web:7c3de2b2d93a966c0ec20f',
    messagingSenderId: '228632083486',
    projectId: 'calendarplusplus-a24d5',
    authDomain: 'calendarplusplus-a24d5.firebaseapp.com',
    storageBucket: 'calendarplusplus-a24d5.firebasestorage.app',
    measurementId: 'G-DTD0CDDS00',
  );

  static void _requireApiKey(String variableName, String value) {
    if (value.isNotEmpty) {
      return;
    }

    throw UnsupportedError(
      'Missing Firebase API key `$variableName`. Provide it with '
      '`--dart-define=$variableName=...` or '
      '`--dart-define-from-file=firebase.env.json`.',
    );
  }
}
