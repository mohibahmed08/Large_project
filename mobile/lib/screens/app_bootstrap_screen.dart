import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/biometric_auth_service.dart';
import '../services/session_storage.dart';
import '../theme/app_theme.dart';
import 'calendar_screen.dart';
import 'login_screen.dart';
import 'reset_password_screen.dart';

class AppBootstrapScreen extends StatefulWidget {
  const AppBootstrapScreen({
    super.key,
    this.initialResetToken,
  });

  final String? initialResetToken;

  @override
  State<AppBootstrapScreen> createState() => _AppBootstrapScreenState();
}

class _AppBootstrapScreenState extends State<AppBootstrapScreen> {
  final BiometricAuthService _biometricAuthService = BiometricAuthService();

  UserSession? _session;
  UserSession? _lockedSession;
  String? _resetToken;
  String _biometricLabel = 'Face ID';
  String? _unlockMessage;
  bool _isLoading = true;
  bool _isUnlocking = false;
  bool _showLoginScreen = false;

  @override
  void initState() {
    super.initState();
    _resetToken = _normalizeToken(widget.initialResetToken);
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant AppBootstrapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextToken = _normalizeToken(widget.initialResetToken);
    if (nextToken != null && nextToken != _resetToken) {
      setState(() {
        _resetToken = nextToken;
        _session = null;
        _lockedSession = null;
        _isLoading = false;
      });
    }
  }

  String? _normalizeToken(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _bootstrap() async {
    if (_resetToken != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final storedToken = await SessionStorage.readToken();
    if (!mounted) {
      return;
    }

    if (storedToken.isEmpty) {
      setState(() {
        _session = null;
        _lockedSession = null;
        _showLoginScreen = false;
        _isLoading = false;
      });
      return;
    }

    try {
      final session = UserSession.fromAccessToken(storedToken);
      final biometricUnlockEnabled =
          await SessionStorage.isBiometricUnlockEnabled();
      final biometricLoginEnabled =
          await SessionStorage.isBiometricLoginEnabled();
      if (!mounted) {
        return;
      }

      if (!biometricUnlockEnabled && !biometricLoginEnabled) {
        setState(() {
          _session = session;
          _lockedSession = null;
          _showLoginScreen = false;
          _isLoading = false;
        });
        return;
      }

      final status = await _biometricAuthService.getStatus();
      if (!mounted) {
        return;
      }

      _biometricLabel = status.label;
      if (!status.supported) {
        setState(() {
          _session = session;
          _lockedSession = null;
          _showLoginScreen = false;
          _isLoading = false;
        });
        return;
      }

      if (biometricLoginEnabled && !biometricUnlockEnabled) {
        setState(() {
          _session = null;
          _lockedSession = null;
          _showLoginScreen = true;
          _isLoading = false;
        });
        return;
      }

      // biometricOnly: true — we want Face ID / Touch ID, not device passcode.
      setState(() {
        _session = null;
        _lockedSession = session;
        _showLoginScreen = false;
        _unlockMessage =
            'Use $_biometricLabel to open your saved session, or choose password login instead.';
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lockedSession != null) {
          unawaited(_retryUnlock(auto: true));
        }
      });
    } catch (_) {
      await SessionStorage.clearSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _lockedSession = null;
        _showLoginScreen = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _retryUnlock({bool auto = false}) async {
    final session = _lockedSession;
    if (session == null) {
      return;
    }

    setState(() {
      _isUnlocking = true;
      if (!auto) {
        _unlockMessage = null;
      }
    });

    // biometricOnly — Face ID/Touch ID only, no passcode fallback here.
    final unlocked = await _biometricAuthService.authenticate(
      reason: 'Use $_biometricLabel to unlock Calendar++.',
      allowDeviceCredential: false,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isUnlocking = false;
      if (unlocked) {
        _session = session;
        _lockedSession = null;
        _unlockMessage = null;
      } else {
        _unlockMessage =
            auto
                ? 'Unlock with $_biometricLabel when you are ready, or choose password login instead.'
                : '$_biometricLabel did not complete. You can try again or sign in with your password.';
      }
    });
  }

  Future<void> _usePasswordInstead() async {
    await SessionStorage.clearSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
      _lockedSession = null;
      _showLoginScreen = false;
      _unlockMessage = null;
    });
  }

  Future<void> _finishResetFlow() async {
    setState(() {
      _resetToken = null;
      _session = null;
      _lockedSession = null;
      _showLoginScreen = false;
      _unlockMessage = null;
      _isLoading = true;
    });
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    if (_resetToken != null) {
      return ResetPasswordScreen(
        token: _resetToken!,
        onDone: () {
          unawaited(_finishResetFlow());
        },
      );
    }

    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_session != null) {
      return CalendarScreen(initialSession: _session!);
    }

    if (_lockedSession != null) {
      return _buildLockedState();
    }

    if (_showLoginScreen) {
      return const LoginScreen();
    }

    return const LoginScreen();
  }

  Widget _buildLoadingState() {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildLockedState() {
    final unlockLabel = _biometricLabel.toLowerCase().contains('face')
        ? 'Unlock with Face ID'
        : _biometricLabel.toLowerCase().contains('fingerprint')
            ? 'Unlock with Fingerprint'
            : 'Unlock securely';

    return Scaffold(
      appBar: AppBar(title: const Text('Unlock Calendar++')),
      body: SafeArea(
        child: Container(
          decoration: AppTheme.backgroundDecoration(),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 42,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Saved session detected',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _unlockMessage ??
                              'Use $_biometricLabel to unlock your saved Calendar++ session.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isUnlocking ? null : _retryUnlock,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _isUnlocking
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(unlockLabel),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isUnlocking ? null : _usePasswordInstead,
                            child: const Text('Use password instead'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
