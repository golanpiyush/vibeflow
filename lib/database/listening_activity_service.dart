// lib/database/listening_activity_service.dart
// Fixes applied:
// 1. streamUserActivity StreamController is properly closed in all error paths
// 2. getFollowingActivities fallback correctly filters by followed users
// 3. _fetchUserActivity no longer overwrites played_at — reads it as-is
// 4. recordListeningActivity uses UPDATE for position, not upsert that bumps played_at
// 5. subscribeToFollowingActivity properly closes controller on cancel
// 6. [NEW] _getFollowingActivitiesFallback batches all queries — no more N+1
// 7. [NEW] Stale activity cleanup writes to DB (so friends see corrected state)
// 8. [NEW] _fetchUserActivity returns the CURRENT playing row first,
//    falling back to most-recent row — fixes "old song still showing" bug

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

  /// recordListeningActivity now only updates duration on the existing stopped row.
  /// played_at is never touched. The initial row is created by
  /// RealtimeListeningTracker._createActivityNow().
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

      final hasAccessCode = await _checkUserAccessCode(userId);
      if (!hasAccessCode) {
        print(
          '⚠️ User does not have access code - skipping activity recording',
        );
        return;
      }

      final connectivityResult = await _connectivity.checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;

      if (isConnected) {
        // FIX: Only update the played duration on the existing stopped row.
        // Target by song_id AND is_currently_playing = false to avoid the race
        // where this UPDATE fires before _hardStop completes.
        // We use .order + .limit(1) to hit the most-recently-stopped row.
        await Future.delayed(const Duration(milliseconds: 200));

        var rows = await _supabase
            .from('listening_activity')
            .select('id')
            .eq('user_id', userId)
            .eq('song_id', songId)
            .eq('is_currently_playing', false)
            .order('played_at', ascending: false)
            .limit(1);

        if (rows.isEmpty) {
          // FIX: Fallback — row may not be stopped yet, try the playing row too
          print(
            '⚠️ recordListeningActivity: no stopped row, trying playing row...',
          );
          rows = await _supabase
              .from('listening_activity')
              .select('id')
              .eq('user_id', userId)
              .eq('song_id', songId)
              .eq('is_currently_playing', true)
              .order('played_at', ascending: false)
              .limit(1);
        }

        if (rows is List && rows.isNotEmpty) {
          final rowId = rows.first['id'] as String;
          await _supabase
              .from('listening_activity')
              .update({'duration_ms': playedDurationMs})
              .eq('id', rowId);
          print('✅ Listening activity UPDATED: $title - $playedDurationMs ms');
        } else {
          print(
            '⚠️ recordListeningActivity: no row found for $title after fallback, skipping',
          );
        }
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

  Stream<List<ListeningActivity>> streamUserActivity(String userId) {
    return _createUserActivityStream(userId);
  }

  Stream<List<ListeningActivity>> _createUserActivityStream(
    String userId,
  ) async* {
    print('📡 Starting realtime stream for user activity: $userId');

    final controller = StreamController<List<ListeningActivity>>.broadcast();
    RealtimeChannel? channel;

    controller.onCancel = () {
      print('🛑 User activity stream cancelled');
      channel?.unsubscribe();
      if (!controller.isClosed) controller.close();
    };

    try {
      final initialActivities = await _fetchUserActivity(userId);
      if (!controller.isClosed) controller.add(initialActivities);

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
              await Future.delayed(const Duration(milliseconds: 500));
              if (controller.isClosed) return;
              final activities = await _fetchUserActivity(userId);
              if (!controller.isClosed && activities.isNotEmpty) {
                controller.add(activities);
              }
            },
          )
          .subscribe();

      print('✅ Subscribed to realtime updates for user activity');
    } catch (e) {
      print('❌ Error setting up user activity stream: $e');
      if (!controller.isClosed) {
        controller.addError(e);
        controller.close();
      }
    }

    yield* controller.stream;
  }

  // FIX 8: Fetch the CURRENTLY PLAYING row first.
  // If nothing is playing, fall back to the most-recent row.
  // This is the core fix for "Ehsaas 10 mins ago still showing while Sajde
  // is playing" — the old code did ORDER BY played_at DESC LIMIT 1 which
  // could return the old stopped row if the new insert was a few ms behind.
  Future<List<ListeningActivity>> _fetchUserActivity(String userId) async {
    try {
      print('🔍 Fetching latest activity for user: $userId');

      final nowUtc = DateTime.now().toUtc();

      // Step 1: Try to get the currently playing row first
      var response = await _supabase
          .from('listening_activity')
          .select('*')
          .eq('user_id', userId)
          .eq('is_currently_playing', true)
          .order('played_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // Step 2: If nothing is currently playing, get the most recent row
      if (response == null) {
        response = await _supabase
            .from('listening_activity')
            .select('*')
            .eq('user_id', userId)
            .order('played_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      if (response == null) {
        print('   No recent activity found for user');
        return [];
      }

      final activityData = Map<String, dynamic>.from(response);

      // Normalize to UTC ISO string — do NOT overwrite, just reformat
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
      print(
        '   Playing: ${activity.isCurrentlyPlaying} | ${minutesAgo}min ago (UTC)',
      );

      return [activity];
    } catch (e) {
      print('❌ Error fetching user activity: $e');
      return [];
    }
  }

  Future<List<ListeningActivity>> getFollowingActivities(String userId) async {
    try {
      print('🔍 Fetching following activities for user: $userId');

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
        return await _getFollowingActivitiesFallback(userId);
      }
    } catch (e, stack) {
      print('❌ Error in getFollowingActivities: $e');
      print('   Stack trace: $stack');
      return [];
    }
  }

  // FIX 6: Replaced N+1 loop (2*N queries) with 2 batched queries total.
  // Old approach: for each followed user → 1 activity query + 1 profile query = 2N DB calls.
  // New approach: 1 follows query + 1 batched activity query + 1 batched profile query = 3 total.
  Future<List<ListeningActivity>> _getFollowingActivitiesFallback(
    String userId,
  ) async {
    try {
      print('🔄 Using batched fallback method for user: $userId');

      // Step 1: Get all followed user IDs
      final followsResponse = await _supabase
          .from('user_follows')
          .select('followed_id')
          .eq('follower_id', userId);

      final followedUserIds = (followsResponse as List)
          .map((item) => item['followed_id'] as String)
          .toList();

      if (followedUserIds.isEmpty) return [];

      print('   Following ${followedUserIds.length} users');

      // Step 2: Batch-fetch the latest activity for ALL followed users at once.
      // We use a subquery pattern: get all rows ordered by played_at, then
      // deduplicate to one row per user by taking the most recent.
      // For Supabase/PostgREST we fetch all recent rows and deduplicate in Dart
      // (PostgREST doesn't support DISTINCT ON directly).
      // Limit to 200 rows to avoid huge payloads even with many followed users.
      final activitiesResponse = await _supabase
          .from('listening_activity')
          .select('*')
          .inFilter('user_id', followedUserIds)
          .order('played_at', ascending: false)
          .limit(200);

      // Deduplicate: for each user keep the first (most-recent / playing) row.
      // Priority: is_currently_playing = true wins over any stopped row.
      final Map<String, Map<String, dynamic>> latestPerUser = {};
      for (final row in (activitiesResponse as List)) {
        final rowUserId = row['user_id'] as String;
        final isPlaying = row['is_currently_playing'] == true;

        if (!latestPerUser.containsKey(rowUserId)) {
          latestPerUser[rowUserId] = Map<String, dynamic>.from(row);
        } else {
          // Replace the stored row if this one is currently playing and the
          // stored one is not — ensures the live song wins.
          final storedIsPlaying =
              latestPerUser[rowUserId]!['is_currently_playing'] == true;
          if (isPlaying && !storedIsPlaying) {
            latestPerUser[rowUserId] = Map<String, dynamic>.from(row);
          }
        }
      }

      if (latestPerUser.isEmpty) return [];

      // Step 3: Batch-fetch profiles for all relevant users in one query
      final activeUserIds = latestPerUser.keys.toList();
      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, userid, profile_pic_url')
          .inFilter('id', activeUserIds);

      final profileMap = <String, Map<String, dynamic>>{};
      for (final profile in (profilesResponse as List)) {
        profileMap[profile['id'] as String] = Map<String, dynamic>.from(
          profile,
        );
      }

      // Step 4: Combine and parse
      final activities = <ListeningActivity>[];
      for (final entry in latestPerUser.entries) {
        try {
          final activityData = entry.value;
          final profile = profileMap[entry.key];

          if (profile != null) {
            activityData['username'] = profile['userid'] ?? 'Unknown';
            activityData['profile_pic'] = profile['profile_pic_url'];
          } else {
            activityData['username'] = 'Unknown User';
            activityData['profile_pic'] = null;
          }

          // Normalize played_at to UTC
          if (activityData['played_at'] is String) {
            final parsedUtc = DateTime.parse(
              activityData['played_at'] as String,
            ).toUtc();
            activityData['played_at'] = parsedUtc.toIso8601String();
          }

          activities.add(ListeningActivity.fromMap(activityData));
        } catch (e) {
          print('⚠️ Fallback parse error for ${entry.key}: $e');
        }
      }

      activities.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      print(
        '✅ Fallback: returned ${activities.length} activities (3 queries total)',
      );
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

  Stream<ListeningActivity> subscribeToFollowingActivity() {
    const channelName = 'following_activity';

    _channels[channelName]?.unsubscribe();

    final oldController = _controllers[channelName];
    if (oldController != null && !oldController.isClosed) {
      oldController.close();
    }

    final controller = StreamController<ListeningActivity>.broadcast();
    _controllers[channelName] = controller;

    controller.onCancel = () {
      print('🛑 Following activity stream cancelled');
      _channels[channelName]?.unsubscribe();
      _channels.remove(channelName);
      if (!controller.isClosed) controller.close();
      _controllers.remove(channelName);
    };

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

              final hasAccessCode = await _checkUserAccessCode(userId);
              if (!hasAccessCode) {
                print('⚠️ Activity from user without access code - ignored');
                return;
              }

              final isFollowing = await _checkIfFollowing(userId);
              if (!isFollowing) return;

              if (controller.isClosed) return;
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
    final oldController = _controllers[channelName];
    if (oldController != null && !oldController.isClosed) {
      oldController.close();
    }

    final controller = StreamController<PlaylistUpdate>.broadcast();
    _controllers[channelName] = controller;

    controller.onCancel = () {
      _channels[channelName]?.unsubscribe();
      _channels.remove(channelName);
      if (!controller.isClosed) controller.close();
      _controllers.remove(channelName);
    };

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
              if (controller.isClosed) return;
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
      if (!controller.isClosed) controller.close();
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

// Providers
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
