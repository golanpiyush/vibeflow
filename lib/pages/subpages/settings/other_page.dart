import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/subpages/settings/about_page.dart';
import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/api_base/yt_music_search_suggestor.dart';
import 'package:vibeflow/widgets/coming_soon_item.dart';

class OtherPage extends ConsumerStatefulWidget {
  const OtherPage({Key? key}) : super(key: key);

  @override
  ConsumerState<OtherPage> createState() => _OtherPageState();
}

class _OtherPageState extends ConsumerState<OtherPage> {
  bool _isSearchHistoryPaused = false;
  bool _isInvincibleServiceEnabled = false;
  bool _isLoadingHistory = false;
  bool _isBatteryOptimizationIgnored = false;
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadHistoryCount();
    _checkBatteryOptimizationStatus();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      setState(() {
        _isSearchHistoryPaused =
            prefs.getBool('search_history_paused') ?? false;
        _isInvincibleServiceEnabled =
            prefs.getBool('invincible_service_enabled') ?? false;
      });
    } catch (e) {
      print('❌ Error loading settings: $e');
    }
  }

  Future<void> _loadHistoryCount() async {
    try {
      final helper = YTMusicSuggestionsHelper();
      final history = await helper.getSearchHistory();
      helper.dispose();

      if (!mounted) return;

      setState(() {
        _historyCount = history.length;
      });
    } catch (e) {
      print('❌ Error loading history count: $e');
    }
  }

  Future<void> _checkBatteryOptimizationStatus() async {
    if (!Platform.isAndroid) return;

    try {
      // Check if battery optimization is ignored
      final status = await Permission.ignoreBatteryOptimizations.status;

      if (!mounted) return;

      setState(() {
        _isBatteryOptimizationIgnored = status.isGranted;
      });

      print(
        '🔋 Battery optimization status: ${status.isGranted ? "Ignored" : "Not ignored"}',
      );
    } catch (e) {
      print('❌ Error checking battery optimization: $e');
    }
  }

  // In _requestBatteryOptimizationExemption method - update the AlertDialog
  Future<void> _requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) {
      _showPlatformNotSupportedDialog();
      return;
    }

    try {
      // Check current status
      final status = await Permission.ignoreBatteryOptimizations.status;

      if (status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Battery optimization already disabled'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Show explanation dialog with theme-aware colors
      final colorScheme = Theme.of(context).colorScheme;

      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(
            'Disable Battery Optimization',
            style: TextStyle(color: colorScheme.onSurface),
          ),
          content: Text(
            'This will allow VibeFlow to run in the background without being killed by the system.\n\n'
            'Required for:\n'
            '• Uninterrupted playback\n'
            '• Persistent notifications\n'
            '• Invincible service\n\n'
            'You will be taken to Android settings to grant this permission.',
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.87)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.primary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (shouldProceed != true || !mounted) return;

      // Request permission
      final result = await Permission.ignoreBatteryOptimizations.request();

      if (!mounted) return;

      if (result.isGranted) {
        setState(() {
          _isBatteryOptimizationIgnored = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Battery optimization disabled successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (result.isPermanentlyDenied) {
        // Open app settings if permanently denied
        _showOpenSettingsDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permission denied. Some features may not work properly.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Error requesting battery optimization: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Update _showOpenSettingsDialog method
  void _showOpenSettingsDialog() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Open Settings',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: Text(
          'Battery optimization permission was denied. '
          'Please enable it manually in app settings for best performance.',
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.87)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colorScheme.primary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Update _showPlatformNotSupportedDialog method
  void _showPlatformNotSupportedDialog() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Not Available',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: Text(
          'Battery optimization settings are only available on Android.',
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.87)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  // Update _clearSearchHistory method's AlertDialog
  Future<void> _clearSearchHistory() async {
    final colorScheme = Theme.of(context).colorScheme;

    if (_historyCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('History is already empty'),
          backgroundColor: colorScheme.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Clear Search History',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: Text(
          'Delete all $_historyCount search entries?',
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.87)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: colorScheme.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoadingHistory = true);

    try {
      final helper = YTMusicSuggestionsHelper();
      await helper.clearHistory();
      helper.dispose();

      if (!mounted) return;

      setState(() {
        _historyCount = 0;
        _isLoadingHistory = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search history cleared'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      print('❌ Error clearing history: $e');
      if (!mounted) return;

      setState(() => _isLoadingHistory = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to clear history'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Update _toggleInvincibleService method's AlertDialog
  Future<void> _toggleInvincibleService(bool value) async {
    // Check if battery optimization is disabled first
    if (value && !_isBatteryOptimizationIgnored) {
      final colorScheme = Theme.of(context).colorScheme;

      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(
            'Battery Optimization Required',
            style: TextStyle(color: colorScheme.onSurface),
          ),
          content: Text(
            'Invincible service requires battery optimization to be disabled.\n\n'
            'Would you like to disable it now?',
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.87)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.primary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        await _requestBatteryOptimizationExemption();

        // Recheck status
        await _checkBatteryOptimizationStatus();

        if (!_isBatteryOptimizationIgnored) {
          // Still not granted, don't enable invincible service
          return;
        }
      } else {
        return;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('invincible_service_enabled', value);

      if (!mounted) return;

      setState(() {
        _isInvincibleServiceEnabled = value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Invincible service enabled - playback will persist'
                : 'Invincible service disabled',
          ),
          backgroundColor: value ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('❌ Error toggling invincible service: $e');
    }
  }

  Future<void> _toggleSearchHistoryPause(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('search_history_paused', value);

      if (!mounted) return;

      setState(() {
        _isSearchHistoryPaused = value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Search history paused - new searches won\'t be saved'
                : 'Search history resumed - searches will be saved',
          ),
          backgroundColor: value ? Colors.orange : Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('❌ Error toggling search history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Theme.of(context).colorScheme for proper theme support
    final colorScheme = Theme.of(context).colorScheme;
    final textPrimaryColor = colorScheme.onSurface;
    final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
    final iconActiveColor = colorScheme.primary;
    final warningColor = Color(0xFFE57373);

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
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Remember to enable "Unknown sources" in the Developer Settings of Android Auto.',
            style: AppTypography.captionSmall(
              context,
            ).copyWith(color: textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),

          ComingSoonToggleItem(
            title: 'Android Auto',
            subtitle: 'Enable Android Auto support',
            value: false,
          ),

          const SizedBox(height: AppSpacing.xl),

          // SEARCH HISTORY SECTION
          Text(
            'SEARCH HISTORY',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          _buildToggleItem(
            context,
            'Pause search history',
            'Neither save new searched queries nor show history',
            _isSearchHistoryPaused,
            _toggleSearchHistoryPause,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),

          const SizedBox(height: AppSpacing.lg),

          _buildActionItem(
            context,
            'Clear search history',
            _historyCount == 0
                ? 'History is empty'
                : '$_historyCount ${_historyCount == 1 ? "entry" : "entries"}',
            _isLoadingHistory ? null : _clearSearchHistory,
            isLoading: _isLoadingHistory,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),

          const SizedBox(height: AppSpacing.xl),

          // SERVICE LIFETIME SECTION
          Text(
            'SERVICE LIFETIME',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'If battery optimizations are applied, the playback notification can suddenly disappear when paused.',
            style: AppTypography.captionSmall(
              context,
            ).copyWith(color: warningColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Since Android 12, disabling battery optimizations is required for the "Invincible service" option to take effect.',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Battery optimization action
          _buildActionItem(
            context,
            'Ignore battery optimizations',
            _isBatteryOptimizationIgnored
                ? '✓ Battery optimizations ignored'
                : 'Tap to disable background restrictions',
            _requestBatteryOptimizationExemption,
            isSuccess: _isBatteryOptimizationIgnored,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),

          const SizedBox(height: AppSpacing.lg),

          _buildToggleItem(
            context,
            'Invincible service',
            'When turning off battery optimizations is not enough',
            _isInvincibleServiceEnabled,
            _toggleInvincibleService,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged, {
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required Color iconActiveColor,
  }) {
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
          onChanged: onChanged,
          activeColor: iconActiveColor,
        ),
      ],
    );
  }

  Widget _buildActionItem(
    BuildContext context,
    String title,
    String subtitle,
    VoidCallback? onTap, {
    bool isLoading = false,
    bool isSuccess = false,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required Color iconActiveColor,
  }) {
    final successColor = Colors.green;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
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
                      color: textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.caption(context).copyWith(
                      color: isSuccess ? successColor : textSecondaryColor,
                      fontWeight: isSuccess
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(iconActiveColor),
                ),
              )
            else if (isSuccess)
              Icon(Icons.check_circle, color: successColor, size: 24),
          ],
        ),
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
    final colorScheme = Theme.of(context).colorScheme;
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

  Widget _buildTopBar(BuildContext context, ColorScheme colorScheme) {
    final textPrimaryColor = colorScheme.onSurface;

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
        page = const AppearancePage();
        break;
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
