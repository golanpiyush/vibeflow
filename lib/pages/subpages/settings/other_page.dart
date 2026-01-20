import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/pages/subpages/settings/about_page.dart';
import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/utils/page_transitions.dart';

// lib/pages/settings/other_page.dart
class OtherPage extends ConsumerWidget {
  const OtherPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final warningColor = Color(0xFFE57373); // Red color for warnings

    return _SettingsPageTemplate(
      title: 'Other',
      currentIndex: 3,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ANDROID AUTO SECTION
          Text(
            'ANDROID AUTO',
            style: AppTypography.caption(context).copyWith(
              color: ref.watch(themeIconActiveColorProvider),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Remember to enable "Unknown sources" in the Developer Settings of Android Auto.',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildToggleItem(
            context,
            ref,
            'Android Auto',
            'Enable Android Auto support',
            false,
            () {},
          ),
          const SizedBox(height: AppSpacing.xl),

          // SEARCH HISTORY SECTION
          Text(
            'SEARCH HISTORY',
            style: AppTypography.caption(context).copyWith(
              color: ref.watch(themeIconActiveColorProvider),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildToggleItem(
            context,
            ref,
            'Pause search history',
            'Neither save new searched queries nor show history',
            false,
            () {},
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildActionItem(
            ref,
            context,
            'Clear search history',
            'History is empty',
            () {},
          ),
          const SizedBox(height: AppSpacing.xl),

          // SERVICE LIFETIME SECTION
          Text(
            'SERVICE LIFETIME',
            style: AppTypography.caption(context).copyWith(
              color: ref.watch(themeIconActiveColorProvider),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'If battery optimizations are applied, the playback notification can suddenly disappear when paused.',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: warningColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Since Android 12, disabling battery optimizations is required for the "Invincible service" option to take effect.',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildActionItem(
            ref,
            context,
            'Ignore battery optimizations',
            'Disable background restrictions',
            () {},
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildToggleItem(
            context,
            ref,
            'Invincible service',
            'When turning off battery optimizations is not enough',
            false,
            () {},
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem(
    BuildContext context, // ✅ ADD THIS
    WidgetRef ref,
    String title,
    String subtitle,
    bool value,
    VoidCallback onChanged,
  ) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.subtitle(context).copyWith(
                  fontWeight: FontWeight.w500,
                  color: textPrimaryColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: textSecondaryColor),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: (_) => onChanged(),
          activeColor: iconActiveColor,
        ),
      ],
    );
  }

  Widget _buildActionItem(
    WidgetRef ref,
    BuildContext context,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.subtitle(
              context,
            ).copyWith(fontWeight: FontWeight.w500, color: textPrimaryColor),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondaryColor),
          ),
        ],
      ),
    );
  }
}

// Template for settings pages
class _SettingsPageTemplate extends ConsumerWidget {
  final String title;
  final int currentIndex;
  final Widget content;

  const _SettingsPageTemplate({
    required this.title,
    required this.currentIndex,
    required this.content,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, ref),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(context, ref),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [content, const SizedBox(height: 100)],
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

  Widget _buildTopBar(BuildContext context, WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.chevron_left, color: textPrimaryColor, size: 28),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                title,
                style: AppTypography.pageTitle(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final sidebarLabelColor = ref.watch(themeTextPrimaryColorProvider);
    final sidebarLabelActiveColor = ref.watch(themeIconActiveColorProvider);

    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: sidebarLabelActiveColor);

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              context,
              icon: Icons.edit_square,
              label: '',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: -1,
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              context,
              label: 'Player',
              isActive: currentIndex == 0,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 0
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 0,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Cache',
              isActive: currentIndex == 1,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 1
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 1,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Database',
              isActive: currentIndex == 2,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 2
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 2,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Other',
              isActive: currentIndex == 3,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 3
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 3,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'About',
              isActive: currentIndex == 4,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 4
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 4,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context, {
    IconData? icon,
    required String label,
    bool isActive = false,
    required Color iconActiveColor,
    required Color iconInactiveColor,
    required TextStyle labelStyle,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          _navigateToPage(context, index, currentIndex: currentIndex);
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
                color: isActive ? iconActiveColor : iconInactiveColor,
              ),
              const SizedBox(height: 16),
            ],
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: labelStyle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

    Navigator.of(context).pushReplacementDirectional(
      page,
      currentIndex: currentIndex,
      targetIndex: targetIndex,
    );
  }
}
