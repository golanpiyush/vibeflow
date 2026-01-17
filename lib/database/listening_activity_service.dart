// lib/database/listening_activity_service.dart
import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:vibeflow/utils/time_utils.dart';

class ListeningActivityService {
  final SupabaseClient _supabase;
  final Connectivity _connectivity;

  ListeningActivityService(this._supabase, this._connectivity);

  static String generateSongId(String title, List<String> artists) {
    final normalizedTitle = title.toLowerCase().trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    final sortedArtists =
        artists
            .map(
              (artist) =>
                  artist.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' '),
            )
            .toSet()
            .toList()
          ..sort();

    final combined = '$normalizedTitle|${sortedArtists.join('||')}';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> recordListeningActivity({
    required String userId,
    required String videoId,
    required String title,
    required List<String> artists,
    required String? thumbnail,
    required int durationMs,
    int playedDurationMs = 0,
  }) async {
    try {
      final songId = generateSongId(title, artists);

      // Check if user has access code
      final hasAccessCode = await _checkUserAccessCode(userId);
      if (!hasAccessCode) {
        print(
          '⚠️ User does not have access code - skipping activity recording',
        );
        return;
      }

      // 🔥 REMOVE the minimum playback check - save immediately!
      // Even if they only listened for 5 seconds, save it

      final activity = {
        'user_id': userId,
        'song_id': songId,
        'source_video_id': videoId,
        'song_title': title,
        'song_artists': artists,
        'song_thumbnail': thumbnail,
        'duration_ms': playedDurationMs, // Current played duration
        'played_at': DateTime.now().toUtc().toIso8601String(),
      };

      final connectivityResult = await _connectivity.checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;

      if (isConnected) {
        // 🔥 FIX: Use UPSERT instead of delete + insert
        // This updates the existing record or creates a new one
        await _supabase
            .from('listening_activity')
            .upsert(activity, onConflict: 'user_id,song_id,played_at');

        print(
          '✅ Listening activity SAVED: $title - $playedDurationMs ms at ${DateTime.now()}',
        );
      }
    } catch (e) {
      print('❌ Error recording listening activity: $e');
    }
  }

  Future<List<ListeningActivity>> getUserListeningHistory({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('listening_activity')
          .select('*')
          .eq('user_id', userId)
          .order('played_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((item) => ListeningActivity.fromMap(item))
          .toList();
    } catch (e) {
      print('Error fetching listening history: $e');
      return [];
    }
  }

  /// Stream current user's listening activity (polls every 5 seconds)
  /// Stream current user's listening activity with realtime updates
  Stream<List<ListeningActivity>> streamUserActivity(String userId) {
    return _createUserActivityStream(userId);
  }

  Stream<List<ListeningActivity>> _createUserActivityStream(
    String userId,
  ) async* {
    print('📡 Starting realtime stream for user activity: $userId');

    // Create a stream controller
    final controller = StreamController<List<ListeningActivity>>();
    RealtimeChannel? channel;

    // Setup cleanup
    controller.onCancel = () {
      print('🛑 User activity stream cancelled');
      channel?.unsubscribe();
    };

    try {
      // Fetch and yield initial data
      final initialActivities = await _fetchUserActivity(userId);
      controller.add(initialActivities);

      // Subscribe to realtime changes
      channel = _supabase
          .channel('user_activity_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'listening_activity',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) async {
              print('🔔 Activity changed: ${payload.eventType}');

              // Wait a moment for the database to be fully updated
              await Future.delayed(const Duration(milliseconds: 500));

              // Refetch and yield updated data
              final activities = await _fetchUserActivity(userId);
              if (activities.isNotEmpty) {
                controller.add(activities);
              }
            },
          )
          .subscribe();

      print('✅ Subscribed to realtime updates for user activity');
    } catch (e) {
      print('❌ Error setting up user activity stream: $e');
      controller.addError(e);
    }

    // Yield from controller stream
    yield* controller.stream;
  }

