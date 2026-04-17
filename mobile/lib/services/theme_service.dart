import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import 'api_config.dart';

const _kThemeKey = 'calpp_mobile_theme';
const _kThemePacksKey = 'calpp_theme_packs';
const _kPendingSharedThemeKey = 'calpp_pending_shared_theme';
const _kLoginBackgroundAsset = 'assets/images/LoginBackground.jpg';

enum ThemeBackgroundMode {
  gradient,
  universal,
  perScene,
  none,
  weatherPackage,
  customImage,
}

enum ThemeImageFit { cover, contain, center }

enum ThemeSceneSlot {
  clearDay,
  clearSunrise,
  clearNight,
  cloudyDay,
  cloudySunrise,
  cloudyNight,
  partlyCloudyDay,
  partlyCloudySunrise,
  partlyCloudyNight,
}

enum WeatherThemeKind { clear, cloudy, rain, snow, storm, fog }

extension WeatherThemeKindX on WeatherThemeKind {
  String get label => switch (this) {
    WeatherThemeKind.clear => 'Clear',
    WeatherThemeKind.cloudy => 'Cloudy',
    WeatherThemeKind.rain => 'Rain',
    WeatherThemeKind.snow => 'Snow',
    WeatherThemeKind.storm => 'Storm',
    WeatherThemeKind.fog => 'Fog',
  };
}

extension ThemeBackgroundModeX on ThemeBackgroundMode {
  String get storageKey => switch (this) {
    ThemeBackgroundMode.gradient => 'gradient',
    ThemeBackgroundMode.universal => 'universal',
    ThemeBackgroundMode.perScene => 'perScene',
    ThemeBackgroundMode.none => 'none',
    ThemeBackgroundMode.weatherPackage => 'weatherPackage',
    ThemeBackgroundMode.customImage => 'customImage',
  };

  String get label => switch (this) {
    ThemeBackgroundMode.gradient => 'Gradient',
    ThemeBackgroundMode.universal => 'Universal image',
    ThemeBackgroundMode.perScene => 'Per-scene images',
    ThemeBackgroundMode.none => 'No image',
    ThemeBackgroundMode.weatherPackage => 'Weather package',
    ThemeBackgroundMode.customImage => 'Custom image',
  };
}

extension ThemeImageFitX on ThemeImageFit {
  String get storageKey => switch (this) {
    ThemeImageFit.cover => 'cover',
    ThemeImageFit.contain => 'contain',
    ThemeImageFit.center => 'center',
  };

  String get label => switch (this) {
    ThemeImageFit.cover => 'Cover (fill & crop)',
    ThemeImageFit.contain => 'Contain (show full image)',
    ThemeImageFit.center => 'Center (no scaling)',
  };

  BoxFit get boxFit => switch (this) {
    ThemeImageFit.cover => BoxFit.cover,
    ThemeImageFit.contain => BoxFit.contain,
    ThemeImageFit.center => BoxFit.none,
  };
}

extension ThemeSceneSlotX on ThemeSceneSlot {
  String get key => switch (this) {
    ThemeSceneSlot.clearDay => 'clearDay',
    ThemeSceneSlot.clearSunrise => 'clearSunrise',
    ThemeSceneSlot.clearNight => 'clearNight',
    ThemeSceneSlot.cloudyDay => 'cloudyDay',
    ThemeSceneSlot.cloudySunrise => 'cloudySunrise',
    ThemeSceneSlot.cloudyNight => 'cloudyNight',
    ThemeSceneSlot.partlyCloudyDay => 'partlyCloudyDay',
    ThemeSceneSlot.partlyCloudySunrise => 'partlyCloudySunrise',
    ThemeSceneSlot.partlyCloudyNight => 'partlyCloudyNight',
  };

  String get label => switch (this) {
    ThemeSceneSlot.clearDay => 'Clear Day',
    ThemeSceneSlot.clearSunrise => 'Sunrise / Sunset (Clear)',
    ThemeSceneSlot.clearNight => 'Clear Night',
    ThemeSceneSlot.cloudyDay => 'Cloudy Day',
    ThemeSceneSlot.cloudySunrise => 'Sunrise / Sunset (Cloudy)',
    ThemeSceneSlot.cloudyNight => 'Cloudy Night',
    ThemeSceneSlot.partlyCloudyDay => 'Partly Cloudy Day',
    ThemeSceneSlot.partlyCloudySunrise => 'Partly Cloudy Sunrise / Sunset',
    ThemeSceneSlot.partlyCloudyNight => 'Partly Cloudy Night',
  };
}

@immutable
class ThemeGradient {
  const ThemeGradient({required this.angle, required this.colors});

  final double angle;
  final List<Color> colors;

  static const fallback = ThemeGradient(
    angle: 135,
    colors: [Color(0xFF0F172A), Color(0xFF2563EB), Color(0xFF7DD3FC)],
  );

  factory ThemeGradient.fromJson(Map<String, dynamic>? json) {
    final rawColors =
        (json?['colors'] as List?)
            ?.map((value) => _normalizeColor(value))
            .whereType<Color>()
            .toList() ??
        fallback.colors;
    return ThemeGradient(
      angle: (json?['angle'] as num?)?.toDouble() ?? fallback.angle,
      colors: rawColors.length >= 2
          ? rawColors.take(3).toList()
          : fallback.colors,
    );
  }

  Map<String, dynamic> toJson() => {
    'angle': angle,
    'colors': colors.map(_colorToHex).toList(),
  };
}

@immutable
class ThemePackSeed {
  const ThemePackSeed({
    required this.id,
    required this.name,
    required this.description,
    required this.btnColor,
    required this.gradient,
    required this.backgroundMode,
    required this.source,
    this.images = const {},
    this.galleryImages = const [],
    this.selectedGalleryImage,
    this.imageFit = ThemeImageFit.cover,
    this.preview,
    this.previewImage,
    this.packId,
  });

  final String id;
  final String name;
  final String description;
  final Color btnColor;
  final ThemeGradient gradient;
  final ThemeBackgroundMode backgroundMode;
  final String source;
  final Map<String, String> images;
  final List<String> galleryImages;
  final String? selectedGalleryImage;
  final ThemeImageFit imageFit;
  final String? preview;
  final String? previewImage;
  final String? packId;
}

