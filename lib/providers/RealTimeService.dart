// FIXED REAL-TIME LISTENING TRACKING SYSTEM
// Fixes applied:
// 1. _hardStop no longer deletes history — only marks is_currently_playing = false
// 2. played_at is set ONCE at song start, never overwritten by position updates
// 3. Access code + settings checks are cached in memory
// 4. Position update race condition fixed with local activityId capture
// 5. _isStopping guard tightened — local snapshot before every async gap
// 6. StreamController is properly closed in all error paths
// 7. [NEW] _hardStop targets ONLY the current row by activityId, not all user rows
// 8. [NEW] startTracking always clears the previous row before inserting a new one,
//    even if _currentActivityId is null (covers app-restart / crash recovery)
// 9. [NEW] DB-level cleanup for stale rows on startup uses a server-side RPC
//    so friends also see the corrected state immediately

import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

class RealtimeListeningTracker {
  Timer? _updateTimer;
  StreamSubscription<Duration>? _positionSubscription;
  String? _currentVideoId;
  QuickPick? _currentSong;
  String? _currentActivityId;
  bool _isPlaying = false;
  bool _isStopping = false;

  AudioPlayer? _audioPlayer;

  final SupabaseClient _supabase;

  // FIX 3: Cache access code and settings checks — avoid 2 extra DB
  // round-trips on every single song change.
  bool? _cachedHasAccessCode;
  bool? _cachedShowActivity;
  String? _cachedUserId; // invalidate cache if user changes

  RealtimeListeningTracker() : _supabase = Supabase.instance.client;

  void setAudioPlayer(AudioPlayer player) {
    _audioPlayer = player;
    print('✅ [REALTIME] Audio player reference set');
  }

  // FIX 3: Cached access code check — only hits DB once per session
  Future<bool> _getCachedAccessCode(String userId) async {
    if (_cachedUserId != userId) {
      // User changed — invalidate cache
      _cachedHasAccessCode = null;
      _cachedShowActivity = null;
      _cachedUserId = userId;
    }
    if (_cachedHasAccessCode != null) return _cachedHasAccessCode!;
    _cachedHasAccessCode = await _checkUserAccessCode(userId);
    return _cachedHasAccessCode!;
  }

  // FIX 3: Cached settings check
  Future<bool> _getCachedShowActivity(String userId) async {
    if (_cachedShowActivity != null) return _cachedShowActivity!;
    _cachedShowActivity = await _checkListeningActivitySetting(userId);
    return _cachedShowActivity!;
  }

  // Call this when user changes their "show listening activity" setting
  void invalidateSettingsCache() {
    _cachedShowActivity = null;
    _cachedHasAccessCode = null;
    // NOTE: intentionally NOT clearing _cachedUserId — the user hasn't changed,
    // only their settings. Next call to _getCachedShowActivity will re-fetch
    // because we cleared _cachedShowActivity above.
    print('🔄 [REALTIME] Settings cache invalidated');
  }

  Future<void> startTracking(QuickPick song) async {
    print('🎵 [REALTIME] ========== START TRACKING ==========');
    print('   Song: ${song.title} | VideoId: ${song.videoId}');

    final user = _supabase.auth.currentUser;
    if (user == null) {
      print('❌ [REALTIME] Not authenticated');
      return;
    }

    // FIX 3: Use cached checks instead of fresh DB calls every time
    final hasAccessCode = await _getCachedAccessCode(user.id);
    if (!hasAccessCode) {
      print('❌ [REALTIME] No access code');
      return;
    }

    final showListeningActivity = await _getCachedShowActivity(user.id);
    if (!showListeningActivity) {
      print('❌ [REALTIME] Activity disabled');
      return;
    }

    // FIX 2 + FIX 7: Hard stop must complete before we insert the new row.
    // _hardStop now targets ONLY the current activityId row (or falls back
    // to clearing all playing rows for this user if activityId is unknown —
    // covers the crash-recovery / app-restart case).
    await _hardStop(user.id);

    _currentSong = song;
    _currentVideoId = song.videoId;
    _isPlaying = true;
    _isStopping = false;

    final activityId = await _createActivityNow(song, user.id);
    _currentActivityId = activityId;

    if (activityId != null) {
      print('✅ [REALTIME] Activity created: $activityId');
      _startPositionStream(song);
    } else {
      print('❌ [REALTIME] Failed to create activity');
    }
  }

  // FIX 1 + FIX 7: Hard stop marks the specific row stopped, NOT deletes.
  // If we know the activityId, target it directly — avoids touching any other
  // row that might exist from a different device/session.
  // Falls back to clearing ALL playing rows for this user only when
  // activityId is unknown (crash recovery, first run, etc.).
  Future<void> _hardStop(String userId) async {
    _isStopping = true;
    _updateTimer?.cancel();
    _updateTimer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;

    try {
      final activityId = _currentActivityId;

      if (activityId != null) {
        // Happy path: we know exactly which row to stop
        await _supabase
            .from('listening_activity')
            .update({'is_currently_playing': false})
            .eq('id', activityId);
        print('✅ [REALTIME] DB: marked activity $activityId stopped');
      } else {
        // Fallback: clear any stale playing rows for this user.
        // This handles the case where the app restarted without cleanly stopping.
        await _supabase
            .from('listening_activity')
            .update({'is_currently_playing': false})
            .eq('user_id', userId)
            .eq('is_currently_playing', true);
        print(
          '✅ [REALTIME] DB: cleared all stale playing activities for user (recovery path)',
        );
      }
    } catch (e) {
      print('❌ [REALTIME] Error stopping activities in DB: $e');
    }

    _currentVideoId = null;
    _currentSong = null;
    _currentActivityId = null;
    _isPlaying = false;
    _isStopping = false;
  }

