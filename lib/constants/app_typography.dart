// lib/constants/app_typography.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  // Page Title
  static TextStyle pageTitle = GoogleFonts.cabin(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Section Headers
  static TextStyle sectionHeader = GoogleFonts.cabin(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Song Title
  static TextStyle songTitle = GoogleFonts.cabin(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  // Artist/Album Name
  static TextStyle subtitle = GoogleFonts.cabin(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // Small text (year, subscribers)
  static TextStyle caption = GoogleFonts.cabin(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // Smaller caption
  static TextStyle captionSmall = GoogleFonts.cabin(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // Sidebar labels
  static TextStyle sidebarLabel = GoogleFonts.cabin(
    fontSize: 10,
    fontWeight: FontWeight.normal,
    color: AppColors.iconInactive,
  );

  static TextStyle sidebarLabelActive = GoogleFonts.cabin(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.iconActive,
  );
}
