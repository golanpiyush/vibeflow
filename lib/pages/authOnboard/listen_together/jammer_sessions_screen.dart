// lib/pages/listen_together/jammer_sessions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/models/listening_together.dart';
import 'package:vibeflow/providers/listen_together_providers.dart';

/// Jammer Sessions Screen
/// Shows all active and past sessions
class JammerSessionsScreen extends ConsumerStatefulWidget {
  const JammerSessionsScreen({super.key});

  @override
  ConsumerState<JammerSessionsScreen> createState() =>
      _JammerSessionsScreenState();
}

class _JammerSessionsScreenState extends ConsumerState<JammerSessionsScreen> {
  int _selectedTab = 0; // 0 = Active, 1 = History

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final primaryColor = colorScheme.primary;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final surfaceColor = colorScheme.surface;

    return Column(
      children: [
        // Tab Selector
        Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  label: 'Active',
                  isSelected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                  themeData: themeData,
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  label: 'History',
                  isSelected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                  themeData: themeData,
                ),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: _selectedTab == 0
              ? _buildActiveSessionsTab(themeData)
              : _buildHistoryTab(themeData),
        ),
        const SizedBox(height: AppSpacing.fourxxxl),
      ],
    );
  }

  Widget _buildTabButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData themeData,
  }) {
    final colorScheme = themeData.colorScheme;
    final primaryColor = colorScheme.primary;
    final textColor = colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.subtitle(context).copyWith(
            color: isSelected ? Colors.white : textColor.withOpacity(0.6),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSessionsTab(ThemeData themeData) {
    final activeSession = ref.watch(activeSessionProvider);
    final colorScheme = themeData.colorScheme;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final primaryColor = colorScheme.primary;

    return activeSession.when(
      data: (session) {
        if (session == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.music_off, size: 64, color: textSecondary),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'No Active Sessions',
                  style: AppTypography.sectionHeader(
                    context,
                  ).copyWith(color: textPrimary, fontSize: 20),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Start or join a session to jam with friends',
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildActiveSessionCard(session, themeData),
              const SizedBox(height: AppSpacing.xl),
              _buildSessionDetails(session, themeData),
            ],
          ),
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: primaryColor)),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: textSecondary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Error loading session',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error.toString(),
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(
    ListeningSession session,
    ThemeData themeData,
  ) {
    final colorScheme = themeData.colorScheme;
    final primaryColor = colorScheme.primary;
    final surfaceColor = colorScheme.surface;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: primaryColor.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  session.isHost
                      ? Icons.broadcast_on_personal
                      : Icons.headphones,
                  color: primaryColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.sessionName ?? 'Jam Session',
                      style: AppTypography.songTitle(context).copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.isHost
                          ? 'You\'re hosting'
                          : 'Hosted by ${session.hostUsername}',
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE',
                      style: AppTypography.caption(context).copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: themeData.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Row(
              children: [
                Icon(Icons.people, color: primaryColor, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${session.participantCount} ${session.participantCount == 1 ? 'person' : 'people'} listening',
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: textPrimary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (session.isHost) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _endSession(session.id),
                icon: const Icon(Icons.stop_circle, size: 18),
                label: const Text('End Session'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _leaveSession(session.id),
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text('Leave Session'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: surfaceColor,
                  foregroundColor: textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                    side: BorderSide(color: themeData.dividerColor),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionDetails(ListeningSession session, ThemeData themeData) {
    final colorScheme = themeData.colorScheme;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final surfaceColor = colorScheme.surface;

    final startTime = DateTime.now().difference(session.createdAt);
    final hours = startTime.inHours;
    final minutes = startTime.inMinutes % 60;
    final duration = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Session Details',
          style: AppTypography.sectionHeader(
            context,
          ).copyWith(color: textPrimary, fontSize: 16),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          ),
          child: Column(
            children: [
              _buildDetailRow(
                icon: Icons.access_time,
                label: 'Duration',
                value: duration,
                themeData: themeData,
              ),
              const SizedBox(height: AppSpacing.md),
              _buildDetailRow(
                icon: Icons.schedule,
                label: 'Started',
                value: _formatTime(session.createdAt),
                themeData: themeData,
              ),
              const SizedBox(height: AppSpacing.md),
              _buildDetailRow(
                icon: Icons.person,
                label: 'Host',
                value: session.hostUsername,
                themeData: themeData,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData themeData,
  }) {
    final colorScheme = themeData.colorScheme;
    final primaryColor = colorScheme.primary;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);

    return Row(
      children: [
        Icon(icon, size: 20, color: primaryColor),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: textSecondary, fontSize: 11),
              ),
              Text(
                value,
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textPrimary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(ThemeData themeData) {
    final colorScheme = themeData.colorScheme;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final surfaceColor = colorScheme.surface;

    // TODO: Fetch session history from provider
    // For now, showing placeholder
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: textSecondary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No Session History',
            style: AppTypography.sectionHeader(
              context,
            ).copyWith(color: textPrimary, fontSize: 20),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your past sessions will appear here',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Future<void> _endSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text(
          'This will end the session for all participants. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(sessionControllerProvider.notifier)
          .endSession();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session ended')));
        ref.invalidate(activeSessionProvider);
      }
    }
  }

  Future<void> _leaveSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Session?'),
        content: const Text('You will stop listening with this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(sessionControllerProvider.notifier)
          .leaveSession();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Left session')));
        ref.invalidate(activeSessionProvider);
      }
    }
  }
}