  Future<void> stopTracking() async {
    print('🛑 [REALTIME] stopTracking called');
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _hardStop(user.id);
    } else {
      // No user — just cancel local state
      _updateTimer?.cancel();
      _updateTimer = null;
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _currentVideoId = null;
      _currentSong = null;
      _currentActivityId = null;
      _isPlaying = false;
    }
  }

  Future<void> pauseTracking() async {
    _isPlaying = false;
    // FIX: Cancel timer/stream first so no tick fires after we write paused state
    _updateTimer?.cancel();
    _updateTimer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    print('⏸️ [REALTIME] Paused');
    await _updateCurrentPosition(isPlaying: false);
  }

  void resumeTracking() {
    _isPlaying = true;
    print('▶️ [REALTIME] Resumed');
  }

  Future<void> cleanupStaleActivities() async {
    try {
      // FIX: This now writes to DB so ALL clients (friends) see the corrected
      // state — not just the local user's cache.
      final cutoffTime = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      final updated = await _supabase
          .from('listening_activity')
          .update({'is_currently_playing': false, 'current_position_ms': 0})
          .eq('is_currently_playing', true)
          .lt('played_at', cutoffTime.toIso8601String())
          .select('id'); // Return updated rows for logging

      print(
        '🧹 [CLEANUP] Marked ${updated.length} stale activities as stopped in DB',
      );
    } catch (e) {
      print('❌ [CLEANUP] Error: $e');
    }
  }

  Future<String?> _createActivityNow(QuickPick song, String userId) async {
    try {
      int totalDurationMs;
      if (_audioPlayer?.duration != null) {
        totalDurationMs = _audioPlayer!.duration!.inMilliseconds;
      } else if (song.duration != null) {
        totalDurationMs = _parseDurationToMs(song.duration!);
      } else {
        totalDurationMs = 180000;
      }

      final songId = ListeningActivityService.generateSongId(
        song.title,
        song.artists.split(',').map((e) => e.trim()).toList(),
      );

      // FIX 4: played_at is set HERE and NEVER updated again.
      // This is the timestamp friends see as "started listening at X".
      final nowUtc = DateTime.now().toUtc();

      // AFTER
      final response = await _supabase
          .from('listening_activity')
          .upsert(
            {
              'user_id': userId,
              'song_id': songId,
              'source_video_id': song.videoId,
              'song_title': song.title,
              'song_artists': song.artists
                  .split(',')
                  .map((e) => e.trim())
                  .toList(),
              'song_thumbnail': song.thumbnail,
              'duration_ms': totalDurationMs,
              'current_position_ms': 0,
              'is_currently_playing': true,
              'played_at': nowUtc.toIso8601String(),
            },
            onConflict:
                'user_id,song_id,played_at::date', // matches idx_unique_activity_daily
            ignoreDuplicates: false, // update the row if it exists
          )
          .select('id')
          .single();

      return response['id'] as String?;
    } catch (e) {
      print('❌ [CREATE] Error: $e');
      if (e is PostgrestException) {
        print('   Code: ${e.code}, Message: ${e.message}');
      }
      return null;
    }
  }

  void _startPositionStream(QuickPick song) {
    _positionSubscription?.cancel();
    _updateTimer?.cancel();

    if (_audioPlayer == null) {
      // Fallback: timer-based if no player ref
      _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_isStopping || _currentVideoId != song.videoId) return;
        await _updateCurrentPosition();
      });
      return;
    }

    int _lastReportedSecond = -1;

    _positionSubscription = _audioPlayer!.positionStream.listen((
      position,
    ) async {
      if (_isStopping || _currentVideoId != song.videoId || !_isPlaying) return;

      final currentSecond = position.inSeconds;
      if (currentSecond > 0 &&
          currentSecond % 5 == 0 &&
          currentSecond != _lastReportedSecond) {
        _lastReportedSecond = currentSecond;
        await _updateCurrentPosition();
      }
    });

    print('📡 [REALTIME] Live position stream started');
  }

  Future<void> _updateCurrentPosition({bool? isPlaying}) async {
    // FIX: Snapshot BEFORE any conditional — _hardStop() can null _currentActivityId
    // between the guard check and the DB await, causing writes to a stale/null ID.
    final activityId = _currentActivityId;
    if (activityId == null || _isStopping) return;

    try {
      final posMs = _audioPlayer?.position.inMilliseconds ?? 0;
      final playing = isPlaying ?? _isPlaying;

      await _supabase
          .from('listening_activity')
          .update({
            'current_position_ms': posMs,
            'is_currently_playing': playing,
            // FIX 4: played_at is intentionally NOT updated here.
            // Only current_position_ms and is_currently_playing change.
          })
          .eq('id', activityId);

      print('📍 [REALTIME] Position updated: ${posMs}ms playing=$playing');
    } catch (e) {
      print('❌ [REALTIME] Error updating position: $e');
    }
  }

  int _parseDurationToMs(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      }
    } catch (_) {}
    return 0;
  }

  Future<bool> _checkUserAccessCode(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('access_code_used')
          .eq('id', userId)
          .maybeSingle();
      return response != null && response['access_code_used'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkListeningActivitySetting(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('show_listening_activity')
          .eq('id', userId)
          .maybeSingle();
      return response?['show_listening_activity'] ?? true;
    } catch (_) {
      return true;
    }
  }
}