@immutable
class MobileTheme {
  MobileTheme({
    String? id,
    String? name,
    String? description,
    Color? btnColor,
    ThemeGradient? gradient,
    ThemeBackgroundMode? backgroundMode,
    String? source,
    Map<String, String> images = const {},
    this.galleryImages = const [],
    this.selectedGalleryImage,
    ThemeImageFit? imageFit,
    this.preview,
    this.previewImage,
    String? packId,
    this.sharedThemeId,
    this.shareCode,
    this.shareSlug,
    this.shareKey,
    this.shareUrl,
    this.isOwnedTheme,
    this.authorName,
    this.authorLabel,
    this.creatorLabel,
    String? presetId,
    String? backgroundPackageId,
    Color? accentColor,
    String? backgroundImagePath,
    BoxFit? backgroundFit,
  }) : id = id ?? presetId ?? 'theme-pack',
       name = name ?? 'Untitled Pack',
       description = description ?? '',
       btnColor = btnColor ?? accentColor ?? const Color(0xFF60A5FA),
       gradient = gradient ?? ThemeGradient.fallback,
       backgroundMode =
           backgroundMode ??
           ((backgroundImagePath?.trim().isNotEmpty ?? false)
               ? ThemeBackgroundMode.customImage
               : ThemeBackgroundMode.none),
       source = source ?? 'user',
       images = images.isNotEmpty
           ? images
           : ((backgroundImagePath?.trim().isNotEmpty ?? false)
                 ? {'universal': backgroundImagePath!.trim()}
                 : const {}),
       imageFit = imageFit ?? _themeImageFitForBoxFit(backgroundFit),
       packId = packId ?? backgroundPackageId ?? presetId;

  final String id;
  final String name;
  final String description;
  final Color btnColor;
  final ThemeGradient gradient;
  final ThemeBackgroundMode backgroundMode;
  final String source;
  final Map<String, String> images;
  final List<String> galleryImages;
  final String? selectedGalleryImage;
  final ThemeImageFit imageFit;
  final String? preview;
  final String? previewImage;
  final String? packId;
  final String? sharedThemeId;
  final String? shareCode;
  final String? shareSlug;
  final String? shareKey;
  final String? shareUrl;
  final bool? isOwnedTheme;
  final String? authorName;
  final String? authorLabel;
  final String? creatorLabel;

  static final defaultTheme = MobileTheme(
    id: 'mobile-default',
    name: 'Mobile Default',
    description: 'No image background with the classic blue Calendar++ accent.',
    btnColor: Color(0xFF60A5FA),
    gradient: ThemeGradient(
      angle: 180,
      colors: [Color(0xFF08111F), Color(0xFF10203A), Color(0xFF163761)],
    ),
    backgroundMode: ThemeBackgroundMode.none,
    source: 'mobile-default',
  );

  factory MobileTheme.fromSeed(ThemePackSeed seed) {
    return MobileTheme(
      id: seed.id,
      name: seed.name,
      description: seed.description,
      btnColor: seed.btnColor,
      gradient: seed.gradient,
      backgroundMode: seed.backgroundMode,
      source: seed.source,
      images: seed.images,
      galleryImages: seed.galleryImages,
      selectedGalleryImage: seed.selectedGalleryImage,
      imageFit: seed.imageFit,
      preview: seed.preview,
      previewImage: seed.previewImage,
      packId: seed.packId,
    );
  }

