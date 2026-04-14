import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'calpp_mobile_theme';

enum ThemeBackgroundMode { none, weatherPackage, customImage }

enum WeatherThemeKind { clear, cloudy, rain, snow, storm, fog }

extension ThemeBackgroundModeX on ThemeBackgroundMode {
  String get storageKey => switch (this) {
        ThemeBackgroundMode.none => 'none',
        ThemeBackgroundMode.weatherPackage => 'weatherPackage',
        ThemeBackgroundMode.customImage => 'customImage',
      };

  String get label => switch (this) {
        ThemeBackgroundMode.none => 'No image',
        ThemeBackgroundMode.weatherPackage => 'Weather package',
        ThemeBackgroundMode.customImage => 'Custom image',
      };
}

extension WeatherThemeKindX on WeatherThemeKind {
  String get storageKey => switch (this) {
        WeatherThemeKind.clear => 'clear',
        WeatherThemeKind.cloudy => 'cloudy',
        WeatherThemeKind.rain => 'rain',
        WeatherThemeKind.snow => 'snow',
        WeatherThemeKind.storm => 'storm',
        WeatherThemeKind.fog => 'fog',
      };

  String get label => switch (this) {
        WeatherThemeKind.clear => 'Clear',
        WeatherThemeKind.cloudy => 'Cloudy',
        WeatherThemeKind.rain => 'Rain',
        WeatherThemeKind.snow => 'Snow',
        WeatherThemeKind.storm => 'Storm',
        WeatherThemeKind.fog => 'Fog',
      };
}

class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.accentColor,
    required this.gradientColors,
  });

  final String id;
  final String name;
  final String description;
  final Color accentColor;
  final List<Color> gradientColors;
}

const kPresetThemes = [
  AppThemePreset(
    id: 'default',
    name: 'Clear Sky',
    description: 'Cold front fading into sun',
    accentColor: Color(0xFF7DD3FC),
    gradientColors: [Color(0xFF0F172A), Color(0xFF2563EB), Color(0xFF7DD3FC)],
  ),
  AppThemePreset(
    id: 'aurora',
    name: 'Storm Front',
    description: 'Lightning over deep cloud bands',
    accentColor: Color(0xFFC084FC),
    gradientColors: [Color(0xFF0B1120), Color(0xFF312E81), Color(0xFF7C3AED)],
  ),
  AppThemePreset(
    id: 'forest',
    name: 'Forest Rain',
    description: 'Wet cedar, moss, and mist',
    accentColor: Color(0xFF86EFAC),
    gradientColors: [Color(0xFF052E16), Color(0xFF166534), Color(0xFF4ADE80)],
  ),
  AppThemePreset(
    id: 'desert',
    name: 'Desert Dusk',
    description: 'Heat haze at golden hour',
    accentColor: Color(0xFFFBBF24),
    gradientColors: [Color(0xFF451A03), Color(0xFFB45309), Color(0xFFF59E0B)],
  ),
  AppThemePreset(
    id: 'ocean',
    name: 'Deep Ocean',
    description: 'Tidewater teal and deep surf',
    accentColor: Color(0xFF2DD4BF),
    gradientColors: [Color(0xFF082F49), Color(0xFF0F766E), Color(0xFF14B8A6)],
  ),
  AppThemePreset(
    id: 'midnight',
    name: 'Midnight Frost',
    description: 'Moonlit frost and steel',
    accentColor: Color(0xFFE2E8F0),
    gradientColors: [Color(0xFF020617), Color(0xFF1E293B), Color(0xFF64748B)],
  ),
];

class MobileTheme {
  const MobileTheme({
    required this.presetId,
    required this.backgroundPackageId,
    required this.accentColor,
    this.backgroundMode = ThemeBackgroundMode.none,
    this.backgroundImagePath,
    this.backgroundFit = BoxFit.cover,
  });

  final String presetId;
  final String backgroundPackageId;
  final Color accentColor;
  final ThemeBackgroundMode backgroundMode;
  final String? backgroundImagePath;
  final BoxFit backgroundFit;

