// lib/constants/theme_colors.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/utils/theme_provider.dart';

// Theme-aware color providers that use the current theme
final themeBackgroundColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      final theme = ref.watch(lightThemeProvider);
      return theme.scaffoldBackgroundColor;
    case ThemeType.material:
      final theme = ref.watch(
        lightThemeProvider,
      ); // Use light or dark based on systemThemeMode
      return theme.scaffoldBackgroundColor;
    case ThemeType.pureBlack:
      return Colors.black;
  }
});

final themeSurfaceColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      return const Color(0xFFF5F5F5);
    case ThemeType.material:
      final theme = ref.watch(lightThemeProvider);
      return theme.cardColor ?? const Color(0xFFF5F5F5);
    case ThemeType.pureBlack:
      return const Color(0xFF1A1A1A);
  }
});

final themeTextPrimaryColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      return Colors.black;
    case ThemeType.material:
      final theme = ref.watch(lightThemeProvider);
      return theme.colorScheme.onSurface;
    case ThemeType.pureBlack:
      return Colors.white;
  }
});

final themeTextSecondaryColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      return Colors.black.withOpacity(0.6);
    case ThemeType.material:
      final theme = ref.watch(lightThemeProvider);
      return theme.colorScheme.onSurface.withOpacity(0.6);
    case ThemeType.pureBlack:
      return const Color(0x99FFFFFF);
  }
});

final themeIconActiveColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      return const Color(0xFF6B4CE8);
    case ThemeType.material:
      final theme = ref.watch(lightThemeProvider);
      return theme.colorScheme.primary;
    case ThemeType.pureBlack:
      return Colors.white;
  }
});

final themeCardBackgroundColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      return Colors.white;
    case ThemeType.material:
      final theme = ref.watch(lightThemeProvider);
      return theme.cardColor ?? Colors.white;
    case ThemeType.pureBlack:
      return const Color(0xFF424242);
  }
});

final themeAccentColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      return const Color(0xFF9C27B0);
    case ThemeType.material:
      final theme = ref.watch(lightThemeProvider);
      return theme.colorScheme.secondary;
    case ThemeType.pureBlack:
      return const Color(0xFF9C27B0);
  }
});

// Card Color Provider (theme-aware)
final themeCardColorProvider = Provider<Color>((ref) {
  final themeState = ref.watch(themeProvider);

  switch (themeState.themeType) {
    case ThemeType.light:
      // Custom light card color
      return Colors.white;

    case ThemeType.material:
      // Material You card color from scheme
      final scheme = ColorScheme.fromSeed(
        seedColor: themeState.seedColor ?? const Color(0xFF6B4CE8),
        brightness: themeState.systemThemeMode == AppThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      );
      return scheme.surface;

    case ThemeType.pureBlack:
      // True AMOLED black card
      return const Color(0xFF0A0A0A);
  }
});