  factory MobileTheme.fromJson(Map<String, dynamic> json) {
    final images = _normalizeImageMap(json['images']);
    final galleryImages = _normalizeStringList(json['galleryImages']);
    final gradient = ThemeGradient.fromJson(
      (json['gradient'] as Map?)?.cast<String, dynamic>(),
    );
    return MobileTheme(
      id: (json['id'] ?? 'theme-pack').toString(),
      name: _trimOrFallback(json['name'], 'Untitled Pack'),
      description: (json['description'] ?? '').toString().trim(),
      btnColor: _normalizeColor(json['btnColor']) ?? defaultTheme.btnColor,
      gradient: gradient,
      backgroundMode: _backgroundModeFromStorage(
        (json['backgroundMode'] ?? '').toString(),
        gradient: gradient,
        images: images,
        galleryImages: galleryImages,
      ),
      source: _trimOrFallback(json['source'], 'user'),
      images: images,
      galleryImages: galleryImages,
      selectedGalleryImage: _trimOrNull(json['selectedGalleryImage']),
      imageFit: _imageFitFromStorage((json['imageFit'] ?? '').toString()),
      preview: _trimOrNull(json['preview']),
      previewImage: _trimOrNull(json['previewImage']),
      packId: _trimOrNull(json['packId']),
      sharedThemeId: _trimOrNull(json['sharedThemeId']),
      shareCode: _trimOrNull(json['shareCode']),
      shareSlug: _trimOrNull(json['shareSlug']),
      shareKey: _trimOrNull(json['shareKey']),
      shareUrl: _trimOrNull(json['shareUrl']),
      isOwnedTheme: json['isOwnedTheme'] as bool?,
      authorName: _trimOrNull(json['authorName']),
      authorLabel: _trimOrNull(json['authorLabel']),
      creatorLabel: _trimOrNull(json['creatorLabel']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'btnColor': _colorToHex(btnColor),
    'images': images,
    'galleryImages': galleryImages,
    if (selectedGalleryImage != null)
      'selectedGalleryImage': selectedGalleryImage,
    'imageFit': imageFit.storageKey,
    'backgroundMode': backgroundMode.storageKey,
    'gradient': gradient.toJson(),
    if (preview != null) 'preview': preview,
    if (previewImage != null) 'previewImage': previewImage,
    if (packId != null) 'packId': packId,
    'source': source,
    if (sharedThemeId != null) 'sharedThemeId': sharedThemeId,
    if (shareCode != null) 'shareCode': shareCode,
    if (shareSlug != null) 'shareSlug': shareSlug,
    if (shareKey != null) 'shareKey': shareKey,
    if (shareUrl != null) 'shareUrl': shareUrl,
    if (isOwnedTheme != null) 'isOwnedTheme': isOwnedTheme,
    if (authorName != null) 'authorName': authorName,
    if (authorLabel != null) 'authorLabel': authorLabel,
    if (creatorLabel != null) 'creatorLabel': creatorLabel,
  };

  MobileTheme copyWith({
    String? id,
    String? name,
    String? description,
    Color? btnColor,
    ThemeGradient? gradient,
    ThemeBackgroundMode? backgroundMode,
    String? source,
    Map<String, String>? images,
    List<String>? galleryImages,
    String? selectedGalleryImage,
    bool clearSelectedGalleryImage = false,
    ThemeImageFit? imageFit,
    String? preview,
    bool clearPreview = false,
    String? previewImage,
    bool clearPreviewImage = false,
    String? packId,
    bool clearPackId = false,
    String? sharedThemeId,
    bool clearSharedThemeId = false,
    String? shareCode,
    bool clearShareCode = false,
    String? shareSlug,
    bool clearShareSlug = false,
    String? shareKey,
    bool clearShareKey = false,
    String? shareUrl,
    bool clearShareUrl = false,
    bool? isOwnedTheme,
    String? authorName,
    bool clearAuthorName = false,
    String? authorLabel,
    bool clearAuthorLabel = false,
    String? creatorLabel,
    bool clearCreatorLabel = false,
  }) {
    return MobileTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      btnColor: btnColor ?? this.btnColor,
      gradient: gradient ?? this.gradient,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      source: source ?? this.source,
      images: images ?? this.images,
      galleryImages: galleryImages ?? this.galleryImages,
      selectedGalleryImage: clearSelectedGalleryImage
          ? null
          : (selectedGalleryImage ?? this.selectedGalleryImage),
      imageFit: imageFit ?? this.imageFit,
      preview: clearPreview ? null : (preview ?? this.preview),
      previewImage: clearPreviewImage
          ? null
          : (previewImage ?? this.previewImage),
      packId: clearPackId ? null : (packId ?? this.packId),
      sharedThemeId: clearSharedThemeId
          ? null
          : (sharedThemeId ?? this.sharedThemeId),
      shareCode: clearShareCode ? null : (shareCode ?? this.shareCode),
      shareSlug: clearShareSlug ? null : (shareSlug ?? this.shareSlug),
      shareKey: clearShareKey ? null : (shareKey ?? this.shareKey),
      shareUrl: clearShareUrl ? null : (shareUrl ?? this.shareUrl),
      isOwnedTheme: isOwnedTheme ?? this.isOwnedTheme,
      authorName: clearAuthorName ? null : (authorName ?? this.authorName),
      authorLabel: clearAuthorLabel ? null : (authorLabel ?? this.authorLabel),
      creatorLabel: clearCreatorLabel
          ? null
          : (creatorLabel ?? this.creatorLabel),
    );
  }

  bool get isBuiltIn =>
      source == 'preset' ||
      source == 'featured' ||
      source == 'mobile-default' ||
      source == 'draft';

  String get identity =>
      sharedThemeId != null && sharedThemeId!.trim().isNotEmpty
      ? 'shared:${sharedThemeId!.trim()}'
      : 'local:$id';

  String get presetId => packId ?? id;
  String get backgroundPackageId => packId ?? id;
  Color get accentColor => btnColor;
  String? get backgroundImagePath =>
      images['universal'] ?? resolvePackGalleryImage(this);
  BoxFit get backgroundFit => imageFit.boxFit;
  List<Color> get gradientColors => gradient.colors;
}

class ThemeSyncResult {
  ThemeSyncResult({required this.theme, required this.session});

  final MobileTheme theme;
  final UserSession session;
}

const kThemeSceneSlots = ThemeSceneSlot.values;

final kPresetThemes = <MobileTheme>[
  MobileTheme.fromSeed(
    ThemePackSeed(
      id: 'default-weather-pack',
      packId: 'default-weather-pack',
      name: 'Weather Photo Pack',
      description: 'The original weather-reactive photo pack from desktop.',
      btnColor: const Color(0xFF60A5FA),
      gradient: ThemeGradient(
        angle: 180,
        colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFF7DD3FC)],
      ),
      backgroundMode: ThemeBackgroundMode.perScene,
      images: {
        ThemeSceneSlot.clearDay.key: 'assets/theme_fallbacks/ClearSky.jpg',
        ThemeSceneSlot.clearSunrise.key:
            'assets/theme_fallbacks/SunsetSunriseClearSky.png',
        ThemeSceneSlot.clearNight.key: 'assets/theme_fallbacks/NightClear.jpg',
        ThemeSceneSlot.cloudyDay.key: 'assets/theme_fallbacks/Cloudy.jpg',
        ThemeSceneSlot.cloudySunrise.key:
            'assets/theme_fallbacks/SunsetSunriseCloudy.jpg',
        ThemeSceneSlot.cloudyNight.key:
            'assets/theme_fallbacks/NightCloudy.jpg',
        ThemeSceneSlot.partlyCloudyDay.key:
            'assets/theme_fallbacks/PartlyCloudy.jpg',
        ThemeSceneSlot.partlyCloudySunrise.key:
            'assets/theme_fallbacks/SunsetSunrisePartlyCloudy.jpg',
        ThemeSceneSlot.partlyCloudyNight.key:
            'assets/theme_fallbacks/NightPartlyCloudy.jpg',
      },
      galleryImages: [
        'assets/theme_fallbacks/ClearSky.jpg',
        'assets/theme_fallbacks/PartlyCloudy.jpg',
        'assets/theme_fallbacks/Cloudy.jpg',
        'assets/theme_fallbacks/SunsetSunriseClearSky.png',
        'assets/theme_fallbacks/SunsetSunrisePartlyCloudy.jpg',
        'assets/theme_fallbacks/SunsetSunriseCloudy.jpg',
        'assets/theme_fallbacks/NightClear.jpg',
        'assets/theme_fallbacks/NightPartlyCloudy.jpg',
        'assets/theme_fallbacks/NightCloudy.jpg',
      ],
      preview: 'assets/theme_fallbacks/ClearSky.jpg',
      previewImage: 'assets/theme_fallbacks/ClearSky.jpg',
      source: 'preset',
    ),
  ),
];

