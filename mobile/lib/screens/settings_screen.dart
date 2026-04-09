import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/account_settings.dart';
import '../models/user_model.dart';
import '../services/account_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/session_storage.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initialSession,
    required this.onSessionUpdated,
  });

  final UserSession initialSession;
  final ValueChanged<UserSession> onSessionUpdated;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AccountService _accountService = AccountService();
  final BiometricAuthService _biometricAuthService = BiometricAuthService();
  static const List<String> _reminderDeliveryOptions = [
    'email',
    'push',
    'both',
  ];
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  late UserSession _session;
  AccountSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRegenerating = false;
  bool _reminderEnabled = false;
  bool _biometricAvailable = false;
  bool _biometricUnlockEnabled = false;
  bool _biometricLoginEnabled = false;
  String _biometricLabel = 'Face ID';
  String _reminderDelivery = 'email';
  int _reminderMinutesBefore = 30;
  static const List<int> _reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440];

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _load();
    _loadBiometricSettings();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _accountService.getSettings(session: _session);
      if (!mounted) return;
      _session = result.session;
      widget.onSessionUpdated(_session);
      _settings = result.settings;
      _firstNameController.text = result.settings.firstName;
      _lastNameController.text = result.settings.lastName;
      _reminderEnabled = result.settings.reminderDefaults.reminderEnabled;
      _reminderMinutesBefore =
          result.settings.reminderDefaults.reminderMinutesBefore;
      _reminderDelivery = result.settings.reminderDefaults.reminderDelivery;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadBiometricSettings() async {
    final status = await _biometricAuthService.getStatus();
    final enabled = await SessionStorage.isBiometricUnlockEnabled();
    final loginEnabled = await SessionStorage.isBiometricLoginEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricAvailable = status.supported;
      _biometricLabel = status.label;
      _biometricUnlockEnabled = enabled && status.supported;
      _biometricLoginEnabled = loginEnabled && status.supported;
    });
  }

  Future<void> _setBiometricUnlock(bool enabled) async {
    if (enabled) {
      final authenticated = await _biometricAuthService.authenticate(
        reason:
            'Use $_biometricLabel to require biometric unlock for Calendar++.',
        allowDeviceCredential: false,
      );
      if (!authenticated) {
        if (mounted) {
          _showSnackBar('$_biometricLabel was not confirmed.');
        }
        return;
      }
    }
    await SessionStorage.setBiometricUnlockEnabled(enabled);
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricUnlockEnabled = enabled;
    });
    _showSnackBar(
      enabled
          ? '$_biometricLabel unlock enabled.'
          : '$_biometricLabel unlock disabled.',
    );
  }

  Future<void> _setBiometricLogin(bool enabled) async {
    if (enabled) {
      final authenticated = await _biometricAuthService.authenticate(
        reason: 'Use $_biometricLabel to enable faster sign in for Calendar++.',
        allowDeviceCredential: false,
      );
      if (!authenticated) {
        if (mounted) {
          _showSnackBar('$_biometricLabel was not confirmed.');
        }
        return;
      }
    }
    await SessionStorage.setBiometricLoginEnabled(enabled);
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricLoginEnabled = enabled;
    });
    _showSnackBar(
      enabled
          ? '$_biometricLabel sign in enabled.'
          : '$_biometricLabel sign in disabled.',
    );
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
    });
    try {
      final result = await _accountService.saveSettings(
        session: _session,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        reminderEnabled: _reminderEnabled,
        reminderMinutesBefore: _reminderMinutesBefore,
        reminderDelivery: _reminderDelivery,
      );
      if (!mounted) return;
      _session = result.session;
      _settings = result.settings;
      widget.onSessionUpdated(_session);
      _showSnackBar('Settings saved.');
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _regenerateFeed() async {
    setState(() {
      _isRegenerating = true;
    });
    try {
      final result = await _accountService.regenerateFeed(session: _session);
      if (!mounted) return;
      _session = result.session;
      _settings = result.settings;
      widget.onSessionUpdated(_session);
      _showSnackBar('Feed link regenerated.');
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isRegenerating = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard(String value, String label) async {
    if (value.trim().isEmpty) {
      _showSnackBar('$label is not available yet.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showSnackBar('$label copied.');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _reminderLabel(int minutes) {
    if (minutes == 0) return 'At time of event';
    if (minutes == 60) return '1 hour before';
    if (minutes == 1440) return '1 day before';
    if (minutes > 60 && minutes % 60 == 0) {
      return '${minutes ~/ 60} hours before';
    }
    return '$minutes minutes before';
  }

  String _reminderDeliveryLabel(String value) {
    switch (value) {
      case 'push':
        return 'Push only';
      case 'both':
        return 'Email and push';
      case 'email':
      default:
        return 'Email only';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _firstNameController,
                          decoration:
                              const InputDecoration(labelText: 'First name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _lastNameController,
                          decoration:
                              const InputDecoration(labelText: 'Last name'),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(labelText: 'Email'),
                          child: Text(_settings?.email ?? ''),
                        ),
                        if ((_settings?.pendingEmail ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Pending email: ${_settings!.pendingEmail}',
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App security',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Use $_biometricLabel to unlock'),
                          subtitle: Text(
                            _biometricAvailable
                                ? 'Require $_biometricLabel before opening your saved session.'
                                : 'Biometric unlock becomes available on supported phones.',
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          value: _biometricUnlockEnabled,
                          onChanged: _biometricAvailable
                              ? (value) {
                                  _setBiometricUnlock(value);
                                }
                              : null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Show $_biometricLabel on login'),
                          subtitle: Text(
                            _biometricAvailable
                                ? 'Offer $_biometricLabel as a quick sign-in option when a saved session exists.'
                                : 'Biometric sign in becomes available on supported phones.',
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          value: _biometricLoginEnabled,
                          onChanged: _biometricAvailable
                              ? (value) {
                                  _setBiometricLogin(value);
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reminder defaults',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable reminders by default'),
                          value: _reminderEnabled,
                          onChanged: (value) {
                            setState(() {
                              _reminderEnabled = value;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue:
                              _reminderOptions.contains(_reminderMinutesBefore)
                                  ? _reminderMinutesBefore
                                  : 30,
                          onChanged: _reminderEnabled
                              ? (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _reminderMinutesBefore = value;
                                  });
                                }
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Default reminder timing',
                          ),
                          items: _reminderOptions
                              .map(
                                (minutes) => DropdownMenuItem<int>(
                                  value: minutes,
                                  child: Text(_reminderLabel(minutes)),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _reminderDeliveryOptions.contains(
                                _reminderDelivery,
                              )
                              ? _reminderDelivery
                              : 'email',
                          onChanged: _reminderEnabled
                              ? (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _reminderDelivery = value;
                                  });
                                }
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Reminder delivery',
                          ),
                          items: _reminderDeliveryOptions
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(_reminderDeliveryLabel(value)),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calendar feed',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _settings?.calendarFeedUrl ?? '',
                          style: const TextStyle(color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () => _copyToClipboard(
                                _settings?.calendarFeedUrl ?? '',
                                'Feed URL',
                              ),
                              child: const Text('Copy feed URL'),
                            ),
                            OutlinedButton(
                              onPressed: () => _copyToClipboard(
                                _settings?.calendarFeedWebcalUrl ?? '',
                                'Webcal link',
                              ),
                              child: const Text('Copy webcal'),
                            ),
                            OutlinedButton(
                              onPressed:
                                  _isRegenerating ? null : _regenerateFeed,
                              child: Text(
                                _isRegenerating
                                    ? 'Regenerating...'
                                    : 'Regenerate',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Saving...' : 'Save changes'),
        ),
      ),
    );
  }
}
