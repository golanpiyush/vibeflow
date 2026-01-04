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
  final DateTime playedAt;
  final DateTime createdAt;

  ListeningActivity({
    required this.id,
    required this.userId,
    required this.songId,
    required this.sourceVideoId,
    required this.songTitle,
    required this.songArtists,
    this.songThumbnail,
    required this.durationMs,
    required this.playedAt,
    required this.createdAt,
  });

  factory ListeningActivity.fromMap(Map<String, dynamic> map) {
    return ListeningActivity(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      songId: map['song_id'] as String,
      sourceVideoId: map['source_video_id'] as String? ?? '',
      songTitle: map['song_title'] as String,
      songArtists: List<String>.from(map['song_artists'] as List),
      songThumbnail: map['song_thumbnail'] as String?,
      durationMs: map['duration_ms'] as int,
      playedAt: DateTime.parse(map['played_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
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
    };
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
