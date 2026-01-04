// lib/services/follow_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

// Providers
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
