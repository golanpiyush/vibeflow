// lib/pages/subpages/settings/about_page.dart - COMPLETE VERSION WITH BACKGROUND UPDATES

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/installer_services/update_manager_service.dart';

import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/other_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/providers/app_update_settings_provider.dart';
import 'package:vibeflow/utils/page_transitions.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String? _lastCheckTime;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    // _loadLastCheckTime();
  }

  // Future<void> _loadLastCheckTime() async {
  //   final lastCheck = await BackgroundUpdateService.getLastCheckTime();
  //   if (mounted) {
  //     setState(() {
  //       _lastCheckTime = BackgroundUpdateService.formatLastCheckTime(lastCheck);
  //     });
  //   }
  // }

  // Future<void> _manualUpdateCheck() async {
  //   if (_isCheckingUpdate) return;

  //   setState(() {
  //     _isCheckingUpdate = true;
  //   });

  //   await BackgroundUpdateService.manualUpdateCheck(
  //     onResult: (result) {
  //       if (mounted) {
  //         setState(() {
  //           _isCheckingUpdate = false;
  //         });

  //         _loadLastCheckTime(); // Refresh last check time

  //         // Show result to user
  //         String message;
  //         Color backgroundColor;

  //         switch (result.status) {
  //           case UpdateStatus.available:
  //             message =
  //                 '🎉 Update available: v${result.updateInfo!.latestVersion}';
  //             backgroundColor = Colors.green;
  //             break;
  //           case UpdateStatus.upToDate:
  //             message = '✅ You\'re on the latest version';
  //             backgroundColor = Colors.blue;
  //             break;
  //           case UpdateStatus.error:
  //             message = '❌ ${result.message}';
  //             backgroundColor = Colors.red;
  //             break;
  //         }

  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //             content: Text(message),
  //             backgroundColor: backgroundColor,
  //             duration: const Duration(seconds: 3),
  //           ),
  //         );
  //       }
  //     },
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final backgroundColor = colorScheme.background;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xxxl),
            _buildTopBar(context, colorScheme),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(context, colorScheme),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<String>(
                            future: _getAppVersion(),
                            builder: (context, snapshot) {
                              final text =
                                  snapshot.data ?? 'v-- by golanpiyush';
                              return Text(
                                text,
                                style: AppTypography.subtitle(context).copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                  fontSize: 16,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.xxxl),

                          // SOCIAL Section
                          Text(
                            'SOCIAL',
                            style: AppTypography.caption(context).copyWith(
                              color: ref.watch(themeIconActiveColorProvider),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            context,
                            'GitHub',
                            'View the source code',
                            ref: ref,
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
                            style: AppTypography.caption(context).copyWith(
                              color: ref.watch(themeIconActiveColorProvider),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            context,
                            'Report an issue',
                            'You will be redirected to GitHub',
                            ref: ref,
                            onTap: () {
                              _launchUrl(
                                'https://github.com/golanpiyush/vibeflow/issues',
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            context,
                            'Request a feature or suggest an idea',
                            'You will be redirected to GitHub',
                            ref: ref,
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
                            style: AppTypography.caption(context).copyWith(
                              color: ref.watch(themeIconActiveColorProvider),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildClickableItem(
                            context,
                            'vfsfitvnm for ViMusic',
                            'And For inspiring this project',
                            ref: ref,
                            onTap: () {
                              _launchUrl(
                                'https://github.com/vfsfitvnm/ViMusic',
                              );
                            },
                          ),

                          // const SizedBox(height: AppSpacing.xl),

                          // // UPDATE SETTINGS Section
                          // Text(
                          //   'UPDATE SETTINGS',
                          //   style: AppTypography.caption(context).copyWith(
                          //     color: ref.watch(themeIconActiveColorProvider),
                          //     fontWeight: FontWeight.w600,
                          //     letterSpacing: 1.2,
                          //   ),
                          // ),
                          // const SizedBox(height: AppSpacing.lg),
                          // _buildToggleItem(
                          //   context,
                          //   'Update Notifications',
                          //   'Get notified when new updates are available (auto-checks every 3 hours)',
                          //   ref: ref,
                          //   value: ref.watch(updateNotificationsProvider),
                          //   onToggle: () async {
                          //     await ref
                          //         .read(updateNotificationsProvider.notifier)
                          //         .toggle();

                          //     // Start or stop background checks based on setting
                          //     if (ref.read(updateNotificationsProvider)) {
                          //       await BackgroundUpdateService.startPeriodicUpdateCheck();
                          //     } else {
                          //       await BackgroundUpdateService.stopPeriodicUpdateCheck();
                          //     }
                          //   },
                          // ),
                          // const SizedBox(height: AppSpacing.lg),
                          // _buildToggleItem(
                          //   context,
                          //   'Auto-check on app start',
                          //   'Automatically check for updates when app starts',
                          //   ref: ref,
                          //   value: ref.watch(autoUpdateOnStartProvider),
                          //   onToggle: () {
                          //     ref
                          //         .read(autoUpdateOnStartProvider.notifier)
                          //         .toggle();
                          //   },
                          // ),
                          // const SizedBox(height: AppSpacing.lg),

                          // // Manual check button
                          // _buildManualCheckButton(context, ref),
                          // const SizedBox(height: AppSpacing.xxxl),
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

  Widget _buildTopBar(BuildContext context, ColorScheme colorScheme) {
    final textPrimaryColor = colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 12),
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
                'About',
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

  Future<String> _getAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    return 'v${info.version} Build:(${info.buildNumber}) by golanpiyush';
  }

  // Widget _buildManualCheckButton(BuildContext context, WidgetRef ref) {
  //   final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
  //   final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
  //   final iconActiveColor = ref.watch(themeIconActiveColorProvider);

  //   return GestureDetector(
  //     onTap: _isCheckingUpdate ? null : _manualUpdateCheck,
  //     child: Container(
  //       padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  //       decoration: BoxDecoration(
  //         color: iconActiveColor.withOpacity(0.1),
  //         borderRadius: BorderRadius.circular(12),
  //         border: Border.all(color: iconActiveColor.withOpacity(0.3), width: 1),
  //       ),
  //       child: Row(
  //         children: [
  //           Expanded(
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 Text(
  //                   'Check for updates now',
  //                   style: AppTypography.subtitle(context).copyWith(
  //                     fontWeight: FontWeight.w600,
  //                     fontSize: 16,
  //                     color: textPrimaryColor,
  //                   ),
  //                 ),
  //                 const SizedBox(height: 4),
  //                 Text(
  //                   _lastCheckTime != null
  //                       ? 'Last checked: $_lastCheckTime'
  //                       : 'Never checked',
  //                   style: AppTypography.caption(
  //                     context,
  //                   ).copyWith(fontSize: 13, color: textSecondaryColor),
  //                 ),
  //               ],
  //             ),
  //           ),
  //           const SizedBox(width: 12),
  //           if (_isCheckingUpdate)
  //             SizedBox(
  //               width: 24,
  //               height: 24,
  //               child: CircularProgressIndicator(
  //                 strokeWidth: 2,
  //                 valueColor: AlwaysStoppedAnimation<Color>(iconActiveColor),
  //               ),
  //             )
  //           else
  //             Icon(Icons.refresh, color: iconActiveColor, size: 24),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildSidebar(BuildContext context, ColorScheme colorScheme) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = colorScheme.primary;
    final iconInactiveColor = colorScheme.onSurface.withOpacity(0.6);
    final sidebarLabelColor = colorScheme.onSurface;
    final sidebarLabelActiveColor = colorScheme.primary;

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
              label: 'Appearance',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: 0,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Player',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: 1,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Cache',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: 2,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Database',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: 3,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Other',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: 4,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'About',
              isActive: true,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelActiveStyle,
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
    required Color iconActiveColor,
    required Color iconInactiveColor,
    required TextStyle labelStyle,
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

  Widget _buildToggleItem(
    BuildContext context,
    String title,
    String subtitle, {
    required WidgetRef ref,
    required bool value,
    required VoidCallback onToggle,
  }) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.subtitle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(fontSize: 14, color: textSecondaryColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: value,
              onChanged: (_) => onToggle(),
              activeColor: iconActiveColor,
              activeTrackColor: iconActiveColor.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClickableItem(
    BuildContext context,
    String title,
    String subtitle, {
    required WidgetRef ref,
    VoidCallback? onTap,
  }) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.subtitle(context).copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: textPrimaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTypography.caption(
                context,
              ).copyWith(fontSize: 14, color: textSecondaryColor),
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

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }
}
