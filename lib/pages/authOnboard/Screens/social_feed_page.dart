// lib/screens/social_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
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
  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addPostFrameCallback((_) {});
  }

  @override
  void dispose() {
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
    final colorScheme = themeData.colorScheme;
    final primaryColor = colorScheme.primary;
    final textColor = colorScheme.onSurface;
    final inactiveColor = colorScheme.onSurface.withOpacity(0.5);

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
              activeColor: primaryColor,
              inactiveColor: inactiveColor,
              onTap: () =>
                  ref.read(socialSidebarIndexProvider.notifier).state = 0,
            ),
            const SizedBox(height: 16),
            _buildSidebarItem(
              label: 'Profiles',
              isActive: selectedIndex == 1,
              activeColor: primaryColor,
              inactiveColor: inactiveColor,
              onTap: () =>
                  ref.read(socialSidebarIndexProvider.notifier).state = 1,
            ),
            const SizedBox(height: 16),
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
                      activeColor: primaryColor,
                      inactiveColor: inactiveColor,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ListenTogetherHomeScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
            _buildSidebarItem(
              label: 'Edit Profile',
              isActive: selectedIndex == 2,
              activeColor: primaryColor,
              inactiveColor: inactiveColor,
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
    required Color activeColor,
    required Color inactiveColor,
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
            style: AppTypography.sidebarLabel(context).copyWith(
              fontSize: 15,
              color: isActive ? activeColor : inactiveColor,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
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
    final colorScheme = themeData.colorScheme;
    final themeState = ref.watch(themeProvider);

    // ✅ Get theme-aware colors from providers
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconColor = ref.watch(themeIconActiveColorProvider);

    // ✅ Determine if we're in pure black mode
    final bool isPureBlack = themeState.themeType == ThemeType.pureBlack;

    // ✅ Use appropriate colors based on theme type
    final Color effectiveBackgroundColor = isPureBlack
        ? Colors
              .black // Pure black background for pure black mode
        : colorScheme.surface; // Material You surface for other modes

    final Color effectiveTextColor = isPureBlack
        ? Colors
              .white // Pure white for pure black mode
        : colorScheme.onSurface; // Material You onSurface for other modes

    final Color effectiveIconColor = isPureBlack
        ? Colors.white.withOpacity(0.9) // Bright white with slight opacity
        : colorScheme.onSurface; // Material You onSurface

    final Color effectiveBorderColor = isPureBlack
        ? Colors.white.withOpacity(0.15) // Subtle white border for pure black
        : colorScheme.onSurface.withOpacity(0.12); // Theme-aware border

    // ✅ Use theme-aware typography
    final pageTitleStyle =
        themeData.textTheme.titleLarge?.copyWith(
          color: effectiveTextColor,
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(
          color: effectiveTextColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        );

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
      decoration: BoxDecoration(
        color: effectiveBackgroundColor,
        border: Border(
          bottom: BorderSide(color: effectiveBorderColor, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Back button
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.arrow_back, color: effectiveIconColor, size: 28),
              tooltip: 'Back',
            ),
            const Spacer(),

            // Cleanup button (only on Friends Activity page)
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

                    // ✅ Theme-aware snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Cleaned up stale activities',
                          style: TextStyle(
                            color: isPureBlack
                                ? Colors.white
                                : colorScheme.onSurface,
                          ),
                        ),
                        backgroundColor: isPureBlack
                            ? const Color(
                                0xFF1A1A1A,
                              ) // Dark gray for pure black
                            : colorScheme.surfaceContainerHighest,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  } catch (e) {
                    print('Error cleaning activities: $e');

                    // ✅ Error snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to cleanup activities',
                          style: TextStyle(
                            color: isPureBlack
                                ? Colors.white
                                : colorScheme.onError,
                          ),
                        ),
                        backgroundColor: colorScheme.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  }
                },
                icon: Icon(
                  Icons.cleaning_services_rounded,
                  color: isPureBlack
                      ? Colors.white.withOpacity(0.7)
                      : colorScheme.onSurface.withOpacity(0.7),
                  size: 24,
                ),
                tooltip: 'Cleanup stale activities',
              ),

            const SizedBox(width: 8),

            // Page title
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

