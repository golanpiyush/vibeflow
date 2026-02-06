import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vibeflow/models/song_model.dart';

/// The Audio Governor - Your audio player's inner thoughts with 24hr persistence
/// Now powered by AI for dynamic, varied messages
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
  bool _isInterrupted = false;

  // Persistence
  static const String _storageKey = 'audio_governor_thoughts';
  static const String _lastCleanupKey = 'audio_governor_last_cleanup';
  Timer? _cleanupTimer;

  // AI message generation
  final Random _random = Random();
  final Map<String, List<String>> _messageCache = {};
  String? _apiKey;
  bool _aiEnabled = false;

  AudioGovernor._() {
    _loadPersistedThoughts();
    _startCleanupTimer();
    _initializeAI();
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

  // ==================== AI INITIALIZATION ====================

  Future<void> _initializeAI() async {
    try {
      await dotenv.load(fileName: ".env");
      _apiKey = dotenv.env['OPENROUTER_API_KEY'];
      _aiEnabled = _apiKey != null && _apiKey!.isNotEmpty;

      if (_aiEnabled) {
        print('✅ [AudioGovernor] AI message generation enabled');
      } else {
        print('⚠️ [AudioGovernor] AI disabled - using fallback messages');
      }
    } catch (e) {
      print('⚠️ [AudioGovernor] Could not load AI config: $e');
      _aiEnabled = false;
    }
  }

  // ==================== PERSISTENCE ====================

  void onPlaybackError(String error, String songName) {
    _think('playback_error', {'error': error, 'song': songName});
  }

  void onUrlRefreshAttempt() {
    _think('url_refresh_attempt', {});
  }

  void onUrlRefreshFailed() {
    _think('url_refresh_failed', {});
  }

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

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastCleanupKey, now.toIso8601String());
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupOldThoughts();
    });
  }

  /// Manually clear all thoughts
  Future<void> clearAllThoughts() async {
    _thoughtHistory.clear();
    _messageCache.clear();
    await _saveThoughts();
    _thoughtStreamController.add(
      AudioThought(
        type: 'system',
        message: 'Memory wiped. Fresh start initiated.',
        timestamp: DateTime.now(),
        context: {},
      ),
    );
    print('🧹 [AudioGovernor] All thoughts manually cleared');
  }

  void _think(String type, Map<String, dynamic> context) async {
    final message = await _generateMessage(type, context);

    final thought = AudioThought(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      context: context,
    );

    _thoughtHistory.insert(0, thought);
    _thoughtStreamController.add(thought);
    _saveThoughts();

    if (kDebugMode) {
      print('🧠 [AudioGovernor] $message');
    }
  }

  // ==================== AI MESSAGE GENERATION ====================

  Future<String> _generateMessage(String type, Map<String, dynamic> ctx) async {
    // Try AI generation first if enabled
    if (_aiEnabled && _random.nextDouble() > 0.3) {
      // 70% chance to use AI
      final aiMessage = await _generateAIMessage(type, ctx);
      if (aiMessage != null) {
        return aiMessage;
      }
    }

    // Fallback to static messages
    return _getFallbackMessage(type, ctx);
  }

  Future<String?> _generateAIMessage(
    String type,
    Map<String, dynamic> ctx,
  ) async {
    // Check cache first
    if (_messageCache.containsKey(type) && _messageCache[type]!.isNotEmpty) {
      final cached = _messageCache[type]!;
      return cached[_random.nextInt(cached.length)];
    }

    try {
      final prompt = _buildPrompt(type, ctx);

      final response = await http
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'com.vibeflow.app',
            },
            body: jsonEncode({
              'model': 'google/gemma-2-9b-it',
              'messages': [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': prompt},
              ],
              'temperature': 0.9,
              'max_tokens': 80,
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] as String?;

        if (content != null && content.trim().isNotEmpty) {
          // Parse multiple variations (separated by newlines)
          final variations = content
              .split('\n')
              .where((s) => s.trim().isNotEmpty && !s.startsWith('#'))
              .map((s) => s.trim())
              .toList();

          if (variations.isNotEmpty) {
            // Cache up to 5 variations
            _messageCache[type] = variations.take(5).toList();
            return variations[_random.nextInt(variations.length)];
          }
        }
      }
    } catch (e) {
      // Silently fail and use fallback
      if (kDebugMode) {
        print('⚠️ [AudioGovernor] AI generation failed: $e');
      }
    }

    return null;
  }

  String get _systemPrompt =>
      '''You are the internal thoughts of an audio player. Generate SHORT (max 12 words), techy but casual messages.

Style: Mix technical terms with casual language. Be slightly quirky but informative.
Tone: Helpful technician who knows what they're doing.
Format: Return 3-5 variations, one per line. No numbering, no hashtags.

Example good messages:
"Buffering stream chunks... network latency at 230ms, should stabilize soon"
"Audio pipeline ready. Let's decode this bad boy"
"URL cache hit! Skipping the whole handshake dance"
"Stream expired. Refreshing auth token in background"
"Processing next track... queue index advancing to position 4"

Keep it:
- Under 12 words
- Technically accurate but simple
- No emojis, no punctuation spam
- Direct and informative''';

  String _buildPrompt(String type, Map<String, dynamic> ctx) {
    switch (type) {
      case 'starting_fresh':
        return 'Event: Loading new song "${ctx['song']}". Generate 3 varied messages about starting audio playback.';

      case 'buffering':
        return 'Event: Audio buffering/loading. Generate 3 messages about network buffer status.';

      case 'loading_url':
        return 'Event: Fetching audio URL from server. Generate 3 messages about URL retrieval.';

      case 'cache_hit':
        final age = ctx['cache_age'] ?? 0;
        return 'Event: Found cached URL from $age minutes ago. Generate 3 messages about cache hit.';

      case 'cache_miss':
        return 'Event: URL not in cache, must fetch fresh. Generate 3 messages about cache miss.';

      case 'url_expired':
        return 'Event: Audio URL expired (403 error). Generate 3 messages about refreshing expired URL.';
      case 'audio_interruption':
        final interruptionType = ctx['interruption_type'] ?? 'unknown';
        return 'Event: Audio interrupted due to $interruptionType. Generate 3 messages about pausing for interruption.';

      case 'interruption_ended':
        final resume = ctx['will_resume'] ?? false;
        return 'Event: Audio interruption ended${resume ? ", will resume playback" : ""}. Generate 3 messages.';

      case 'skip_forward':
        return 'Event: User skipped to next track. Generate 3 messages about skipping forward.';

      case 'skip_backward':
        return 'Event: User went back to previous track. Generate 3 messages about skipping backward.';

      case 'paused_mid_song':
        final pos = _formatDuration(ctx['position'] as Duration?);
        return 'Event: Playback paused at $pos. Generate 3 messages about pausing.';

      case 'resuming':
        final pos = _formatDuration(ctx['position'] as Duration?);
        return 'Event: Resuming playback from $pos. Generate 3 messages about resuming.';

      case 'headphones_unplugged':
        return 'Event: Headphones disconnected suddenly. Generate 3 messages about auto-pausing.';

      case 'headphones_connected':
        final resume = ctx['will_resume'] ?? false;
        return 'Event: Headphones connected${resume ? ", will auto-resume" : ""}. Generate 3 messages.';

      case 'connection_lost':
        return 'Event: Internet connection lost. Generate 3 messages about network failure.';
      case 'playlist_mode_start':
        final count = ctx['song_count'] ?? 0;
        return 'Event: User started playing a playlist with $count songs. Radio disabled for sequential playback. Generate 3 messages about playlist mode.';
      case 'connection_restored':
        return 'Event: Internet connection restored. Generate 3 messages about network recovery.';

      case 'shuffle_enabled':
        return 'Event: Shuffle mode enabled. Generate 3 messages about randomizing queue.';

      case 'loop_mode_change':
        final mode = ctx['loop_mode'];
        return 'Event: Loop mode changed to $mode. Generate 3 messages about loop mode.';

      default:
        return 'Event: $type happened. Generate 3 short techy messages about this audio event.';
    }
  }

  String _getFallbackMessage(String type, Map<String, dynamic> ctx) {
    final fallbacks = <String, List<String>>{
      'starting_fresh': [
        'Loading audio stream for ${ctx['song']}... decoding pipeline ready',
        'Initiating playback. Buffer preloading first 30 seconds',
        'Stream acquisition started. Handshake with server complete',
      ],
      'buffering': [
        'Network buffer low. Downloading more chunks... 47% complete',
        'Buffering stream segments. Latency spike detected, compensating',
        'Prebuffering next 15 seconds. Connection stable at 2.3 Mbps',
      ],
      'loading_url': [
        'Querying media server for stream URL. RTT: ~180ms',
        'Sending auth token. Awaiting signed URL response',
        'HTTP request dispatched. Expecting 200 OK in 400-600ms',
      ],
      'cache_hit': [
        'Cache hit! URL still valid. Skipping network round trip',
        'Found cached stream URL. Age: ${ctx['cache_age']}min. Still fresh',
        'Local cache match. Zero latency. Instant playback ready',
      ],
      'cache_miss': [
        'Cache miss. Fetching new URL from upstream server',
        'No cached URL found. Initiating fresh request to API',
        'Stream URL not cached. Requesting from backend...',
      ],
      'url_expired': [
        'Stream URL expired (403). Refreshing auth credentials silently',
        'Token invalidated. Rotating to fresh signed URL in background',
        'URL TTL exceeded. Auto-refreshing without interrupting playback',
      ],
      'skip_forward': [
        'Queue index advancing. Loading next track metadata',
        'Skipping forward. Preloading upcoming audio buffer',
        'Next track requested. Shifting playback position in queue',
      ],
      'skip_backward': [
        'Rewinding queue pointer. Loading previous track data',
        'Back button pressed. Resetting to prior queue position',
        'Queue index decrementing. Previous track loading',
      ],
      'playlist_mode_start': [
        'Playlist loaded: $Song tracks queued. Radio disabled',
        'Entering playlist mode. $Song songs ready. Auto-progression enabled',
        'User playlist active. $Song tracks. No radio needed',
      ],

      'paused_mid_song': [
        'Playback suspended at ${_formatDuration(ctx['position'] as Duration?)}. Buffer maintained',
        'Audio pipeline paused. Current position saved to state',
        'Stream halted at timestamp ${_formatDuration(ctx['position'] as Duration?)}. Ready to resume',
      ],
      'resuming': [
        'Resuming from ${_formatDuration(ctx['position'] as Duration?)}. Buffer still valid',
        'Playback restarted. Decoder picking up at saved position',
        'Audio pipeline active again. Continuing from ${_formatDuration(ctx['position'] as Duration?)}',
      ],
      'headphones_unplugged': [
        'Audio device disconnected. Auto-pause triggered immediately',
        'Headphone jack event detected. Stopping output to prevent leak',
        'Output device removed. Halting playback as safety measure',
      ],
      'headphones_connected': [
        'Audio output device connected. ${ctx['will_resume'] == true ? 'Auto-resuming in 500ms' : 'Ready when you are'}',
        'Headphones detected. ${ctx['will_resume'] == true ? 'Restarting playback' : 'Awaiting user input'}',
        'New audio route established. ${ctx['will_resume'] == true ? 'Continuing where we left off' : 'Standing by'}',
      ],
      'audio_interruption': [
        'Audio focus lost. Pausing playback for higher priority sound',
        'System interruption detected. Suspending audio pipeline',
        'Playback paused due to external audio event',
      ],

      'interruption_ended': [
        'Interruption ended. Checking whether playback should resume',
        'Audio focus restored. Ready to continue playback',
        'System audio released. ${ctx['will_resume'] == true ? 'Resuming playback' : 'Standing by'}',
      ],

      'connection_lost': [
        'Network interface down. Pausing until connection restored',
        'Internet connectivity lost. Buffer exhausted, halting stream',
        'WiFi/cellular disconnected. Playback impossible without network',
      ],
      'connection_restored': [
        'Network back online. Checking if we should resume playback',
        'Connection reestablished. Stream ready to continue',
        'Internet restored. Audio pipeline can restart now',
      ],
      'shuffle_enabled': [
        'Shuffle mode ON. Randomizing queue order using Fisher-Yates',
        'Random playback activated. Queue indices being scrambled',
        'Shuffle algorithm engaged. Track order now non-sequential',
      ],
      'loop_mode_change': [
        'Loop mode: ${ctx['loop_mode']}. Playback strategy updated',
        'Repeat setting changed to ${ctx['loop_mode']}. Adjusting queue behavior',
        'Loop config: ${ctx['loop_mode']}. End-of-queue behavior modified',
      ],
      'song_completed': [
        'Track finished. Advancing to next in queue',
        'Playback complete. Triggering next track load sequence',
        'Song ended. Checking queue for continuation',
      ],
      'stopped_completely': [
        'Full stop requested. Releasing audio resources',
        'Playback terminated. Cleaning up decoder pipeline',
        'Audio service stopping. Freeing allocated buffers',
      ],
    };

    final options = fallbacks[type];
    if (options != null && options.isNotEmpty) {
      return options[_random.nextInt(options.length)];
    }

    return 'Audio event: $type';
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

  void onPlaylistStart(int songCount) {
    _think('playlist_mode_start', {'song_count': songCount});
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
    _isInterrupted = true;
    _think('audio_interruption', {'interruption_type': type});
  }

  void onInterruptionEnded(bool willResume) {
    _isInterrupted = false;
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
