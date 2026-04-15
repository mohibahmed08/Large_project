import 'package:flutter/material.dart';

import '../services/theme_service.dart';

class AppTheme {
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
  static const textPrimary = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFFB7C3D4);

  static final ThemeService _themeService = ThemeService();

  static MobileTheme get currentTheme => _themeService.current;
  static Color get accent => currentTheme.btnColor;
  static Color get buttonForeground => onColorFor(accent);

  static Color get accentStrong =>
      _mix(accent, currentTheme.gradient.colors.last, 0.42);

  static Color get background =>
      _mix(currentTheme.gradient.colors.first, Colors.black, 0.62);

  static Color get surface => _mix(const Color(0xFF101828), accent, 0.10);

  static Color get surfaceAlt => _mix(const Color(0xFF172033), accent, 0.18);

  static Color get border =>
      _mix(const Color(0xFF334155), accent, 0.18).withValues(alpha: 0.44);

  static List<Color> get backgroundGradientColors {
    final gradient = currentTheme.gradient.colors;
    final mid = gradient.length > 2
        ? gradient[1]
        : _mix(gradient.first, gradient.last, 0.5);
    return [
      _mix(gradient.first, Colors.black, 0.24),
      _mix(mid, Colors.black, 0.34),
      _mix(gradient.last, Colors.black, 0.46),
    ];
  }

  static BoxDecoration backgroundDecoration({bool authSurface = false}) {
    final imageProvider = authSurface
        ? _themeService.loginBackgroundImageProvider()
        : _themeService.backgroundImageProvider();
    final overlayOpacity = authSurface
        ? 0.58
        : _themeService.backgroundOverlayOpacity;
    final imageFit = authSurface ? BoxFit.cover : currentTheme.imageFit.boxFit;
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
                Colors.black.withValues(alpha: overlayOpacity),
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
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface.withValues(alpha: 0.82),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        labelStyle: TextStyle(color: textMuted),
        hintStyle: TextStyle(color: textMuted),
        floatingLabelStyle: TextStyle(
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
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: buttonForeground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: buttonForeground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
          foregroundColor: textPrimary,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceAlt,
        contentTextStyle: TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.92),
        indicatorColor: accent.withValues(alpha: 0.2),
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
