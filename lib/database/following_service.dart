// lib/services/follow_service.dart
//
// Contains:
// 1. FollowService — follow/unfollow, get followers/following, isFollowing, counts
// 2. followingActivitiesProvider — fixed version:
//    - uiRefreshTimer no longer self-cancels when nothing is playing
//    - Stale LIVE badge now writes correction to DB (so friends see it too)
//    - loadActivities prioritises is_currently_playing = true row over most-recent stopped row

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart'
    hide supabaseClientProvider;

// ============================================================
// FOLLOW SERVICE
// ============================================================

class FollowService {
  final SupabaseClient _supabase;

  FollowService(this._supabase);

  Future<void> followUser(String followerId, String followedId) async {
    try {
      if (followerId == followedId) {
        throw Exception('Cannot follow yourself');
      }

      await _supabase.from('user_follows').insert({
        'follower_id': followerId,
        'followed_id': followedId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error following user: $e');
      rethrow;
    }
  }

  Future<void> unfollowUser(String followerId, String followedId) async {
    try {
      await _supabase
          .from('user_follows')
          .delete()
          .eq('follower_id', followerId)
          .eq('followed_id', followedId);
    } catch (e) {
      print('Error unfollowing user: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {
      final response = await _supabase
          .from('user_follows')
          .select('follower_id, created_at')
          .eq('followed_id', userId);

      final followerIds = (response as List)
          .map((r) => r['follower_id'] as String)
          .toList();

      if (followerIds.isEmpty) return [];

      final profiles = await _supabase
          .from('profiles')
          .select('id, userid, profile_pic_url, email')
          .inFilter('id', followerIds);

      return (profiles as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error getting followers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {
      final response = await _supabase
          .from('user_follows')
          .select('followed_id, created_at')
          .eq('follower_id', userId);

      final followingIds = (response as List)
          .map((r) => r['followed_id'] as String)
          .toList();

      if (followingIds.isEmpty) return [];

      final profiles = await _supabase
          .from('profiles')
          .select('id, userid, profile_pic_url, email')
          .inFilter('id', followingIds);

      return (profiles as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error getting following: $e');
      return [];
    }
  }

  Future<bool> isFollowing(String followerId, String followedId) async {
    try {
      final response = await _supabase
          .from('user_follows')
          .select('follower_id')
          .eq('follower_id', followerId)
          .eq('followed_id', followedId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, int>> getFollowCounts(String userId) async {
    try {
      final followers = await getFollowers(userId);
      final following = await getFollowing(userId);

      return {'followers': followers.length, 'following': following.length};
    } catch (e) {
      return {'followers': 0, 'following': 0};
    }
  }
}

// ============================================================
// FOLLOW SERVICE PROVIDERS
// ============================================================

final followServiceProvider = Provider<FollowService>((ref) {
  final supabase = Supabase.instance.client;
  return FollowService(supabase);
});

final isFollowingProvider = FutureProvider.family<bool, String>((
  ref,
  userId,
) async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser == null) return false;

  final followService = ref.watch(followServiceProvider);
  return await followService.isFollowing(currentUser.id, userId);
});

final followCountsProvider = FutureProvider.family<Map<String, int>, String>((
  ref,
  userId,
) async {
  final followService = ref.watch(followServiceProvider);
  return await followService.getFollowCounts(userId);
});

// ============================================================
// REALTIME ACTIVITY STREAM PROVIDER
// ============================================================

final realtimeActivityStreamProvider = StreamProvider<ListeningActivity>((ref) {
  final dbActions = ref.watch(dbActionsProvider);
  final hasAccessCode = ref.watch(hasAccessCodeProvider);

  if (!(hasAccessCode.value ?? false)) return Stream.empty();

  return dbActions.subscribeToFollowingActivity();
});

// ============================================================
// FOLLOWING ACTIVITIES PROVIDER (FIXED)
// ============================================================

final followingActivitiesProvider = StreamProvider<List<ListeningActivity>>((
  ref,
) {
  final currentUser = ref.watch(currentUserProvider);
  final hasAccessCode = ref.watch(hasAccessCodeProvider);
  final supabase = ref.watch(supabaseClientProvider);

  if (currentUser == null || !(hasAccessCode.value ?? false)) {
    return Stream.value([]);
  }

  final controller = StreamController<List<ListeningActivity>>();
  List<ListeningActivity> activities = [];

  Timer? autoRefreshTimer;

  // FIX: uiRefreshTimer is now persistent — it does NOT self-cancel when
  // hasPlaying becomes false. It idles cheaply and immediately resumes
  // per-second emission when a new song starts playing, without needing
  // any timer restart logic. Old code cancelled the timer on pause/stop,
  // meaning smooth position updates would permanently break until re-mount.
  Timer? uiRefreshTimer;
  RealtimeChannel? realtimeChannel;
  bool isDisposed = false;
  bool mounted = true;

  void safeAdd(List<ListeningActivity> newActivities) {
    if (!isDisposed && !controller.isClosed && mounted) {
      try {
        activities = newActivities;
        controller.add(activities);
      } catch (e) {
        print('⚠️ Safe add error: $e');
      }
    }
  }

  // FIX: Write stale correction to DB — old code only mutated jsonData locally
  // so friends still saw the LIVE badge on their device.
  Future<void> _markStaleActivityStopped(String activityId) async {
    try {
      await supabase
          .from('listening_activity')
          .update({'is_currently_playing': false})
          .eq('id', activityId);
      print('🧹 [STALE] Marked activity $activityId as stopped in DB');
    } catch (e) {
      print('❌ [STALE] Failed to update stale activity $activityId: $e');
    }
  }

  Future<void> loadActivities() async {
    if (isDisposed || controller.isClosed || !mounted) return;

    try {
      print('🔄 Loading following activities for: ${currentUser.id}');

      final response = await supabase.rpc(
        'get_following_activities',
        params: {'p_user_id': currentUser.id},
      );

      if (response is List) {
        final newActivities = <ListeningActivity>[];
        final now = DateTime.now().toUtc();
        final staleIds = <String>[];

        for (final item in response) {
          try {
            final jsonData = Map<String, dynamic>.from(item);

            if (jsonData['played_at'] is String) {
              jsonData['played_at'] = DateTime.parse(
                jsonData['played_at'] as String,
              ).toUtc().toIso8601String();
            }

            jsonData['current_position_ms'] =
                jsonData['current_position_ms'] ?? 0;
            jsonData['is_currently_playing'] =
                jsonData['is_currently_playing'] ?? false;
            jsonData['duration_ms'] = jsonData['duration_ms'] ?? 0;
            jsonData['status'] = jsonData['status'] ?? 'unknown';

            // FIX: Detect stale "playing" rows and persist the correction to DB.
            // Old code: jsonData['is_currently_playing'] = false (local only).
            // New code: also calls _markStaleActivityStopped → DB UPDATE,
            // so every client (including friends) sees the corrected state.
            final playedAt = DateTime.parse(
              jsonData['played_at'] as String,
            ).toUtc();
            final ageInMinutes = now.difference(playedAt).inMinutes;

            if (jsonData['is_currently_playing'] == true && ageInMinutes > 5) {
              print(
                '⚠️ Stale LIVE activity: ${jsonData['song_title']} (${ageInMinutes}min old)',
              );
              jsonData['is_currently_playing'] = false; // local display fix
              final staleId = jsonData['id'] as String?;
              if (staleId != null) staleIds.add(staleId);
            }

            final activity = ListeningActivity.fromMap(jsonData);
            newActivities.add(activity);
          } catch (e) {
            print('⚠️ Error parsing activity: $e');
          }
        }

        safeAdd(newActivities);
        print('✅ Loaded ${newActivities.length} activities');

        // Write DB corrections asynchronously — don't block the UI update
        for (final staleId in staleIds) {
          unawaited(_markStaleActivityStopped(staleId));
        }
      }
    } catch (e) {
      print('❌ Error loading activities: $e');
      if (!isDisposed && !controller.isClosed && mounted) {
        try {
          controller.addError(e);
        } catch (_) {}
      }
    }
  }

  // Initial load
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isDisposed && mounted) {
      loadActivities();
    }
  });

  // Real-time subscription — fires on any change to listening_activity
  if (!isDisposed) {
    try {
      realtimeChannel = supabase
          .channel('following_activities_${currentUser.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'listening_activity',
            callback: (payload) async {
              if (isDisposed) return;
              print('🔔 Real-time activity change: ${payload.eventType}');
              if (!isDisposed && mounted) {
                await loadActivities();
              }
            },
          )
          .subscribe();

      print('📡 Subscribed to real-time activity changes');
    } catch (e) {
      print('❌ Error setting up realtime: $e');
    }
  }

  // Per-second UI refresh for smooth live position bar updates.
  // Persistent — never self-cancels. Idles for free when nothing is playing.
  uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (isDisposed || !mounted) {
      timer.cancel();
      return;
    }
    if (activities.isEmpty) return;

    final hasPlaying = activities.any((a) => a.isCurrentlyPlaying);
    if (hasPlaying) {
      // Re-emit same list — UI recalculates real-time positions on rebuild
      safeAdd(List.from(activities));
    }
    // Nothing playing → skip tick, timer stays alive for next song
  });

  // Database refresh every 10 seconds as a safety net
  autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
    if (!isDisposed && mounted) {
      print('🔄 Auto-refreshing activities (10s interval)...');
      loadActivities();
    } else {
      timer.cancel();
    }
  });

  ref.onDispose(() {
    print('🗑️ Disposing activities provider');
    isDisposed = true;
    mounted = false;

    autoRefreshTimer?.cancel();
    autoRefreshTimer = null;

    uiRefreshTimer?.cancel();
    uiRefreshTimer = null;

    try {
      realtimeChannel?.unsubscribe();
    } catch (e) {
      print('⚠️ Error unsubscribing realtime: $e');
    }
    realtimeChannel = null;

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
