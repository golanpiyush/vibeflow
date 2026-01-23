import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vibeflow/constants/ai_models_config.dart';
import 'package:vibeflow/services/sync_services/listening_profiling.dart';
import 'package:vibeflow/services/sync_services/musicIntelligence.dart';

/// UI-facing service for AI-generated daily playlists
/// Provides simple methods for UI to interact with the intelligence system
class DailyPlaylistService {
  static DailyPlaylistService? _instance;

  final _statusController = StreamController<PlaylistServiceStatus>.broadcast();

  DailyPlaylistService._();

  static DailyPlaylistService get instance {
    _instance ??= DailyPlaylistService._();
    return _instance!;
  }

  /// Stream of service status updates
  Stream<PlaylistServiceStatus> get statusStream => _statusController.stream;

  /// Check if user is eligible for AI playlists
  /// Returns eligibility status and requirements
  Future<EligibilityStatus> checkEligibility() async {
    try {
      final profile = await ListeningProfileBuilder.instance.buildProfile();

      if (profile == null) {
        return EligibilityStatus(
          isEligible: false,
          reason: 'No listening data available',
          uniqueSongs: 0,
          listeningDays: 0,
          requiresUniqueSongs: GatingRules.minUniqueSongs,
          requiresListeningDays: GatingRules.minListeningDays,
        );
      }

      final isEligible =
          profile.uniqueSongCount >= GatingRules.minUniqueSongs &&
          profile.distinctListeningDays >= GatingRules.minListeningDays;

      return EligibilityStatus(
        isEligible: isEligible,
        reason: isEligible
            ? 'Eligible for AI playlists'
            : 'Need more listening history',
        uniqueSongs: profile.uniqueSongCount,
        listeningDays: profile.distinctListeningDays,
        requiresUniqueSongs: GatingRules.minUniqueSongs,
        requiresListeningDays: GatingRules.minListeningDays,
      );
    } catch (e) {
      print('❌ [PlaylistService] Error checking eligibility: $e');
      return EligibilityStatus(
        isEligible: false,
        reason: 'Error checking eligibility',
        uniqueSongs: 0,
        listeningDays: 0,
        requiresUniqueSongs: GatingRules.minUniqueSongs,
        requiresListeningDays: GatingRules.minListeningDays,
      );
    }
  }

  /// Generate today's playlist
  /// Returns null if generation fails or user is not eligible
  Future<DailyPlaylist?> generatePlaylist() async {
    _statusController.add(PlaylistServiceStatus.checking);

    try {
      // Build profile
      _statusController.add(PlaylistServiceStatus.buildingProfile);
      final profile = await ListeningProfileBuilder.instance.buildProfile();

      if (profile == null) {
        _statusController.add(
          PlaylistServiceStatus.error('No listening data available'),
        );
        return null;
      }

      // Generate playlist
      _statusController.add(PlaylistServiceStatus.generating);
      final orchestrator = MusicIntelligenceOrchestrator.instance;
      final result = await orchestrator.generateDailyPlaylist(profile: profile);

      if (result == null || !result.success) {
        final errorMsg = result?.errorMessage ?? 'Unknown error';
        _statusController.add(PlaylistServiceStatus.error(errorMsg));
        return null;
      }

      // Success
      final playlist = DailyPlaylist(
        songs: result.songs
            .map(
              (s) => PlaylistSong(
                title: s.title,
                artist: s.artist,
                album: s.album,
              ),
            )
            .toList(),
        generatedAt: DateTime.now(),
        profileSnapshot: ProfileSnapshot(
          uniqueSongs: profile.uniqueSongCount,
          listeningDays: profile.distinctListeningDays,
          topGenres: profile.inferredGenres,
        ),
      );

      _statusController.add(PlaylistServiceStatus.success);
      return playlist;
    } catch (e) {
      print('❌ [PlaylistService] Generation failed: $e');
      _statusController.add(PlaylistServiceStatus.error(e.toString()));
      return null;
    }
  }

  void dispose() {
    _statusController.close();
  }
}

/// Playlist service status
class PlaylistServiceStatus {
  final String state;
  final String? message;

  PlaylistServiceStatus._(this.state, [this.message]);

  static final checking = PlaylistServiceStatus._('checking');
  static final buildingProfile = PlaylistServiceStatus._('building_profile');
  static final generating = PlaylistServiceStatus._('generating');
  static final success = PlaylistServiceStatus._('success');

  static PlaylistServiceStatus error(String message) {
    return PlaylistServiceStatus._('error', message);
  }

  bool get isError => state == 'error';
  bool get isSuccess => state == 'success';
  bool get isLoading => !isError && !isSuccess;
}

/// Eligibility status
class EligibilityStatus {
  final bool isEligible;
  final String reason;
  final int uniqueSongs;
  final int listeningDays;
  final int requiresUniqueSongs;
  final int requiresListeningDays;

  EligibilityStatus({
    required this.isEligible,
    required this.reason,
    required this.uniqueSongs,
    required this.listeningDays,
    required this.requiresUniqueSongs,
    required this.requiresListeningDays,
  });

  int get songsRemaining => (requiresUniqueSongs - uniqueSongs).clamp(0, 999);
  int get daysRemaining =>
      (requiresListeningDays - listeningDays).clamp(0, 999);

  double get progressPercent {
    final songProgress = (uniqueSongs / requiresUniqueSongs).clamp(0.0, 1.0);
    final dayProgress = (listeningDays / requiresListeningDays).clamp(0.0, 1.0);
    return ((songProgress + dayProgress) / 2 * 100);
  }
}

/// Generated daily playlist
class DailyPlaylist {
  final List<PlaylistSong> songs;
  final DateTime generatedAt;
  final ProfileSnapshot profileSnapshot;

  DailyPlaylist({
    required this.songs,
    required this.generatedAt,
    required this.profileSnapshot,
  });

  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final genDate = DateTime(
      generatedAt.year,
      generatedAt.month,
      generatedAt.day,
    );

    if (genDate == today) {
      return "Today's Playlist";
    } else if (genDate == today.subtract(const Duration(days: 1))) {
      return "Yesterday's Playlist";
    } else {
      return '${generatedAt.month}/${generatedAt.day}/${generatedAt.year}';
    }
  }
}

class PlaylistSong {
  final String title;
  final String artist;
  final String? album;

  PlaylistSong({required this.title, required this.artist, this.album});

  String get displayText {
    if (album != null && album!.isNotEmpty) {
      return '$title – $artist ($album)';
    }
    return '$title – $artist';
  }
}

class ProfileSnapshot {
  final int uniqueSongs;
  final int listeningDays;
  final List<String> topGenres;

  ProfileSnapshot({
    required this.uniqueSongs,
    required this.listeningDays,
    required this.topGenres,
  });
}
