import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart'
    hide supabaseClientProvider;
import 'dart:convert'; // For utf8
import 'package:crypto/crypto.dart'; // For sha256

class ListeningActivityService {
  final SupabaseClient _supabase;
  final Connectivity _connectivity;

  ListeningActivityService(this._supabase, this._connectivity);

  // Generate deterministic song ID (matches database function)
  static String generateSongId(String title, List<String> artists) {
    // Normalize title: lowercase, trim, remove extra spaces
    final normalizedTitle = title.toLowerCase().trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    // Sort artists alphabetically and normalize
    final sortedArtists =
        artists
            .map(
              (artist) =>
                  artist.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' '),
            )
            .toSet()
            .toList()
          ..sort();

    // Combine with delimiter that won't appear in normalized data
    final combined = '$normalizedTitle|${sortedArtists.join('||')}';

    // Return SHA256 hash
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
      // Generate song ID
      final songId = generateSongId(title, artists);

      // Check if user has access code (RLS will also enforce this)
      final hasAccessCode = await _checkUserAccessCode(userId);
      if (!hasAccessCode) {
        throw Exception('User does not have access code');
      }

      // Record only if listened for at least 30 seconds or 50% of song
      final shouldRecord =
          playedDurationMs >= 30000 ||
          (durationMs > 0 && playedDurationMs >= durationMs ~/ 2);

      if (!shouldRecord) {
        return;
      }

      final activity = {
        'user_id': userId,
        'song_id': songId,
        'source_video_id': videoId,
        'song_title': title,
        'song_artists': artists,
        'song_thumbnail': thumbnail,
        'duration_ms': playedDurationMs,
        'played_at': DateTime.now().toIso8601String(),
      };

      // Check connectivity
      final connectivityResult = await _connectivity.checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;

      if (isConnected) {
        // Insert directly to Supabase
        await _supabase.from('listening_activity').insert(activity);
      } else {
        // Queue for offline sync
        await _queueOfflineActivity(activity);
      }
    } catch (e) {
      // Log error but don't crash the app
      print('Error recording listening activity: $e');
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

  Future<List<ListeningActivity>> getFollowingActivities(String userId) async {
    try {
      // This uses the following_activity view which RLS filters
      final response = await _supabase
          .from('following_activity')
          .select('*')
          .order('played_at', ascending: false)
          .limit(100);

      return (response as List)
          .where((item) => item['user_id'] != userId) // Exclude own activities
          .map((item) => ListeningActivity.fromMap(item))
          .toList();
    } catch (e) {
      print('Error fetching following activities: $e');
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
      // Store in local database for offline sync
      // This would integrate with your DatabaseService
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

  Stream<ListeningActivity> subscribeToFollowingActivity() {
    const channelName = 'following_activity';

    // Clean up existing subscription
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
          callback: (payload) {
            try {
              final activity = ListeningActivity.fromMap(payload.newRecord);
              controller.add(activity);
            } catch (e) {
              print('Error parsing listening activity: $e');
            }
          },
        )
        .subscribe();

    _channels[channelName] = channel;

    return controller.stream;
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
    for (final channel in _channels.values) {
      channel.subscribe();
    }
  }

  void _pauseAllChannels() {
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
  }

  void dispose() {
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    _channels.clear();

    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }

  // Add this method that was referenced but missing
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

// State Management with Riverpod
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
