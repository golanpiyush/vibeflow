// lib/screens/social_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart'
    hide supabaseClientProvider;
import 'package:vibeflow/pages/authOnboard/Screens/edit_profile.dart';
import 'package:vibeflow/pages/authOnboard/Screens/profiles_discovery_page.dart';
import 'package:vibeflow/providers/realtime_activity_provider.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'dart:async';

// State provider for selected sidebar item
final socialSidebarIndexProvider = StateProvider<int>((ref) => 0);

// Provider to get ONLY current user's latest activity (separate query)
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

  // Function to load current user's activity
  Future<void> loadCurrentUserActivity() async {
    if (isDisposed || controller.isClosed) return;

    try {
      print('🔍 Fetching current user activity...');

      final response = await supabase
          .from('listening_activity')
          .select('*')
          .eq('user_id', currentUser.id)
          .order('played_at')
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final jsonData = Map<String, dynamic>.from(response);

        // Parse timestamp as UTC
        if (jsonData['played_at'] is String) {
          jsonData['played_at'] = DateTime.parse(
            jsonData['played_at'] as String,
          ).toUtc().toIso8601String();
        }

        // Add profile data
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
          print('✅ Current user activity loaded: ${activity.songTitle}');
        }
      } else {
        if (!isDisposed && !controller.isClosed) {
          controller.add(null);
          print('ℹ️ No current user activity found');
        }
      }
    } catch (e) {
      print('❌ Error loading current user activity: $e');
      if (!isDisposed && !controller.isClosed) {
        controller.add(null);
      }
    }
  }

  // Initial load
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isDisposed) {
      loadCurrentUserActivity();
    }
  });

  // Subscribe to real-time updates for current user
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

          print('🔔 Current user activity changed');

          if (!isDisposed) {
            await loadCurrentUserActivity();
          }
        },
      )
      .subscribe();

  print('📡 Subscribed to current user activity updates');

  // Cleanup
  ref.onDispose(() {
    print('🗑️ Disposing current user activity provider');
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
    // Only start auto-refresh after initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoRefresh();
    });
  }

  void _startAutoRefresh() {
    // Cancel existing timer if any
    _autoRefreshTimer?.cancel();

    // Refresh every 30 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // Only refresh if we're still on the Friends tab
      final selectedIndex = ref.read(socialSidebarIndexProvider);
      if (selectedIndex == 0 && mounted) {
        print('🔄 Auto-refreshing social feed...');
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
    final selectedIndex = ref.watch(socialSidebarIndexProvider);
    final backgroundColor = ref.watch(themeBackgroundColorProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            // LEFT SIDEBAR - Vertical Navigation
            _buildSidebar(context, ref, selectedIndex),

            // RIGHT CONTENT AREA
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xxxl),
                  _buildTopBar(context, ref, selectedIndex),
                  Expanded(child: _buildContent(selectedIndex, ref)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref, int selectedIndex) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final sidebarLabelColor = ref.watch(themeTextPrimaryColorProvider);
    final sidebarLabelActiveColor = ref.watch(themeIconActiveColorProvider);

    // Create theme-aware text styles
    final sidebarLabelStyle = AppTypography.sidebarLabel.copyWith(
      color: sidebarLabelColor,
    );
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive.copyWith(
      color: sidebarLabelActiveColor,
    );

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              label: 'Friends',
              isActive: selectedIndex == 0,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
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
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: selectedIndex == 1
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              onTap: () =>
                  ref.read(socialSidebarIndexProvider.notifier).state = 1,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Edit Profile',
              isActive: selectedIndex == 2,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
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
    required Color iconActiveColor,
    required Color iconInactiveColor,
    required TextStyle labelStyle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  Widget _buildTopBar(BuildContext context, WidgetRef ref, int selectedIndex) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final backgroundColor = ref.watch(themeBackgroundColorProvider);

    final pageTitleStyle = AppTypography.pageTitle.copyWith(
      color: textPrimaryColor,
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
      color: backgroundColor,
      child: Row(
        children: [
          // ⬅️ Back button (LEFT)
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back, color: iconActiveColor, size: 28),
          ),

          // pushes title to extreme right
          const Spacer(),

          // Refresh button (only show on Friends tab)
          if (selectedIndex == 0)
            IconButton(
              onPressed: () {
                ref.invalidate(followingActivitiesProvider);
                ref.invalidate(currentUserLatestActivityProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Refreshing feed...',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    duration: const Duration(seconds: 1),
                    backgroundColor: iconActiveColor.withOpacity(0.8),
                  ),
                );
              },
              icon: Icon(Icons.refresh, color: iconActiveColor, size: 24),
              tooltip: 'Refresh',
            ),

          const SizedBox(width: 8),

          // 📝 Title (RIGHT aligned)
          Text(pageTitle, style: pageTitleStyle, textAlign: TextAlign.right),
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

// FRIENDS ACTIVITY CONTENT
class _FriendsActivityContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(followingActivitiesProvider);
    final currentUserActivityAsync = ref.watch(
      currentUserLatestActivityProvider,
    );
    final currentUser = ref.watch(currentUserProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return activitiesAsync.when(
      data: (friendsActivities) {
        // Filter out current user from friends list (shouldn't be there, but just in case)
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
            // Wait a bit for the refresh
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: CustomScrollView(
            slivers: [
              // Current User's Activity at Top
              SliverToBoxAdapter(
                child: currentUserActivityAsync.when(
                  data: (currentUserActivity) {
                    if (currentUserActivity == null) {
                      // Show placeholder when user hasn't listened to anything
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: iconActiveColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: iconActiveColor.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.music_note,
                                color: textSecondaryColor.withOpacity(0.5),
                                size: 36,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Start listening',
                                      style: AppTypography.subtitle.copyWith(
                                        color: textPrimaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Play a song to share with your friends',
                                      style: AppTypography.caption.copyWith(
                                        color: textSecondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.play_circle_fill,
                                color: iconActiveColor,
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
                                style: AppTypography.caption.copyWith(
                                  color: currentUserActivity.isCurrentlyPlaying
                                      ? Colors.green
                                      : textSecondaryColor,
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
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'LIVE',
                                        style: AppTypography.caption.copyWith(
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
                            color: textSecondaryColor.withOpacity(0.2),
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
                          color: iconActiveColor,
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
                          Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Could not load your activity',
                              style: AppTypography.caption.copyWith(
                                color: textPrimaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Friends Activity Header
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
                    style: AppTypography.caption.copyWith(
                      color: textSecondaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Friends Activity List or Empty State
              if (filteredFriendsActivities.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: textSecondaryColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No friend activity yet',
                          style: AppTypography.subtitle.copyWith(
                            color: textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your friends haven\'t listened to anything recently',
                          style: AppTypography.caption.copyWith(
                            color: textSecondaryColor,
                          ),
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
          Center(child: CircularProgressIndicator(color: iconActiveColor)),
      error: (error, stack) {
        print('❌ Error in followingActivitiesProvider: $error');
        print('Stack trace: $stack');

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: textSecondaryColor.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading activities',
                style: AppTypography.subtitle.copyWith(color: textPrimaryColor),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  error.toString(),
                  style: AppTypography.caption.copyWith(
                    color: textSecondaryColor,
                  ),
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
      // ✅ Use real-time position
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
    final statusText = _getStatusText();
    final artists = widget.activity.songArtists.join(', ');

    final cardBackgroundColor = widget.ref.watch(
      themeCardBackgroundColorProvider,
    );
    final textPrimaryColor = widget.ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = widget.ref.watch(
      themeTextSecondaryColorProvider,
    );
    final iconActiveColor = widget.ref.watch(themeIconActiveColorProvider);
    final thumbnailRadius = widget.ref.watch(thumbnailRadiusProvider);

    // ✅ Use real-time progress
    final progressPercentage = widget.activity.realtimeProgressPercentage;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isCurrentUser
            ? iconActiveColor.withOpacity(0.1)
            : cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.activity.isCurrentlyPlaying
              ? iconActiveColor.withOpacity(0.3)
              : Colors.transparent,
          width: widget.activity.isCurrentlyPlaying ? 1.5 : 0,
        ),
        boxShadow: widget.activity.isCurrentlyPlaying
            ? [
                BoxShadow(
                  color: iconActiveColor.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // User Profile Picture with online indicator
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
                          color: cardBackgroundColor,
                          child: Icon(
                            Icons.person,
                            color: textSecondaryColor,
                            size: 20,
                          ),
                        ),
                      )
                    : Container(
                        width: 36,
                        height: 36,
                        color: cardBackgroundColor,
                        child: Icon(
                          Icons.person,
                          color: textSecondaryColor,
                          size: 20,
                        ),
                      ),
              ),
              // Online indicator
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
                      border: Border.all(color: cardBackgroundColor, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Song Thumbnail
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
                          color: cardBackgroundColor,
                          child: Icon(
                            Icons.music_note,
                            color: textSecondaryColor,
                            size: 20,
                          ),
                        ),
                      ),
                      // Progress overlay
                      if (widget.activity.isCurrentlyPlaying)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: progressPercentage,
                            backgroundColor: Colors.black.withOpacity(0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
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
                    color: cardBackgroundColor,
                    child: Icon(
                      Icons.music_note,
                      color: textSecondaryColor,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Song Info
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // User and Status Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.activity.username,
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: textPrimaryColor,
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
                            : textSecondaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.activity.isCurrentlyPlaying ? 'LIVE' : 'OFFLINE',
                        style: AppTypography.caption.copyWith(
                          color: widget.activity.isCurrentlyPlaying
                              ? Colors.green
                              : textSecondaryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Song Title
                Text(
                  widget.activity.songTitle,
                  style: AppTypography.songTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textPrimaryColor,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),

                // Artists and Status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        artists,
                        style: AppTypography.caption.copyWith(
                          color: textSecondaryColor,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• $statusText',
                      style: AppTypography.caption.copyWith(
                        color: widget.activity.isCurrentlyPlaying
                            ? Colors.green
                            : textSecondaryColor,
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

                // Progress Bar (only when playing)
                if (widget.activity.isCurrentlyPlaying &&
                    widget.activity.durationMs > 0)
                  Column(
                    children: [
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progressPercentage,
                        backgroundColor: textSecondaryColor.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          iconActiveColor,
                        ),
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            // ✅ FIX: Use real-time calculated position instead of widget.activity.currentPositionMs
                            _formatDuration(
                              widget.activity.realtimeCurrentPositionMs,
                            ),
                            style: AppTypography.caption.copyWith(
                              color: textSecondaryColor,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            _formatDuration(widget.activity.durationMs),
                            style: AppTypography.caption.copyWith(
                              color: textSecondaryColor,
                              fontSize: 10,
                            ),
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

// Profiles Screen Content (without its own Scaffold)
class ProfilesScreenContent extends StatelessWidget {
  const ProfilesScreenContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const ProfilesScreen();
  }
}

// Edit Profile Screen Content (without its own Scaffold)
class EditProfileScreenContent extends StatelessWidget {
  const EditProfileScreenContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const EditProfileScreen();
  }
}