// ADD this new realtime provider (replace followingActivitiesProvider usage)
final realtimeFollowingActivitiesProvider = StreamProvider<List<ListeningActivity>>((
  ref,
) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return Stream.value([]);

  final supabase = ref.watch(supabaseClientProvider);
  final controller = StreamController<List<ListeningActivity>>();
  bool isDisposed = false;
  RealtimeChannel? channel;

  Future<void> loadActivities() async {
    if (isDisposed || controller.isClosed) return;
    try {
      print('🔍 [Realtime] Loading for user: ${currentUser.id}');

      // First check if user has follows at all
      final followsCheck = await supabase
          .from('user_follows')
          .select('followed_id')
          .eq('follower_id', currentUser.id);

      print('👥 [Realtime] Follows count: ${(followsCheck as List).length}');
      print('👥 [Realtime] Follows: $followsCheck');

      if ((followsCheck as List).isEmpty) {
        print('⚠️ [Realtime] No follows found!');
        if (!isDisposed && !controller.isClosed) controller.add([]);
        return;
      }

      final followedIds = (followsCheck as List)
          .map((f) => f['followed_id'] as String)
          .toList();

      print('👥 [Realtime] Following IDs: $followedIds');

      // Direct query instead of RPC
      final response = await supabase
          .from('listening_activity')
          .select('*, profiles!user_id(userid, profile_pic_url)')
          .inFilter('user_id', followedIds)
          .order('played_at', ascending: false)
          .limit(50);

      print('📊 [Realtime] Raw response count: ${(response as List).length}');
      print(
        '📊 [Realtime] First item: ${response.isNotEmpty ? response.first : "empty"}',
      );

      final activities = <ListeningActivity>[];
      for (final item in response as List) {
        try {
          final jsonData = Map<String, dynamic>.from(item as Map);

          // Extract joined profile data
          final profileData = jsonData['profiles'] as Map<String, dynamic>?;
          jsonData['username'] = profileData?['userid'] ?? 'Unknown';
          jsonData['profile_pic'] = profileData?['profile_pic_url'];
          jsonData.remove('profiles');

          if (jsonData['played_at'] is String) {
            jsonData['played_at'] = DateTime.parse(
              jsonData['played_at'] as String,
            ).toUtc().toIso8601String();
          }

          // Ensure required fields have defaults
          jsonData['is_currently_playing'] ??= false;
          jsonData['current_position_ms'] ??= 0;

          print(
            '✅ [Realtime] Parsed: ${jsonData['song_title']} by ${jsonData['username']}',
          );
          activities.add(ListeningActivity.fromMap(jsonData));
        } catch (e) {
          print('⚠️ Error parsing activity item: $e');
          print('   Item was: $item');
        }
      }

      print('✅ [Realtime] Total activities loaded: ${activities.length}');
      if (!isDisposed && !controller.isClosed) controller.add(activities);
    } catch (e, stack) {
      print('❌ Error loading activities: $e');
      print('   Stack: ${stack.toString().split('\n').take(5).join('\n')}');
      if (!isDisposed && !controller.isClosed) controller.add([]);
    }
  }

  // Initial load
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isDisposed) loadActivities();
  });

  // Realtime: fires on any change to listening_activity
  channel = supabase
      .channel('following_activities_live_${currentUser.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'listening_activity',
        callback: (payload) async {
          if (isDisposed) return;
          print('🔴 [Realtime] Activity changed, refreshing feed...');
          await loadActivities();
        },
      )
      .subscribe((status, [error]) {
        print('📡 [Realtime] Subscription status: $status');
        if (error != null) print('❌ [Realtime] Error: $error');
      });

  ref.onDispose(() {
    isDisposed = true;
    try {
      channel?.unsubscribe();
    } catch (e) {}
    if (!controller.isClosed) {
      try {
        controller.close();
      } catch (e) {}
    }
  });

  return controller.stream;
});

