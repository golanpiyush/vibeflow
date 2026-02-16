// lib/screens/profiles_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:lottie/lottie.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/database/following_service.dart';

/// =======================
/// PROVIDERS
/// =======================

final allUsersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    print('❌ No current user found');
    return [];
  }

  try {
    final response = await supabase
        .from('profiles')
        .select('id, userid, profile_pic_url, email')
        .neq('id', currentUser.id);

    print('✅ Fetched ${(response as List).length} users');
    return (response as List).cast<Map<String, dynamic>>();
  } catch (e) {
    print('❌ Error fetching users: $e');
    return [];
  }
});

final followStatesProvider = StateProvider<Map<String, bool>>((ref) => {});

/// =======================
/// SCREEN
/// =======================

class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleFollow(String userId, bool isCurrentlyFollowing) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to follow users')),
      );
      return;
    }

    final followService = ref.read(followServiceProvider);
    final followStates = ref.read(followStatesProvider.notifier);

    // Get username for snackbar message
    final users = ref.read(allUsersProvider).value ?? [];
    final targetUser = users.firstWhere(
      (u) => u['id'] == userId,
      orElse: () => {'userid': 'User'},
    );
    final username = targetUser['userid'] as String? ?? 'User';

    // Optimistically update UI
    followStates.state = {...followStates.state, userId: !isCurrentlyFollowing};

    try {
      if (isCurrentlyFollowing) {
        await followService.unfollowUser(currentUser.id, userId);
        print('✅ Unfollowed user: $userId');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.compress_sharp,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text('Unfollowed $username'),
                ],
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color.fromARGB(255, 167, 65, 65),
            ),
          );
        }
      } else {
        await followService.followUser(currentUser.id, userId);
        print('✅ Followed user: $userId');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('Following $username'),
                ],
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green[700],
            ),
          );
        }
      }

      ref.invalidate(isFollowingProvider(userId));
    } catch (e) {
      print('❌ Error toggling follow: $e');

      followStates.state = {
        ...followStates.state,
        userId: isCurrentlyFollowing,
      };

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to ${isCurrentlyFollowing ? "unfollow" : "follow"} $username',
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red[700],
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _toggleFollow(userId, isCurrentlyFollowing),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final usersAsync = ref.watch(allUsersProvider);

    final bgColor = themeData.scaffoldBackgroundColor;
    final textPrimary = themeData.textTheme.bodyLarge?.color ?? Colors.white;
    final cardColor = themeData.cardColor;
    final accentColor = themeData.primaryColor;

    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            /// SEARCH BAR
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  hintStyle: TextStyle(color: textPrimary.withOpacity(0.5)),
                  filled: true,
                  fillColor: cardColor,
                  prefixIcon: Icon(Icons.search, color: accentColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(42),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            /// USER LIST
            Expanded(
              child: usersAsync.when(
                data: (users) {
                  final filteredUsers = users.where((u) {
                    final name = (u['userid'] as String? ?? '').toLowerCase();
                    final email = (u['email'] as String? ?? '').toLowerCase();
                    return name.contains(_searchQuery) ||
                        email.contains(_searchQuery);
                  }).toList();

                  if (filteredUsers.isEmpty) {
                    return SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: keyboardOpen ? 20 : 80),
                            SizedBox(
                              height: keyboardOpen ? 140 : 260,
                              child: Lottie.asset(
                                'assets/animations/not_found.json',
                                repeat: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No other users yet'
                                  : 'No users found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textPrimary.withOpacity(0.7),
                              ),
                            ),
                            if (_searchQuery.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Invite friends to join!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textPrimary.withOpacity(0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(allUsersProvider);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredUsers.length,
                      itemBuilder: (_, i) => _UserCard(
                        user: filteredUsers[i],
                        onToggleFollow: _toggleFollow,
                      ),
                    ),
                  );
                },
                loading: () => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 6,
                  itemBuilder: (_, __) =>
                      _UserCardShimmer(themeData: themeData),
                ),
                error: (error, stack) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: textPrimary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load users',
                          style: TextStyle(color: textPrimary, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => ref.invalidate(allUsersProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =======================
/// USER CARD
/// =======================

class _UserCard extends ConsumerWidget {
  final Map<String, dynamic> user;
  final Function(String, bool) onToggleFollow;

  const _UserCard({required this.user, required this.onToggleFollow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;

    final cardColor = themeData.colorScheme.surface;
    final accentColor = colorScheme.primary;
    final textPrimary = colorScheme.onSurface;

    final userId = user['id'] as String;
    final username = user['userid'] as String? ?? 'Unknown';
    final profilePic = user['profile_pic_url'] as String?;

    final hasValidProfilePic =
        profilePic != null &&
        profilePic.isNotEmpty &&
        profilePic.startsWith('http');

    final isFollowingAsync = ref.watch(isFollowingProvider(userId));
    final followStates = ref.watch(followStatesProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          /// PROFILE PICTURE
          CircleAvatar(
            radius: 28,
            backgroundColor: accentColor.withOpacity(0.2),
            child: hasValidProfilePic
                ? ClipOval(
                    child: Image.network(
                      profilePic,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            username.isNotEmpty
                                ? username[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentColor,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          /// USER INFO
          Expanded(
            child: Text(
              username,
              style: themeData.textTheme.bodyLarge?.copyWith(
                color: textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          /// FOLLOW BUTTON
          isFollowingAsync.when(
            data: (isFollowing) {
              final displayFollowing = followStates[userId] ?? isFollowing;

              return ElevatedButton(
                onPressed: () => onToggleFollow(userId, displayFollowing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: displayFollowing
                      ? themeData.colorScheme.surface
                      : accentColor,
                  foregroundColor: displayFollowing
                      ? colorScheme.onSurface
                      : colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(38),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  displayFollowing ? 'Following' : 'Follow',
                  style: themeData.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              );
            },
            loading: () => SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentColor,
              ),
            ),
            error: (_, __) => ElevatedButton(
              onPressed: () => ref.invalidate(isFollowingProvider(userId)),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeData.colorScheme.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child: Text('Retry', style: themeData.textTheme.labelLarge),
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================
/// SHIMMER LOADING
/// =======================

class _UserCardShimmer extends StatelessWidget {
  final ThemeData themeData;

  const _UserCardShimmer({required this.themeData});

  @override
  Widget build(BuildContext context) {
    final isDark = themeData.brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 80,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[400],
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
