import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  static const int _maxAvatarBytes = 12 * 1024 * 1024;
  static const int _maxThemeImageBytes = 12 * 1024 * 1024;
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
  Color _draftAccent = AppTheme.accent;
  String _draftPresetId = 'mobile-default';
  String _draftBackgroundPackageId = 'mobile-default';
  ThemeBackgroundMode _draftBackgroundMode = ThemeBackgroundMode.none;
  WeatherThemeKind _previewWeatherKind = WeatherThemeKind.clear;
  String _draftBgPath = '';
  BoxFit _draftBgFit = BoxFit.cover;
  Map<String, String> _draftSceneImages = <String, String>{};
  final TextEditingController _themeImportController = TextEditingController();

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
      _draftSceneImages = Map<String, String>.from(t.images);
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _newEmailController.dispose();
    _themeImportController.dispose();
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
      await _themeService.mergeAccountThemePacks(result.settings.customThemes);
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
      String? avatarUrl;
      if (_pendingAvatarDataUrl != null) {
        final upload = await _accountService.uploadImage(
          session: _session,
          imageDataUrl: _pendingAvatarDataUrl!,
          purpose: 'avatars',
          fileName: 'avatar.png',
        );
        _session = upload.session;
        avatarUrl = upload.imageUrl;
      } else if (_avatarMarkedForRemoval) {
        avatarUrl = '';
      }
      final result = await _accountService.saveSettings(
        session: _session,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        reminderEnabled: _reminderEnabled,
        reminderMinutesBefore: _reminderMinutesBefore,
        reminderDelivery: _reminderDelivery,
        avatarUrl: avatarUrl,
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
        _showSnackBar('Profile picture must be 12 MB or smaller.');
        return;
      }

      final extension = _fileExtension(picked.name).toLowerCase();
      final mime = _mimeTypeForExtension(
        extension.isNotEmpty ? extension : 'jpg',
      );
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
        _showSnackBar(
          'Profile picture must be PNG, JPEG, GIF, WEBP, AVIF, HEIC, or HEIF.',
        );
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.length > _maxAvatarBytes) {
        _showSnackBar('Profile picture must be 12 MB or smaller.');
        return;
      }

      final dataUrl =
          'data:${_mimeTypeForExtension(extension)};base64,${base64Encode(bytes)}';
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
      await Share.shareXFiles([shareFile], subject: result.filename);
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
    final previewPackage = _themeService.presetById(_draftBackgroundPackageId);
    await _themeService.applyThemePack(
      _draftPreviewTheme.copyWith(
        name: previewPackage.name,
        description: previewPackage.description,
        gradient: previewPackage.gradient,
        galleryImages: previewPackage.galleryImages,
        selectedGalleryImage: previewPackage.selectedGalleryImage,
        preview: previewPackage.preview,
        previewImage: previewPackage.previewImage,
        source: _draftPresetId == 'custom' ? 'user' : previewPackage.source,
      ),
    );
    if (!mounted) return;
    _showSnackBar('Appearance saved.');
  }

  Future<void> _pickThemeBackground(ImageSource source) async {
    final path = await _pickAndUploadThemeImage(
      source,
      fileNamePrefix: 'theme-background',
    );
    if (path == null || !mounted) return;
    setState(() {
      _draftBgPath = path;
    });
  }

  Future<void> _pickThemeSceneBackground(
    ThemeSceneSlot slot,
    ImageSource source,
  ) async {
    final path = await _pickAndUploadThemeImage(
      source,
      fileNamePrefix: slot.key,
    );
    if (path == null || !mounted) return;
    setState(() {
      _draftSceneImages = Map<String, String>.from(_draftSceneImages)
        ..[slot.key] = path;
    });
  }

  Future<String?> _pickAndUploadThemeImage(
    ImageSource source, {
    required String fileNamePrefix,
  }) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 84,
      );
      if (picked == null) {
        return null;
      }

      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxThemeImageBytes) {
        if (mounted) {
          _showSnackBar('Theme image must be 12 MB or smaller.');
        }
        return null;
      }

      final rawExtension = _fileExtension(picked.name);
      final extension = rawExtension.isEmpty ? 'jpg' : rawExtension;
      final mimeType = _mimeTypeForExtension(extension);
      if (!mimeType.startsWith('image/')) {
        if (mounted) {
          _showSnackBar(
            'Theme image must be PNG, JPEG, GIF, WEBP, AVIF, HEIC, or HEIF.',
          );
        }
        return null;
      }

      final upload = await _accountService.uploadImage(
        session: _session,
        imageDataUrl: 'data:$mimeType;base64,${base64Encode(bytes)}',
        purpose: 'theme-backgrounds',
        fileName: '$fileNamePrefix.$extension',
      );
      _session = upload.session;
      widget.onSessionUpdated(_session);
      return upload.imageUrl;
    } catch (error) {
      if (mounted) {
        _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
      }
      return null;
    }
  }

  List<Color> _dynamicAccentChoices(BuildContext context, Color seedColor) {
    final layoutWidth = MediaQuery.of(context).size.width - 32;
    final columns = (layoutWidth / 52).floor().clamp(5, 8);
    final targetCount = columns * 2;
    final colors = <Color>[seedColor, ...kThemeAccentSwatches];
    final seedHsl = HSLColor.fromColor(seedColor);
    final generated = <Color>[
      seedHsl
          .withLightness((seedHsl.lightness + 0.18).clamp(0.18, 0.82))
          .toColor(),
      seedHsl
          .withLightness((seedHsl.lightness - 0.18).clamp(0.18, 0.82))
          .toColor(),
      seedHsl.withHue((seedHsl.hue + 24) % 360).toColor(),
      seedHsl.withHue((seedHsl.hue + 330) % 360).toColor(),
      seedHsl
          .withSaturation((seedHsl.saturation + 0.14).clamp(0.18, 1.0))
          .toColor(),
      seedHsl
          .withSaturation((seedHsl.saturation - 0.18).clamp(0.18, 1.0))
          .toColor(),
      seedHsl
          .withLightness((seedHsl.lightness + 0.28).clamp(0.18, 0.84))
          .toColor(),
      seedHsl
          .withLightness((seedHsl.lightness - 0.28).clamp(0.16, 0.82))
          .toColor(),
    ];

    for (final color in generated) {
      if (!colors.any((existing) => existing.toARGB32() == color.toARGB32())) {
        colors.add(color);
      }
      if (colors.length >= targetCount) {
        break;
      }
    }

    return colors.take(targetCount).toList();
  }

  Widget _buildAccentSwatchButton({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.18),
            width: isSelected ? 2.4 : 1.2,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }

  Widget _buildSceneImageEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Custom weather pack',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Set a different image for each weather/time scene.',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        ...ThemeSceneSlot.values.map((slot) {
          final imagePath = _draftSceneImages[slot.key]?.trim() ?? '';
          final imageProvider = imagePath.isEmpty
              ? null
              : _themeService.imageProviderForPath(imagePath);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 84,
                      height: 62,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withValues(alpha: 0.06),
                        image: imageProvider == null
                            ? null
                            : DecorationImage(
                                image: imageProvider,
                                fit: BoxFit.cover,
                                onError: (error, stackTrace) {},
                              ),
                      ),
                      child: imageProvider == null
                          ? const Icon(
                              Icons.image_outlined,
                              color: AppTheme.textMuted,
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
                            onPressed: () => _pickThemeSceneBackground(
                              slot,
                              ImageSource.gallery,
                            ),
                            icon: const Icon(
                              Icons.photo_library_outlined,
                              size: 16,
                            ),
                            label: const Text('Gallery'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pickThemeSceneBackground(
                              slot,
                              ImageSource.camera,
                            ),
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                            ),
                            label: const Text('Camera'),
                          ),
                          if (imagePath.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _draftSceneImages = Map<String, String>.from(
                                    _draftSceneImages,
                                  )..remove(slot.key);
                                });
                              },
                              child: const Text(
                                'Remove',
                                style: TextStyle(color: AppTheme.danger),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  MobileTheme get _draftPreviewTheme {
    final previewPackage = _themeService.presetById(_draftBackgroundPackageId);
    final resolvedImages = switch (_draftBackgroundMode) {
      ThemeBackgroundMode.customImage => {
        ...previewPackage.images,
        'universal': _draftBgPath,
      }..removeWhere((key, value) => value.trim().isEmpty),
      ThemeBackgroundMode.perScene || ThemeBackgroundMode.weatherPackage => {
        ...previewPackage.images,
        ..._draftSceneImages,
      }..removeWhere((key, value) => value.trim().isEmpty),
      _ => Map<String, String>.from(
        _draftSceneImages,
      )..removeWhere((key, value) => value.trim().isEmpty),
    };

    return MobileTheme(
      presetId: _draftPresetId,
      backgroundPackageId: _draftBackgroundPackageId,
      accentColor: _draftAccent,
      backgroundMode: _draftBackgroundMode,
      backgroundImagePath: _draftBgPath.isEmpty ? null : _draftBgPath,
      backgroundFit: _draftBgFit,
      images: resolvedImages,
      gradient: previewPackage.gradient,
      galleryImages: previewPackage.galleryImages,
      selectedGalleryImage: previewPackage.selectedGalleryImage,
      preview: previewPackage.preview,
      previewImage: previewPackage.previewImage,
      name: previewPackage.name,
      description: previewPackage.description,
      source: _draftPresetId == 'custom' ? 'user' : previewPackage.source,
    );
  }

  Future<void> _resetThemeDraft() async {
    await _themeService.reset();
    if (!mounted) {
      return;
    }
    setState(() {
      _draftPresetId = MobileTheme.defaultTheme.id;
      _draftBackgroundPackageId = MobileTheme.defaultTheme.id;
      _draftBackgroundMode = ThemeBackgroundMode.none;
      _previewWeatherKind = WeatherThemeKind.clear;
      _draftAccent = MobileTheme.defaultTheme.accentColor;
      _draftBgPath = '';
      _draftBgFit = BoxFit.cover;
      _draftSceneImages = <String, String>{};
    });
    _showSnackBar('Appearance reset to default.');
  }

  bool _isValidThemeSlug(String value) {
    final slug = value.trim().toLowerCase();
    return RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$').hasMatch(slug);
  }

  String _suggestThemeSlug(MobileTheme theme) {
    final existing = theme.shareSlug?.trim().toLowerCase() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final normalized = theme.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isEmpty) {
      return 'calendar-theme';
    }
    return normalized.length > 32 ? normalized.substring(0, 32) : normalized;
  }

  Widget _buildFeaturedWeatherThemesCard(BuildContext context) {
    final featuredThemes = <MobileTheme>[...kPresetThemes, ...kFeaturedThemes];
    final selectedTheme = _themeService.presetById(_draftBackgroundPackageId);
    final backgroundModes = <ThemeBackgroundMode>[
      ThemeBackgroundMode.none,
      ThemeBackgroundMode.weatherPackage,
      ThemeBackgroundMode.perScene,
      ThemeBackgroundMode.customImage,
    ];

    Widget buildThemeTile(MobileTheme theme) {
      final isSelected =
          (_draftBackgroundPackageId == theme.id) ||
          (_draftBackgroundPackageId == theme.packId);
      final previewImage = _themeService.backgroundImageProvider(
        theme: theme,
        previewWeatherKind: WeatherThemeKind.clear,
      );
      final previewColors = theme.gradientColors.length >= 2
          ? theme.gradientColors
          : MobileTheme.defaultTheme.gradientColors;
      return SizedBox(
        width: 172,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _draftPresetId = theme.id;
              _draftBackgroundPackageId = theme.packId ?? theme.id;
              _draftAccent = theme.accentColor;
              _draftBackgroundMode = ThemeBackgroundMode.weatherPackage;
              _draftBgPath = '';
              _draftSceneImages = Map<String, String>.from(theme.images);
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Colors.white.withValues(alpha: isSelected ? 0.08 : 0.04),
              border: Border.all(
                color: isSelected
                    ? theme.accentColor
                    : Colors.white.withValues(alpha: 0.10),
                width: isSelected ? 2 : 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: previewColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    image: previewImage == null
                        ? null
                        : DecorationImage(
                            image: previewImage,
                            fit: BoxFit.cover,
                            onError: (error, stackTrace) {},
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  theme.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? theme.accentColor
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  theme.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Featured Weather Photo Themes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Match the desktop theme browser, tuned for a phone-sized layout. Mobile defaults to no background unless you pick a photo pack.',
              style: TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('No background'),
                  selected: _draftBackgroundMode == ThemeBackgroundMode.none,
                  onSelected: (_) {
                    setState(() {
                      _draftBackgroundMode = ThemeBackgroundMode.none;
                      _draftBackgroundPackageId = MobileTheme.defaultTheme.id;
                      _draftPresetId = MobileTheme.defaultTheme.id;
                      _draftBgPath = '';
                      _draftSceneImages = <String, String>{};
                    });
                  },
                ),
                if (_draftBackgroundPackageId != MobileTheme.defaultTheme.id)
                  ChoiceChip(
                    label: Text(selectedTheme.name),
                    selected: _draftBackgroundMode != ThemeBackgroundMode.none,
                    onSelected: (_) {},
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) =>
                    buildThemeTile(featuredThemes[index]),
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemCount: featuredThemes.length,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Accent color',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final accentChoices = _dynamicAccentChoices(
                  context,
                  selectedTheme.accentColor,
                );
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: accentChoices.map((color) {
                    final isSelected =
                        _draftAccent.toARGB32() == color.toARGB32();
                    return _buildAccentSwatchButton(
                      color: color,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _draftAccent = color;
                          _draftPresetId = 'custom';
                        });
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            const Text(
              'Background style',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: backgroundModes.map((mode) {
                final label = switch (mode) {
                  ThemeBackgroundMode.perScene => 'Custom weather pack',
                  _ => mode.label,
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: _draftBackgroundMode == mode,
                  onSelected: (_) {
                    setState(() {
                      _draftBackgroundMode = mode;
                    });
                  },
                );
              }).toList(),
            ),
            if (_draftBackgroundMode == ThemeBackgroundMode.perScene)
              _buildSceneImageEditor(),
            if (_draftBackgroundMode == ThemeBackgroundMode.weatherPackage ||
                _draftBackgroundMode == ThemeBackgroundMode.perScene) ...[
              const SizedBox(height: 14),
              Text(
                'Preview weather scene',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Custom image',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  if (_draftBgPath.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _draftBgPath = '';
                      }),
                      child: const Text(
                        'Remove',
                        style: TextStyle(color: AppTheme.danger),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 420;
                  final previewThumb = Container(
                    width: stacked ? double.infinity : 108,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      image: _draftBgPath.isEmpty
                          ? null
                          : (() {
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
                            })(),
                    ),
                    child: _draftBgPath.isEmpty
                        ? const Center(
                            child: Text(
                              'No image selected',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          )
                        : null,
                  );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickThemeBackground(ImageSource.gallery),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 16,
                        ),
                        label: const Text('Gallery'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickThemeBackground(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                        label: const Text('Camera'),
                      ),
                    ],
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        previewThumb,
                        const SizedBox(height: 12),
                        actions,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      previewThumb,
                      const SizedBox(width: 12),
                      Expanded(child: actions),
                    ],
                  );
                },
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
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context) {
    final previewTheme = _draftPreviewTheme;
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
            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Live mobile preview of the current Calendar++ theme draft.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              height: 168,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: previewPackage.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                image: previewImageProvider == null
                    ? null
                    : DecorationImage(
                        image: previewImageProvider,
                        fit:
                            _draftBackgroundMode ==
                                ThemeBackgroundMode.customImage
                            ? _draftBgFit
                            : BoxFit.cover,
                        onError: (error, stackTrace) {},
                      ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.52),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      previewPackage.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _draftBackgroundMode == ThemeBackgroundMode.weatherPackage
                          ? '${_previewWeatherKind.label} scene preview'
                          : _draftBackgroundMode ==
                                ThemeBackgroundMode.customImage
                          ? 'Custom photo background'
                          : _draftBackgroundMode.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _draftAccent,
                            foregroundColor: AppTheme.onColorFor(_draftAccent),
                          ),
                          child: const Text('Preview'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            previewPackage.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _resetThemeDraft,
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

  Future<void> _importSharedThemeFromSettings() async {
    final value = _themeImportController.text.trim();
    if (value.isEmpty) {
      _showSnackBar('Paste a share link or theme code first.');
      return;
    }
    try {
      final result = await _themeService.importSharedTheme(_session, value);
      _session = result.session;
      widget.onSessionUpdated(_session);
      _themeImportController.clear();
      await _loadTheme();
      _showSnackBar('Imported "${result.theme.name}" and applied it.');
    } catch (error) {
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _shareThemePack(BuildContext context, MobileTheme theme) async {
    final box = context.findRenderObject() as RenderBox?;
    MobileTheme shareTheme = theme;
    if ((shareTheme.shareUrl ?? '').trim().isEmpty &&
        (shareTheme.shareCode ?? '').trim().isEmpty) {
      final result = await _themeService.saveSharedTheme(_session, shareTheme);
      _session = result.session;
      widget.onSessionUpdated(_session);
      shareTheme = result.theme;
      await _loadTheme();
    }
    if (!mounted) return;
    await Share.share(
      'Check out this Calendar++ theme: ${shareTheme.name}'
      '${(shareTheme.shareCode ?? '').trim().isNotEmpty ? ' (${shareTheme.shareCode})' : ''}'
      '${(shareTheme.shareUrl ?? '').trim().isNotEmpty ? ' ${shareTheme.shareUrl}' : ''}',
      subject: 'Calendar++ theme: ${shareTheme.name}',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _openThemeShareSheet(MobileTheme theme) async {
    MobileTheme shareTheme = theme;
    if ((shareTheme.shareUrl ?? '').trim().isEmpty &&
        (shareTheme.shareCode ?? '').trim().isEmpty) {
      final result = await _themeService.saveSharedTheme(_session, shareTheme);
      _session = result.session;
      widget.onSessionUpdated(_session);
      shareTheme = result.theme;
      await _loadTheme();
    }
    final slugController = TextEditingController(
      text: _suggestThemeSlug(shareTheme),
    );
    Timer? slugDebounce;
    String mode = 'qr';
    bool isSavingSlug = false;
    bool isCheckingSlug = false;
    bool? isSlugAvailable;
    String slugMessage = '';

    if (!mounted) {
      slugController.dispose();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> refreshShare({
              String? shareSlug,
              bool announceSaved = false,
            }) async {
              setSheetState(() {
                isSavingSlug = true;
              });
              try {
                final result = await _themeService.saveSharedTheme(
                  _session,
                  shareTheme,
                  shareSlug: shareSlug,
                );
                _session = result.session;
                widget.onSessionUpdated(_session);
                shareTheme = result.theme;
                slugController.value = TextEditingValue(
                  text: _suggestThemeSlug(shareTheme),
                  selection: TextSelection.collapsed(
                    offset: _suggestThemeSlug(shareTheme).length,
                  ),
                );
                await _loadTheme();
                if (!mounted) {
                  return;
                }
                setSheetState(() {
                  isSavingSlug = false;
                  isSlugAvailable = shareSlug == null ? isSlugAvailable : true;
                  slugMessage = announceSaved
                      ? 'Theme link updated.'
                      : slugMessage;
                });
                if (announceSaved) {
                  _showSnackBar('Theme link updated.');
                }
              } catch (error) {
                if (!mounted) {
                  return;
                }
                setSheetState(() {
                  isSavingSlug = false;
                  slugMessage = error.toString().replaceFirst(
                    'Exception: ',
                    '',
                  );
                });
              }
            }

            void scheduleSlugCheck(String rawValue) {
              final candidate = rawValue.trim().toLowerCase();
              slugDebounce?.cancel();
              if (candidate.isEmpty) {
                setSheetState(() {
                  isCheckingSlug = false;
                  isSlugAvailable = null;
                  slugMessage = 'Pick a short ending for your share link.';
                });
                return;
              }
              if (!_isValidThemeSlug(candidate)) {
                setSheetState(() {
                  isCheckingSlug = false;
                  isSlugAvailable = false;
                  slugMessage =
                      'Use lowercase letters, numbers, or hyphens only.';
                });
                return;
              }
              setSheetState(() {
                isCheckingSlug = true;
                slugMessage = 'Checking availability...';
              });
              slugDebounce = Timer(const Duration(milliseconds: 280), () async {
                try {
                  final available = await _themeService
                      .checkShareSlugAvailability(
                        _session,
                        candidate,
                        excludeThemeId: shareTheme.sharedThemeId,
                      );
                  if (!mounted) {
                    return;
                  }
                  setSheetState(() {
                    isCheckingSlug = false;
                    isSlugAvailable = available;
                    slugMessage = available
                        ? 'This code is available.'
                        : 'That code is already taken.';
                  });
                } catch (_) {
                  if (!mounted) {
                    return;
                  }
                  setSheetState(() {
                    isCheckingSlug = false;
                    isSlugAvailable = null;
                    slugMessage = 'Could not check availability right now.';
                  });
                }
              });
            }

            final shareUrl = (shareTheme.shareUrl ?? '').trim();
            final shareCode =
                (shareTheme.shareSlug ?? shareTheme.shareCode ?? '').trim();

            Widget buildInfoTile({
              required String label,
              required String value,
              required String fallback,
              required VoidCallback onCopy,
            }) {
              final displayValue = value.isEmpty ? fallback : value;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      displayValue,
                      style: const TextStyle(fontSize: 15, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: value.isEmpty ? null : onCopy,
                        child: Text('Copy $label'),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101828).withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Share Theme',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Deep links import themes right back in. Share the QR, send the link, or edit the code ending to make it easier to remember.',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: CupertinoSlidingSegmentedControl<String>(
                                  groupValue: mode,
                                  children: const {
                                    'qr': Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Text('QR'),
                                    ),
                                    'link': Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Text('Link'),
                                    ),
                                    'edit': Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Edit Code',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  },
                                  onValueChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setSheetState(() {
                                      mode = value;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white.withValues(alpha: 0.08),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: switch (mode) {
                                'qr' => Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (shareUrl.isNotEmpty)
                                      QrImageView(
                                        data: shareUrl,
                                        size: 210,
                                        backgroundColor: Colors.white,
                                      )
                                    else
                                      const Text('Create a share link first.'),
                                    const SizedBox(height: 12),
                                    SelectableText(
                                      shareUrl.isEmpty
                                          ? 'Create a share link first.'
                                          : shareUrl,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                                'link' => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    buildInfoTile(
                                      label: 'Link',
                                      value: shareUrl,
                                      fallback: 'Create a share link first.',
                                      onCopy: () => _copyToClipboard(
                                        shareUrl,
                                        'Theme link',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    buildInfoTile(
                                      label: 'Code',
                                      value: shareCode,
                                      fallback: 'Create a share code first.',
                                      onCopy: () => _copyToClipboard(
                                        shareCode,
                                        'Theme code',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () => _shareThemePack(
                                          context,
                                          shareTheme,
                                        ),
                                        icon: const Icon(
                                          Icons.ios_share_outlined,
                                        ),
                                        label: const Text('Open Share Sheet'),
                                      ),
                                    ),
                                  ],
                                ),
                                _ => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Edit the ending of your theme link.',
                                      style: TextStyle(
                                        color: AppTheme.textMuted,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: slugController,
                                      autocorrect: false,
                                      textCapitalization:
                                          TextCapitalization.none,
                                      onChanged: scheduleSlugCheck,
                                      decoration: const InputDecoration(
                                        labelText: 'Theme code / link ending',
                                        hintText: 'spring-mountain',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        if (isCheckingSlug)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        else if (isSlugAvailable == true)
                                          const Icon(
                                            Icons.check_circle_outline,
                                            size: 18,
                                            color: Colors.greenAccent,
                                          )
                                        else if (isSlugAvailable == false)
                                          const Icon(
                                            Icons.error_outline,
                                            size: 18,
                                            color: Colors.orangeAccent,
                                          ),
                                        if (isCheckingSlug ||
                                            isSlugAvailable != null)
                                          const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            slugMessage.isEmpty
                                                ? 'Short, readable codes work best.'
                                                : slugMessage,
                                            style: const TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 12,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    buildInfoTile(
                                      label: 'Current Link',
                                      value: shareUrl,
                                      fallback: 'Create a share link first.',
                                      onCopy: () => _copyToClipboard(
                                        shareUrl,
                                        'Theme link',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: isSavingSlug
                                            ? null
                                            : () async {
                                                final candidate = slugController
                                                    .text
                                                    .trim()
                                                    .toLowerCase();
                                                if (!_isValidThemeSlug(
                                                  candidate,
                                                )) {
                                                  setSheetState(() {
                                                    isSlugAvailable = false;
                                                    slugMessage =
                                                        'Use lowercase letters, numbers, or hyphens only.';
                                                  });
                                                  return;
                                                }
                                                await refreshShare(
                                                  shareSlug: candidate,
                                                  announceSaved: true,
                                                );
                                              },
                                        child: Text(
                                          isSavingSlug
                                              ? 'Saving...'
                                              : 'Save Code',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              },
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: isSavingSlug
                                        ? null
                                        : () => refreshShare(),
                                    child: Text(
                                      shareCode.isEmpty
                                          ? 'Create Share'
                                          : 'Refresh Share',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _shareThemePack(context, shareTheme),
                                    child: const Text('Open Share Sheet'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    slugDebounce?.cancel();
    slugController.dispose();
  }

  Future<void> _deleteThemeFromLibrary(MobileTheme theme) async {
    try {
      _session = await _themeService.deleteSharedTheme(_session, theme);
      widget.onSessionUpdated(_session);
      if (mounted) {
        setState(() {});
      }
      _showSnackBar('Theme removed.');
    } catch (error) {
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _buildThemeSharingCard(BuildContext context) {
    final savedThemes = _themeService.savedThemePacks
        .where((theme) => !theme.isBuiltIn)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme Sharing',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Import a link or code, open the share sheet, and edit the ending of your theme links without leaving mobile.',
              style: TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _themeImportController,
              decoration: const InputDecoration(
                labelText: 'Import shared theme',
                hintText: 'Paste a share link or 6-digit code',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _importSharedThemeFromSettings,
                    child: const Text('Import & Apply'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _openThemeShareSheet(_themeService.current),
                  child: const Text('Share Current Theme'),
                ),
              ],
            ),
            if (savedThemes.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...savedThemes.map((theme) {
                final isCurrent = ThemeService.themePackMatches(
                  _themeService.current,
                  theme,
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    await _themeService.applyThemePack(theme);
                    if (!mounted) {
                      return;
                    }
                    await _loadTheme();
                    _showSnackBar('Applied "${theme.name}".');
                  },
                  leading: isCurrent
                      ? Icon(Icons.check_circle, color: theme.btnColor)
                      : const Icon(Icons.palette_outlined),
                  title: Text(theme.name),
                  subtitle: Text(theme.authorLabel ?? theme.description),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      IconButton(
                        onPressed: () => _openThemeShareSheet(theme),
                        icon: const Icon(Icons.ios_share_outlined),
                      ),
                      IconButton(
                        onPressed: () => _deleteThemeFromLibrary(theme),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final avatarDataUrl = _currentAvatarDataUrl();
    final avatarLabel =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();

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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'PNG, JPEG, GIF, WEBP, AVIF, HEIC, or HEIF up to 12 MB.',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                    ),
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
                                onPressed: _isSaving
                                    ? null
                                    : _removeAvatarImage,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
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
                          decoration: const InputDecoration(
                            labelText: 'Current email',
                          ),
                          child: Text(_settings?.email ?? ''),
                        ),
                        if ((_settings?.pendingEmail ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.mark_email_unread_outlined,
                                size: 14,
                                color: AppTheme.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Pending: ${_settings!.pendingEmail}',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 13,
                                  ),
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
                            onPressed: _isRequestingEmailChange
                                ? null
                                : _requestEmailChange,
                            child: Text(
                              _isRequestingEmailChange
                                  ? 'Sending...'
                                  : 'Change email',
                            ),
                          ),
                        ),
                        if (_emailChangeFeedback.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _emailChangeFeedback,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  _emailChangeFeedback.toLowerCase().contains(
                                        'error',
                                      ) ||
                                      _emailChangeFeedback
                                          .toLowerCase()
                                          .contains('could not') ||
                                      _emailChangeFeedback
                                          .toLowerCase()
                                          .contains('invalid')
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
                              onPressed: _isExportingCalendar
                                  ? null
                                  : _exportCalendar,
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 16,
                              ),
                              label: Text(
                                _isExportingCalendar
                                    ? 'Exporting...'
                                    : 'Export .ics',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildFeaturedWeatherThemesCard(context),
                const SizedBox(height: 16),
                _buildThemeSharingCard(context),
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
