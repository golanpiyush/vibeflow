// lib/pages/listen_together/jammer_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/database/profile_service.dart';
import 'package:vibeflow/providers/jammer_status_provider.dart';

/// Jammer Settings Screen
/// Manage Jammer mode preferences and permissions
class JammerSettingsScreen extends ConsumerStatefulWidget {
  const JammerSettingsScreen({super.key});

  @override
  ConsumerState<JammerSettingsScreen> createState() =>
      _JammerSettingsScreenState();
}

class _JammerSettingsScreenState extends ConsumerState<JammerSettingsScreen> {
  bool _isJammerOn = false;
  bool _showListeningActivity = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;

      final response = await Supabase.instance.client
          .from('profiles')
          .select('is_jammer_on, show_listening_activity')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _isJammerOn = response['is_jammer_on'] ?? false;
          _showListeningActivity = response['show_listening_activity'] ?? true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({
            'is_jammer_on': _isJammerOn,
            'show_listening_activity': _showListeningActivity,
          })
          .eq('id', currentUser.id);

      // Refresh jammer status provider
      ref.invalidate(jammerStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final primaryColor = colorScheme.primary;
    final surfaceColor = colorScheme.surface;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final bgColor = themeData.scaffoldBackgroundColor;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: primaryColor));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Jammer Settings',
            style: AppTypography.sectionHeader(
              context,
            ).copyWith(color: textPrimary, fontSize: 24),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Manage your Jammer mode preferences',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Jammer Mode Toggle
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              border: Border.all(
                color: _isJammerOn
                    ? Colors.green.withOpacity(0.5)
                    : themeData.dividerColor,
                width: _isJammerOn ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: _isJammerOn
                            ? Colors.green.withOpacity(0.2)
                            : primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                      ),
                      child: Icon(
                        _isJammerOn ? Icons.music_note : Icons.music_off,
                        color: _isJammerOn ? Colors.green : primaryColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Jammer Mode',
                            style: AppTypography.songTitle(context).copyWith(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isJammerOn ? 'Enabled' : 'Disabled',
                            style: AppTypography.caption(context).copyWith(
                              color: _isJammerOn ? Colors.green : textSecondary,
                              fontWeight: _isJammerOn ? FontWeight.w600 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isJammerOn,
                      onChanged: (value) {
                        setState(() {
                          _isJammerOn = value;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: primaryColor),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Enable to host or join jam sessions with friends',
                          style: AppTypography.caption(
                            context,
                          ).copyWith(color: textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Listening Activity Toggle
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                      ),
                      child: Icon(
                        Icons.visibility,
                        color: primaryColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Show Listening Activity',
                            style: AppTypography.songTitle(context).copyWith(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Let friends see what you\'re listening to',
                            style: AppTypography.caption(
                              context,
                            ).copyWith(color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _showListeningActivity,
                      onChanged: (value) {
                        setState(() {
                          _showListeningActivity = value;
                        });
                      },
                      activeColor: primaryColor,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Privacy Information
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              border: Border.all(color: primaryColor.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.privacy_tip, color: primaryColor, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Privacy & Permissions',
                      style: AppTypography.subtitle(context).copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _buildPrivacyPoint(
                  'Only mutual followers can invite you to sessions',
                  themeData,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildPrivacyPoint(
                  'Your listening activity is only visible when enabled',
                  themeData,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildPrivacyPoint(
                  'You can leave any session at any time',
                  themeData,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Save Settings',
                      style: AppTypography.songTitle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // About Section
          _buildAboutSection(themeData),
        ],
      ),
    );
  }

  Widget _buildPrivacyPoint(String text, ThemeData themeData) {
    final textSecondary = themeData.colorScheme.onSurface.withOpacity(0.6);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: textSecondary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(ThemeData themeData) {
    final colorScheme = themeData.colorScheme;
    final surfaceColor = colorScheme.surface;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About Jammer Mode',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Jammer Mode lets you listen to music in perfect sync with your friends. When you join a session, everyone hears the same song at the exact same time, creating a shared listening experience.',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondary, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'For the best experience:',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildPrivacyPoint(
            'Be within 5 meters of other participants',
            themeData,
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildPrivacyPoint('Use good internet connection', themeData),
          const SizedBox(height: AppSpacing.xs),
          _buildPrivacyPoint(
            'Make sure both users follow each other',
            themeData,
          ),
          const SizedBox(height: AppSpacing.fourxxxl),
        ],
      ),
    );
  }
}
