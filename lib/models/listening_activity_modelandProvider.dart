// Models
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/database/access_code_service.dart';
import 'package:vibeflow/database/listening_activity_service.dart';

class ListeningActivity {
  final String id;
  final String userId;
  final String songId;
  final String sourceVideoId;
  final String songTitle;
  final List<String> songArtists;
  final String? songThumbnail;
  final int durationMs;
  final int currentPositionMs; // Last known position from DB
  final bool isCurrentlyPlaying;
  final DateTime playedAt;
  final DateTime createdAt;
  final String username;
  final String? profilePic;
  final String status;

  ListeningActivity({
    required this.id,
    required this.userId,
    required this.songId,
    required this.sourceVideoId,
    required this.songTitle,
    required this.songArtists,
    this.songThumbnail,
    required this.durationMs,
    required this.currentPositionMs,
    required this.isCurrentlyPlaying,
    required this.playedAt,
    required this.createdAt,
    required this.username,
    this.profilePic,
    required this.status,
  });

  factory ListeningActivity.fromMap(Map<String, dynamic> map) {
    // 🔥 FIX: Always parse as UTC
    DateTime parsePlayedAt(String playedAtString) {
      final dateTime = DateTime.parse(playedAtString);
      // If it doesn't end with Z, assume it's UTC and add it
      if (!playedAtString.endsWith('Z')) {
        return DateTime.parse('${playedAtString}Z').toUtc();
      }
      return dateTime.toUtc();
    }

    return ListeningActivity(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      songId: map['song_id'] as String,
      sourceVideoId: map['source_video_id'] as String? ?? '',
      songTitle: map['song_title'] as String,
      songArtists: List<String>.from(map['song_artists'] as List),
      songThumbnail: map['song_thumbnail'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),

      durationMs: (map['duration_ms'] as int?) ?? 0,
      currentPositionMs: (map['current_position_ms'] as int?) ?? 0,
      isCurrentlyPlaying: (map['is_currently_playing'] as bool?) ?? false,
      playedAt: DateTime.parse(
        map['played_at'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      ).toUtc(),
      username: map['username']?.toString() ?? 'Unknown',
      profilePic: map['profile_pic']?.toString(),
      status: map['status']?.toString() ?? 'unknown',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'song_id': songId,
      'source_video_id': sourceVideoId,
      'song_title': songTitle,
      'song_artists': songArtists,
      'song_thumbnail': songThumbnail,
      'duration_ms': durationMs,
      'played_at': playedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'username': username,
      'profile_pic': profilePic,
    };
  }

  // ✅ ADD THIS GETTER:
  int get realtimeCurrentPositionMs {
    if (!isCurrentlyPlaying) {
      return currentPositionMs; // Use stored position if not playing
    }

    // Calculate real-time position based on elapsed time
    final now = DateTime.now().toUtc();
    final elapsed = now.difference(playedAt).inMilliseconds;
    final estimatedPosition = currentPositionMs + elapsed;

    // Clamp to duration to prevent overflow
    return estimatedPosition.clamp(0, durationMs);
  }

  // ✅ NEW: Real-time position calculation
  int get realtimePositionMs {
    if (!isCurrentlyPlaying) {
      // If paused, return last known position
      return currentPositionMs;
    }

    // Calculate elapsed time since playedAt
    final now = DateTime.now().toUtc();
    final elapsed = now.difference(playedAt).inMilliseconds;

    // Real-time position = last known position + elapsed time
    final calculatedPosition = currentPositionMs + elapsed;

    // Don't exceed song duration
    return calculatedPosition.clamp(0, durationMs);
  }

  // ✅ NEW: Real-time progress percentage
  double get realtimeProgressPercentage {
    if (durationMs <= 0) return 0.0;
    return (realtimePositionMs / durationMs).clamp(0.0, 1.0);
  }

  // ✅ NEW: Real-time formatted duration
  String get realtimeFormattedDuration {
    final position = realtimePositionMs;
    final minutes = (position / 60000).floor();
    final seconds = ((position % 60000) / 1000).floor();
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  // Helper getter for progress percentage
  double get progressPercentage {
    if (durationMs <= 0) return 0.0;
    return (currentPositionMs / durationMs).clamp(0.0, 1.0);
  }

  // Helper getter for formatted duration
  String get formattedDuration {
    final minutes = (currentPositionMs / 60000).floor();
    final seconds = ((currentPositionMs % 60000) / 1000).floor();
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}

class PlaylistUpdate {
  final String type;
  final String playlistId;
  final dynamic data;
  final DateTime timestamp;

  PlaylistUpdate({
    required this.type,
    required this.playlistId,
    required this.data,
    required this.timestamp,
  });

  factory PlaylistUpdate.fromPayload(PostgresChangePayload payload) {
    // Convert enum to string properly
    String eventTypeString;
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        eventTypeString = 'insert';
        break;
      case PostgresChangeEvent.update:
        eventTypeString = 'update';
        break;
      case PostgresChangeEvent.delete:
        eventTypeString = 'delete';
        break;
      default:
        eventTypeString = 'all';
    }

    return PlaylistUpdate(
      type: eventTypeString,
      playlistId: payload.newRecord['playlist_id'] as String,
      data: payload.newRecord,
      timestamp: DateTime.now(),
    );
  }
}

// Providers
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final connectivityProvider = Provider<Connectivity>((ref) {
  return Connectivity();
});

final accessCodeServiceProvider = Provider<AccessCodeService>((ref) {
  return AccessCodeService(ref.watch(supabaseClientProvider));
});

final listeningActivityServiceProvider = Provider<ListeningActivityService>((
  ref,
) {
  return ListeningActivityService(
    ref.watch(supabaseClientProvider),
    ref.watch(connectivityProvider),
  );
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService(
    ref.watch(supabaseClientProvider),
    ref.watch(connectivityProvider),
  );
});

// Fixed provider - now returns Stream<List<ListeningActivity>>
final followingActivityProvider = StreamProvider<List<ListeningActivity>>((
  ref,
) async* {
  final realtimeService = ref.watch(realtimeServiceProvider);
  final listeningService = ref.watch(listeningActivityServiceProvider);
  final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;

  if (userId == null) {
    yield [];
    return;
  }

  // Get initial activities
  final initialActivities = await listeningService.getFollowingActivities(
    userId,
  );
  yield initialActivities;

  // Listen for real-time updates and refresh the list
  await for (final _ in realtimeService.subscribeToFollowingActivity()) {
    // When a new activity comes in, fetch the updated list
    final updatedActivities = await listeningService.getFollowingActivities(
      userId,
    );
    yield updatedActivities;
  }
});
