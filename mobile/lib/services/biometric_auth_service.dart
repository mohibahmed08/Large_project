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

  Future<bool> authenticate({required String reason}) async {
    if (kIsWeb) {
      return false;
    }

    try {
      return await _localAuthentication.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