  static MobileTheme get defaultTheme => const MobileTheme(
        presetId: 'default',
        backgroundPackageId: 'default',
        accentColor: Color(0xFF7DD3FC),
        backgroundMode: ThemeBackgroundMode.none,
      );

  MobileTheme copyWith({
    String? presetId,
    String? backgroundPackageId,
    Color? accentColor,
    ThemeBackgroundMode? backgroundMode,
    String? backgroundImagePath,
    bool clearBackground = false,
    BoxFit? backgroundFit,
  }) {
    return MobileTheme(
      presetId: presetId ?? this.presetId,
      backgroundPackageId: backgroundPackageId ?? this.backgroundPackageId,
      accentColor: accentColor ?? this.accentColor,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      backgroundImagePath: clearBackground
          ? null
          : (backgroundImagePath ?? this.backgroundImagePath),
      backgroundFit: backgroundFit ?? this.backgroundFit,
    );
  }

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'backgroundPackageId': backgroundPackageId,
        'accentColor': accentColor.toARGB32(),
        'backgroundMode': backgroundMode.storageKey,
        if (backgroundImagePath != null)
          'backgroundImagePath': backgroundImagePath,
        'backgroundFit': _fitIndex(backgroundFit),
      };

  factory MobileTheme.fromJson(Map<String, dynamic> json) {
    final backgroundImagePath = json['backgroundImagePath'] as String?;
    final presetId = (json['presetId'] ?? 'default').toString();
    return MobileTheme(
      presetId: presetId,
      backgroundPackageId:
          (json['backgroundPackageId'] ?? presetId).toString(),
      accentColor:
          Color((json['accentColor'] as num?)?.toInt() ?? 0xFF7DD3FC),
      backgroundMode: _backgroundModeFromStorage(
        json['backgroundMode']?.toString(),
        hasCustomImage: (backgroundImagePath?.trim().isNotEmpty ?? false),
      ),
      backgroundImagePath: backgroundImagePath,
      backgroundFit: _fitFromIndex((json['backgroundFit'] as num?)?.toInt()),
    );
  }

  static ThemeBackgroundMode _backgroundModeFromStorage(
    String? value, {
    bool hasCustomImage = false,
  }) {
    switch (value) {
      case 'weatherPackage':
        return ThemeBackgroundMode.weatherPackage;
      case 'customImage':
        return ThemeBackgroundMode.customImage;
      case 'none':
        return ThemeBackgroundMode.none;
      default:
        return hasCustomImage
            ? ThemeBackgroundMode.customImage
            : ThemeBackgroundMode.none;
    }
  }

  static int _fitIndex(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return 1;
      case BoxFit.none:
        return 2;
      default:
        return 0;
    }
  }

  static BoxFit _fitFromIndex(int? index) {
    switch (index) {
      case 1:
        return BoxFit.contain;
      case 2:
        return BoxFit.none;
      default:
        return BoxFit.cover;
    }
  }
}

class ThemeService extends ChangeNotifier {
  factory ThemeService() => _instance;

  ThemeService._internal();

  static final ThemeService _instance = ThemeService._internal();

  Future<void>? _loadFuture;
  MobileTheme _current = MobileTheme.defaultTheme;
  int? _activeWeatherCode;

  MobileTheme get current => _current;
  int? get activeWeatherCode => _activeWeatherCode;
  WeatherThemeKind get activeWeatherKind => weatherKindForCode(_activeWeatherCode);

  Future<void> load() {
    return _loadFuture ??= _loadInternal();
  }

