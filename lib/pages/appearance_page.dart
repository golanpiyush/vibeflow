// lib/pages/appearance_page.dart
import 'package:flutter/material.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/pages/subpages/settings/about_page.dart';
import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/other_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/utils/page_transitions.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({Key? key}) : super(key: key);

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  String selectedTheme = 'PureBlack';
  String themeMode = 'System';
  String thumbnailRoundness = 'Heavy';
  bool useSystemFont = false;
  bool applyFontPadding = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildColorsSection(),
                          const SizedBox(height: AppSpacing.xxxl),
                          _buildShapesSection(),
                          const SizedBox(height: AppSpacing.xxxl),
                          _buildTextSection(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.chevron_left,
              color: AppColors.textPrimary,
              size: 28,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Appearance', style: AppTypography.pageTitle),
            ),
          ),
        ],
      ),
    );
  }

  // Update the _buildSidebar method in appearance_page.dart
  Widget _buildSidebar() {
    final double availableHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              icon: Icons.edit_square,
              label: '',
              isActive: true,
              index: -1,
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(label: 'Player', index: 0),
            const SizedBox(height: 24),
            _buildSidebarItem(label: 'Cache', index: 1),
            const SizedBox(height: 24),
            _buildSidebarItem(label: 'Database', index: 2),
            const SizedBox(height: 24),
            _buildSidebarItem(label: 'Other', index: 3),
            const SizedBox(height: 24),
            _buildSidebarItem(label: 'About', index: 4),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Update _buildSidebarItem to handle navigation
  Widget _buildSidebarItem({
    IconData? icon,
    required String label,
    bool isActive = false,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isActive && index != -1) {
          _navigateToPage(context, index, currentIndex: -1);
        }
      },
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 28,
                color: isActive ? AppColors.iconActive : AppColors.iconInactive,
              ),
              const SizedBox(height: 16),
            ],
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style:
                    (isActive
                            ? AppTypography.sidebarLabelActive
                            : AppTypography.sidebarLabel)
                        .copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add this method to AppearancePage
  void _navigateToPage(
    BuildContext context,
    int targetIndex, {
    required int currentIndex,
  }) {
    Widget page;
    switch (targetIndex) {
      case -1:
        Navigator.popUntil(context, (route) => route.isFirst);
        return;
      case 0:
        page = const PlayerSettingsPage();
        break;
      case 1:
        page = const CachePage();
        break;
      case 2:
        page = const DatabasePage();
        break;
      case 3:
        page = const OtherPage();
        break;
      case 4:
        page = const AboutPage();
        break;
      default:
        return;
    }

    // Even cleaner with extension
    Navigator.of(context).pushReplacementDirectional(
      page,
      currentIndex: currentIndex,
      targetIndex: targetIndex,
    );
  }

  Widget _buildColorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COLORS',
          style: AppTypography.caption.copyWith(
            color: AppColors.iconActive,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildSettingItem(
          title: 'Theme',
          subtitle: selectedTheme,
          onTap: () {
            // Show theme picker
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _buildSettingItem(
          title: 'Theme mode',
          subtitle: themeMode,
          onTap: () {
            // Show theme mode picker
          },
        ),
      ],
    );
  }

  Widget _buildShapesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SHAPES',
          style: AppTypography.caption.copyWith(
            color: AppColors.iconActive,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thumbnail roundness',
                    style: AppTypography.subtitle.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    thumbnailRoundness,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.iconActive, width: 2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TEXT',
          style: AppTypography.caption.copyWith(
            color: AppColors.iconActive,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildSwitchItem(
          title: 'Use system font',
          subtitle: 'Use the font applied by the system',
          value: useSystemFont,
          onChanged: (value) {
            setState(() {
              useSystemFont = value;
            });
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildSwitchItem(
          title: 'Apply font padding',
          subtitle: 'Add spacing around texts',
          value: applyFontPadding,
          onChanged: (value) {
            setState(() {
              applyFontPadding = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSettingItem({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.subtitle.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.subtitle.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.iconActive,
          inactiveThumbColor: AppColors.textSecondary,
          inactiveTrackColor: AppColors.cardBackground,
        ),
      ],
    );
  }
}
