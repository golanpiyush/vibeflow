// lib/screens/social_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/database/access_code_service.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/database/profile_service.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart'
    hide supabaseClientProvider;
import 'package:vibeflow/pages/authOnboard/Screens/edit_profile.dart';
import 'package:vibeflow/pages/authOnboard/Screens/profiles_discovery_page.dart';
import 'package:vibeflow/pages/authOnboard/listen_together/listen_together_home_screen.dart';
import 'package:vibeflow/providers/realtime_activity_provider.dart';
import 'dart:async';

import 'package:vibeflow/utils/theme_provider.dart';

final socialSidebarIndexProvider = StateProvider<int>((ref) => 0);

final currentUserLatestActivityProvider = StreamProvider<ListeningActivity?>((
  ref,
) {
  final currentUser = ref.watch(currentUserProvider);

  if (currentUser == null) {
    return Stream.value(null);
  }

  final supabase = ref.watch(supabaseClientProvider);
  final controller = StreamController<ListeningActivity?>();
  bool isDisposed = false;
  RealtimeChannel? channel;

  Future<void> loadCurrentUserActivity() async {
    if (isDisposed || controller.isClosed) return;

    try {
      final response = await supabase
          .from('listening_activity')
          .select('*')
          .eq('user_id', currentUser.id)
          .order('played_at')
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final jsonData = Map<String, dynamic>.from(response);

        if (jsonData['played_at'] is String) {
          jsonData['played_at'] = DateTime.parse(
            jsonData['played_at'] as String,
          ).toUtc().toIso8601String();
        }

        final profile = await supabase
            .from('profiles')
            .select('userid, profile_pic_url')
            .eq('id', currentUser.id)
            .maybeSingle();

        if (profile != null) {
          jsonData['username'] = profile['userid'] ?? 'You';
          jsonData['profile_pic'] = profile['profile_pic_url'];
        } else {
          jsonData['username'] = 'You';
          jsonData['profile_pic'] = null;
        }

        final activity = ListeningActivity.fromMap(jsonData);

        if (!isDisposed && !controller.isClosed) {
          controller.add(activity);
        }
      } else {
        if (!isDisposed && !controller.isClosed) {
          controller.add(null);
        }
      }
    } catch (e) {
      if (!isDisposed && !controller.isClosed) {
        controller.add(null);
      }
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isDisposed) {
      loadCurrentUserActivity();
    }
  });

  channel = supabase
      .channel('current_user_activity_${currentUser.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'listening_activity',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: currentUser.id,
        ),
        callback: (payload) async {
          if (isDisposed) return;
          if (!isDisposed) {
            await loadCurrentUserActivity();
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    isDisposed = true;

    try {
      channel?.unsubscribe();
    } catch (e) {
      print('⚠️ Error unsubscribing: $e');
    }

    if (!controller.isClosed) {
      try {
        controller.close();
      } catch (e) {
        print('⚠️ Error closing controller: $e');
      }
    }
  });

  return controller.stream;
});

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoRefresh();
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final selectedIndex = ref.read(socialSidebarIndexProvider);
      if (selectedIndex == 0 && mounted) {
        ref.invalidate(followingActivitiesProvider);
        ref.invalidate(currentUserLatestActivityProvider);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final selectedIndex = ref.watch(socialSidebarIndexProvider);

    return Scaffold(
      backgroundColor: themeData.scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(context, ref, selectedIndex, themeData),
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xxxl),
                  _buildTopBar(context, ref, selectedIndex, themeData),
                  Expanded(child: _buildContent(selectedIndex, ref)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    int selectedIndex,
    ThemeData themeData,
  ) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final primaryColor = themeData.primaryColor;
    final textSecondary =
        themeData.textTheme.bodyMedium?.color ?? Colors.white70;

    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: textSecondary);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: primaryColor);

    Future<bool> _shouldShowJammer() async {
      try {
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser == null) return false;

        final supabase = Supabase.instance.client;
        final accessCodeService = AccessCodeService(supabase);
        final profileService = ProfileService(supabase);

        final hasAccessCode = await accessCodeService.checkIfUserHasAccessCode(
          currentUser.id,
        );
        if (!hasAccessCode) return false;

        final profile = await profileService.getUserProfileById(currentUser.id);
        if (profile == null) return false;

        final isBetaTester = profile['is_beta_tester'] == true;
        return isBetaTester;
      } catch (e) {
        return false;
      }
    }

    return Container(
      width: 80,
      height: availableHeight,
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              label: 'Friends',
              isActive: selectedIndex == 0,
              labelStyle: selectedIndex == 0
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              onTap: () =>
                  ref.read(socialSidebarIndexProvider.notifier).state = 0,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Profiles',
              isActive: selectedIndex == 1,
              labelStyle: selectedIndex == 1
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              onTap: () =>
                  ref.read(socialSidebarIndexProvider.notifier).state = 1,
            ),
            const SizedBox(height: 24),
            FutureBuilder<bool>(
              future: _shouldShowJammer(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 56);
                }

                if (snapshot.hasError || !snapshot.hasData || !snapshot.data!) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSidebarItem(
                      label: 'Jammer',
                      isActive: selectedIndex == 3,
                      labelStyle: selectedIndex == 3
                          ? sidebarLabelActiveStyle
                          : sidebarLabelStyle,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ListenTogetherHomeScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
            _buildSidebarItem(
              label: 'Edit Profile',
              isActive: selectedIndex == 2,
              labelStyle: selectedIndex == 2
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              onTap: () =>
                  ref.read(socialSidebarIndexProvider.notifier).state = 2,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required String label,
    bool isActive = false,
    required TextStyle labelStyle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 100,
        alignment: Alignment.center,
        child: RotatedBox(
          quarterTurns: -1,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: labelStyle.copyWith(fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    WidgetRef ref,
    int selectedIndex,
    ThemeData themeData,
  ) {
    final textColor = themeData.textTheme.bodyLarge?.color ?? Colors.white;
    final iconColor = themeData.iconTheme.color ?? Colors.white;

    final pageTitleStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textColor);

    String pageTitle = '';
    switch (selectedIndex) {
      case 0:
        pageTitle = 'Friends Activity';
        break;
      case 1:
        pageTitle = 'Discover Users';
        break;
      case 2:
        pageTitle = 'Edit Profile';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: themeData.scaffoldBackgroundColor,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back, color: iconColor, size: 28),
          ),
          const Spacer(),
          if (selectedIndex == 0)
            IconButton(
              onPressed: () async {
                try {
                  final supabase = Supabase.instance.client;
                  final cutoffTime = DateTime.now().toUtc().subtract(
                    const Duration(minutes: 5),
                  );

                  await supabase
                      .from('listening_activity')
                      .update({
                        'is_currently_playing': false,
                        'current_position_ms': 0,
                      })
                      .eq('is_currently_playing', true)
                      .lt('played_at', cutoffTime.toIso8601String());

                  ref.invalidate(followingActivitiesProvider);
                  ref.invalidate(currentUserLatestActivityProvider);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cleaned up stale activities'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  print('Error cleaning activities: $e');
                }
              },
              icon: Icon(Icons.cleaning_services, color: iconColor, size: 24),
              tooltip: 'Cleanup',
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pageTitle,
              style: pageTitleStyle,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(int selectedIndex, WidgetRef ref) {
    switch (selectedIndex) {
      case 0:
        return _FriendsActivityContent();
      case 1:
        return const ProfilesScreenContent();
      case 2:
        return const EditProfileScreenContent();
      default:
        return _FriendsActivityContent();
    }
  }
}

final userListeningActivityEnabledProvider = StreamProvider<bool>((ref) {
  final currentUser = ref.watch(currentUserProvider);

  if (currentUser == null) {
    return Stream.value(true);
  }

  final supabase = ref.watch(supabaseClientProvider);

  return supabase
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', currentUser.id)
      .map((data) {
        if (data.isEmpty) return true;
        return data.first['show_listening_activity'] ?? true;
      });
});

class _FriendsActivityContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = Theme.of(context);

    final activitiesAsync = ref.watch(followingActivitiesProvider);
    final currentUserActivityAsync = ref.watch(
      currentUserLatestActivityProvider,
    );
    final listeningActivityEnabledAsync = ref.watch(
      userListeningActivityEnabledProvider,
    );
    final currentUser = ref.watch(currentUserProvider);

    final textPrimary = themeData.textTheme.bodyLarge?.color ?? Colors.white;
    final textSecondary =
        themeData.textTheme.bodyMedium?.color ?? Colors.white70;
    final primaryColor = themeData.primaryColor;

    return listeningActivityEnabledAsync.when(
      data: (isListeningActivityEnabled) {
        if (!isListeningActivityEnabled) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_off,
                    size: 80,
                    color: textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Listening Activity is Off',
                    style: AppTypography.pageTitle(
                      context,
                    ).copyWith(color: textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Enable "Show Listening Activity" in Edit Profile\nto see what your friends are listening to',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primaryColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 20, color: primaryColor),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'Your activity is also hidden from friends',
                            style: AppTypography.caption(
                              context,
                            ).copyWith(color: textPrimary, fontSize: 12),
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

        return activitiesAsync.when(
          data: (friendsActivities) {
            final filteredFriendsActivities = friendsActivities
                .where(
                  (activity) =>
                      currentUser == null || activity.userId != currentUser.id,
                )
                .toList();

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(followingActivitiesProvider);
                ref.invalidate(currentUserLatestActivityProvider);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: currentUserActivityAsync.when(
                      data: (currentUserActivity) {
                        if (currentUserActivity == null) {
                          return Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: primaryColor.withOpacity(0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.music_note,
                                    color: textSecondary.withOpacity(0.5),
                                    size: 36,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Start listening',
                                          style: AppTypography.subtitle(context)
                                              .copyWith(
                                                color: textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Play a song to share with your friends',
                                          style: AppTypography.caption(
                                            context,
                                          ).copyWith(color: textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.play_circle_fill,
                                    color: primaryColor,
                                    size: 32,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.lg,
                                AppSpacing.lg,
                                AppSpacing.sm,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    currentUserActivity.isCurrentlyPlaying
                                        ? '🎵 You\'re listening now'
                                        : '⏸️ Your last listen',
                                    style: AppTypography.caption(context)
                                        .copyWith(
                                          color:
                                              currentUserActivity
                                                  .isCurrentlyPlaying
                                              ? Colors.green
                                              : textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                  ),
                                  const Spacer(),
                                  if (currentUserActivity.isCurrentlyPlaying)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Colors.green,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'LIVE',
                                            style:
                                                AppTypography.caption(
                                                  context,
                                                ).copyWith(
                                                  color: Colors.green,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                              ),
                              child: _ActivityCard(
                                activity: currentUserActivity,
                                ref: ref,
                                isCurrentUser: true,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                              ),
                              child: Divider(
                                color: textSecondary.withOpacity(0.2),
                                thickness: 1,
                              ),
                            ),
                          ],
                        );
                      },
                      loading: () => Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Center(
                          child: SizedBox(
                            height: 40,
                            child: CircularProgressIndicator(
                              color: primaryColor,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                      error: (error, stack) => Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Could not load your activity',
                                  style: AppTypography.caption(
                                    context,
                                  ).copyWith(color: textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: Text(
                        'Friends Activity',
                        style: AppTypography.caption(context).copyWith(
                          color: textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (filteredFriendsActivities.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No friend activity yet',
                              style: AppTypography.subtitle(
                                context,
                              ).copyWith(color: textPrimary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your friends haven\'t listened to anything recently',
                              style: AppTypography.caption(
                                context,
                              ).copyWith(color: textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.lg,
                        right: AppSpacing.lg,
                        bottom: 120,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _ActivityCard(
                            activity: filteredFriendsActivities[index],
                            ref: ref,
                          );
                        }, childCount: filteredFriendsActivities.length),
                      ),
                    ),
                ],
              ),
            );
          },
          loading: () =>
              Center(child: CircularProgressIndicator(color: primaryColor)),
          error: (error, stack) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading activities',
                    style: AppTypography.subtitle(
                      context,
                    ).copyWith(color: textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error.toString(),
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      ref.invalidate(followingActivitiesProvider);
                      ref.invalidate(currentUserLatestActivityProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: primaryColor)),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Error checking settings',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatefulWidget {
  final ListeningActivity activity;
  final WidgetRef ref;
  final bool isCurrentUser;

  const _ActivityCard({
    required this.activity,
    required this.ref,
    this.isCurrentUser = false,
  });

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  Timer? _uiUpdateTimer;

  @override
  void initState() {
    super.initState();
    if (widget.activity.isCurrentlyPlaying) {
      _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.activity.isCurrentlyPlaying && _uiUpdateTimer == null) {
      _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.activity.isCurrentlyPlaying && _uiUpdateTimer != null) {
      _uiUpdateTimer?.cancel();
      _uiUpdateTimer = null;
    }
  }

  String _getStatusText() {
    if (widget.activity.isCurrentlyPlaying) {
      final position = widget.activity.realtimePositionMs;
      final minutes = (position / 60000).floor();
      final seconds = ((position % 60000) / 1000).floor();
      final totalMinutes = (widget.activity.durationMs / 60000).floor();
      final totalSeconds = ((widget.activity.durationMs % 60000) / 1000)
          .floor();

      return '🎵 ${minutes}:${seconds.toString().padLeft(2, '0')} / ${totalMinutes}:${totalSeconds.toString().padLeft(2, '0')}';
    } else {
      final now = DateTime.now();
      final difference = now.difference(widget.activity.playedAt);

      if (difference.inSeconds < 60) {
        return 'just finished';
      } else if (difference.inMinutes < 60) {
        final minutes = difference.inMinutes;
        return '$minutes ${minutes == 1 ? 'min' : 'mins'} ago';
      } else if (difference.inHours < 24) {
        final hours = difference.inHours;
        return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
      } else {
        final days = difference.inDays;
        return '$days ${days == 1 ? 'day' : 'days'} ago';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final statusText = _getStatusText();
    final artists = widget.activity.songArtists.join(', ');

    final cardBg = themeData.cardColor;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final primaryColor = colorScheme.primary;
    final thumbnailRadius = widget.ref.watch(thumbnailRadiusProvider);

    final progressPercentage = widget.activity.realtimeProgressPercentage;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isCurrentUser ? primaryColor.withOpacity(0.1) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.activity.isCurrentlyPlaying
              ? primaryColor.withOpacity(0.3)
              : Colors.transparent,
          width: widget.activity.isCurrentlyPlaying ? 1.5 : 0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            children: [
              ClipOval(
                child:
                    widget.activity.profilePic != null &&
                        widget.activity.profilePic!.isNotEmpty
                    ? Image.network(
                        widget.activity.profilePic!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 36,
                          height: 36,
                          color: colorScheme.surface,
                          child: Icon(
                            Icons.person,
                            color: textSecondary,
                            size: 20,
                          ),
                        ),
                      )
                    : Container(
                        width: 36,
                        height: 36,
                        color: colorScheme.surface,
                        child: Icon(
                          Icons.person,
                          color: textSecondary,
                          size: 20,
                        ),
                      ),
              ),
              if (widget.activity.isCurrentlyPlaying)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cardBg, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(54 * thumbnailRadius),
            child:
                widget.activity.songThumbnail != null &&
                    widget.activity.songThumbnail!.isNotEmpty
                ? Stack(
                    children: [
                      Image.network(
                        widget.activity.songThumbnail!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 54,
                          height: 54,
                          color: themeData.colorScheme.surface,
                          child: Icon(
                            Icons.music_note,
                            color: textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                      if (widget.activity.isCurrentlyPlaying)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: progressPercentage,
                            backgroundColor: Colors.black.withOpacity(0.3),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.green,
                            ),
                            minHeight: 3,
                          ),
                        ),
                    ],
                  )
                : Container(
                    width: 54,
                    height: 54,
                    color: themeData.colorScheme.surface,
                    child: Icon(
                      Icons.music_note,
                      color: textSecondary,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.activity.username,
                        style:
                            themeData.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                              fontSize: 13,
                            ) ??
                            AppTypography.caption(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                              fontSize: 13,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: widget.activity.isCurrentlyPlaying
                            ? Colors.green.withOpacity(0.2)
                            : textSecondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.activity.isCurrentlyPlaying ? 'LIVE' : 'OFFLINE',
                        style:
                            themeData.textTheme.labelSmall?.copyWith(
                              color: widget.activity.isCurrentlyPlaying
                                  ? Colors.green
                                  : textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ) ??
                            AppTypography.caption(context).copyWith(
                              color: widget.activity.isCurrentlyPlaying
                                  ? Colors.green
                                  : textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.activity.songTitle,
                  style:
                      themeData.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                        fontSize: 15,
                      ) ??
                      AppTypography.songTitle(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                        fontSize: 15,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        artists,
                        style:
                            themeData.textTheme.bodySmall?.copyWith(
                              color: textSecondary,
                              fontSize: 12,
                            ) ??
                            AppTypography.caption(
                              context,
                            ).copyWith(color: textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• $statusText',
                      style:
                          themeData.textTheme.labelSmall?.copyWith(
                            color: widget.activity.isCurrentlyPlaying
                                ? Colors.green
                                : textSecondary,
                            fontSize: 11,
                            fontWeight: widget.activity.isCurrentlyPlaying
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ) ??
                          AppTypography.caption(context).copyWith(
                            color: widget.activity.isCurrentlyPlaying
                                ? Colors.green
                                : textSecondary,
                            fontSize: 11,
                            fontWeight: widget.activity.isCurrentlyPlaying
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (widget.activity.isCurrentlyPlaying &&
                    widget.activity.durationMs > 0)
                  Column(
                    children: [
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progressPercentage,
                        backgroundColor: textSecondary.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(
                              widget.activity.realtimeCurrentPositionMs,
                            ),
                            style:
                                themeData.textTheme.labelSmall?.copyWith(
                                  color: textSecondary,
                                  fontSize: 10,
                                ) ??
                                AppTypography.caption(
                                  context,
                                ).copyWith(color: textSecondary, fontSize: 10),
                          ),
                          Text(
                            _formatDuration(widget.activity.durationMs),
                            style:
                                themeData.textTheme.labelSmall?.copyWith(
                                  color: textSecondary,
                                  fontSize: 10,
                                ) ??
                                AppTypography.caption(
                                  context,
                                ).copyWith(color: textSecondary, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final minutes = (milliseconds / 60000).floor();
    final seconds = ((milliseconds % 60000) / 1000).floor();
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}

class ProfilesScreenContent extends StatelessWidget {
  const ProfilesScreenContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const ProfilesScreen();
  }
}

class EditProfileScreenContent extends StatelessWidget {
  const EditProfileScreenContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const EditProfileScreen();
  }
}