class _FriendsActivityContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;

    // Use ref.watch to listen to providers
    final activitiesAsync = ref.watch(realtimeFollowingActivitiesProvider);
    // final activitiesAsync = ref.watch(followingActivitiesProvider);

    final currentUserActivityAsync = ref.watch(
      currentUserLatestActivityProvider,
    );
    final listeningActivityEnabledAsync = ref.watch(
      userListeningActivityEnabledProvider,
    );
    final currentUser = ref.watch(currentUserProvider);

    // Use colorScheme for all colors
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final primaryColor = colorScheme.primary;
    final surfaceColor = colorScheme.surface;
    final errorColor = colorScheme.error;

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
                            ).copyWith(color: textSecondary, fontSize: 12),
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
              color: primaryColor,
              backgroundColor: surfaceColor,
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
                            color: errorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: errorColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: errorColor,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Could not load your activity',
                                  style: AppTypography.caption(
                                    context,
                                  ).copyWith(color: textSecondary),
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
                          color: textPrimary,
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
          loading: () => Center(
            child: CircularProgressIndicator(
              color: primaryColor,
              backgroundColor: surfaceColor,
            ),
          ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(
          color: primaryColor,
          backgroundColor: surfaceColor,
        ),
      ),
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

  // Helper to calculate dynamic font size based on text length
  double _getDynamicTitleFontSize(String text) {
    if (text.length > 30) return 13.0;
    if (text.length > 20) return 14.0;
    return 15.0;
  }

  double _getDynamicArtistFontSize(String text) {
    if (text.length > 40) return 10.0;
    if (text.length > 30) return 11.0;
    return 12.0;
  }

  double _getDynamicUsernameFontSize(String text) {
    if (text.length > 15) return 11.0;
    if (text.length > 10) return 12.0;
    return 13.0;
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final statusText = _getStatusText();
    final artists = widget.activity.songArtists.join(', ');

    // Use colorScheme for all colors
    final cardBg = colorScheme.surface;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.6);
    final primaryColor = colorScheme.primary;
    final surfaceColor = colorScheme.surface;
    final thumbnailRadius = widget.ref.watch(thumbnailRadiusProvider);

    final progressPercentage = widget.activity.realtimeProgressPercentage;

    // Calculate dynamic font sizes
    final titleFontSize = _getDynamicTitleFontSize(widget.activity.songTitle);
    final artistFontSize = _getDynamicArtistFontSize(artists);
    final usernameFontSize = _getDynamicUsernameFontSize(
      widget.activity.username,
    );

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
          // Profile picture with status indicator
          Stack(
            children: [
              ClipOval(
                child:
                    widget.activity.profilePic != null &&
                        widget.activity.profilePic!.isNotEmpty &&
                        (widget.activity.profilePic!.startsWith('http://') ||
                            widget.activity.profilePic!.startsWith('https://'))
                    ? Image.network(
                        widget.activity.profilePic!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 36,
                          height: 36,
                          color: surfaceColor,
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
                        color: surfaceColor,
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

          // Album thumbnail with progress bar overlay
          ClipRRect(
            borderRadius: BorderRadius.circular(54 * thumbnailRadius),
            child:
                widget.activity.songThumbnail != null &&
                    widget.activity.songThumbnail!.isNotEmpty &&
                    (widget.activity.songThumbnail!.startsWith('http://') ||
                        widget.activity.songThumbnail!.startsWith('https://'))
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
                          color: surfaceColor,
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
                    color: surfaceColor,
                    child: Icon(
                      Icons.music_note,
                      color: textSecondary,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Text content - UPDATED with online/offline badge in top right corner
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Main content column
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Username
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.activity.username,
                                style:
                                    themeData.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                      fontSize: usernameFontSize,
                                    ) ??
                                    AppTypography.caption(context).copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                      fontSize: usernameFontSize,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Song title with dynamic font size
                        Text(
                          widget.activity.songTitle,
                          style:
                              themeData.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                                fontSize: titleFontSize,
                              ) ??
                              AppTypography.songTitle(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                                fontSize: titleFontSize,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 2),

                        // Artist names and timestamp
                        Row(
                          children: [
                            // Artist names with dynamic font size
                            Flexible(
                              child: Text(
                                artists,
                                style:
                                    themeData.textTheme.bodySmall?.copyWith(
                                      color: textSecondary,
                                      fontSize: artistFontSize,
                                    ) ??
                                    AppTypography.caption(context).copyWith(
                                      color: textSecondary,
                                      fontSize: artistFontSize,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Only show separator if artist exists
                            if (artists.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  '•',
                                  style:
                                      themeData.textTheme.labelSmall?.copyWith(
                                        color: textSecondary,
                                        fontSize: 11,
                                      ) ??
                                      AppTypography.caption(context).copyWith(
                                        color: textSecondary,
                                        fontSize: 11,
                                      ),
                                ),
                              ),

                            // Status text with dynamic sizing
                            Flexible(
                              child: Text(
                                statusText,
                                style:
                                    themeData.textTheme.labelSmall?.copyWith(
                                      color: widget.activity.isCurrentlyPlaying
                                          ? Colors.green
                                          : textSecondary,
                                      fontSize:
                                          widget.activity.isCurrentlyPlaying
                                          ? 10
                                          : 11,
                                      fontWeight:
                                          widget.activity.isCurrentlyPlaying
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ) ??
                                    AppTypography.caption(context).copyWith(
                                      color: widget.activity.isCurrentlyPlaying
                                          ? Colors.green
                                          : textSecondary,
                                      fontSize:
                                          widget.activity.isCurrentlyPlaying
                                          ? 10
                                          : 11,
                                      fontWeight:
                                          widget.activity.isCurrentlyPlaying
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // Progress bar for currently playing songs
                        if (widget.activity.isCurrentlyPlaying &&
                            widget.activity.durationMs > 0)
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progressPercentage,
                                backgroundColor: textSecondary.withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  primaryColor,
                                ),
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(
                                      widget.activity.realtimeCurrentPositionMs,
                                    ),
                                    style:
                                        themeData.textTheme.labelSmall
                                            ?.copyWith(
                                              color: textSecondary,
                                              fontSize: 9,
                                            ) ??
                                        AppTypography.caption(context).copyWith(
                                          color: textSecondary,
                                          fontSize: 9,
                                        ),
                                  ),
                                  Text(
                                    _formatDuration(widget.activity.durationMs),
                                    style:
                                        themeData.textTheme.labelSmall
                                            ?.copyWith(
                                              color: textSecondary,
                                              fontSize: 9,
                                            ) ??
                                        AppTypography.caption(context).copyWith(
                                          color: textSecondary,
                                          fontSize: 9,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),

                    // ONLINE/OFFLINE BADGE - Positioned in top right corner
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: widget.activity.isCurrentlyPlaying
                              ? Colors.green.withOpacity(0.2)
                              : textSecondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.activity.isCurrentlyPlaying
                                ? Colors.green.withOpacity(0.3)
                                : textSecondary.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          widget.activity.isCurrentlyPlaying
                              ? 'LIVE'
                              : 'OFFLINE',
                          style:
                              themeData.textTheme.labelSmall?.copyWith(
                                color: widget.activity.isCurrentlyPlaying
                                    ? Colors.green
                                    : textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ) ??
                              AppTypography.caption(context).copyWith(
                                color: widget.activity.isCurrentlyPlaying
                                    ? Colors.green
                                    : textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
