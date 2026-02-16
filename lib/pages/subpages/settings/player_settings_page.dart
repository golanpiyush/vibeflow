// lib/pages/settings/player_settings_page.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart'
    show AudioService, AudioServiceConfig;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/database/profile_service.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart';
import 'package:vibeflow/pages/audio_equalizer_page.dart';
import 'package:vibeflow/pages/subpages/settings/about_page.dart';
import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/other_page.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/widgets/coming_soon_item.dart';

final audioHandlerProvider = Provider<BackgroundAudioHandler?>((ref) {
  return null; // Will be set when AudioService initializes
});

// Add this StateProvider to track settings
final resumePlaybackEnabledProvider = StateProvider<bool>((ref) => false);
final persistentQueueEnabledProvider = StateProvider<bool>((ref) => false);
final loudnessNormalizationEnabledProvider = StateProvider<bool>(
  (ref) => false,
);
final lineByLineLyricsEnabledProvider = StateProvider<bool>((ref) => false);

// Update the PlayerSettingsPage widget:
class PlayerSettingsPage extends ConsumerStatefulWidget {
  const PlayerSettingsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends ConsumerState<PlayerSettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  // In player_settings_page.dart, update _loadSettings:
  Future<void> _loadSettings() async {
    try {
      final handler = getAudioHandler();
      if (handler != null) {
        ref.read(resumePlaybackEnabledProvider.notifier).state =
            handler.resumePlaybackEnabled;
        ref.read(persistentQueueEnabledProvider.notifier).state =
            handler.persistentQueueEnabled;
        ref.read(loudnessNormalizationEnabledProvider.notifier).state =
            handler.loudnessNormalizationEnabled;
        ref.read(lineByLineLyricsEnabledProvider.notifier).state =
            handler.lineByLineLyricsEnabled;
        print(
          '✅ [UI] Settings loaded - Resume: ${handler.resumePlaybackEnabled}, Normalization: ${handler.loudnessNormalizationEnabled}',
        );
      } else {
        print('⚠️ [UI] Audio handler not available yet');

        await Future.delayed(const Duration(milliseconds: 500));
        final retryHandler = getAudioHandler();
        if (retryHandler != null && mounted) {
          ref.read(resumePlaybackEnabledProvider.notifier).state =
              retryHandler.resumePlaybackEnabled;
          ref.read(persistentQueueEnabledProvider.notifier).state =
              retryHandler.persistentQueueEnabled;
          ref.read(loudnessNormalizationEnabledProvider.notifier).state =
              retryHandler.loudnessNormalizationEnabled;

          print('✅ [UI] Settings loaded on retry');
        }
      }
    } catch (e) {
      print('❌ [UI] Error loading settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final resumePlaybackEnabled = ref.watch(resumePlaybackEnabledProvider);
    final loudnessNormalizationEnabled = ref.watch(
      loudnessNormalizationEnabledProvider,
    );
    final persistentQueueEnabled = ref.watch(persistentQueueEnabledProvider);
    final iconActiveColor = colorScheme.primary;
    final textPrimaryColor = colorScheme.onSurface;
    final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);

    return _SettingsPageTemplate(
      title: 'Players',
      currentIndex: 0,
      themeData: themeData,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PLAYER SECTION
          Text(
            'PLAYER',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          ComingSoonToggleItem(
            title: 'Persistent queue',
            subtitle: 'Save and restore playing songs',
            value: false,
          ),

          const SizedBox(height: AppSpacing.lg),

          _buildToggleItem(
            'Resume playback',
            'When a wired or Bluetooth device is connected',
            resumePlaybackEnabled,
            () async {
              final handler = getAudioHandler();
              if (handler == null) {
                HapticFeedbackService().vibratingForNotAllowed();
                return;
              }

              final notifier = ref.read(resumePlaybackEnabledProvider.notifier);
              final newValue = !notifier.state;

              try {
                await handler.setResumePlaybackEnabled(newValue);
                notifier.state = newValue;

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newValue ? 'Auto-resume enabled' : 'Auto-resume disabled',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                HapticFeedbackService().vibrateAudioError();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to update setting'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),

          const SizedBox(height: AppSpacing.xl),

          // AUDIO SECTION
          Text(
            'AUDIO',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          _buildToggleItem(
            'Loudness normalization',
            'Normalize volume across tracks',
            loudnessNormalizationEnabled,
            () async {
              final handler = getAudioHandler();
              if (handler == null) {
                HapticFeedbackService().vibratingForNotAllowed();
                return;
              }

              final notifier = ref.read(
                loudnessNormalizationEnabledProvider.notifier,
              );
              final newValue = !notifier.state;

              try {
                await handler.setLoudnessNormalizationEnabled(newValue);
                notifier.state = newValue;

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newValue
                          ? 'Normalization enabled'
                          : 'Normalization disabled',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                HapticFeedbackService().vibrateAudioError();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to update setting'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),

          const SizedBox(height: AppSpacing.lg),

          _buildNavigationItem(
            context,
            'Equalizer',
            'Adjust sound frequencies',
            () {
              Navigator.of(
                context,
              ).pushMaterialFadeThrough(const AudioEqualizerPage());
            },
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconInactiveColor: textSecondaryColor,
          ),

          const SizedBox(height: AppSpacing.xl),

          // PLAYBACK SECTION
          Text(
            'PLAYBACK',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GestureDetector(
            onTap: () {
              unawaited(HapticFeedbackService().vibratingForNotAllowed());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cannot be changed'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: _buildSettingItem(
              'Audio quality',
              'Auto',
              textPrimaryColor: textPrimaryColor,
              textSecondaryColor: textSecondaryColor,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          ComingSoonItem(title: 'Crossfade', subtitle: 'Off'),

          const SizedBox(height: AppSpacing.lg),

          if (ref.watch(supabaseClientProvider).auth.currentUser != null) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              'BETA MODE',
              style: AppTypography.caption(context).copyWith(
                color: iconActiveColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            ref
                .watch(hasAccessCodeProvider)
                .when(
                  data: (hasAccessCode) {
                    if (!hasAccessCode) return const SizedBox.shrink();

                    // Watch current user profile for beta status
                    final userProfile = ref.watch(currentUserProfileProvider);

                    return userProfile.when(
                      data: (profile) {
                        final isBetaEnabled =
                            profile?['is_beta_tester'] ?? false;

                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: AnimatedBetaButton(
                                isBetaEnabled: isBetaEnabled,
                                onPressed: () =>
                                    _toggleBetaTester(context, ref),
                                accentColor: iconActiveColor,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        );
                      },
                      loading: () => Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.science),
                              label: const Text('Beta Features'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
          ],
          const SizedBox(height: AppSpacing.lg),

          // Line-by-line lyrics toggle
          _buildToggleItem(
            'Line-by-line lyrics',
            'Spotify-style synchronized lyrics',
            ref.watch(lineByLineLyricsEnabledProvider),
            () async {
              final handler = getAudioHandler();
              if (handler == null) {
                HapticFeedbackService().vibratingForNotAllowed();
                return;
              }

              final notifier = ref.read(
                lineByLineLyricsEnabledProvider.notifier,
              );
              final newValue = !notifier.state;

              try {
                await handler.setLineByLineLyricsEnabled(newValue);
                notifier.state = newValue;

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newValue
                          ? 'Line-by-line lyrics enabled'
                          : 'Line-by-line lyrics disabled',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                HapticFeedbackService().vibrateAudioError();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to update setting'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    String title,
    String value, {
    required Color textPrimaryColor,
    required Color textSecondaryColor,
  }) {
    return Column(
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
          value,
          style: AppTypography.caption(
            context,
          ).copyWith(color: textSecondaryColor),
        ),
      ],
    );
  }

  Widget _buildToggleItem(
    String title,
    String subtitle,
    bool value,
    VoidCallback onChanged, {
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
          onChanged: (_) => onChanged(),
          activeColor: iconActiveColor,
        ),
      ],
    );
  }

  Widget _buildNavigationItem(
    BuildContext context,
    String title,
    String subtitle,
    VoidCallback onTap, {
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required Color iconInactiveColor,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: textSecondaryColor),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: iconInactiveColor, size: 24),
        ],
      ),
    );
  }

  Future<void> _toggleBetaTester(BuildContext context, WidgetRef ref) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Get current status
      final profile = await ref.read(currentUserProfileProvider.future);
      final currentStatus = profile?['is_beta_tester'] ?? false;
      final newStatus = !currentStatus;

      // Update in database
      await ref
          .read(supabaseClientProvider)
          .from('profiles')
          .update({'is_beta_tester': newStatus})
          .eq('id', userId);

      // Refresh the profile provider
      ref.invalidate(currentUserProfileProvider);

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus ? 'Beta features enabled ✨' : 'Beta features disabled',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// Template for settings pages
class _SettingsPageTemplate extends ConsumerWidget {
  final String title;
  final int currentIndex;
  final Widget content;
  final ThemeData themeData;

  const _SettingsPageTemplate({
    required this.title,
    required this.currentIndex,
    required this.content,
    required this.themeData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

// AnimatedBetaButton Widget - Add this as a separate class
class AnimatedBetaButton extends StatefulWidget {
  final bool isBetaEnabled;
  final VoidCallback onPressed;
  final Color accentColor;

  const AnimatedBetaButton({
    Key? key,
    required this.isBetaEnabled,
    required this.onPressed,
    required this.accentColor,
  }) : super(key: key);

  @override
  State<AnimatedBetaButton> createState() => _AnimatedBetaButtonState();
}

class _AnimatedBetaButtonState extends State<AnimatedBetaButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePress() {
    _controller.forward().then((_) {
      _controller.reset();
      widget.onPressed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: widget.isBetaEnabled ? Colors.green : widget.accentColor,
          width: 2,
        ),
        color: widget.isBetaEnabled
            ? Colors.green.withOpacity(0.1)
            : Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handlePress,
          borderRadius: BorderRadius.circular(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RotationTransition(
                  turns: _rotationAnimation,
                  child: Icon(
                    widget.isBetaEnabled ? Icons.check_circle : Icons.science,
                    color: widget.isBetaEnabled
                        ? Colors.green
                        : widget.accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: widget.isBetaEnabled
                        ? Colors.green
                        : widget.accentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  child: Text(
                    widget.isBetaEnabled ? 'Beta Enabled' : 'Beta Features',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
