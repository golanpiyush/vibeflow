// lib/screens/social_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/pages/authOnboard/Screens/edit_profile.dart';
import 'package:vibeflow/pages/authOnboard/Screens/profiles_discovery_page.dart';
import 'package:vibeflow/utils/theme_provider.dart';

// State provider for selected sidebar item
final socialSidebarIndexProvider = StateProvider<int>((ref) => 0);

// Dummy data for now - will use real data from following_activity later
final followingActivitiesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  await Future.delayed(const Duration(seconds: 1));

  return [
    {
      'user_id': 'user1',
      'username': 'alex_music',
      'profile_pic': 'https://i.pravatar.cc/150?img=1',
      'song_title': 'Blinding Lights',
      'song_artists': ['The Weeknd'],
      'song_thumbnail': 'https://picsum.photos/200/200?random=1',
      'played_at': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
    },
    {
      'user_id': 'user2',
      'username': 'sarah_beats',
      'profile_pic': 'https://i.pravatar.cc/150?img=2',
      'song_title': 'Levitating',
      'song_artists': ['Dua Lipa', 'DaBaby'],
      'song_thumbnail': 'https://picsum.photos/200/200?random=2',
      'played_at': DateTime.now()
          .subtract(const Duration(minutes: 15))
          .toIso8601String(),
    },
    {
      'user_id': 'user3',
      'username': 'mike_vibes',
      'profile_pic': 'https://i.pravatar.cc/150?img=3',
      'song_title': 'Save Your Tears',
      'song_artists': ['The Weeknd', 'Ariana Grande'],
      'song_thumbnail': 'https://picsum.photos/200/200?random=3',
      'played_at': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
    },
    {
      'user_id': 'user4',
      'username': 'emma_rhythm',
      'profile_pic': 'https://i.pravatar.cc/150?img=4',
      'song_title': 'Good 4 U',
      'song_artists': ['Olivia Rodrigo'],
      'song_thumbnail': 'https://picsum.photos/200/200?random=4',
      'played_at': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    },
    {
      'user_id': 'user5',
      'username': 'chris_tunes',
      'profile_pic': 'https://i.pravatar.cc/150?img=5',
      'song_title': 'Peaches',
      'song_artists': ['Justin Bieber', 'Daniel Caesar', 'Giveon'],
      'song_thumbnail': 'https://picsum.photos/200/200?random=5',
      'played_at': DateTime.now()
          .subtract(const Duration(hours: 3))
          .toIso8601String(),
    },
  ];
});

class SocialScreen extends ConsumerWidget {
  const SocialScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return activitiesAsync.when(
      data: (activities) {
        if (activities.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_off,
                  size: 64,
                  color: textSecondaryColor.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No activity yet',
                  style: AppTypography.subtitle.copyWith(
                    color: textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Follow some users to see their activity',
                  style: AppTypography.caption.copyWith(
                    color: textSecondaryColor,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: 120,
          ),
          itemCount: activities.length,
          itemBuilder: (context, index) {
            return _ActivityCard(activity: activities[index], ref: ref);
          },
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(
          color: ref.watch(themeIconActiveColorProvider),
        ),
      ),
      error: (error, stack) => Center(
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
          ],
        ),
      ),
    );
  }
}

// Activity Card Widget
class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> activity;
  final WidgetRef ref;

  const _ActivityCard({required this.activity, required this.ref});

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final playedAt = DateTime.parse(activity['played_at']);
    final timeAgo = _getTimeAgo(playedAt);
    final artists = (activity['song_artists'] as List).join(', ');

    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color.fromARGB(0, 244, 67, 54),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // User Profile Picture
          ClipOval(
            child: Image.network(
              activity['profile_pic'],
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 28,
                height: 28,
                color: cardBackgroundColor,
                child: Icon(Icons.person, color: textSecondaryColor, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Song Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(54 * thumbnailRadius),
            child: Image.network(
              activity['song_thumbnail'],
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
          ),
          const SizedBox(width: 12),

          // Song Info
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // allow Column to shrink
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        activity['username'],
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: textPrimaryColor,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• $timeAgo',
                      style: AppTypography.caption.copyWith(
                        color: textSecondaryColor,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  activity['song_title'],
                  style: AppTypography.songTitle.copyWith(
                    fontWeight: FontWeight.w500,
                    color: textPrimaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  artists,
                  style: AppTypography.caption.copyWith(
                    color: textSecondaryColor,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Profiles Screen Content (without its own Scaffold)
class ProfilesScreenContent extends StatelessWidget {
  const ProfilesScreenContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Return just the content part, not the full ProfilesScreen with Scaffold
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
