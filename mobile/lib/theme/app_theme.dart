import 'package:flutter/material.dart';

import '../services/theme_service.dart';

class AppTheme {
  static const textPrimary = Color(0xFFF3F4F6);
  static const textMuted = Color(0xFF9CA3AF);
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);

  static final ThemeService _themeService = ThemeService();

  static MobileTheme get currentTheme => _themeService.current;

  static AppThemePreset get currentPreset {
    final presetId = currentTheme.presetId;
    return kPresetThemes.firstWhere(
      (preset) => preset.id == presetId,
      orElse: () => backgroundPreset,
    );
  }

  static AppThemePreset get backgroundPreset {
    final packageId = currentTheme.backgroundPackageId;
    return kPresetThemes.firstWhere(
      (preset) => preset.id == packageId,
      orElse: () => kPresetThemes.first,
    );
  }

  static Color get accent => currentTheme.accentColor;
  static Color get buttonForeground => onColorFor(accent);

  static Color get accentStrong =>
      _mix(accent, backgroundPreset.gradientColors.last, 0.42);

  static Color get background =>
      _mix(backgroundPreset.gradientColors.first, Colors.black, 0.62);

  static Color get surface => _mix(const Color(0xFF12121F), accent, 0.10);

  static Color get surfaceAlt => _mix(const Color(0xFF1F2937), accent, 0.16);

  static Color get border =>
      _mix(const Color(0xFF2D3748), accent, 0.20).withValues(alpha: 0.42);

  static List<Color> get backgroundGradientColors {
    final gradient = backgroundPreset.gradientColors;
    final mid = gradient.length > 2
        ? gradient[1]
        : _mix(gradient.first, gradient.last, 0.5);
    return [
      _mix(gradient.first, Colors.black, 0.28),
      _mix(mid, Colors.black, 0.38),
      _mix(gradient.last, Colors.black, 0.50),
    ];
  }

  static BoxDecoration backgroundDecoration() {
    final imageProvider = _themeService.backgroundImageProvider();
    final imageFit = currentTheme.backgroundMode == ThemeBackgroundMode.customImage
        ? currentTheme.backgroundFit
        : BoxFit.cover;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: backgroundGradientColors,
      ),
      image: imageProvider == null
          ? null
          : DecorationImage(
              image: imageProvider,
              fit: imageFit,
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.46),
                BlendMode.darken,
              ),
            ),
    );
  }

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.dark(
      primary: accent,
      secondary: accentStrong,
      surface: surface,
      surfaceContainerHighest: surfaceAlt,
      onPrimary: buttonForeground,
      onSurface: textPrimary,
      onSecondary: textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface.withValues(alpha: 0.90),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textMuted),
        floatingLabelStyle: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.75)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: danger.withValues(alpha: 0.85)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: danger.withValues(alpha: 0.95)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: buttonForeground,
          disabledBackgroundColor: accent.withValues(alpha: 0.55),
          disabledForegroundColor: textPrimary.withValues(alpha: 0.75),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: buttonForeground,
          disabledBackgroundColor: accent.withValues(alpha: 0.55),
          disabledForegroundColor: textPrimary.withValues(alpha: 0.75),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.32)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: buttonForeground,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: Colors.white.withValues(alpha: 0.18),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return buttonForeground;
          }
          return textPrimary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.78);
          }
          return Colors.white.withValues(alpha: 0.18);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceAlt,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.96),
        indicatorColor: accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? accent : textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
    );
  }

  static Color _mix(Color base, Color tint, double amount) {
    return Color.lerp(base, tint, amount) ?? base;
  }

  static Color onColorFor(Color color) {
    return color.computeLuminance() > 0.58
        ? const Color(0xFF08111F)
        : Colors.white;
  }
}
