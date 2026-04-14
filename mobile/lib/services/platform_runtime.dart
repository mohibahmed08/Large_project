import 'package:flutter/foundation.dart';

bool get isNativeIOS =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get isNativeAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isNativeMobile => isNativeIOS || isNativeAndroid;

String get platformRuntimeLabel {
  if (kIsWeb) {
    return 'web';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

String get deviceRegistrationPlatform {
  if (kIsWeb) {
    return 'web';
  }
  if (isNativeIOS) {
    return 'ios';
  }
  if (isNativeAndroid) {
    return 'android';
  }
  return platformRuntimeLabel;
}
