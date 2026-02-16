// lib/constants/app_spacing.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/utils/theme_provider.dart';

class AppSpacing {
  // Base spacing unit
  static const double baseUnit = 8.0;

  // Spacing Scale (with padding)
  static const double xs = baseUnit * 0.5; // 4
  static const double sm = baseUnit; // 8
  static const double md = baseUnit * 1.5; // 12
  static const double lg = baseUnit * 2; // 16
  static const double xl = baseUnit * 3; // 24
  static const double xxl = baseUnit * 4; // 32
  static const double xxxl = baseUnit * 6; // 48
  static const double fourxxxl = baseUnit * 8; // 52

  // Spacing Scale (without padding - slightly reduced)
  static const double xsNoPadding = baseUnit * 0.375; // 3
  static const double smNoPadding = baseUnit * 0.75; // 6
  static const double mdNoPadding = baseUnit * 1.25; // 10
  static const double lgNoPadding = baseUnit * 1.75; // 14
  static const double xlNoPadding = baseUnit * 2.5; // 20
  static const double xxlNoPadding = baseUnit * 3.5; // 28
  static const double xxxlNoPadding = baseUnit * 5; // 40

  // Component specific
  static const double sidebarWidth = 80.0;
  static const double albumArtSize = 56.0;
  static const double albumCardSize = 160.0;
  static const double artistCardSize = 140.0;
  static const double artistImageSize = 120.0;

  // Border Radius
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusCircle = 1000.0;
}

class ResponsiveSpacing {
  static double albumArtSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 46.0;
    if (w < 400) return 50.0;
    return 54.0; // was 64 — too big
  }

  static double listItemHeight(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 64.0;
    if (w < 400) return 68.0;
    return 72.0; // was 80 — too tall
  }

  static double albumCardSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 110.0;
    if (w < 400) return 120.0;
    return 130.0; // was 160 — way too big
  }

  static double artistImageSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 88.0;
    if (w < 400) return 96.0;
    return 104.0; // was 120 — too big
  }

  static double artistCardWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 100.0;
    if (w < 400) return 110.0;
    return 120.0; // was 145 — too wide
  }

  static double sectionHeaderFontSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 17.0;
    if (w < 400) return 18.0;
    return 19.0;
  }

  static double pageTitleFontSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 24.0;
    if (w < 400) return 26.0;
    return 28.0;
  }
}

// Providers for dynamic spacing based on font padding setting
final dynamicSpacingXsProvider = Provider<double>((ref) {
  final applyPadding = ref.watch(themeProvider).applyFontPadding;
  return applyPadding ? AppSpacing.xs : AppSpacing.xsNoPadding;
});

final dynamicSpacingSmProvider = Provider<double>((ref) {
  final applyPadding = ref.watch(themeProvider).applyFontPadding;
  return applyPadding ? AppSpacing.sm : AppSpacing.smNoPadding;
});

final dynamicSpacingMdProvider = Provider<double>((ref) {
  final applyPadding = ref.watch(themeProvider).applyFontPadding;
  return applyPadding ? AppSpacing.md : AppSpacing.mdNoPadding;
});

final dynamicSpacingLgProvider = Provider<double>((ref) {
  final applyPadding = ref.watch(themeProvider).applyFontPadding;
  return applyPadding ? AppSpacing.lg : AppSpacing.lgNoPadding;
});

final dynamicSpacingXlProvider = Provider<double>((ref) {
  final applyPadding = ref.watch(themeProvider).applyFontPadding;
  return applyPadding ? AppSpacing.xl : AppSpacing.xlNoPadding;
});

final dynamicSpacingXxlProvider = Provider<double>((ref) {
  final applyPadding = ref.watch(themeProvider).applyFontPadding;
  return applyPadding ? AppSpacing.xxl : AppSpacing.xxlNoPadding;
});

final dynamicSpacingXxxlProvider = Provider<double>((ref) {
  final applyPadding = ref.watch(themeProvider).applyFontPadding;
  return applyPadding ? AppSpacing.xxxl : AppSpacing.xxxlNoPadding;
});

// Helper extension for easy access in widgets
extension DynamicSpacingContext on BuildContext {
  double getSpacing(WidgetRef ref, double withPadding, double withoutPadding) {
    final applyPadding = ref.watch(themeProvider).applyFontPadding;
    return applyPadding ? withPadding : withoutPadding;
  }
}