  Future<void> _loadInternal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kThemeKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final json = jsonDecode(raw) as Map<String, dynamic>;
      _current = MobileTheme.fromJson(json);
    } catch (_) {
      // Ignore malformed persisted values and keep the default theme.
    }
  }

  Future<void> applyPreset(AppThemePreset preset) async {
    _current = _current.copyWith(
      presetId: preset.id,
      backgroundPackageId: preset.id,
      accentColor: preset.accentColor,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> applyAccentColor(Color color) async {
    _current = _current.copyWith(
      presetId: 'custom',
      accentColor: color,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> applyBackgroundMode(ThemeBackgroundMode mode) async {
    _current = _current.copyWith(backgroundMode: mode);
    await _persist();
    notifyListeners();
  }

  Future<void> applyBackgroundPackage(String packageId) async {
    _current = _current.copyWith(backgroundPackageId: packageId);
    await _persist();
    notifyListeners();
  }

  Future<String?> pickBackgroundImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      return picked?.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> applyBackgroundImage(String path, BoxFit fit) async {
    _current = _current.copyWith(
      backgroundMode: ThemeBackgroundMode.customImage,
      backgroundImagePath: path,
      backgroundFit: fit,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> clearBackgroundImage() async {
    _current = _current.copyWith(clearBackground: true);
    await _persist();
    notifyListeners();
  }

  Future<void> setStoredBackgroundImage(String? path, BoxFit fit) async {
    _current = _current.copyWith(
      backgroundImagePath: path?.trim().isEmpty ?? true ? null : path,
      clearBackground: path == null || path.trim().isEmpty,
      backgroundFit: fit,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> applyBackgroundFit(BoxFit fit) async {
    _current = _current.copyWith(backgroundFit: fit);
    await _persist();
    notifyListeners();
  }

  void setActiveWeatherCode(int? code) {
    if (_activeWeatherCode == code) {
      return;
    }
    _activeWeatherCode = code;
    if (_current.backgroundMode == ThemeBackgroundMode.weatherPackage) {
      notifyListeners();
    }
  }

  Future<void> reset() async {
    _current = MobileTheme.defaultTheme;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeKey, jsonEncode(_current.toJson()));
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  AppThemePreset presetById(String id) {
    return kPresetThemes.firstWhere(
      (preset) => preset.id == id,
      orElse: () => kPresetThemes.first,
    );
  }

  WeatherThemeKind weatherKindForCode(int? code) {
    if (code == null) {
      return WeatherThemeKind.clear;
    }
    if (code == 0 || code == 1) {
      return WeatherThemeKind.clear;
    }
    if (code == 2 || code == 3) {
      return WeatherThemeKind.cloudy;
    }
    if (code == 45 || code == 48) {
      return WeatherThemeKind.fog;
    }
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 86)) {
      return WeatherThemeKind.rain;
    }
    if (code >= 71 && code <= 77) {
      return WeatherThemeKind.snow;
    }
    if (code == 95 || code == 96 || code == 99) {
      return WeatherThemeKind.storm;
    }
    return WeatherThemeKind.cloudy;
  }

  String weatherBackgroundAssetPath(String packageId, WeatherThemeKind kind) {
    final resolvedPackage = presetById(packageId).id;
    return 'assets/theme_packages/$resolvedPackage/${kind.storageKey}.png';
  }

  ImageProvider<Object>? imageProviderForPath(String? path) {
    final normalizedPath = path?.trim() ?? '';
    if (normalizedPath.isEmpty) {
      return null;
    }

    try {
      if (kIsWeb) {
        return NetworkImage(normalizedPath);
      }

      final file = File(normalizedPath);
      if (!file.existsSync()) {
        return null;
      }
      return FileImage(file);
    } catch (_) {
      return null;
    }
  }

  ImageProvider<Object>? weatherPackageImageProvider({
    String? packageId,
    WeatherThemeKind? weatherKind,
  }) {
    return AssetImage(
      weatherBackgroundAssetPath(
        packageId ?? _current.backgroundPackageId,
        weatherKind ?? activeWeatherKind,
      ),
    );
  }

  ImageProvider<Object>? backgroundImageProvider({
    MobileTheme? theme,
    WeatherThemeKind? previewWeatherKind,
  }) {
    final effectiveTheme = theme ?? _current;
    switch (effectiveTheme.backgroundMode) {
      case ThemeBackgroundMode.none:
        return null;
      case ThemeBackgroundMode.customImage:
        return imageProviderForPath(effectiveTheme.backgroundImagePath);
      case ThemeBackgroundMode.weatherPackage:
        return weatherPackageImageProvider(
          packageId: effectiveTheme.backgroundPackageId,
          weatherKind: previewWeatherKind,
        );
    }
  }
}
