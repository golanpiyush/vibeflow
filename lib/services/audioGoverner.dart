import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:shared_preferences/shared_preferences.dart';

/// The Audio Governor - Your audio player's inner thoughts with 24hr persistence
class AudioGovernor {
  static AudioGovernor? _instance;

  // Stream controller for thoughts
  final _thoughtStreamController = StreamController<AudioThought>.broadcast();

  // Persistent thought history (cleared after 24 hours)
  final List<AudioThought> _thoughtHistory = [];

  // Current state tracking
  String? _currentSong;
  String? _currentArtist;
  Duration _currentPosition = Duration.zero;
  int _queueSize = 0;
  LoopMode _loopMode = LoopMode.off;
  bool _isShuffleOn = false;
  ProcessingState _processingState = ProcessingState.idle;
  bool _wasPlaying = false;

  // Persistence
  static const String _storageKey = 'audio_governor_thoughts';
  static const String _lastCleanupKey = 'audio_governor_last_cleanup';
  Timer? _cleanupTimer;

  AudioGovernor._() {
    _loadPersistedThoughts();
    _startCleanupTimer();
  }

  static AudioGovernor get instance {
    _instance ??= AudioGovernor._();
    return _instance!;
  }

  /// Stream of audio player thoughts
  Stream<AudioThought> get thoughtStream => _thoughtStreamController.stream;

  /// Get all thoughts (for UI)
  List<AudioThought> get allThoughts => List.unmodifiable(_thoughtHistory);

  /// Current thought (for UI display)
  AudioThought? get currentThought =>
      _thoughtHistory.isNotEmpty ? _thoughtHistory.first : null;

  /// Get thought count
  int get thoughtCount => _thoughtHistory.length;

  // ==================== PERSISTENCE ====================

  Future<void> _loadPersistedThoughts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final thoughtsJson = prefs.getString(_storageKey);