final kFeaturedThemes = <MobileTheme>[
  _buildFeaturedTheme(
    id: 'mountain-featured',
    packId: 'mountain',
    name: 'Mountain Photo Pack',
    description: 'Real featured mountain scenes mapped per weather slot.',
    btnColor: const Color(0xFF67E8F9),
    coverExtension: 'png',
    sceneExtension: 'jpg',
  ),
  _buildFeaturedTheme(
    id: 'forest-featured',
    packId: 'forest',
    name: 'Forest Photo Pack',
    description: 'Weather-based forest photography with mist and canopy glow.',
    btnColor: const Color(0xFF4ADE80),
    coverExtension: 'jpg',
    sceneExtension: 'jpg',
  ),
  _buildFeaturedTheme(
    id: 'desert-featured',
    packId: 'desert',
    name: 'Desert Photo Pack',
    description: 'Weather-based desert skies, sandstone, and dusk light.',
    btnColor: const Color(0xFFF59E0B),
    coverExtension: 'webp',
    sceneExtension: 'png',
  ),
  _buildFeaturedTheme(
    id: 'beach-featured',
    packId: 'beach',
    name: 'Beach Photo Pack',
    description:
        'Weather-based shoreline scenes with surf, haze, and horizon glow.',
    btnColor: const Color(0xFF38BDF8),
    coverExtension: 'jpg',
    sceneExtension: 'jpg',
  ),
];

final kThemeAccentSwatches = <Color>[
  const Color(0xFF60A5FA),
  const Color(0xFF38BDF8),
  const Color(0xFF22C55E),
  const Color(0xFFF59E0B),
  const Color(0xFFF97316),
  const Color(0xFFF43F5E),
  const Color(0xFFA855F7),
  const Color(0xFF94A3B8),
  const Color(0xFFF8FAFC),
];

class ThemeService extends ChangeNotifier {
  factory ThemeService() => _instance;

  ThemeService._internal();

  static final ThemeService _instance = ThemeService._internal();

  Future<void>? _loadFuture;
  MobileTheme _current = MobileTheme.defaultTheme;
  List<MobileTheme> _savedThemePacks = const [];
  int? _activeWeatherCode;
  DateTime _activeWeatherDate = DateTime.now();
  String? _resolvedBackgroundPath;
  double? _resolvedImageLuminance;
  double _backgroundOverlayOpacity = 0.56;

  MobileTheme get current => _current;
  List<MobileTheme> get savedThemePacks => List.unmodifiable(_savedThemePacks);
  List<MobileTheme> get builtInThemePacks => [
    MobileTheme.defaultTheme,
    ...kPresetThemes,
    ...kFeaturedThemes,
  ];
  int? get activeWeatherCode => _activeWeatherCode;
  DateTime get activeWeatherDate => _activeWeatherDate;
  ThemeSceneSlot get activeSceneSlot =>
      sceneSlotForCode(_activeWeatherCode, _activeWeatherDate);
  String get activeSceneKey => activeSceneSlot.key;
  double get backgroundOverlayOpacity => _backgroundOverlayOpacity;
  double? get resolvedImageLuminance => _resolvedImageLuminance;
  WeatherThemeKind get activeWeatherKind {
    return switch (activeSceneSlot) {
      ThemeSceneSlot.clearDay ||
      ThemeSceneSlot.clearSunrise ||
      ThemeSceneSlot.clearNight => WeatherThemeKind.clear,
      ThemeSceneSlot.partlyCloudyDay ||
      ThemeSceneSlot.partlyCloudySunrise ||
      ThemeSceneSlot.partlyCloudyNight => WeatherThemeKind.cloudy,
      _ => WeatherThemeKind.cloudy,
    };
  }

  Future<void> load() {
    return _loadFuture ??= _loadInternal();
  }

  Future<void> _loadInternal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawTheme = prefs.getString(_kThemeKey);
      if (rawTheme != null && rawTheme.isNotEmpty) {
        _current = MobileTheme.fromJson(
          (jsonDecode(rawTheme) as Map).cast<String, dynamic>(),
        );
      }

