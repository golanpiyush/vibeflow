// lib/utils/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================================
// FONT FAMILY ENUM
// ============================================================================
enum AppFontFamily {
  system, // System default
  inter,
  poppins,
  roboto,
  montserrat,
  notoSans,
}

// ============================================================================
// THEME PROVIDER - Now with Font Support
// ============================================================================

enum ThemeType { light, material, pureBlack }

enum AppThemeMode { light, dark }

enum ThumbnailRoundness { light, medium, heavy }

// Theme State Class - FIXED with proper fontFamily field
class ThemeState {
  final ThemeType themeType;
  final AppThemeMode systemThemeMode;
  final Color? seedColor;
  final ThumbnailRoundness thumbnailRoundness;
  final AppFontFamily fontFamily; // ✅ This is a field, not a getter
  final bool applyFontPadding;

  const ThemeState({
    this.themeType = ThemeType.pureBlack,
    this.systemThemeMode = AppThemeMode.dark,
    this.seedColor,
    this.thumbnailRoundness = ThumbnailRoundness.heavy,
    this.fontFamily = AppFontFamily.notoSans, // ✅ DEFAULT
    this.applyFontPadding = false,
  });

  ThemeState copyWith({
    ThemeType? themeType,
    AppThemeMode? systemThemeMode,
    Color? seedColor,
    ThumbnailRoundness? thumbnailRoundness,
    AppFontFamily? fontFamily,
    bool? applyFontPadding,
  }) {
    return ThemeState(
      themeType: themeType ?? this.themeType,
      systemThemeMode: systemThemeMode ?? this.systemThemeMode,
      seedColor: seedColor ?? this.seedColor,
      thumbnailRoundness: thumbnailRoundness ?? this.thumbnailRoundness,
      fontFamily: fontFamily ?? this.fontFamily,
      applyFontPadding: applyFontPadding ?? this.applyFontPadding,
    );
  }
}

// Theme Notifier
class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(const ThemeState()) {
    _loadThemePreferences();
  }

  static const String _themeTypeKey = 'theme_type';
  static const String _systemThemeModeKey = 'system_theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _thumbnailRoundnessKey = 'thumbnail_roundness';
  static const String _fontFamilyKey = 'font_family';
  static const String _applyFontPaddingKey = 'apply_font_padding';

  Future<void> _loadThemePreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final themeTypeIndex = prefs.getInt(_themeTypeKey) ?? 2;
    final systemModeIndex = prefs.getInt(_systemThemeModeKey) ?? 1;
    final seedColorValue = prefs.getInt(_seedColorKey);
    final roundnessIndex = prefs.getInt(_thumbnailRoundnessKey) ?? 2;
    final fontFamilyIndex = prefs.getInt(_fontFamilyKey) ?? 0;
    final applyFontPadding = prefs.getBool(_applyFontPaddingKey) ?? false;

    state = ThemeState(
      themeType: ThemeType.values[themeTypeIndex],
      systemThemeMode: AppThemeMode.values[systemModeIndex],
      seedColor: seedColorValue != null ? Color(seedColorValue) : null,
      thumbnailRoundness: ThumbnailRoundness.values[roundnessIndex],
      fontFamily: AppFontFamily.values[fontFamilyIndex],
      applyFontPadding: applyFontPadding,
    );
  }

  Future<void> setThemeType(ThemeType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeTypeKey, type.index);
    state = state.copyWith(themeType: type);
  }

  Future<void> setSystemThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_systemThemeModeKey, mode.index);
    state = state.copyWith(systemThemeMode: mode);
  }

  Future<void> setSeedColor(Color? color) async {
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_seedColorKey, color.value);
    } else {
      await prefs.remove(_seedColorKey);
    }
    state = state.copyWith(seedColor: color);
  }

  Future<void> setThumbnailRoundness(ThumbnailRoundness roundness) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_thumbnailRoundnessKey, roundness.index);
    state = state.copyWith(thumbnailRoundness: roundness);
  }

  Future<void> setFontFamily(AppFontFamily font) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fontFamilyKey, font.index);
    state = state.copyWith(fontFamily: font);
  }

  Future<void> setApplyFontPadding(bool apply) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_applyFontPaddingKey, apply);
    state = state.copyWith(applyFontPadding: apply);
  }

  ThemeMode get themeMode {
    if (state.themeType == ThemeType.material) {
      switch (state.systemThemeMode) {
        case AppThemeMode.light:
          return ThemeMode.light;
        case AppThemeMode.dark:
          return ThemeMode.dark;
      }
    }
    switch (state.themeType) {
      case ThemeType.light:
        return ThemeMode.light;
      case ThemeType.material:
        return ThemeMode.system;
      case ThemeType.pureBlack:
        return ThemeMode.dark;
    }
  }
}

// Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

// Font Family Provider
final fontFamilyProvider = Provider<AppFontFamily>((ref) {
  return ref.watch(themeProvider).fontFamily;
});

// Font Padding Provider
final fontPaddingProvider = Provider<bool>((ref) {
  return ref.watch(themeProvider).applyFontPadding;
});

// Helper to get TextTheme based on selected font
TextTheme _getTextTheme(AppFontFamily fontFamily) {
  switch (fontFamily) {
    case AppFontFamily.system:
      return ThemeData.light().textTheme;
    case AppFontFamily.inter:
      return GoogleFonts.interTextTheme();
    case AppFontFamily.poppins:
      return GoogleFonts.poppinsTextTheme();
    case AppFontFamily.roboto:
      return GoogleFonts.robotoTextTheme();
    case AppFontFamily.montserrat:
      return GoogleFonts.montserratTextTheme();
    case AppFontFamily.notoSans:
      return GoogleFonts.notoSansTextTheme();
  }
}

// Helper function to build custom light theme
ThemeData _buildCustomLightTheme(AppFontFamily fontFamily) {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.white,
    primaryColor: const Color(0xFF6B4CE8),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF6B4CE8),
      secondary: Color(0xFF00D9FF),
      surface: Colors.white,
      background: Colors.white,
      error: Color(0xFFFF3B30),
    ),
    textTheme: _getTextTheme(fontFamily),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
    ),
  );
}

// Helper function to build pure black theme
ThemeData _buildPureBlackTheme(AppFontFamily fontFamily) {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    primaryColor: Colors.black,
    colorScheme: const ColorScheme.dark(
      primary: Colors.black,
      secondary: Color(0xFF1A1A1A),
      surface: Color(0xFF0A0A0A),
      background: Colors.black,
      error: Color(0xFFFF3B30),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
      onBackground: Colors.white,
    ),
    textTheme: _getTextTheme(fontFamily),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.black,
    ),
    dialogBackgroundColor: const Color(0xFF0A0A0A),
    cardColor: const Color(0xFF0A0A0A),
    dividerColor: const Color(0xFF1A1A1A),
  );
}

// Theme Data Providers
final lightThemeProvider = Provider<ThemeData>((ref) {
  final themeState = ref.watch(themeProvider);
  final fontFamily = themeState.fontFamily;

  switch (themeState.themeType) {
    case ThemeType.light:
      return _buildCustomLightTheme(fontFamily);

    case ThemeType.material:
      final baseTheme = themeState.seedColor != null
          ? ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: themeState.seedColor!,
                brightness: Brightness.light,
              ),
            )
          : ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6B4CE8),
                brightness: Brightness.light,
              ),
            );

      return baseTheme.copyWith(textTheme: _getTextTheme(fontFamily));

    case ThemeType.pureBlack:
      return _buildPureBlackTheme(fontFamily);
  }
});

final darkThemeProvider = Provider<ThemeData>((ref) {
  final themeState = ref.watch(themeProvider);
  final fontFamily = themeState.fontFamily;

  switch (themeState.themeType) {
    case ThemeType.light:
      return _buildCustomLightTheme(fontFamily);

    case ThemeType.material:
      final baseTheme = themeState.seedColor != null
          ? ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: themeState.seedColor!,
                brightness: Brightness.dark,
              ),
            )
          : ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6B4CE8),
                brightness: Brightness.dark,
              ),
            );

      return baseTheme.copyWith(textTheme: _getTextTheme(fontFamily));

    case ThemeType.pureBlack:
      return _buildPureBlackTheme(fontFamily);
  }
});

final thumbnailRadiusProvider = Provider<double>((ref) {
  final roundness = ref.watch(themeProvider).thumbnailRoundness;

  switch (roundness) {
    case ThumbnailRoundness.light:
      return 0.02;
    case ThumbnailRoundness.medium:
      return 0.05;
    case ThumbnailRoundness.heavy:
      return 0.10;
  }
});
