// FIXED REAL-TIME LISTENING TRACKING SYSTEM
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

class RealtimeListeningTracker {
  Timer? _updateTimer;
  DateTime? _currentSongStartTime;
  String? _currentVideoId;
  QuickPick? _currentSong;
  String? _currentActivityId;
  bool _isPlaying = false;

  // Store reference to audio player
  AudioPlayer? _audioPlayer;

  final SupabaseClient _supabase;

  RealtimeListeningTracker() : _supabase = Supabase.instance.client;

  // Set the audio player reference
  void setAudioPlayer(AudioPlayer player) {
    _audioPlayer = player;
    print('✅ [REALTIME] Audio player reference set');
  }

  // 🎯 START TRACKING A NEW SONG
  Future<void> startTracking(QuickPick song) async {
    print('🎵 [REALTIME] ========== START TRACKING ==========');
    print('   Song: ${song.title}');
    print('   Artists: ${song.artists}');
    print('   VideoId: ${song.videoId}');
    print('   Duration: ${song.duration}');

    // Check if user is authenticated
    final user = _supabase.auth.currentUser;
    if (user == null) {
      print('❌ [REALTIME] System will not track - not an authenticated user!');
      return;
    }
    print('✅ [REALTIME] User authenticated: ${user.id}');

    // Check if user has access code
    final hasAccessCode = await _checkUserAccessCode(user.id);
    if (!hasAccessCode) {
      print(
        '❌ [REALTIME] System will not track - user does not seem to have access codes!',
      );
      return;
    }
    print('✅ [REALTIME] User has access code');

    // Check if user has listening activity enabled
    final showListeningActivity = await _checkListeningActivitySetting(user.id);
    if (!showListeningActivity) {
      print(
        '❌ [REALTIME] Cannot track - user has disabled listening activity!',
      );
      return;
    }
    print('✅ [REALTIME] User has listening activity enabled');

    // 🔧 FIX 1: Stop previous tracking with longer delay to ensure cleanup
    await stopTracking();
    print('✅ [REALTIME] Previous tracking stopped');

    // 🔧 FIX 2: Longer delay to ensure DB cleanup completed
    await Future.delayed(const Duration(milliseconds: 500));

    // Set current song
    _currentSong = song;
    _currentVideoId = song.videoId;
    _currentSongStartTime = DateTime.now().toUtc();
    _isPlaying = true;

    print('📝 [REALTIME] State updated, creating activity...');

    // Create activity IMMEDIATELY
    final activityId = await _createActivityNow(song);
    _currentActivityId = activityId;

    if (activityId != null) {
      print('✅ [REALTIME] ✨ SUCCESS! Activity ID: $activityId');
      print('🔄 [REALTIME] Starting real-time updates...');
      // Start real-time updates every 10 seconds
      _startRealtimeUpdates(song);
    } else {
      print('❌ [REALTIME] 🚨 FAILED to create activity!');
    }
    print('🎵 [REALTIME] ========== END START TRACKING ==========');
  }