      final rawPacks = prefs.getString(_kThemePacksKey);
      if (rawPacks != null && rawPacks.isNotEmpty) {
        final decoded = jsonDecode(rawPacks);
        if (decoded is List) {
          final loadedPacks = decoded
              .whereType<Map>()
              .map((item) => MobileTheme.fromJson(item.cast<String, dynamic>()))
              .toList();
          _savedThemePacks = _mergeThemePacks(const [], loadedPacks);
        }
      }
    } catch (_) {
      _current = MobileTheme.defaultTheme;
      _savedThemePacks = const [];
    }

    await _refreshResolvedImageMetrics(notify: false);
  }

  Future<void> mergeAccountThemePacks(List<MobileTheme> packs) async {
    _savedThemePacks = _mergeThemePacks(_savedThemePacks, packs);
    await _persistSavedThemePacks();
    notifyListeners();
  }

  Future<void> applyThemePack(MobileTheme theme) async {
    _current = sanitizeThemePack(theme, fallback: MobileTheme.defaultTheme);
    if (!_current.isBuiltIn || _current.sharedThemeId != null) {
      _savedThemePacks = _mergeThemePacks(_savedThemePacks, [_current]);
      await _persistSavedThemePacks();
    }
    await _persistCurrentTheme();
    await _refreshResolvedImageMetrics();
  }

  Future<MobileTheme> upsertLocalThemePack(MobileTheme theme) async {
    final normalized = sanitizeThemePack(
      theme,
      fallback: MobileTheme.defaultTheme,
    );
    _savedThemePacks = _mergeThemePacks(_savedThemePacks, [normalized]);
    await _persistSavedThemePacks();
    notifyListeners();
    return normalized;
  }

  Future<void> deleteLocalThemePack(MobileTheme theme) async {
    _savedThemePacks = _savedThemePacks
        .where((pack) => !themePackMatches(pack, theme))
        .toList();
    if (themePackMatches(_current, theme)) {
      _current = MobileTheme.defaultTheme;
      await _persistCurrentTheme();
      await _refreshResolvedImageMetrics(notify: false);
    }
    await _persistSavedThemePacks();
    notifyListeners();
  }

  Future<void> reset() async {
    _current = MobileTheme.defaultTheme;
    await _persistCurrentTheme();
    await _refreshResolvedImageMetrics();
  }

  MobileTheme presetById(String id) {
    return [
      MobileTheme.defaultTheme,
      ...kPresetThemes,
      ...kFeaturedThemes,
    ].firstWhere(
      (theme) => theme.id == id || theme.packId == id,
      orElse: () => MobileTheme.defaultTheme,
    );
  }

  Future<void> applyAccentColor(Color color) async {
    await applyThemePack(_current.copyWith(btnColor: color, source: 'user'));
  }

  Future<void> applyPreset(MobileTheme preset) => applyThemePack(preset);

  Future<void> applyBackgroundPackage(String packageId) async {
    final preset = presetById(packageId);
    await applyThemePack(
      _current.copyWith(
        packId: preset.packId ?? preset.id,
        gradient: preset.gradient,
        images: preset.images,
      ),
    );
  }

  Future<void> applyBackgroundMode(ThemeBackgroundMode mode) async {
    await applyThemePack(_current.copyWith(backgroundMode: mode));
  }

  Future<void> setStoredBackgroundImage(String? path, BoxFit fit) async {
    final normalized = path?.trim() ?? '';
    if (normalized.isEmpty) {
      await applyThemePack(
        _current.copyWith(
          images: Map<String, String>.from(_current.images)
            ..remove('universal'),
        ),
      );
      return;
    }
    await applyThemePack(
      _current.copyWith(
        backgroundMode: ThemeBackgroundMode.universal,
        imageFit: _themeImageFitForBoxFit(fit),
        images: {..._current.images, 'universal': normalized},
      ),
    );
  }

  void setActiveWeatherCode(int? code, {DateTime? at}) {
    final nextDate = at ?? DateTime.now();
    if (_activeWeatherCode == code &&
        _activeWeatherDate.year == nextDate.year &&
        _activeWeatherDate.month == nextDate.month &&
        _activeWeatherDate.day == nextDate.day &&
        _activeWeatherDate.hour == nextDate.hour) {
      return;
    }
    _activeWeatherCode = code;
    _activeWeatherDate = nextDate;
    unawaited(_refreshResolvedImageMetrics());
  }

  Future<String?> pickBackgroundImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 84,
      );
      return picked?.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> setPendingSharedThemeValue(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = extractSharedThemeValue(value);
    if (normalized.isEmpty) {
      await prefs.remove(_kPendingSharedThemeKey);
    } else {
      await prefs.setString(_kPendingSharedThemeKey, normalized);
    }
  }

  Future<String> readPendingSharedThemeValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPendingSharedThemeKey) ?? '';
  }

  Future<void> clearPendingSharedThemeValue() {
    return setPendingSharedThemeValue(null);
  }

  Future<ThemeSyncResult> saveSharedTheme(
    UserSession session,
    MobileTheme theme, {
    String? shareSlug,
  }) async {
    final json = await _post(session, 'upsertcustomtheme', {
      'theme': sanitizeThemePack(
        theme,
        fallback: MobileTheme.defaultTheme,
      ).toJson(),
      if ((shareSlug ?? '').trim().isNotEmpty) 'shareSlug': shareSlug!.trim(),
    });
    final synced = sanitizeThemePack(
      MobileTheme.fromJson((json['theme'] as Map).cast<String, dynamic>()),
      fallback: theme,
    );
    await upsertLocalThemePack(synced);
    if (themePackMatches(_current, theme)) {
      await applyThemePack(synced);
    }
    return ThemeSyncResult(
      theme: synced,
      session: _updatedSession(session, json),
    );
  }

  Future<bool> checkShareSlugAvailability(
    UserSession session,
    String slug, {
    String? excludeThemeId,
  }) async {
    final json = await _post(session, 'checkthemeslug', {
      'slug': slug.trim(),
      if ((excludeThemeId ?? '').trim().isNotEmpty)
        'excludeThemeId': excludeThemeId!.trim(),
    });
    return json['available'] == true;
  }

  Future<ThemeSyncResult> importSharedTheme(
    UserSession session,
    String shareValue,
  ) async {
    final resolvedShareValue = extractSharedThemeValue(shareValue);
    if (resolvedShareValue.isEmpty) {
      throw Exception('Paste a theme code or share link first.');
    }
    final json = await _post(session, 'importsharedtheme', {
      'shareValue': resolvedShareValue,
    });
    final theme = sanitizeThemePack(
      MobileTheme.fromJson((json['theme'] as Map).cast<String, dynamic>()),
      fallback: MobileTheme.defaultTheme,
    );
    await upsertLocalThemePack(theme);
    await applyThemePack(theme);
    await clearPendingSharedThemeValue();
    return ThemeSyncResult(
      theme: theme,
      session: _updatedSession(session, json),
    );
  }

  Future<UserSession> deleteSharedTheme(
    UserSession session,
    MobileTheme theme,
  ) async {
    final sharedThemeId = theme.sharedThemeId?.trim() ?? '';
    if (sharedThemeId.isEmpty) {
      await deleteLocalThemePack(theme);
      return session;
    }
    final json = await _post(session, 'deletecustomtheme', {
      'sharedThemeId': sharedThemeId,
    });
    await deleteLocalThemePack(theme);
    return _updatedSession(session, json);
  }

  Future<bool> importPendingSharedThemeIfNeeded(UserSession session) async {
    final pending = await readPendingSharedThemeValue();
    if (pending.isEmpty) {
      return false;
    }
    await importSharedTheme(session, pending);
    return true;
  }

  MobileTheme? themeById(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final allThemes = [...builtInThemePacks, ..._savedThemePacks];
    for (final theme in allThemes) {
      if (theme.id == normalized) {
        return theme;
      }
    }
    return null;
  }

  ImageProvider<Object> loginBackgroundImageProvider() {
    return const AssetImage(_kLoginBackgroundAsset);
  }

  String displayImageUrl(String? path) => path?.trim() ?? '';

  ImageProvider<Object>? imageProviderForPath(String? path) {
    final normalizedPath = _normalizeBundledAssetPath(path?.trim() ?? '');
    if (normalizedPath.isEmpty) {
      return null;
    }

    if (normalizedPath.startsWith('assets/')) {
      return AssetImage(normalizedPath);
    }
    if (_looksLikeNetworkUrl(normalizedPath)) {
      return NetworkImage(normalizedPath);
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

  String? resolveEffectiveBackgroundPath({
    MobileTheme? theme,
    ThemeSceneSlot? sceneSlot,
  }) {
    final effectiveTheme = theme ?? _current;
    final effectiveScene = sceneSlot ?? activeSceneSlot;
    final galleryImage = resolvePackGalleryImage(effectiveTheme);

    if ((effectiveTheme.backgroundMode == ThemeBackgroundMode.gradient ||
            effectiveTheme.backgroundMode == ThemeBackgroundMode.none) &&
        effectiveTheme.gradient.colors.length >= 2) {
      return null;
    }

    if (effectiveTheme.backgroundMode != ThemeBackgroundMode.perScene &&
        effectiveTheme.backgroundMode != ThemeBackgroundMode.weatherPackage &&
        galleryImage != null) {
      return galleryImage;
    }

    final universal = effectiveTheme.images['universal']?.trim();
    if (universal != null && universal.isNotEmpty) {
      return universal;
    }

    final sceneImage = effectiveTheme.images[effectiveScene.key]?.trim();
    if (sceneImage != null && sceneImage.isNotEmpty) {
      return sceneImage;
    }

    if (galleryImage != null) {
      return galleryImage;
    }

    final previewImage = effectiveTheme.previewImage?.trim();
    if (previewImage != null && previewImage.isNotEmpty) {
      return previewImage;
    }

    final preview = effectiveTheme.preview?.trim();
    if (preview != null &&
        preview.isNotEmpty &&
        !preview.startsWith('linear-gradient(')) {
      return preview;
    }

    return weatherFallbackAssetPath(effectiveScene);
  }

  ImageProvider<Object>? backgroundImageProvider({
    MobileTheme? theme,
    ThemeSceneSlot? sceneSlot,
    WeatherThemeKind? previewWeatherKind,
  }) {
    final normalizedSlot =
        sceneSlot ??
        switch (previewWeatherKind) {
          WeatherThemeKind.clear => ThemeSceneSlot.clearDay,
          WeatherThemeKind.cloudy => ThemeSceneSlot.cloudyDay,
          WeatherThemeKind.rain => ThemeSceneSlot.cloudyDay,
          WeatherThemeKind.snow => ThemeSceneSlot.cloudyDay,
          WeatherThemeKind.storm => ThemeSceneSlot.cloudyNight,
          WeatherThemeKind.fog => ThemeSceneSlot.cloudySunrise,
          null => null,
        };
    return imageProviderForPath(
      resolveEffectiveBackgroundPath(theme: theme, sceneSlot: normalizedSlot),
    );
  }

  ThemeSceneSlot sceneSlotForCode(int? code, [DateTime? date]) {
    final reference = date ?? DateTime.now();
    final hour = reference.hour;
    final isSunrise = (hour >= 6 && hour < 9) || (hour >= 18 && hour < 21);
    final isDay = hour >= 9 && hour < 18;

    final family = switch (code) {
      null => 'clear',
      0 || 1 => 'clear',
      2 => 'partlyCloudy',
      3 ||
      45 ||
      48 ||
      >= 51 && <= 67 ||
      >= 71 && <= 86 ||
      95 ||
      96 ||
      99 => 'cloudy',
      _ => 'cloudy',
    };

    if (family == 'clear') {
      if (isDay) return ThemeSceneSlot.clearDay;
      if (isSunrise) return ThemeSceneSlot.clearSunrise;
      return ThemeSceneSlot.clearNight;
    }
    if (family == 'partlyCloudy') {
      if (isDay) return ThemeSceneSlot.partlyCloudyDay;
      if (isSunrise) return ThemeSceneSlot.partlyCloudySunrise;
      return ThemeSceneSlot.partlyCloudyNight;
    }
    if (isDay) return ThemeSceneSlot.cloudyDay;
    if (isSunrise) return ThemeSceneSlot.cloudySunrise;
    return ThemeSceneSlot.cloudyNight;
  }

  String weatherFallbackAssetPath(ThemeSceneSlot slot) {
    switch (slot) {
      case ThemeSceneSlot.clearDay:
        return 'assets/theme_fallbacks/ClearSky.jpg';
      case ThemeSceneSlot.clearSunrise:
        return 'assets/theme_fallbacks/SunsetSunriseClearSky.png';
      case ThemeSceneSlot.clearNight:
        return 'assets/theme_fallbacks/NightClear.jpg';
      case ThemeSceneSlot.cloudyDay:
        return 'assets/theme_fallbacks/Cloudy.jpg';
      case ThemeSceneSlot.cloudySunrise:
        return 'assets/theme_fallbacks/SunsetSunriseCloudy.jpg';
      case ThemeSceneSlot.cloudyNight:
        return 'assets/theme_fallbacks/NightCloudy.jpg';
      case ThemeSceneSlot.partlyCloudyDay:
        return 'assets/theme_fallbacks/PartlyCloudy.jpg';
      case ThemeSceneSlot.partlyCloudySunrise:
        return 'assets/theme_fallbacks/SunsetSunrisePartlyCloudy.jpg';
      case ThemeSceneSlot.partlyCloudyNight:
        return 'assets/theme_fallbacks/NightPartlyCloudy.jpg';
    }
  }

  static MobileTheme sanitizeThemePack(
    MobileTheme input, {
    required MobileTheme fallback,
  }) {
    final mergedImages = {
      ...fallback.images,
      ...input.images.map((key, value) => MapEntry(key.trim(), value.trim()))
        ..removeWhere((key, value) => key.isEmpty || value.isEmpty),
    };
    final galleryImages = input.galleryImages
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final gradient = ThemeGradient(
      angle: input.gradient.angle,
      colors: input.gradient.colors.length >= 2
          ? input.gradient.colors.take(3).toList()
          : fallback.gradient.colors,
    );
    final backgroundMode = _backgroundModeFromStorage(
      input.backgroundMode.storageKey,
      gradient: gradient,
      images: mergedImages,
      galleryImages: galleryImages,
    );
    return input.copyWith(
      id: input.id.trim().isEmpty ? fallback.id : input.id.trim(),
      name: input.name.trim().isEmpty ? fallback.name : input.name.trim(),
      description: input.description.trim(),
      btnColor: input.btnColor,
      gradient: gradient,
      backgroundMode: backgroundMode,
      images: mergedImages,
      galleryImages: galleryImages,
      selectedGalleryImage: _trimOrNull(input.selectedGalleryImage),
      imageFit: input.imageFit,
      preview: _trimOrNull(input.preview),
      previewImage: _trimOrNull(input.previewImage),
      packId: _trimOrNull(input.packId),
      source: input.source.trim().isEmpty
          ? fallback.source
          : input.source.trim(),
      sharedThemeId: _trimOrNull(input.sharedThemeId),
      shareCode: _trimOrNull(input.shareCode),
      shareSlug: _trimOrNull(input.shareSlug),
      shareKey: _trimOrNull(input.shareKey),
      shareUrl: _trimOrNull(input.shareUrl),
      authorName: _trimOrNull(input.authorName),
      authorLabel: _trimOrNull(input.authorLabel),
      creatorLabel: _trimOrNull(input.creatorLabel),
    );
  }

  static bool themePackMatches(MobileTheme? first, MobileTheme? second) {
    if (first == null || second == null) {
      return false;
    }
    final firstShared = first.sharedThemeId?.trim() ?? '';
    final secondShared = second.sharedThemeId?.trim() ?? '';
    if (firstShared.isNotEmpty || secondShared.isNotEmpty) {
      return firstShared == secondShared && firstShared.isNotEmpty;
    }
    return first.id == second.id;
  }

  static List<MobileTheme> mergeThemePacks(
    List<MobileTheme> first,
    List<MobileTheme> second,
  ) {
    return _mergeThemePacks(first, second);
  }

  static String extractSharedThemeValue(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      final uri = Uri.parse(trimmed);
      final sharedValue = uri.queryParameters['theme']?.trim() ?? '';
      if (sharedValue.isNotEmpty) {
        return sharedValue;
      }
      return (uri.scheme.isEmpty && uri.host.isEmpty && uri.path.isNotEmpty)
          ? uri.path.trim()
          : trimmed;
    } catch (_) {
      return trimmed;
    }
  }

  Future<void> _persistCurrentTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeKey, jsonEncode(_current.toJson()));
    } catch (_) {}
  }

  Future<void> _persistSavedThemePacks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kThemePacksKey,
        jsonEncode(_savedThemePacks.map((pack) => pack.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _refreshResolvedImageMetrics({bool notify = true}) async {
    _resolvedBackgroundPath = resolveEffectiveBackgroundPath();
    _resolvedImageLuminance = await _estimateImageLuminance(
      _resolvedBackgroundPath,
    );
    final luminance = _resolvedImageLuminance;
    _backgroundOverlayOpacity = switch (luminance) {
      null => 0.48,
      > 0.75 => 0.76,
      > 0.58 => 0.66,
      > 0.42 => 0.58,
      _ => 0.50,
    };
    if (notify) {
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _post(
    UserSession session,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': session.userId,
        'jwtToken': session.accessToken,
        ...body,
      }),
    );
    final json = _decodeJson(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }
    throw Exception(json['error']?.toString() ?? 'Request failed.');
  }

  Future<double?> _estimateImageLuminance(String? source) async {
    final normalized = source?.trim() ?? '';
    if (normalized.isEmpty || normalized.startsWith('linear-gradient(')) {
      return null;
    }

    try {
      Uint8List bytes;
      if (normalized.startsWith('assets/')) {
        final data = await rootBundle.load(normalized);
        bytes = data.buffer.asUint8List();
      } else if (_looksLikeNetworkUrl(normalized)) {
        final response = await http.get(Uri.parse(normalized));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        bytes = response.bodyBytes;
      } else if (kIsWeb) {
        return null;
      } else {
        final file = File(normalized);
        if (!await file.exists()) {
          return null;
        }
        bytes = await file.readAsBytes();
      }

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 24,
        targetHeight: 24,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        return null;
      }
      final pixels = data.buffer.asUint8List();
      if (pixels.isEmpty) {
        return null;
      }

      var luminanceSum = 0.0;
      var samples = 0;
      for (var i = 0; i <= pixels.length - 4; i += 16) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3] / 255.0;
        final luminance = ((0.2126 * r) + (0.7152 * g) + (0.0722 * b)) / 255.0;
        luminanceSum += luminance * a;
        samples += 1;
      }
      return samples == 0 ? null : luminanceSum / samples;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decodeJson(String body) {
    if (body.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  static UserSession _updatedSession(
    UserSession session,
    Map<String, dynamic> json,
  ) {
    final refreshed = json['jwtToken']?.toString() ?? '';
    return refreshed.isEmpty
        ? session
        : session.copyWith(accessToken: refreshed);
  }
}

ThemeBackgroundMode _backgroundModeFromStorage(
  String value, {
  required ThemeGradient gradient,
  required Map<String, String> images,
  required List<String> galleryImages,
}) {
  switch (value) {
    case 'gradient':
      return ThemeBackgroundMode.gradient;
    case 'universal':
      return ThemeBackgroundMode.universal;
    case 'perScene':
      return ThemeBackgroundMode.perScene;
    case 'none':
      return ThemeBackgroundMode.none;
    case 'weatherPackage':
      return ThemeBackgroundMode.weatherPackage;
    case 'customImage':
      return ThemeBackgroundMode.customImage;
    default:
      if (gradient.colors.length >= 2) {
        return ThemeBackgroundMode.gradient;
      }
      if ((images['universal']?.trim().isNotEmpty ?? false) ||
          galleryImages.isNotEmpty) {
        return ThemeBackgroundMode.universal;
      }
      return ThemeBackgroundMode.perScene;
  }
}

ThemeImageFit _imageFitFromStorage(String value) {
  return switch (value) {
    'contain' => ThemeImageFit.contain,
    'center' => ThemeImageFit.center,
    _ => ThemeImageFit.cover,
  };
}

ThemeImageFit _themeImageFitForBoxFit(BoxFit? fit) {
  return switch (fit) {
    BoxFit.contain => ThemeImageFit.contain,
    BoxFit.none => ThemeImageFit.center,
    _ => ThemeImageFit.cover,
  };
}

Color? _normalizeColor(Object? value) {
  final raw = value?.toString().trim().toLowerCase() ?? '';
  final match = RegExp(r'^#?([0-9a-f]{6})$').firstMatch(raw);
  if (match != null) {
    return Color(int.parse('ff${match.group(1)!}', radix: 16));
  }
  return null;
}

String _colorToHex(Color color) {
  final value = color.toARGB32() & 0x00FFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0')}';
}

String _trimOrFallback(Object? value, String fallback) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? fallback : normalized;
}

