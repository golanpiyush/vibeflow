import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';

import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/other_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/utils/page_transitions.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(context),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSpacing.lg),
                          // Version subtitle
                          Text(
                            'v1.0.0 by golanpiyush',
                            style: AppTypography.subtitle.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxxl),

                          // SOCIAL Section
                          Text(
                            'SOCIAL',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.iconActive,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            'GitHub',
                            'View the source code',
                            onTap: () {
                              _launchUrl(
                                'https://github.com/golanpiyush/vibeflow',
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.xxxl),

                          // TROUBLESHOOTING Section
                          Text(
                            'TROUBLESHOOTING',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.iconActive,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            'Report an issue',
                            'You will be redirected to GitHub',
                            onTap: () {
                              _launchUrl(
                                'https://github.com/golanpiyush/vibeflow/issues',
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            'Request a feature or suggest an idea',
                            'You will be redirected to GitHub',
                            onTap: () {
                              _launchUrl(
                                'https://github.com/golanpiyush/vibeflow/issues',
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.xxxl),

                          // SPECIAL THANKS Section
                          Text(
                            'SPECIAL THANKS TO',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.iconActive,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            'vfsfitvnm for ViMusic',
                            'And For inspiring this project',
                            // ViMusic thanks
                            onTap: () {
                              _launchUrl(
                                'https://github.com/vfsfitvnm/ViMusic',
                              );
                            },
                          ),
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

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24, // Added top padding
        bottom: 12,
      ),
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
              child: Text('About', style: AppTypography.pageTitle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final double availableHeight = MediaQuery.of(context).size.height;

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
              index: -1,
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(context, label: 'Appearance', index: 0),
            const SizedBox(height: 24),
            _buildSidebarItem(context, label: 'Player', index: 1),
            const SizedBox(height: 24),
            _buildSidebarItem(context, label: 'Cache', index: 2),
            const SizedBox(height: 24),
            _buildSidebarItem(context, label: 'Database', index: 3),
            const SizedBox(height: 24),
            _buildSidebarItem(context, label: 'Other', index: 4),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'About',
              isActive: true,
              index: 5,
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
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          _navigateToPage(context, index, currentIndex: 5);
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
        // Appearance page - add your page here
        return;
      case 1:
        page = const PlayerSettingsPage();
        break;
      case 2:
        page = const CachePage();
        break;
      case 3:
        page = const DatabasePage();
        break;
      case 4:
        page = const OtherPage();
        break;
      case 5:
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

  Widget _buildClickableItem(
    String title,
    String subtitle, {
    VoidCallback? onTap,
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
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }
}