  // Helper method to fetch user activity
  Future<List<ListeningActivity>> _fetchUserActivity(String userId) async {
    try {
      print('🔍 Fetching latest activity for user: $userId');

      // 🔥 FIX: Use UTC to avoid timezone issues
      final nowUtc = DateTime.now().toUtc();

      final response = await _supabase
          .from('listening_activity')
          .select('*')
          .eq('user_id', userId)
          .order('played_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        print('   No recent activity found for user');
        return [];
      }

      final activityData = Map<String, dynamic>.from(response);

      // 🔥 FIX: Ensure played_at is parsed as UTC
      final playedAtString = activityData['played_at'] as String;
      final playedAtUtc = DateTime.parse(playedAtString).toUtc();
      activityData['played_at'] = playedAtUtc.toIso8601String();

      // Fetch profile data
      final profile = await _supabase
          .from('profiles')
          .select('id, userid, profile_pic_url')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        activityData['username'] = profile['userid'] ?? 'Unknown';
        activityData['profile_pic'] = profile['profile_pic_url'];
      } else {
        activityData['username'] = 'Unknown User';
        activityData['profile_pic'] = null;
      }

      final activity = ListeningActivity.fromMap(activityData);

      final timeAgo = nowUtc.difference(playedAtUtc);
      final minutesAgo = timeAgo.inMinutes;

      print(
        '   Current song: ${activity.songTitle} by ${activity.songArtists.join(', ')}',
      );
      print('   Played $minutesAgo minutes ago (UTC)');

      return [activity];
    } catch (e) {
      print('❌ Error fetching user activity: $e');
      return [];
    }
  }

  // Helper method to fetch user activity
  Future<List<ListeningActivity>> getFollowingActivities(String userId) async {
    try {
      print('🔍 Fetching following activities for user: $userId');

      // Try the function first
      try {
        final response = await _supabase.rpc(
          'get_following_activities',
          params: {'p_user_id': userId},
        );

        print('📊 Function response count: ${response.length}');

        final activities = <ListeningActivity>[];

        for (final item in response) {
          try {
            final jsonData = Map<String, dynamic>.from(item);

            // Parse UTC timestamp properly
            if (jsonData['played_at'] is String) {
              final playedAtString = jsonData['played_at'] as String;
              final parsedUtc = DateTime.parse(playedAtString).toUtc();
              jsonData['played_at'] = parsedUtc.toIso8601String();
            }

            final activity = ListeningActivity.fromMap(jsonData);
            activities.add(activity);

            print('🎵 Found: ${activity.username} - ${activity.songTitle}');
            print('   Time: ${TimeUtils.formatTimeAgo(activity.playedAt)}');
          } catch (e) {
            print('⚠️ Error parsing activity: $e');
          }
        }

        print('✅ Found ${activities.length} activities via function');
        return activities;
      } catch (funcError) {
        print('⚠️ Function failed, using manual query: $funcError');

        // Fallback: Manual query
        return await _getFollowingActivitiesFallback(userId);
      }
    } catch (e, stack) {
      print('❌ Error in getFollowingActivities: $e');
      print('   Stack trace: $stack');
      return [];
    }
  }

  // Fallback method if function doesn't exist
  Future<List<ListeningActivity>> _getFollowingActivitiesFallback(
    String userId,
  ) async {
    try {
      print('🔄 Using fallback method for user: $userId');

      // Get followed users
      final followsResponse = await _supabase
          .from('user_follows')
          .select('followed_id')
          .eq('follower_id', userId);

      final followedUserIds = (followsResponse as List)
          .map((item) => item['followed_id'] as String)
          .toList();

      if (followedUserIds.isEmpty) return [];

      final activities = <ListeningActivity>[];

      for (final followedId in followedUserIds) {
        try {
          final latestActivity = await _supabase
              .from('listening_activity')
              .select('*')
              .eq('user_id', followedId)
              .order('played_at', ascending: false)
              .limit(1)
              .maybeSingle();

          if (latestActivity != null) {
            final profile = await _supabase
                .from('profiles')
                .select('userid, profile_pic_url')
                .eq('id', followedId)
                .maybeSingle();

            final activityData = Map<String, dynamic>.from(latestActivity);

            if (profile != null) {
              activityData['username'] = profile['userid'] ?? 'Unknown';
              activityData['profile_pic'] = profile['profile_pic_url'];
            }

            activities.add(ListeningActivity.fromMap(activityData));
          }
        } catch (e) {
          print('⚠️ Fallback error for $followedId: $e');
        }
      }

      activities.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      return activities;
    } catch (e) {
      print('❌ Fallback method also failed: $e');
      return [];
    }
  }

  Future<Map<String, int>> getListeningStats(String userId) async {
    try {
      final response = await _supabase.rpc(
        'get_listening_stats',
        params: {'user_id_param': userId},
      );

      return {
        'total_plays': response['total_plays'] ?? 0,
        'total_duration': response['total_duration'] ?? 0,
        'unique_songs': response['unique_songs'] ?? 0,
      };
    } catch (e) {
      print('Error fetching listening stats: $e');
      return {'total_plays': 0, 'total_duration': 0, 'unique_songs': 0};
    }
  }

  Future<bool> _checkUserAccessCode(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('access_code_used')
          .eq('id', userId)
          .maybeSingle();

      return response != null && response['access_code_used'] != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> _queueOfflineActivity(Map<String, dynamic> activity) async {
    try {
      print('Queued offline activity: $activity');
    } catch (e) {
      print('Error queueing offline activity: $e');
    }
  }
}

