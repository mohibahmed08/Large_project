import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/session_storage.dart';
import '../theme/app_theme.dart';
import 'calendar_screen.dart';

// ── Post-login biometric sign-in prompt ────────────────────────────────────
/// Shows a bottom sheet prompting the user to enable biometric sign-in
/// on the login screen only. Only shown when neither biometric mode
/// is already enabled.
Future<void> maybeSuggestBiometricSetup(
  BuildContext context, {
  required UserSession session,
}) async {
  final biometricService = BiometricAuthService();
  final status = await biometricService.getStatus();
  if (!status.supported) return;

  final biometricUnlockEnabled =
      await SessionStorage.isBiometricUnlockEnabled();
  final biometricLoginEnabled =
      await SessionStorage.isBiometricLoginEnabled();
  if (biometricUnlockEnabled || biometricLoginEnabled) return;

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BiometricSetupSheet(
      biometricLabel: status.label,
      session: session,
    ),
  );
}

Future<bool> _confirmBiometricSetupFromPrompt({
  required BuildContext context,
  required BiometricAuthService biometricService,
  required String biometricLabel,
  required String reason,
  required String successMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final authenticated = await biometricService.authenticate(
    reason: reason,
    allowDeviceCredential: false,
  );
  if (authenticated) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }

  final action = await showModalBottomSheet<_PromptBiometricRecoveryAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _PromptBiometricRecoverySheet(
      biometricLabel: biometricLabel,
    ),
  );

  if (!context.mounted) {
    return false;
  }

  if (action == _PromptBiometricRecoveryAction.retry) {
    final retried = await biometricService.authenticate(
      reason: reason,
      allowDeviceCredential: false,
    );
    if (retried) {
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      return true;
    }
  } else if (action == _PromptBiometricRecoveryAction.settings) {
    await Geolocator.openAppSettings();
    if (!context.mounted) {
      return false;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'System settings opened. Enable $biometricLabel for Calendar++, then try again.',
        ),
      ),
    );
    return false;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '$biometricLabel setup did not complete. You can turn it on later from Settings.',
      ),
    ),
  );
  return false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _biometricAuthService = BiometricAuthService();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _showPassword = false;

  // Biometric sign-in state for the logged-out login screen.
  bool _biometricAvailable = false;
  bool _hasBiometricLoginSession = false;
  bool _biometricLoginEnabled = false;
  String _biometricLabel = 'Face ID';
  bool _autoBiometricAttempted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkBiometricAvailability());
  }

  Future<void> _checkBiometricAvailability() async {
    final token = await SessionStorage.readBiometricLoginToken();
    final hasBiometricLoginSession = token.isNotEmpty;
    final biometricLoginEnabled =
        await SessionStorage.isBiometricLoginEnabled();
    final status = await _biometricAuthService.getStatus();
    if (!mounted) return;
    setState(() {
      _hasBiometricLoginSession = hasBiometricLoginSession;
      _biometricAvailable = status.supported;
      _biometricLoginEnabled = biometricLoginEnabled;
      _biometricLabel = status.label;
    });

    if (hasBiometricLoginSession &&
        status.supported &&
        biometricLoginEnabled &&
        !_autoBiometricAttempted) {
      _autoBiometricAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_loginWithBiometrics(auto: true));
      });
    }
  }

  /// Attempt to sign in using the biometric-login token + biometric confirmation.
  Future<void> _loginWithBiometrics({bool auto = false}) async {
    if (_isLoading) return;

    final token = await SessionStorage.readBiometricLoginToken();
    if (token.isEmpty) {
      if (!auto) _showSnackBar('No saved Face ID sign-in session found.');
      return;
    }

    setState(() => _isLoading = true);

    final authenticated = await _biometricAuthService.authenticate(
      reason: 'Use $_biometricLabel to sign in to Calendar++.',
      allowDeviceCredential: false, // biometric-only — no passcode fallback
    );

    if (!mounted) return;

    if (authenticated) {
      try {
        final session = UserSession.fromAccessToken(token);
        await SessionStorage.saveSession(session);
        setState(() => _isLoading = false);
        _openCalendar(session);
      } catch (_) {
        await SessionStorage.clearBiometricLoginSession();
        setState(() => _isLoading = false);
        setState(() {
          _hasBiometricLoginSession = false;
        });
        _showSnackBar(
          'Saved Face ID sign-in session is invalid. Please sign in with your password.',
        );
      }
    } else {
      setState(() => _isLoading = false);
      if (!auto) {
        _showSnackBar('$_biometricLabel did not complete.');
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        final session = await _authService.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
        await SessionStorage.saveSession(session);
        if (await SessionStorage.isBiometricLoginEnabled()) {
          await SessionStorage.saveBiometricLoginSession(session);
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
        });
        _openCalendar(session);
        return;
      } else {
        await _authService.signup(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (!mounted) {
          return;
        }

        _showSnackBar(
          'Account created. Check your email to verify the account before logging in.',
        );
        setState(() {
          _isLogin = true;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              emailController.text.trim(),
            ),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    emailController.dispose();

    if (!mounted) {
      return;
    }

    final normalizedEmail = (email ?? '').trim();
    if (normalizedEmail.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.requestPasswordReset(normalizedEmail);
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'If an account exists for $normalizedEmail, a password reset link has been sent.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openCalendar(UserSession session) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (ctx) => _BiometricOnboardingWrapper(
          session: session,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _showBiometricButton =>
      _isLogin &&
      _biometricAvailable &&
      _hasBiometricLoginSession &&
      _biometricLoginEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar++')),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF23263A),
                AppTheme.background,
                AppTheme.surface,
              ],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Text(
                              'Calendar++',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceAlt.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _AuthTabButton(
                                    label: 'LOGIN',
                                    isSelected: _isLogin,
                                    onTap: () {
                                      setState(() {
                                        _isLogin = true;
                                      });
                                    },
                                  ),
                                  _AuthTabButton(
                                    label: 'REGISTER',
                                    isSelected: !_isLogin,
                                    onTap: () {
                                      setState(() {
                                        _isLogin = false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              _isLogin ? 'Welcome Back' : 'Create Account',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),

                          // ── Face ID / Touch ID quick-login ───────────────
                          if (_showBiometricButton) ...[
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () => _loginWithBiometrics(),
                                icon: Icon(
                                  _biometricLabel.toLowerCase().contains('face')
                                      ? Icons.face_unlock_outlined
                                      : Icons.fingerprint,
                                  color: AppTheme.accent,
                                ),
                                label: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    'Sign in with $_biometricLabel',
                                    style: const TextStyle(
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: AppTheme.accent.withValues(alpha: 0.5),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    'or sign in with password',
                                    style: TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                          ],

                          const SizedBox(height: 18),
                          if (!_isLogin) ...[
                            TextFormField(
                              controller: _firstNameController,
                              decoration: const InputDecoration(
                                labelText: 'First name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isLogin) {
                                  return null;
                                }
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your first name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Last name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isLogin) {
                                  return null;
                                }
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your last name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _showPassword = !_showPassword;
                                  });
                                },
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your password';
                              }
                              if (!_isLogin && value.length < 8) {
                                return 'Use at least 8 characters';
                              }
                              return null;
                            },
                          ),
                          if (_isLogin) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed:
                                    _isLoading ? null : _handleForgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                          ],
                          if (!_isLogin) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: !_showPassword,
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isLogin) {
                                  return null;
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _submit,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        _isLogin
                                            ? 'Login'
                                            : 'Create account',
                                      ),
                              ),
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
      ),
    );
  }
}