String? _trimOrNull(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

Map<String, String> _normalizeImageMap(Object? value) {
  final map = <String, String>{};
  if (value is! Map) {
    return map;
  }
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    final path = entry.value.toString().trim();
    if (key.isNotEmpty && path.isNotEmpty) {
      map[key] = path;
    }
  }
  return map;
}

List<String> _normalizeStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, String> _fallbackSceneImages() {
  return {
    for (final slot in ThemeSceneSlot.values)
      slot.key: ThemeService().weatherFallbackAssetPath(slot),
  };
}

String? resolvePackGalleryImage(MobileTheme theme) {
  final universal = theme.images['universal']?.trim();
  if (universal != null && universal.isNotEmpty) {
    return universal;
  }
  final selected = theme.selectedGalleryImage?.trim();
  if (selected != null && selected.isNotEmpty) {
    return selected;
  }
  if (theme.galleryImages.isNotEmpty) {
    return theme.galleryImages.first.trim();
  }
  return null;
}

bool _looksLikeNetworkUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

String _normalizeBundledAssetPath(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  if (!normalized.startsWith('assets/')) {
    return normalized;
  }
  return normalized.replaceFirst(RegExp(r'^(assets/)+'), 'assets/');
}

List<MobileTheme> _mergeThemePacks(
  List<MobileTheme> first,
  List<MobileTheme> second,
) {
  final merged = <String, MobileTheme>{};
  for (final theme in [...first, ...second]) {
    merged[_themePackMergeKey(theme)] = theme;
  }
  return merged.values.toList();
}