class RealtimeService {
  final SupabaseClient _supabase;
  final Connectivity _connectivity;

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<dynamic>> _controllers = {};
  bool _isConnected = false;

  RealtimeService(this._supabase, this._connectivity) {
    _setupConnectionListener();
  }

  void _setupConnectionListener() {
    _connectivity.onConnectivityChanged.listen((result) {
      final wasConnected = _isConnected;
      _isConnected = result != ConnectivityResult.none;

      if (_isConnected && !wasConnected) {
        _reconnectAllChannels();
      } else if (!_isConnected && wasConnected) {
        _pauseAllChannels();
      }
    });
  }

  /// Subscribe to listening activity from users you follow
  /// Only shows activity from users with access codes
  Stream<ListeningActivity> subscribeToFollowingActivity() {
    const channelName = 'following_activity';

    _channels[channelName]?.unsubscribe();
    _controllers[channelName]?.close();

    final controller = StreamController<ListeningActivity>.broadcast();
    _controllers[channelName] = controller;

    final channel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'listening_activity',
          callback: (payload) async {
            try {
              final userId = payload.newRecord['user_id'] as String?;

              if (userId == null) return;

              // Verify user has access code
              final hasAccessCode = await _checkUserAccessCode(userId);
              if (!hasAccessCode) {
                print('⚠️ Activity from user without access code - ignored');
                return;
              }

              // Verify current user follows this user
              final isFollowing = await _checkIfFollowing(userId);
              if (!isFollowing) return;

              final activity = ListeningActivity.fromMap(payload.newRecord);
              controller.add(activity);
              print('🎵 Realtime: ${activity.songTitle}');
            } catch (e) {
              print('❌ Error parsing activity: $e');
            }
          },
        )
        .subscribe();

    _channels[channelName] = channel;
    print('✅ Subscribed to following activity');

    return controller.stream;
  }

  Future<bool> _checkIfFollowing(String followedUserId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return false;

      final response = await _supabase
          .from('user_follows')
          .select('follower_id')
          .eq('follower_id', currentUser.id)
          .eq('followed_id', followedUserId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkUserAccessCode(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('access_code_used')
          .eq('id', userId)
          .maybeSingle();

      return response != null && response['access_code_used'] != null;
    } catch (e) {
      return false;
    }
  }

  Stream<PlaylistUpdate> subscribeToPlaylist(String playlistId) {
    final channelName = 'playlist_$playlistId';

    _channels[channelName]?.unsubscribe();
    _controllers[channelName]?.close();

    final controller = StreamController<PlaylistUpdate>.broadcast();
    _controllers[channelName] = controller;

    final channel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'playlist_songs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'playlist_id',
            value: playlistId,
          ),
          callback: (payload) {
            try {
              final update = PlaylistUpdate.fromPayload(payload);
              controller.add(update);
            } catch (e) {
              print('Error parsing playlist update: $e');
            }
          },
        )
        .subscribe();

    _channels[channelName] = channel;

    return controller.stream;
  }

  void _reconnectAllChannels() {
    print('🔄 Reconnecting all realtime channels...');
    for (final channel in _channels.values) {
      channel.subscribe();
    }
  }

  void _pauseAllChannels() {
    print('⏸️ Pausing all realtime channels...');
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
  }

  void dispose() {
    print('🗑️ Disposing realtime service...');
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    _channels.clear();

    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }

  Future<List<ListeningActivity>> getFollowingActivities(String userId) async {
    try {
      final response = await _supabase
          .from('following_activity')
          .select('*')
          .order('played_at', ascending: false)
          .limit(100);

      return (response as List)
          .where((item) => item['user_id'] != userId)
          .map((item) => ListeningActivity.fromMap(item))
          .toList();
    } catch (e) {
      print('Error fetching following activities: $e');
      return [];
    }
  }
}

// Providers remain the same
final authStateProvider = StreamProvider<User?>((ref) {
  return ref
      .watch(supabaseClientProvider)
      .auth
      .onAuthStateChange
      .map((event) => event.session?.user);
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

final userProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);

  if (user == null) return null;

  try {
    final response = await ref
        .watch(supabaseClientProvider)
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .maybeSingle();

    return response;
  } catch (e) {
    return null;
  }
});

final hasAccessCodeProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  final accessCodeService = ref.watch(accessCodeServiceProvider);

  if (user == null) return false;

  return await accessCodeService.checkIfUserHasAccessCode(user.id);
});
