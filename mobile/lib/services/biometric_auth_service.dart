import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class BiometricStatus {
  const BiometricStatus({
    required this.supported,
    required this.label,
  });

  final bool supported;
  final String label;
}

class BiometricAuthService {
  BiometricAuthService({LocalAuthentication? localAuthentication})
      : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  Future<BiometricStatus> getStatus() async {
    if (kIsWeb) {
      return const BiometricStatus(
        supported: false,
        label: 'Biometrics',
      );
    }

    try {
      final isDeviceSupported = await _localAuthentication.isDeviceSupported();
      final canCheckBiometrics =
          await _localAuthentication.canCheckBiometrics;
      if (!isDeviceSupported && !canCheckBiometrics) {
        return const BiometricStatus(
          supported: false,
          label: 'Biometrics',
        );
      }

      final biometrics = await _localAuthentication.getAvailableBiometrics();
      if (biometrics.contains(BiometricType.face)) {
        return const BiometricStatus(
          supported: true,
          label: 'Face ID',
        );
      }
      if (biometrics.contains(BiometricType.fingerprint)) {
        return const BiometricStatus(
          supported: true,
          label: 'Fingerprint',
        );
      }

      return const BiometricStatus(
        supported: true,
        label: 'Biometrics',
      );
    } catch (_) {
      return const BiometricStatus(
        supported: false,
        label: 'Biometrics',
      );
    }
  }

  /// Authenticate with biometrics only (Face ID / Touch ID).
  /// Pass [allowDeviceCredential: true] only when you explicitly want to
  /// fall back to PIN/password (e.g. when the user taps "Use password instead").
  Future<bool> authenticate({
    required String reason,
    bool allowDeviceCredential = false,
  }) async {
    if (kIsWeb) {
      return false;
    }

    try {
      return await _localAuthentication.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          // Only allow the biometric sensor; do NOT fall back to device
          // passcode/password unless the caller explicitly requests it.
          biometricOnly: !allowDeviceCredential,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
