// lib/pages/listen_together/listen_together_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/models/listening_together.dart';
import 'package:vibeflow/pages/authOnboard/Screens/edit_profile.dart';
import 'package:vibeflow/providers/jammer_status_provider.dart';
import 'package:vibeflow/providers/listen_together_providers.dart';

/// Listen Together (Jammer) Home Screen
/// Shows options to host or join a nearby session
class ListenTogetherHomeScreen extends ConsumerStatefulWidget {
  const ListenTogetherHomeScreen({super.key});

  @override
  ConsumerState<ListenTogetherHomeScreen> createState() =>
      _ListenTogetherHomeScreenState();
}

class _ListenTogetherHomeScreenState
    extends ConsumerState<ListenTogetherHomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Check jammer status when screen loads
    Future.microtask(() {
      // Force refresh
      ref.read(jammerStatusProvider.notifier).refresh();
    });

    // Listen for jammer status changes
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      final jammerState = ref.read(jammerStatusProvider);
      jammerState.whenData((isJammerOn) {
        if (mounted) {
          ref.read(invitationControllerProvider.notifier).refresh();
        }
      });
    });
  }

  Future<void> _onReturnFromSettings() async {
    print('🔄 [JAMMER] Returned from settings, refreshing...');

    // Refresh jammer status
    await ref.read(jammerStatusProvider.notifier).refresh();

    // Give it a moment to load
    await Future.delayed(const Duration(milliseconds: 300));

    // Check if now enabled
    final jammerState = ref.read(jammerStatusProvider);
    jammerState.whenData((isJammerOn) {
      if (isJammerOn && mounted) {
        print('✅ [JAMMER] Now enabled! Loading invitations...');
        ref.read(invitationControllerProvider.notifier).refresh();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎵 Jammer Mode enabled! You can now jam with friends',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = ref.watch(activeSessionProvider);
    final invitations = ref.watch(invitationControllerProvider);
    final mutualFollowers = ref.watch(mutualFollowersProvider);
    final jammerStatus = ref.watch(jammerStatusProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            _buildTopBar(context),

            // Main Content
            Expanded(
              child: jammerStatus.when(
                data: (isJammerOn) {
                  if (!isJammerOn) {
                    // Show jammer disabled view
                    return _buildJammerDisabledView();
                  }

                  // Normal content when jammer is enabled
                  return activeSession.when(
                    data: (session) {
                      if (session != null) {
                        return _buildActiveSessionView(session);
                      }
                      return _buildMainContent(invitations, mutualFollowers);
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                    error: (error, stack) => _buildErrorView(error.toString()),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
                error: (error, stack) => _buildErrorView(error.toString()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJammerDisabledView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Icon
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.05),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.music_off,
                      size: 80,
                      color: AppColors.accent,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Jammer Mode is Disabled',
              style: AppTypography.sectionHeader(
                context,
              ).copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Enable Jammer Mode to sync music\nwith your friends in real-time',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              ),
              child: Column(
                children: [
                  _buildFeatureRow(
                    icon: Icons.headphones,
                    title: 'Listen Together',
                    description: 'Sync playback with friends',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildFeatureRow(
                    icon: Icons.people,
                    title: 'Host or Join',
                    description: 'Create or join jam sessions',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildFeatureRow(
                    icon: Icons.sync,
                    title: 'Real-time Sync',
                    description: 'Everyone hears the same beat',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back from listen together screen

                // Navigate to edit profile screen and wait
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfileScreen(),
                  ),
                );

                // Note: Can't call _onReturnFromSettings here because context is disposed
              },
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Go to Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Go Back',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: Icon(icon, color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.subtitle(context).copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.iconActive,
              size: 28,
            ),
          ),
          const Spacer(),
          Text('Jammer', style: AppTypography.pageTitle(context)),
        ],
      ),
    );
  }

  Widget _buildMainContent(
    List<SessionInvitation> invitations,
    AsyncValue<List<MutualFollower>> mutualFollowersAsync,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero Section
          _buildHeroSection(),

          const SizedBox(height: AppSpacing.xxxl),

          // Pending Invitations
          if (invitations.isNotEmpty) ...[
            _buildPendingInvitations(invitations),
            const SizedBox(height: AppSpacing.xxxl),
          ],

          // Host or Join Section
          _buildHostOrJoinSection(mutualFollowersAsync),

          const SizedBox(height: AppSpacing.xl),

          // How It Works
          _buildHowItWorks(),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withOpacity(0.2),
            AppColors.accent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.accent.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          // Animated Icon
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.1),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.headphones,
                    size: 64,
                    color: AppColors.accent,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Listen Together',
            style: AppTypography.sectionHeader(
              context,
            ).copyWith(color: AppColors.textPrimary, fontSize: 28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Share your music experience in real-time\nwith friends nearby',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingInvitations(List<SessionInvitation> invitations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.notifications_active,
              color: AppColors.accent,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Pending Invitations',
              style: AppTypography.sectionHeader(
                context,
              ).copyWith(fontSize: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${invitations.length}',
                style: AppTypography.caption(context).copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...invitations.map((invitation) {
          return _buildInvitationCard(invitation);
        }),
      ],
    );
  }

  Widget _buildInvitationCard(SessionInvitation invitation) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.accent.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Host Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.surfaceLight,
                backgroundImage: invitation.hostProfilePic != null
                    ? NetworkImage(invitation.hostProfilePic!)
                    : null,
                child: invitation.hostProfilePic == null
                    ? const Icon(Icons.person, color: AppColors.iconInactive)
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invitation.hostUsername,
                      style: AppTypography.songTitle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'invited you to jam',
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${invitation.participantCount}',
                      style: AppTypography.caption(context).copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (invitation.currentSongTitle != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.music_note,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Currently playing:',
                          style: AppTypography.caption(context).copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          invitation.currentSongTitle!,
                          style: AppTypography.caption(context).copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (invitation.currentSongArtists != null)
                          Text(
                            invitation.currentSongArtists!.join(', '),
                            style: AppTypography.caption(context).copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptInvitation(invitation),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                    ),
                  ),
                  child: const Text('Join'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(
                onPressed: () => _declineInvitation(invitation),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                    side: BorderSide(color: AppColors.divider, width: 1),
                  ),
                ),
                child: const Text('Decline'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHostOrJoinSection(
    AsyncValue<List<MutualFollower>> mutualFollowersAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start or Join',
          style: AppTypography.sectionHeader(context).copyWith(fontSize: 18),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: _buildHostCard(mutualFollowersAsync)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _buildJoinCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildHostCard(AsyncValue<List<MutualFollower>> mutualFollowersAsync) {
    final onlineCount = mutualFollowersAsync.when(
      data: (followers) => followers.where((f) => f.isOnline).length,
      loading: () => 0,
      error: (_, __) => 0,
    );

    return GestureDetector(
      onTap: () => _showCreateSessionDialog(mutualFollowersAsync),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(
            color: AppColors.accent.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.broadcast_on_personal,
                color: AppColors.accent,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Host',
              style: AppTypography.songTitle(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Start a session',
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (onlineCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$onlineCount online',
                  style: AppTypography.caption(context).copyWith(
                    color: AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJoinCard() {
    return GestureDetector(
      onTap: () => _startScanning(),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(
            color: _isScanning
                ? AppColors.success.withOpacity(0.5)
                : AppColors.divider,
            width: _isScanning ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: _isScanning
                    ? AppColors.success.withOpacity(0.2)
                    : AppColors.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: _isScanning
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.success,
                      ),
                    )
                  : const Icon(
                      Icons.radar,
                      color: AppColors.iconActive,
                      size: 32,
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _isScanning ? 'Scanning...' : 'Join',
              style: AppTypography.songTitle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: _isScanning ? AppColors.success : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _isScanning ? 'Looking nearby' : 'Find sessions',
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: AppTypography.songTitle(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildHowItWorksStep(
            icon: Icons.group_add,
            title: 'Mutual followers only',
            description: 'Only friends who follow each other can jam together',
          ),
          const SizedBox(height: AppSpacing.md),
          _buildHowItWorksStep(
            icon: Icons.headphones,
            title: 'Synchronized playback',
            description: 'Everyone hears the same thing at the same time',
          ),
          const SizedBox(height: AppSpacing.md),
          _buildHowItWorksStep(
            icon: Icons.location_on,
            title: 'Works best nearby',
            description: 'For the best experience, be within 5 meters',
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksStep({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.subtitle(context).copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveSessionView(ListeningSession session) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.celebration, color: AppColors.accent, size: 64),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'You\'re in a session!',
              style: AppTypography.sectionHeader(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              session.isHost
                  ? 'You\'re hosting: ${session.sessionName ?? "Session"}'
                  : 'Hosted by ${session.hostUsername}',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Navigate to active session screen
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(
                //     builder: (context) => ActiveSessionScreen(sessionId: session.id),
                //   ),
                // );
              },
              icon: const Icon(Icons.headphones),
              label: const Text('Go to Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 64),
            const SizedBox(height: AppSpacing.lg),
            Text('Oops!', style: AppTypography.sectionHeader(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error,
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              onPressed: () {
                ref.invalidate(activeSessionProvider);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // Actions

  void _showCreateSessionDialog(
    AsyncValue<List<MutualFollower>> mutualFollowersAsync,
  ) {
    showDialog(
      context: context,
      builder: (context) =>
          _CreateSessionDialog(mutualFollowersAsync: mutualFollowersAsync),
    );
  }

  Future<void> _acceptInvitation(SessionInvitation invitation) async {
    final success = await ref
        .read(sessionControllerProvider.notifier)
        .acceptInvitation(invitation.id, invitation.sessionId);

    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Joined session!')));
      ref.invalidate(activeSessionProvider);
    }
  }

  Future<void> _declineInvitation(SessionInvitation invitation) async {
    final success = await ref
        .read(invitationControllerProvider.notifier)
        .declineInvitation(invitation.id);

    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation declined')));
    }
  }

  // Replace the _startScanning method in ListenTogetherHomeScreen

  Future<void> _startScanning() async {
    if (_isScanning) return;

    print('🔍 [SCAN] Starting scan for nearby sessions...');
    setState(() => _isScanning = true);

    try {
      // Force immediate refresh of invitations
      await ref.read(invitationControllerProvider.notifier).refresh();

      // Wait a moment for UI feedback
      await Future.delayed(const Duration(milliseconds: 1500));

      // Check if we have invitations now
      final invitations = ref.read(invitationControllerProvider);

      if (mounted) {
        setState(() => _isScanning = false);

        if (invitations.isEmpty) {
          print('📭 [SCAN] No pending invitations found');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No nearby sessions found'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          print('📬 [SCAN] Found ${invitations.length} invitation(s)!');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Found ${invitations.length} session(s)!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [SCAN] Error during scan: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Create Session Dialog
class _CreateSessionDialog extends ConsumerStatefulWidget {
  final AsyncValue<List<MutualFollower>> mutualFollowersAsync;

  const _CreateSessionDialog({required this.mutualFollowersAsync});

  @override
  ConsumerState<_CreateSessionDialog> createState() =>
      _CreateSessionDialogState();
}

class _CreateSessionDialogState extends ConsumerState<_CreateSessionDialog> {
  final _nameController = TextEditingController();
  final Set<String> _selectedUsers = {};
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Start a Session', style: AppTypography.dialogTitle(context)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameController,
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Session name (optional)',
                hintStyle: AppTypography.subtitle(
                  context,
                ).copyWith(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Invite Friends (${_selectedUsers.length})',
              style: AppTypography.subtitle(context).copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: widget.mutualFollowersAsync.when(
                data: (followers) {
                  if (followers.isEmpty) {
                    return Center(
                      child: Text(
                        'No mutual followers found',
                        style: AppTypography.caption(
                          context,
                        ).copyWith(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: followers.length,
                    itemBuilder: (context, index) {
                      final follower = followers[index];
                      final isSelected = _selectedUsers.contains(
                        follower.userId,
                      );

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedUsers.add(follower.userId);
                            } else {
                              _selectedUsers.remove(follower.userId);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.surfaceLight,
                              backgroundImage: follower.profilePic != null
                                  ? NetworkImage(follower.profilePic!)
                                  : null,
                              child: follower.profilePic == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: AppColors.iconInactive,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                follower.username,
                                style: AppTypography.subtitle(
                                  context,
                                ).copyWith(color: AppColors.textPrimary),
                              ),
                            ),
                            if (follower.isOnline)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        activeColor: AppColors.accent,
                        checkColor: Colors.white,
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
                error: (error, stack) => Center(
                  child: Text(
                    'Error loading friends',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: AppColors.error),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                      ),
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createSession() async {
    setState(() => _isCreating = true);

    try {
      final controller = ref.read(sessionControllerProvider.notifier);
      final sessionId = await controller.createSession(
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      );

      if (sessionId != null && _selectedUsers.isNotEmpty) {
        // Invite selected users
        final db = ref.read(dbActionsProvider);
        for (final userId in _selectedUsers) {
          await db.inviteUserToSession(sessionId, userId);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session created!')));
        // Refresh to show active session
        ref.invalidate(activeSessionProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}
