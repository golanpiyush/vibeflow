// lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// THEME PROVIDER - Now with 3 Theme Types
// ============================================================================

// Theme Type Enum - REPLACES AppThemeMode
enum ThemeType {
  light, // Custom Light Theme (your original design)
  material, // Material You Dynamic Theme
  pureBlack, // Pure Black Theme
}

// Theme Mode Enum (for system dark/light)
enum AppThemeMode { light, dark }

enum ThumbnailRoundness {
  light, // 2%
  medium, // 5%
  heavy, // 10%
}

// Theme State Class - UPDATED
class ThemeState {
  final ThemeType themeType; // Which theme: light/material/pureBlack
  final AppThemeMode systemThemeMode; // For material theme: light/dark
  final Color? seedColor; // For material theme
  final ThumbnailRoundness thumbnailRoundness;

  const ThemeState({
    this.themeType = ThemeType.pureBlack, // Default to PureBlack
    this.systemThemeMode = AppThemeMode.dark,
    this.seedColor,
    this.thumbnailRoundness = ThumbnailRoundness.heavy,
  });

  ThemeState copyWith({
    ThemeType? themeType,
    AppThemeMode? systemThemeMode,
    Color? seedColor,
    ThumbnailRoundness? thumbnailRoundness,
  }) {
    return ThemeState(
      themeType: themeType ?? this.themeType,
      systemThemeMode: systemThemeMode ?? this.systemThemeMode,
      seedColor: seedColor ?? this.seedColor,
      thumbnailRoundness: thumbnailRoundness ?? this.thumbnailRoundness,
    );
  }
}

// Theme Notifier - UPDATED
class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(const ThemeState()) {
    _loadThemePreferences();
  }

  static const String _themeTypeKey = 'theme_type';
  static const String _systemThemeModeKey = 'system_theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _thumbnailRoundnessKey = 'thumbnail_roundness';

  Future<void> _loadThemePreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final themeTypeIndex =
        prefs.getInt(_themeTypeKey) ?? 2; // Default to PureBlack
    final systemModeIndex =
        prefs.getInt(_systemThemeModeKey) ?? 1; // Default to dark
    final seedColorValue = prefs.getInt(_seedColorKey);
    final roundnessIndex = prefs.getInt(_thumbnailRoundnessKey) ?? 2;

    state = ThemeState(
      themeType: ThemeType.values[themeTypeIndex],
      systemThemeMode: AppThemeMode.values[systemModeIndex],
      seedColor: seedColorValue != null ? Color(seedColorValue) : null,
      thumbnailRoundness: ThumbnailRoundness.values[roundnessIndex],
    );
  }

  // Set the theme type (Light/Material/PureBlack)
  Future<void> setThemeType(ThemeType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeTypeKey, type.index);
    state = state.copyWith(themeType: type);
  }

  // Set light/dark mode for Material theme
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

  // Helper to get ThemeMode for MaterialApp
  ThemeMode get themeMode {
    if (state.themeType == ThemeType.material) {
      switch (state.systemThemeMode) {
        case AppThemeMode.light:
          return ThemeMode.light;
        case AppThemeMode.dark:
          return ThemeMode.dark;
      }
    }
    // For Light and PureBlack themes, use light/dark respectively
    switch (state.themeType) {
      case ThemeType.light:
        return ThemeMode.light;
      case ThemeType.material:
        return ThemeMode.system; // Shouldn't reach here
      case ThemeType.pureBlack:
        return ThemeMode.dark;
    }
  }
}

// Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

// Helper function to build custom light theme
ThemeData _buildCustomLightTheme() {
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
ThemeData _buildPureBlackTheme() {
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

// Theme Data Providers - FIXED (no circular dependency)
final lightThemeProvider = Provider<ThemeData>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      // Custom Light Theme (your original design)
      return _buildCustomLightTheme();

    case ThemeType.material:
      // Material You Light Theme
      if (themeState.seedColor != null) {
        return ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: themeState.seedColor!,
            brightness: Brightness.light,
          ),
        );
      }
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4CE8),
          brightness: Brightness.light,
        ),
      );

    case ThemeType.pureBlack:
      // Pure Black Theme - return dark theme for consistency
      return _buildPureBlackTheme();
  }
});

final darkThemeProvider = Provider<ThemeData>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      // Light theme - return light theme for consistency
      return _buildCustomLightTheme();

    case ThemeType.material:
      // Material You Dark Theme
      if (themeState.seedColor != null) {
        return ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: themeState.seedColor!,
            brightness: Brightness.dark,
          ),
        );
      }
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4CE8),
          brightness: Brightness.dark,
        ),
      );

    case ThemeType.pureBlack:
      // PURE BLACK THEME
      return _buildPureBlackTheme();
  }
});

final thumbnailRadiusProvider = Provider<double>((ref) {
  final roundness = ref.watch(themeProvider).thumbnailRoundness;

  switch (roundness) {
    case ThumbnailRoundness.light:
      return 0.02; // 2%
    case ThumbnailRoundness.medium:
      return 0.05; // 5%
    case ThumbnailRoundness.heavy:
      return 0.10; // 10%
  }
});