  // ⏰ AUTO-CLEANUP: Mark old activities as stopped
  Future<void> cleanupStaleActivities() async {
    try {
      final cutoffTime = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );

      await _supabase
          .from('listening_activity')
          .update({'is_currently_playing': false, 'current_position_ms': 0})
          .eq('is_currently_playing', true)
          .lt('played_at', cutoffTime.toIso8601String());

      print('🧹 [CLEANUP] Cleaned up stale activities older than 5 minutes');
    } catch (e) {
      print('❌ [CLEANUP] Error cleaning stale activities: $e');
    }
  }

  // Update stopTracking to be more aggressive:
  Future<void> stopTracking() async {
    print('🛑 [REALTIME] STOPPING TRACKING');

    // Cancel update timer FIRST
    _updateTimer?.cancel();
    _updateTimer = null;

    // Mark ALL user's activities as stopped (not just current one)
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        await _supabase
            .from('listening_activity')
            .update({
              'is_currently_playing': false,
              'played_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', user.id)
            .eq('is_currently_playing', true);

        print('✅ [REALTIME] Marked all user activities as stopped');
      } catch (e) {
        print('❌ [REALTIME] Error stopping all activities: $e');
      }
    }

    // Reset state
    _currentVideoId = null;
    _currentSong = null;
    _currentActivityId = null;
    _isPlaying = false;
    _currentSongStartTime = null;
  }

  // ⏸️ PAUSE TRACKING (when user pauses)
  Future<void> pauseTracking() async {
    _isPlaying = false;
    print('⏸️ [REALTIME] PAUSED tracking');

    // Update last position
    if (_currentSong != null && _currentActivityId != null) {
      await _updateCurrentPosition();
    }
  }

  // ▶️ RESUME TRACKING (when user resumes)
  void resumeTracking() {
    _isPlaying = true;
    print('▶️ [REALTIME] RESUMED tracking');
  }

  // 🔄 UPDATE TO NEW SONG (skip, next, etc.)
  void updateToNewSong(QuickPick newSong) {
    print('🔄 [REALTIME] SWITCHING to new song: ${newSong.title}');

    // Stop old tracking
    stopTracking();

    // 🔧 FIX 4: Longer delay before starting new tracking
    Future.delayed(const Duration(milliseconds: 800), () {
      startTracking(newSong);
    });
  }

  // ✨ CREATE ACTIVITY IMMEDIATELY
  Future<String?> _createActivityNow(QuickPick song) async {
    print('💾 [CREATE] ========== CREATING ACTIVITY ==========');

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        print('❌ [CREATE] No authenticated user');
        return null;
      }
      print('✅ [CREATE] User ID: ${user.id}');

      // 🔧 FIX 5: Get ACTUAL duration from audio player if available
      int totalDurationMs;

      if (_audioPlayer?.duration != null) {
        totalDurationMs = _audioPlayer!.duration!.inMilliseconds;
        print('📏 [CREATE] Using player duration: ${totalDurationMs}ms');
      } else if (song.duration != null) {
        totalDurationMs = _parseDurationToMs(song.duration!);
        print(
          '📏 [CREATE] Using song duration: ${totalDurationMs}ms (${song.duration})',
        );
      } else {
        totalDurationMs = 180000; // Fallback to 3 minutes
        print('⚠️ [CREATE] Using fallback duration: ${totalDurationMs}ms');
      }

      final songId = ListeningActivityService.generateSongId(
        song.title,
        song.artists.split(',').map((e) => e.trim()).toList(),
      );
      print('🆔 [CREATE] Generated song_id: $songId');

      // Delete ANY old activity for this user
      print('🧹 [CREATE] Deleting old activities...');
      try {
        final deleteResult = await _supabase
            .from('listening_activity')
            .delete()
            .eq('user_id', user.id)
            .select();

        print('✅ [CREATE] Deleted ${deleteResult?.length ?? 0} old activities');
      } catch (e) {
        print('⚠️ [CREATE] Delete error (continuing): $e');
      }

      // Small delay after delete
      await Future.delayed(const Duration(milliseconds: 150));

      // Create new activity
      final nowUtc = DateTime.now().toUtc();
      final activityData = {
        'user_id': user.id,
        'song_id': songId,
        'source_video_id': song.videoId,
        'song_title': song.title,
        'song_artists': song.artists.split(',').map((e) => e.trim()).toList(),
        'song_thumbnail': song.thumbnail,
        'duration_ms': totalDurationMs, // 🔧 Now uses actual duration
        'current_position_ms': 0,
        'is_currently_playing': true,
        'played_at': nowUtc.toIso8601String(),
      };

      print('📤 [CREATE] Activity data:');
      print('   user_id: ${activityData['user_id']}');
      print('   song_id: ${activityData['song_id']}');
      print('   song_title: ${activityData['song_title']}');
      print('   song_artists: ${activityData['song_artists']}');
      print('   duration_ms: ${activityData['duration_ms']}');
      print('   current_position_ms: ${activityData['current_position_ms']}');
      print('   is_currently_playing: ${activityData['is_currently_playing']}');
      print('   played_at: ${activityData['played_at']}');

      print('🚀 [CREATE] Executing INSERT...');
      final response = await _supabase
          .from('listening_activity')
          .insert(activityData)
          .select('id')
          .single();

      print('📥 [CREATE] Response received: $response');

      if (response != null && response['id'] != null) {
        final activityId = response['id'] as String;
        print('✅ [CREATE] ✨ SUCCESS! Activity created: $activityId');
        print('💾 [CREATE] ========== END CREATING ACTIVITY ==========');
        return activityId;
      } else {
        print('❌ [CREATE] Response was null or missing ID');
        print('💾 [CREATE] ========== END CREATING ACTIVITY ==========');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ [CREATE] ========== ERROR ==========');
      print('   Error: $e');
      print('   Type: ${e.runtimeType}');

      if (e is PostgrestException) {
        print('   PostgrestException Details:');
        print('   - Code: ${e.code}');
        print('   - Message: ${e.message}');
        print('   - Details: ${e.details}');
        print('   - Hint: ${e.hint}');
      }

      print('   Stack trace:');
      print('   $stackTrace');
      print('💾 [CREATE] ========== END CREATING ACTIVITY ==========');
      return null;
    }
  }

  // 🔄 REAL-TIME UPDATES EVERY 10 SECONDS
  void _startRealtimeUpdates(QuickPick song) {
    _updateTimer?.cancel();

    _updateTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isPlaying || _currentVideoId != song.videoId) {
        print('⚠️ [REALTIME] Song changed or paused, stopping updates');
        timer.cancel();
        return;
      }

      try {
        await _updateCurrentPosition();
      } catch (e) {
        print('❌ [REALTIME] Update error: $e');
      }
    });

    print('⏱️ [REALTIME] Started real-time updates (every 10s)');
  }

  // 📍 UPDATE CURRENT POSITION
  Future<void> _updateCurrentPosition() async {
    if (_currentActivityId == null) return;

    try {
      // Get ACTUAL position from audio player
      int currentPositionMs;

      if (_audioPlayer != null) {
        // Use actual player position
        currentPositionMs = _audioPlayer!.position.inMilliseconds;
        print(
          '📍 [REALTIME] Using actual player position: ${currentPositionMs}ms',
        );
      } else {
        // Fallback: calculate from start time (old behavior)
        if (_currentSongStartTime == null) return;
        currentPositionMs = DateTime.now()
            .toUtc()
            .difference(_currentSongStartTime!)
            .inMilliseconds;
        print(
          '⚠️ [REALTIME] No player reference, using calculated position: ${currentPositionMs}ms',
        );
      }

      // Update with ACTUAL current position AND timestamp
      await _supabase
          .from('listening_activity')
          .update({
            'current_position_ms': currentPositionMs,
            'is_currently_playing': _isPlaying,
            'played_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _currentActivityId!);

      print(
        '📍 [REALTIME] Updated position: ${currentPositionMs}ms (playing: $_isPlaying)',
      );
    } catch (e) {
      print('❌ [REALTIME] Error updating position: $e');
    }
  }

  // ✅ MARK ACTIVITY AS COMPLETED
  Future<void> _markAsCompleted() async {
    if (_currentActivityId == null) return;

    try {
      // Get final position before marking complete
      int finalPositionMs = 0;
      if (_audioPlayer != null) {
        finalPositionMs = _audioPlayer!.position.inMilliseconds;
      }

      await _supabase
          .from('listening_activity')
          .update({
            'current_position_ms': finalPositionMs,
            'is_currently_playing': false,
            'played_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _currentActivityId!);

      print(
        '✅ [REALTIME] Marked activity as completed (final pos: ${finalPositionMs}ms)',
      );
    } catch (e) {
      print('❌ [REALTIME] Error marking as completed: $e');
    }
  }

  // Helper: Parse duration string to milliseconds
  int _parseDurationToMs(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      }
    } catch (e) {
      print('⚠️ Error parsing duration: $e');
    }
    return 0;
  }

  // Check if user has access code
  Future<bool> _checkUserAccessCode(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('access_code_used')
          .eq('id', userId)
          .maybeSingle();

      final hasCode = response != null && response['access_code_used'] != null;
      print('🔑 [REALTIME] Access code check for $userId: $hasCode');
      return hasCode;
    } catch (e) {
      print('❌ [REALTIME] Error checking access code: $e');
      return false;
    }
  }

  // Check if user has listening activity enabled
  Future<bool> _checkListeningActivitySetting(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('show_listening_activity')
          .eq('id', userId)
          .maybeSingle();

      final isEnabled =
          response?['show_listening_activity'] ?? true; // Default to true
      print('🎵 [REALTIME] Listening activity setting for $userId: $isEnabled');
      return isEnabled;
    } catch (e) {
      print('❌ [REALTIME] Error checking listening activity setting: $e');
      return true; // Default to true on error
    }
  }
}