      if (thoughtsJson != null) {
        final List<dynamic> decoded = jsonDecode(thoughtsJson);
        _thoughtHistory.clear();
        _thoughtHistory.addAll(
          decoded.map((json) => AudioThought.fromJson(json)).toList(),
        );

        // Clean up old thoughts immediately on load
        await _cleanupOldThoughts();

        print(
          '💾 [AudioGovernor] Loaded ${_thoughtHistory.length} persisted thoughts',
        );
      }
    } catch (e) {
      print('❌ [AudioGovernor] Error loading thoughts: $e');
    }
  }

  Future<void> _saveThoughts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final thoughtsJson = jsonEncode(
        _thoughtHistory.map((t) => t.toJson()).toList(),
      );
      await prefs.setString(_storageKey, thoughtsJson);
    } catch (e) {
      print('❌ [AudioGovernor] Error saving thoughts: $e');
    }
  }

  Future<void> _cleanupOldThoughts() async {
    final now = DateTime.now();
    final cutoffTime = now.subtract(const Duration(hours: 24));

    final originalCount = _thoughtHistory.length;
    _thoughtHistory.removeWhere(
      (thought) => thought.timestamp.isBefore(cutoffTime),
    );

    final removedCount = originalCount - _thoughtHistory.length;
    if (removedCount > 0) {
      print(
        '🧹 [AudioGovernor] Cleaned up $removedCount thoughts older than 24 hours',
      );
      await _saveThoughts();

      // Update last cleanup time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastCleanupKey, now.toIso8601String());
    }
  }

  void _startCleanupTimer() {
    // Run cleanup every hour
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupOldThoughts();
    });
  }

  /// Manually clear all thoughts
  Future<void> clearAllThoughts() async {
    _thoughtHistory.clear();
    await _saveThoughts();
    _thoughtStreamController.add(
      AudioThought(
        type: 'system',
        message: 'Memory cleared! Starting fresh...',
        timestamp: DateTime.now(),
        context: {},
      ),
    );
    print('🧹 [AudioGovernor] All thoughts manually cleared');
  }

  // ==================== THOUGHT GENERATION ====================

  void _think(String type, Map<String, dynamic> context) {
    final thought = AudioThought(
      type: type,
      message: _generateMessage(type, context),
      timestamp: DateTime.now(),
      context: context,
    );

    // Add to beginning of history (newest first)
    _thoughtHistory.insert(0, thought);
    _thoughtStreamController.add(thought);

    // Save to persistent storage
    _saveThoughts();

    // Print for debugging
    if (kDebugMode) {
      print('🧠 [AudioGovernor] ${thought.message}');
    }
  }

  String _generateMessage(String type, Map<String, dynamic> ctx) {
    switch (type) {
      // ==================== PLAYBACK STATES ====================
      case 'starting_fresh':
        return "Ooh, they want to hear ${ctx['song']}! Let me grab that stream real quick... should be ready in like half a second";

      case 'already_playing':
        return "Wait... isn't this already playing? I mean, I'm literally streaming it right now. Maybe they just double-tapped?";

      case 'resuming':
        final timestamp = _formatDuration(ctx['position'] as Duration?);
        return "Oh hey, we're back! Cool, let me pick up right where we were... ah yes, $timestamp, I remember this part";

      case 'song_completed':
        return "Aaaaand that's a wrap on ${ctx['song']}! Man, that was good. Alright, what's next on the list?";

      case 'buffering':
        return "Ugh, gimme a sec... the internet is being super slow right now. Almost there... almost...";

      case 'loading_url':
        return "Okay so I need to talk to YouTube's servers to get this song... usually takes about 500ms unless they're being weird today";

      case 'url_expired':
        return "Oh crap, the link died. No worries though, happens all the time. Let me just grab a fresh one... nobody will even notice";

      case 'auto_playing_next':
        final mode = ctx['loop_mode'] ?? 'off';
        final action = mode == 'all'
            ? 'loop back to the start'
            : 'play the next track';
        return "That song just ended and loop mode is $mode, so I guess we're going to $action. Here we go!";

      case 'paused_mid_song':
        final timestamp = _formatDuration(ctx['position'] as Duration?);
        return "They hit pause at $timestamp. Guess they need a break? I'll just chill here until they're ready to continue";

      case 'stopped_completely':
        return "Welp, that's it for today I guess. Cleaning up all my stuff... see ya next time! 👋";

      // ==================== USER ACTIONS ====================
      case 'skip_forward':
        return "SKIP! Okay okay, I get it, not feeling this one. Moving to the next track... hope this one's better for ya";

      case 'skip_backward':
        final position = ctx['position'] as Duration?;
        if (position != null && position.inSeconds > 3) {
          return "Going backwards? Alright, lemme check... we're at ${position.inSeconds}s, so I'll just restart this one";
        }
        return "Going to the previous track! They really want to hear that one again";

      case 'seek_action':
        final timestamp = _formatDuration(ctx['position'] as Duration?);
        return "Whoa, they just jumped to $timestamp! Someone knows exactly where they want to be in this song";

      case 'fast_forward':
        return "10 seconds forward! Either they're trying to skip an intro or they REALLY want to get to the chorus";

      case 'rewind':
        return "10 seconds back! Did they miss something? Or maybe that part was just too fire and they gotta hear it again 🔥";

      case 'volume_change':
        final volume = ctx['volume'] ?? 100;
        return "Volume's now at $volume%... nice, finding that sweet spot. Not too loud, not too quiet";

      case 'queue_addition':
        final count = ctx['queue_count'] ?? 0;
        return "Ooh they're adding ${ctx['song']} to the queue! Nice choice. That makes $count songs total now";

      case 'queue_removal':
        final count = ctx['queue_count'] ?? 0;
        return "And ${ctx['song']} is OUT of the queue. Damn, what did that song do to deserve this? Down to $count songs";

      // ==================== MODE CHANGES ====================
      case 'loop_mode_change':
        final mode = ctx['loop_mode'];
        String action;
        if (mode == 'off')
          action = "play through once and stop";
        else if (mode == 'one')
          action = "repeat the same song forever";
        else
          action = "loop the whole queue";
        return "Loop mode just changed to $mode! So now when songs end, I'll $action. Got it, changing strategy";

      case 'shuffle_enabled':
        return "SHUFFLE TIME! Okay let me mix this all up... making it random and chaotic, just how they like it";

      case 'shuffle_disabled':
        return "Back to normal order. No more chaos, we're going sequential again. Honestly kinda relaxing";

      case 'radio_mode_start':
        return "Radio mode activated! Based on ${ctx['song']}, let me find 25 similar bangers... this is gonna be a vibe";

      case 'radio_queue_empty':
        return "Uhh... we ran out of radio songs. Should I fetch more? Or just... stop? Someone tell me what to do";

      case 'repeat_one_active':
        return "Repeat ONE is on, which means I'm gonna play this EXACT song over and over until they stop me. Hope they really like it!";

      // ==================== NETWORK & TECHNICAL ====================
      case 'connection_lost':
        return "OH NO the internet just died! I can't stream anything without connection... pausing until we're back online";

      case 'connection_restored':
        return "Internet's back baby! So uh... were we playing something before? Should I start again?";

      case 'error_403_recovery':
        return "Bruh, YouTube just blocked my URL (403 error). Typical. Let me quietly grab a new one in the background...";

      case 'cache_hit':
        final age = ctx['cache_age'] ?? 0;
        return "YOOO this URL is already in my cache from ${age}min ago! No need to ask YouTube. Instant playback, let's GO ⚡";

      case 'cache_miss':
        return "This URL isn't cached... which means I gotta ask YouTube for it. Shouldn't take long though";

      case 'url_refresh_success':
        return "Got the new URL! Switching to it seamlessly... user won't even know I had to refresh it 😎";

      // ==================== DEVICE EVENTS ====================
      case 'headphones_unplugged':
        return "YO HEADPHONES JUST GOT YANKED OUT! Auto-pausing immediately because we do NOT want this blasting on speakers";

      case 'headphones_connected':
        final willResume = ctx['will_resume'] ?? false;
        return willResume
            ? "Headphones just connected! They were listening before, so I'll auto-resume in 500ms"
            : "Headphones connected! Ready to play when they are";

      case 'bluetooth_connected':
        return "Bluetooth device connected! Nice. If they were listening before, I can auto-resume now";

      case 'audio_interruption':
        final type = ctx['interruption_type'] ?? 'unknown';
        return type == 'duck'
            ? "Something needs my attention... lowering volume to 30% real quick"
            : "Something interrupted me... probably a call or alarm. Pausing for now";

      case 'interruption_ended':
        final willResume = ctx['will_resume'] ?? false;
        return willResume
            ? "Interruption's over! Auto-resume is ON, so I'll start playing again"
            : "Interruption's over, but auto-resume is OFF. They'll have to hit play manually";

      case 'background_mode':
        return "App just went to the background but I'm still here, still playing, still vibing 🎵 Background mode activated";

      default:
        return "Something's happening... not sure what though 🤔";
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // ==================== PUBLIC API - Called by BackgroundAudioHandler ====================

  void onPlaySong(String songName, String artist) {
    _currentSong = songName;
    _currentArtist = artist;

    if (_processingState == ProcessingState.ready && _wasPlaying) {
      _think('already_playing', {'song': songName, 'artist': artist});
    } else {
      _think('starting_fresh', {'song': songName, 'artist': artist});
    }
  }

  void onResume(Duration position) {
    _currentPosition = position;
    _think('resuming', {'position': position, 'song': _currentSong});
  }

  void onSongCompleted(String songName) {
    _think('song_completed', {'song': songName});
  }

  void onBuffering() {
    _think('buffering', {});
  }

  void onLoadingUrl(String songName) {
    _think('loading_url', {'song': songName});
  }

  void onUrlExpired() {
    _think('url_expired', {});
  }

  void onAutoPlayNext(LoopMode loopMode) {
    _think('auto_playing_next', {
      'loop_mode': loopMode.toString().split('.').last,
    });
  }

  void onPause(Duration position) {
    _currentPosition = position;
    _think('paused_mid_song', {'position': position});
  }

  void onStop() {
    _think('stopped_completely', {});
  }

  void onSkipForward() {
    _think('skip_forward', {});
  }

  void onSkipBackward(Duration position) {
    _think('skip_backward', {'position': position});
  }

  void onSeek(Duration position) {
    _currentPosition = position;
    _think('seek_action', {'position': position});
  }

  void onFastForward() {
    _think('fast_forward', {});
  }

  void onRewind() {
    _think('rewind', {});
  }

  void onVolumeChange(double volume) {
    _think('volume_change', {'volume': (volume * 100).round()});
  }

  void onQueueAdd(String songName, int queueCount) {
    _queueSize = queueCount;
    _think('queue_addition', {'song': songName, 'queue_count': queueCount});
  }

  void onQueueRemove(String songName, int queueCount) {
    _queueSize = queueCount;
    _think('queue_removal', {'song': songName, 'queue_count': queueCount});
  }

  void onLoopModeChange(LoopMode mode) {
    _loopMode = mode;
    final modeStr = mode.toString().split('.').last;
    _think('loop_mode_change', {'loop_mode': modeStr});
  }

  void onShuffleEnabled() {
    _isShuffleOn = true;
    _think('shuffle_enabled', {});
  }

  void onShuffleDisabled() {
    _isShuffleOn = false;
    _think('shuffle_disabled', {});
  }

  void onRadioStart(String basedOnSong) {
    _think('radio_mode_start', {'song': basedOnSong});
  }

  void onRadioQueueEmpty() {
    _think('radio_queue_empty', {});
  }

  void onRepeatOneActive() {
    _think('repeat_one_active', {});
  }

  void onConnectionLost() {
    _think('connection_lost', {});
  }

  void onConnectionRestored() {
    _think('connection_restored', {});
  }

  void on403Error() {
    _think('error_403_recovery', {});
  }

  void onCacheHit(int ageMinutes) {
    _think('cache_hit', {'cache_age': ageMinutes});
  }

  void onCacheMiss() {
    _think('cache_miss', {});
  }

  void onUrlRefreshSuccess() {
    _think('url_refresh_success', {});
  }

  void onHeadphonesUnplugged() {
    _wasPlaying = true;
    _think('headphones_unplugged', {});
  }

  void onHeadphonesConnected(bool willResume) {
    _think('headphones_connected', {'will_resume': willResume});
  }

  void onBluetoothConnected() {
    _think('bluetooth_connected', {});
  }

  void onAudioInterruption(String type) {
    _think('audio_interruption', {'interruption_type': type});
  }

  void onInterruptionEnded(bool willResume) {
    _think('interruption_ended', {'will_resume': willResume});
  }

  void onBackgroundMode() {
    _think('background_mode', {});
  }

  void updateProcessingState(ProcessingState state) {
    _processingState = state;
  }

  void updatePlayingState(bool playing) {
    _wasPlaying = playing;
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _thoughtStreamController.close();
  }
}

/// Data class representing a single thought
class AudioThought {
  final String type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic> context;

  AudioThought({
    required this.type,
    required this.message,
    required this.timestamp,
    required this.context,
  });

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get formattedTime {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  // JSON serialization
  Map<String, dynamic> toJson() => {
    'type': type,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'context': _serializeContext(context),
  };

  static Map<String, dynamic> _serializeContext(Map<String, dynamic> context) {
    final serialized = <String, dynamic>{};
    context.forEach((key, value) {
      if (value is Duration) {
        serialized[key] = {
          '__type': 'Duration',
          'milliseconds': value.inMilliseconds,
        };
      } else {
        serialized[key] = value;
      }
    });
    return serialized;
  }

  static Map<String, dynamic> _deserializeContext(
    Map<String, dynamic> context,
  ) {
    final deserialized = <String, dynamic>{};
    context.forEach((key, value) {
      if (value is Map && value['__type'] == 'Duration') {
        deserialized[key] = Duration(
          milliseconds: value['milliseconds'] as int,
        );
      } else {
        deserialized[key] = value;
      }
    });
    return deserialized;
  }

  factory AudioThought.fromJson(Map<String, dynamic> json) => AudioThought(
    type: json['type'] as String,
    message: json['message'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    context: _deserializeContext(
      Map<String, dynamic>.from(json['context'] as Map),
    ),
  );
}
