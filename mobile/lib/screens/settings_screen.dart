import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/account_settings.dart';
import '../models/user_model.dart';
import '../services/account_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/platform_runtime.dart';
import '../services/session_storage.dart';
import '../services/theme_service.dart';
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
  final ThemeService _themeService = ThemeService();
  static const int _maxAvatarBytes = 2 * 1024 * 1024;
  static const List<String> _reminderDeliveryOptions = [
    'email',
    'push',
    'both',
  ];
  static const XTypeGroup _avatarTypeGroup = XTypeGroup(
    label: 'images',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'heic', 'heif'],
  );
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  late UserSession _session;
  AccountSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRegenerating = false;
  bool _isRequestingEmailChange = false;
  bool _isExportingCalendar = false;
  final TextEditingController _newEmailController = TextEditingController();
  String _emailChangeFeedback = '';
  bool _reminderEnabled = false;
  bool _biometricAvailable = false;
  bool _biometricUnlockEnabled = false;
  bool _biometricLoginEnabled = false;
  String _biometricLabel = 'Face ID';
  String _reminderDelivery = 'email';
  int _reminderMinutesBefore = 30;
  String? _pendingAvatarDataUrl;
  bool _avatarMarkedForRemoval = false;
  static const List<int> _reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440];
  // Theme editor state
  Color _draftAccent = AppTheme.accent;
  String _draftPresetId = 'default';
  String _draftBackgroundPackageId = 'default';
  ThemeBackgroundMode _draftBackgroundMode = ThemeBackgroundMode.none;
  WeatherThemeKind _previewWeatherKind = WeatherThemeKind.clear;
  String _draftBgPath = '';
  BoxFit _draftBgFit = BoxFit.cover;

  Future<bool> _confirmBiometricSetup({
    required String reason,
    required String successMessage,
  }) async {
    final authenticated = await _biometricAuthService.authenticate(
      reason: reason,
      allowDeviceCredential: false,
    );
    if (authenticated) {
      return true;
    }
    if (!mounted) {
      return false;
    }

    final action = await showModalBottomSheet<_BiometricRecoveryAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _BiometricRecoverySheet(biometricLabel: _biometricLabel),
    );

    if (!mounted) {
      return false;
    }

    if (action == _BiometricRecoveryAction.retry) {
      final retried = await _biometricAuthService.authenticate(
        reason: reason,
        allowDeviceCredential: false,
      );
      if (!mounted) {
        return false;
      }
      if (retried) {
        _showSnackBar(successMessage);
        return true;
      }
    } else if (action == _BiometricRecoveryAction.settings) {
      await Geolocator.openAppSettings();
      if (!mounted) {
        return false;
      }
      _showSnackBar(
        'System settings opened. Enable $_biometricLabel access there, then try again.',
      );
      await _loadBiometricSettings();
      return false;
    }

    _showSnackBar(
      '$_biometricLabel setup did not complete. You can try again anytime from Settings.',
    );
    return false;
  }

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _load();
    _loadBiometricSettings();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    await _themeService.load();
    if (!mounted) return;
    final t = _themeService.current;
    setState(() {
      _draftAccent = t.accentColor;
      _draftPresetId = t.presetId;
      _draftBackgroundPackageId = t.backgroundPackageId;
      _draftBackgroundMode = t.backgroundMode;
      _previewWeatherKind = _themeService.activeWeatherKind;
      _draftBgPath = t.backgroundImagePath ?? '';
      _draftBgFit = t.backgroundFit;
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _newEmailController.dispose();
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
      _pendingAvatarDataUrl = null;
      _avatarMarkedForRemoval = false;
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
      final authenticated = await _confirmBiometricSetup(
        reason:
            'Use $_biometricLabel to require biometric unlock for Calendar++.',
        successMessage: '$_biometricLabel unlock enabled.',
      );
      if (!authenticated) {
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
    if (!enabled) {
      _showSnackBar('$_biometricLabel unlock disabled.');
    }
  }

  Future<void> _setBiometricLogin(bool enabled) async {
    if (enabled) {
      final authenticated = await _confirmBiometricSetup(
        reason: 'Use $_biometricLabel to enable faster sign in for Calendar++.',
        successMessage: '$_biometricLabel sign in enabled.',
      );
      if (!authenticated) {
        return;
      }
    }
    await SessionStorage.setBiometricLoginEnabled(enabled);
    if (enabled) {
      await SessionStorage.saveBiometricLoginSession(_session);
    } else {
      await SessionStorage.clearBiometricLoginSession();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricLoginEnabled = enabled;
    });
    if (!enabled) {
      _showSnackBar('$_biometricLabel sign in disabled.');
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
    });
    try {
      final avatarDataUrl =
          _pendingAvatarDataUrl ?? (_avatarMarkedForRemoval ? '' : null);
      final result = await _accountService.saveSettings(
        session: _session,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        reminderEnabled: _reminderEnabled,
        reminderMinutesBefore: _reminderMinutesBefore,
        reminderDelivery: _reminderDelivery,
        avatarDataUrl: avatarDataUrl,
      );
      if (!mounted) return;
      _session = result.session;
      _settings = result.settings;
      _pendingAvatarDataUrl = null;
      _avatarMarkedForRemoval = false;
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

  /// On iOS/Android, show a bottom sheet to pick camera or gallery via image_picker.
  /// On other platforms, fall back to file_selector.
  Future<void> _pickAvatar() async {
    if (isNativeMobile) {
      await _pickAvatarMobile();
    } else {
      await _pickAvatarDesktop();
    }
  }

  Future<void> _pickAvatarMobile() async {
    // Show action sheet to let user choose camera or gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxAvatarBytes) {
        if (!mounted) return;
        _showSnackBar('Profile picture must be 2 MB or smaller.');
        return;
      }

      final extension = _fileExtension(picked.name).toLowerCase();
      final mime = _mimeTypeForExtension(extension.isNotEmpty ? extension : 'jpg');
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      if (!mounted) return;
      setState(() {
        _pendingAvatarDataUrl = dataUrl;
        _avatarMarkedForRemoval = false;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Could not read the selected image.');
    }
  }

  Future<void> _pickAvatarDesktop() async {
    try {
      final file = await openFile(acceptedTypeGroups: [_avatarTypeGroup]);
      if (file == null) {
        return;
      }

      final extension = _fileExtension(file.name);
      if (!const {
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'avif',
        'heic',
        'heif',
      }.contains(extension)) {
        _showSnackBar('Profile picture must be PNG, JPEG, GIF, WEBP, AVIF, HEIC, or HEIF.');
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.length > _maxAvatarBytes) {
        _showSnackBar('Profile picture must be 2 MB or smaller.');
        return;
      }

      final dataUrl = 'data:${_mimeTypeForExtension(extension)};base64,${base64Encode(bytes)}';
      setState(() {
        _pendingAvatarDataUrl = dataUrl;
        _avatarMarkedForRemoval = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Could not read the selected image.');
    }
  }

  void _removeAvatarImage() {
    setState(() {
      _pendingAvatarDataUrl = null;
      _avatarMarkedForRemoval = true;
    });
  }

  Uint8List? _avatarBytes(String? dataUrl) {
    final value = dataUrl?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }

    final commaIndex = value.indexOf(',');
    if (commaIndex < 0 || commaIndex + 1 >= value.length) {
      return null;
    }

    try {
      return base64Decode(value.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  String _currentAvatarDataUrl() {
    if (_pendingAvatarDataUrl != null) {
      return _pendingAvatarDataUrl!;
    }
    if (_avatarMarkedForRemoval) {
      return '';
    }
    return _settings?.avatarUrl ?? '';
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _mimeTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'avif':
        return 'image/avif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'application/octet-stream';
    }
  }

  Widget _buildAvatarFallback(String avatarLabel) {
    return Center(
      child: Text(
        _initialsForName(avatarLabel),
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildAvatarPreview({
    required String avatarSource,
    required String avatarLabel,
  }) {
    final avatarBytes = _avatarBytes(avatarSource);
    final uri = Uri.tryParse(avatarSource);
    final isNetworkImage =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    Widget child;
    if (avatarBytes != null) {
      child = Image.memory(
        avatarBytes,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildAvatarFallback(avatarLabel),
      );
    } else if (isNetworkImage) {
      child = Image.network(
        avatarSource,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildAvatarFallback(avatarLabel),
      );
    } else {
      child = _buildAvatarFallback(avatarLabel);
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
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

  Future<void> _requestEmailChange() async {
    final nextEmail = _newEmailController.text.trim();
    if (nextEmail.isEmpty) return;
    setState(() {
      _isRequestingEmailChange = true;
      _emailChangeFeedback = '';
    });
    try {
      final result = await _accountService.requestEmailChange(
        session: _session,
        nextEmail: nextEmail,
      );
      if (!mounted) return;
      _session = result.session;
      widget.onSessionUpdated(_session);
      _newEmailController.clear();
      setState(() {
        _emailChangeFeedback = result.message;
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _emailChangeFeedback = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingEmailChange = false;
        });
      }
    }
  }

  Future<void> _exportCalendar() async {
    setState(() {
      _isExportingCalendar = true;
    });
    try {
      final result = await _accountService.exportCalendar(session: _session);
      if (!mounted) return;
      _session = result.session;
      widget.onSessionUpdated(_session);
      if (result.icsContent.isEmpty) {
        _showSnackBar('No calendar data to export.');
        return;
      }
      if (!mounted) return;
      final shareFile = await _buildCalendarExportFile(
        result.icsContent,
        result.filename,
      );
      await Share.shareXFiles(
        [shareFile],
        subject: result.filename,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isExportingCalendar = false;
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

  Future<XFile> _buildCalendarExportFile(
    String icsContent,
    String filename,
  ) async {
    if (kIsWeb) {
      return XFile.fromData(
        Uint8List.fromList(const Utf8Codec().encode(icsContent)),
        mimeType: 'text/calendar',
        name: filename,
      );
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(icsContent, encoding: const Utf8Codec());
    return XFile(file.path, mimeType: 'text/calendar', name: filename);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  // ── Appearance / Theme card ───────────────────────────────────────────────

  Future<void> _applyTheme() async {
    if (_draftPresetId == 'custom') {
      await _themeService.applyAccentColor(_draftAccent);
    } else {
      final preset = kPresetThemes.firstWhere(
        (p) => p.id == _draftPresetId,
        orElse: () => kPresetThemes.first,
      );
      await _themeService.applyPreset(preset);
    }
    await _themeService.applyBackgroundPackage(_draftBackgroundPackageId);
    await _themeService.applyBackgroundMode(_draftBackgroundMode);
    await _themeService.setStoredBackgroundImage(
      _draftBgPath.isEmpty ? null : _draftBgPath,
      _draftBgFit,
    );
    if (!mounted) return;
    _showSnackBar('Appearance saved.');
  }

  Future<void> _pickThemeBackground(ImageSource source) async {
    final path = await _themeService.pickBackgroundImage(source);
    if (path == null || !mounted) return;
    setState(() {
      _draftBgPath = path;
    });
  }

  Widget _buildAppearanceCard(BuildContext context) {
    final previewTheme = MobileTheme(
      presetId: _draftPresetId,
      backgroundPackageId: _draftBackgroundPackageId,
      accentColor: _draftAccent,
      backgroundMode: _draftBackgroundMode,
      backgroundImagePath: _draftBgPath.isEmpty ? null : _draftBgPath,
      backgroundFit: _draftBgFit,
    );
    final previewPackage = _themeService.presetById(_draftBackgroundPackageId);
    final previewImageProvider = _themeService.backgroundImageProvider(
      theme: previewTheme,
      previewWeatherKind: _previewWeatherKind,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Choose colors and background style.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text(
              'Theme package',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kPresetThemes.map((preset) {
                final isSelected = _draftBackgroundPackageId == preset.id;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _draftPresetId = preset.id;
                      _draftBackgroundPackageId = preset.id;
                      _draftAccent = preset.accentColor;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 90,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? preset.accentColor
                            : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 2 : 1.5,
                      ),
                      color: isSelected
                          ? preset.accentColor.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.03),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: preset.gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? preset.accentColor
                                : AppTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          preset.description,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Text(
                  'Accent color',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                for (final color in [
                  ...kPresetThemes.map((preset) => preset.accentColor),
                  const Color(0xFFFB7185),
                  const Color(0xFF38BDF8),
                  const Color(0xFFF97316),
                ])
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _draftAccent = color;
                        _draftPresetId = 'custom';
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(left: 5),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _draftAccent.toARGB32() == color.toARGB32()
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Background behavior',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ThemeBackgroundMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(mode.label),
                  selected: _draftBackgroundMode == mode,
                  onSelected: (_) {
                    setState(() {
                      _draftBackgroundMode = mode;
                    });
                  },
                );
              }).toList(),
            ),
            if (_draftBackgroundMode == ThemeBackgroundMode.none) ...[
              const SizedBox(height: 10),
              const Text(
                'No background image.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
            if (_draftBackgroundMode == ThemeBackgroundMode.weatherPackage) ...[
              const SizedBox(height: 12),
              Text(
                'Weather package: ${previewPackage.name}',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Preview weather type.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WeatherThemeKind.values.map((kind) {
                  return ChoiceChip(
                    label: Text(kind.label),
                    selected: _previewWeatherKind == kind,
                    onSelected: (_) {
                      setState(() {
                        _previewWeatherKind = kind;
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            if (_draftBackgroundMode == ThemeBackgroundMode.customImage) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Custom image',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (_draftBgPath.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _draftBgPath = '';
                      }),
                      child: const Text(
                        'Remove',
                        style: TextStyle(color: AppTheme.danger, fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      image: _draftBgPath.isNotEmpty
                          ? (() {
                              final imageProvider = _themeService
                                  .imageProviderForPath(_draftBgPath);
                              if (imageProvider == null) {
                                return null;
                              }

                              return DecorationImage(
                                image: imageProvider,
                                fit: _draftBgFit,
                                onError: (error, stackTrace) {},
                              );
                            })()
                          : null,
                    ),
                    child: _draftBgPath.isEmpty
                        ? const Center(
                            child: Text(
                              'None',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                          ),
                          label: const Text(
                            'Gallery',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () =>
                              _pickThemeBackground(ImageSource.gallery),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: const Text(
                            'Camera',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () =>
                              _pickThemeBackground(ImageSource.camera),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_draftBgPath.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<BoxFit>(
                  initialValue: _draftBgFit,
                  decoration: const InputDecoration(labelText: 'Image fit'),
                  items: const [
                    DropdownMenuItem(
                      value: BoxFit.cover,
                      child: Text('Cover (fill & crop)'),
                    ),
                    DropdownMenuItem(
                      value: BoxFit.contain,
                      child: Text('Contain (show full image)'),
                    ),
                    DropdownMenuItem(
                      value: BoxFit.none,
                      child: Text('Center (no scaling)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _draftBgFit = value;
                    });
                  },
                ),
              ],
            ],
            const SizedBox(height: 16),
            Container(
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: previewPackage.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                image: previewImageProvider == null
                    ? null
                    : DecorationImage(
                        image: previewImageProvider,
                        fit: _draftBackgroundMode == ThemeBackgroundMode.customImage
                            ? _draftBgFit
                            : BoxFit.cover,
                        onError: (error, stackTrace) {},
                      ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _draftAccent,
                        foregroundColor: AppTheme.onColorFor(_draftAccent),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      child: const Text('Preview'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _draftBackgroundMode == ThemeBackgroundMode.weatherPackage
                            ? '${previewPackage.name} • ${_previewWeatherKind.label}'
                            : _draftBackgroundMode == ThemeBackgroundMode.customImage
                                ? 'Custom image'
                                : 'No image',
                        style: TextStyle(
                          color: _draftAccent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await _themeService.reset();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _draftPresetId = 'default';
                      _draftBackgroundPackageId = 'default';
                      _draftBackgroundMode = ThemeBackgroundMode.none;
                      _previewWeatherKind = WeatherThemeKind.clear;
                      _draftAccent = MobileTheme.defaultTheme.accentColor;
                      _draftBgPath = '';
                      _draftBgFit = BoxFit.cover;
                    });
                    _showSnackBar('Appearance reset to default.');
                  },
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _applyTheme,
                    child: const Text('Apply appearance'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final avatarDataUrl = _currentAvatarDataUrl();
    final avatarLabel = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();

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
                        Row(
                          children: [
                            _buildAvatarPreview(
                              avatarSource: avatarDataUrl,
                              avatarLabel: avatarLabel,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Profile picture',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'PNG, JPEG, GIF, WEBP, AVIF, HEIC, or HEIF up to 2 MB.',
                                    style: const TextStyle(color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _isSaving ? null : _pickAvatar,
                              child: const Text('Choose picture'),
                            ),
                            if (avatarDataUrl.isNotEmpty)
                              OutlinedButton(
                                onPressed: _isSaving ? null : _removeAvatarImage,
                                child: const Text('Remove picture'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(labelText: 'Current email'),
                          child: Text(_settings?.email ?? ''),
                        ),
                        if ((_settings?.pendingEmail ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.mark_email_unread_outlined, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Pending: ${_settings!.pendingEmail}',
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _newEmailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _requestEmailChange(),
                          decoration: const InputDecoration(
                            labelText: 'New email address',
                            hintText: 'Enter new email',
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: _isRequestingEmailChange ? null : _requestEmailChange,
                            child: Text(_isRequestingEmailChange ? 'Sending...' : 'Change email'),
                          ),
                        ),
                        if (_emailChangeFeedback.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _emailChangeFeedback,
                            style: TextStyle(
                              fontSize: 13,
                              color: _emailChangeFeedback.toLowerCase().contains('error') ||
                                      _emailChangeFeedback.toLowerCase().contains('could not') ||
                                      _emailChangeFeedback.toLowerCase().contains('invalid')
                                  ? Theme.of(context).colorScheme.error
                                  : AppTheme.textMuted,
                            ),
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
                                ? 'Offer $_biometricLabel on the signed-out login screen only. This does not control the app-unlock prompt above.'
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
                          initialValue:
                              _reminderDeliveryOptions.contains(
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
                              onPressed: _isRegenerating
                                  ? null
                                  : _regenerateFeed,
                              child: Text(
                                _isRegenerating
                                    ? 'Regenerating...'
                                    : 'Regenerate',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isExportingCalendar ? null : _exportCalendar,
                              icon: const Icon(Icons.download_outlined, size: 16),
                              label: Text(
                                _isExportingCalendar ? 'Exporting...' : 'Export .ics',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildAppearanceCard(context),
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

  String _initialsForName(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'U';
    }
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

enum _BiometricRecoveryAction { retry, settings }

class _BiometricRecoverySheet extends StatelessWidget {
  const _BiometricRecoverySheet({required this.biometricLabel});

  final String biometricLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
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
            'If you dismissed or denied the biometric prompt earlier, you can try again now. If the system keeps blocking it, open system settings and allow $biometricLabel for Calendar++ first.',
            style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _BiometricRecoveryAction.retry),
              child: Text('Try $biometricLabel again'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, _BiometricRecoveryAction.settings),
              child: const Text('Open system settings'),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
          ),
        ],
      ),
    );
  }
}
