// lib/constants/app_typography.dart
import 'package:flutter/material.dart';

class AppTypography {
  // ✅ All methods now accept BuildContext to get font from theme

  // Page Title
  static TextStyle pageTitle(BuildContext context) {
    return Theme.of(context).textTheme.headlineMedium!.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w600,
    );
  }

  // Standard body text
  static TextStyle body(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontSize: 14, fontWeight: FontWeight.w400);
  }

  // Section Headers
  static TextStyle sectionHeader(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.titleLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w600);
  }

  static TextStyle dialogTitle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );
  }

  // Song Title
  static TextStyle songTitle(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.bodyLarge!.copyWith(fontSize: 17, fontWeight: FontWeight.w500);
  }

  // Artist/Album Name
  static TextStyle subtitle(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  }

  // Small text (year, subscribers)
  static TextStyle caption(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(fontSize: 12, fontWeight: FontWeight.w400);
  }

  // Smaller caption
  static TextStyle captionSmall(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.labelSmall!.copyWith(fontSize: 11, fontWeight: FontWeight.w400);
  }

  // Sidebar labels
  static TextStyle sidebarLabel(BuildContext context) {
    return Theme.of(context).textTheme.labelMedium!.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.normal,
    );
  }

  static TextStyle sidebarLabelActive(BuildContext context) {
    return Theme.of(context).textTheme.labelMedium!.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
  }
}