String _themePackMergeKey(MobileTheme theme) {
  final sharedThemeId = theme.sharedThemeId?.trim() ?? '';
  if (sharedThemeId.isNotEmpty) {
    return 'shared:$sharedThemeId';
  }

  final shareSlug = theme.shareSlug?.trim().toLowerCase() ?? '';
  if (shareSlug.isNotEmpty) {
    return 'slug:$shareSlug';
  }

  final shareCode = theme.shareCode?.trim().toUpperCase() ?? '';
  if (shareCode.isNotEmpty) {
    return 'code:$shareCode';
  }

  final shareValue = ThemeService.extractSharedThemeValue(theme.shareUrl);
  if (shareValue.isNotEmpty) {
    return 'share:${shareValue.toLowerCase()}';
  }

  return theme.identity;
}

MobileTheme _buildFeaturedTheme({
  required String id,
  required String packId,
  required String name,
  required String description,
  required Color btnColor,
  required String coverExtension,
  required String sceneExtension,
}) {
  final coverImage = 'assets/theme_featured/$packId/cover.$coverExtension';
  return MobileTheme.fromSeed(
    ThemePackSeed(
      id: id,
      packId: packId,
      name: name,
      description: description,
      btnColor: btnColor,
      gradient: ThemeGradient.fallback,
      backgroundMode: ThemeBackgroundMode.perScene,
      images: {
        ThemeSceneSlot.clearDay.key:
            'assets/theme_featured/$packId/ClearDay.$sceneExtension',
        ThemeSceneSlot.clearSunrise.key:
            'assets/theme_featured/$packId/ClearSunset.$sceneExtension',
        ThemeSceneSlot.clearNight.key:
            'assets/theme_featured/$packId/ClearNight.$sceneExtension',
        ThemeSceneSlot.cloudyDay.key:
            'assets/theme_featured/$packId/CloudyDay.$sceneExtension',
        ThemeSceneSlot.cloudySunrise.key:
            'assets/theme_featured/$packId/CloudySunset.$sceneExtension',
        ThemeSceneSlot.cloudyNight.key:
            'assets/theme_featured/$packId/CloudyNight.$sceneExtension',
        ThemeSceneSlot.partlyCloudyDay.key:
            'assets/theme_featured/$packId/PartlyCloudyDay.$sceneExtension',
        ThemeSceneSlot.partlyCloudySunrise.key:
            'assets/theme_featured/$packId/PartlyCloudySunset.$sceneExtension',
        ThemeSceneSlot.partlyCloudyNight.key:
            'assets/theme_featured/$packId/PartlyCloudyNight.$sceneExtension',
      },
      galleryImages: [
        coverImage,
        'assets/theme_featured/$packId/ClearDay.$sceneExtension',
        'assets/theme_featured/$packId/PartlyCloudyDay.$sceneExtension',
        'assets/theme_featured/$packId/CloudyDay.$sceneExtension',
        'assets/theme_featured/$packId/ClearSunset.$sceneExtension',
        'assets/theme_featured/$packId/PartlyCloudySunset.$sceneExtension',
        'assets/theme_featured/$packId/CloudySunset.$sceneExtension',
        'assets/theme_featured/$packId/ClearNight.$sceneExtension',
        'assets/theme_featured/$packId/PartlyCloudyNight.$sceneExtension',
        'assets/theme_featured/$packId/CloudyNight.$sceneExtension',
      ],
      preview: coverImage,
      previewImage: coverImage,
      source: 'featured',
    ),
  );
}