// ── Wrapper that shows the CalendarScreen then prompts for Face ID setup ──────
class _BiometricOnboardingWrapper extends StatefulWidget {
  const _BiometricOnboardingWrapper({required this.session});
  final UserSession session;

  @override
  State<_BiometricOnboardingWrapper> createState() =>
      _BiometricOnboardingWrapperState();
}

class _BiometricOnboardingWrapperState
    extends State<_BiometricOnboardingWrapper> {
  @override
  void initState() {
    super.initState();
    // Show the prompt shortly after the calendar appears so it feels natural.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          unawaited(
            maybeSuggestBiometricSetup(
              context,
              session: widget.session,
            ),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CalendarScreen(initialSession: widget.session);
  }
}

// ── Bottom sheet content ──────────────────────────────────────────────────────
class _BiometricSetupSheet extends StatelessWidget {
  const _BiometricSetupSheet({
    required this.biometricLabel,
    required this.session,
  });
  final String biometricLabel;
  final UserSession session;

  @override
  Widget build(BuildContext context) {
    final biometricService = BiometricAuthService();
    final faceIcon = biometricLabel.toLowerCase().contains('face')
        ? Icons.face_unlock_outlined
        : Icons.fingerprint;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 34),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(faceIcon, color: AppTheme.accent, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Show $biometricLabel on the login screen',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Use $biometricLabel as a sign-in option on the login screen only. This is separate from the app-unlock setting in Settings.',
            style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: Icon(faceIcon),
              label: Text('Enable $biometricLabel'),
              onPressed: () async {
                final authenticated = await _confirmBiometricSetupFromPrompt(
                  context: context,
                  biometricService: biometricService,
                  biometricLabel: biometricLabel,
                  reason:
                      'Use $biometricLabel to enable faster sign in for Calendar++.',
                  successMessage: '$biometricLabel sign in enabled.',
                );
                if (!context.mounted) {
                  return;
                }
                if (!authenticated) {
                  return;
                }
                await SessionStorage.setBiometricLoginEnabled(true);
                await SessionStorage.saveBiometricLoginSession(session);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$biometricLabel sign in enabled.'),
                  ),
                );
                Navigator.pop(context);
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Not now',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PromptBiometricRecoveryAction { retry, settings }

class _PromptBiometricRecoverySheet extends StatelessWidget {
  const _PromptBiometricRecoverySheet({
    required this.biometricLabel,
  });

  final String biometricLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 34),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Finish setting up $biometricLabel',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You can retry the system biometric prompt now. If you denied it before, open system settings and allow $biometricLabel for Calendar++ first.',
            style: const TextStyle(
              color: AppTheme.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _PromptBiometricRecoveryAction.retry,
              ),
              child: Text('Try $biometricLabel again'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(
                context,
                _PromptBiometricRecoveryAction.settings,
              ),
              child: const Text('Open system settings'),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Not now',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AuthTabButton extends StatelessWidget {
  const _AuthTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppTheme.accent : AppTheme.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
