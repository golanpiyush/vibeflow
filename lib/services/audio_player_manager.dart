// lib/services/audio_player_manager.dart

import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:vibeflow/services/last_played_service.dart';
import 'package:vibeflow/services/playback_governance.dart';

class AudioPlayerManager {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final VibeFlowCore _core = VibeFlowCore();
  static final http.Client _httpClient = http.Client();

  String? _currentStreamUrl;

  // Getter for current audio URL
  String? get currentAudioUrl => _currentStreamUrl;

  final Map<String, _CachedUrl> _urlCache = {};
  String? _currentVideoId;
  QuickPick? _currentSong;
  bool _isInitialized = false;

  // Governance and Radio
  final PlaybackGovernance _governance = PlaybackGovernance();
  final RadioService _radioService = RadioService();
  List<QuickPick> _radioQueue = [];
  int _radioQueueIndex = -1; // -1 means no song from radio is playing

  // Radio prefetch config
  static const int RADIO_QUEUE_SIZE = 25;
  static const int PREFETCH_THRESHOLD = 24; // Prefetch when at 24th song
  bool _isPrefetchingRadio = false;
  List<QuickPick> _nextRadioQueue = []; // Buffer for next radio batch

  // Queue management
  final List<QuickPick> _queue = [];
  int _queueIndex = -1;

  // Autoplay timer
  Timer? _idleTimer;
  bool _isLoadingRadio = false;
  bool _autoplayEnabled = true;

  // History for previous button
  final List<QuickPick> _playbackHistory = [];
  int _historyIndex = -1;

  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;

  AudioPlayerManager() {
    _setupErrorHandling();
    _setupCompletionHandler();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🎵 [AudioPlayerManager] Initializing...');
      await _core.initialize();
      _isInitialized = true;
      print('✅ [AudioPlayerManager] Initialization complete');
    } catch (e) {
      print('❌ [AudioPlayerManager] Initialization failed: $e');
      rethrow;
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'AudioPlayerManager not initialized. Call initialize() first.',
      );
    }
  }

  void _setupErrorHandling() {
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.idle &&
          _currentVideoId != null &&
          _currentSong != null) {
        print('⚠️ [AudioPlayerManager] Player stopped unexpectedly');
        _startIdleTimer();
      }
    });
  }

  /// Setup automatic next song playback when current song completes
  /// Setup automatic next song playback when current song completes
  void _setupCompletionHandler() {
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        print('✅ [AudioPlayerManager] Song completed, auto-playing next...');

        // ✅ CRITICAL: Don't use Future.delayed - play immediately
        _playNextSongAutomatically();
      }
    });
  }

  /// Start idle timer - triggers autoplay after 15 seconds of inactivity
  void _startIdleTimer() {
    _cancelIdleTimer();

    if (!_autoplayEnabled) {
      print('⏸️ [AudioPlayerManager] Autoplay disabled, skipping idle timer');
      return;
    }

    print('⏱️ [AudioPlayerManager] Starting 15s idle timer...');

    _idleTimer = Timer(const Duration(seconds: 15), () async {
      print('🎵 [AudioPlayerManager] 15s idle - triggering autoplay');

      // Check if player is still idle
      if (!_audioPlayer.playing && _currentSong != null) {
        await _triggerAutoplay();
      }
    });
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Trigger autoplay - load radio if needed and play next song
  Future<void> _triggerAutoplay() async {
    if (_currentSong == null) {
      print('⚠️ [AudioPlayerManager] No current song for autoplay');
      return;
    }

    // Load radio if not already loaded
    if (_radioQueue.isEmpty && !_isLoadingRadio) {
      print('📻 [AudioPlayerManager] Loading radio for autoplay...');
      await _loadRadioInBackground(_currentSong!);
    }

    // Play first radio song
    if (_radioQueue.isNotEmpty) {
      _radioQueueIndex = 0;
      await playSong(
        _radioQueue[_radioQueueIndex],
        source: NavigationSource.AUTOPLAY,
      );
    } else {
      print('⚠️ [AudioPlayerManager] No radio songs available for autoplay');
    }
  }

  /// Automatically play next song (triggered on song completion)
  Future<void> _playNextSongAutomatically() async {
    _cancelIdleTimer();

    // ✅ Priority 1: Manual queue
    if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) {
      print('▶️ [AudioPlayerManager] Auto-playing from manual queue');
      _queueIndex++;
      await playSong(_queue[_queueIndex], source: NavigationSource.QUEUE);
      return;
    }

    // ✅ Priority 2: Radio queue (start if not started)
    if (_radioQueue.isNotEmpty && _radioQueueIndex == -1) {
      print('📻 [AudioPlayerManager] Starting radio queue');
      _radioQueueIndex = 0;
      await playSong(
        _radioQueue[_radioQueueIndex],
        source: NavigationSource.AUTOPLAY,
      );
      return;
    }

    // ✅ Priority 3: Next song in radio queue
    if (_radioQueue.isNotEmpty && _radioQueueIndex < _radioQueue.length - 1) {
      print('📻 [AudioPlayerManager] Auto-playing next from radio');
      _radioQueueIndex++;
      await playSong(
        _radioQueue[_radioQueueIndex],
        source: NavigationSource.AUTOPLAY,
      );
      return;
    }

    // ✅ Priority 4: Transition to next radio batch
    if (_radioQueue.isNotEmpty && _radioQueueIndex == _radioQueue.length - 1) {
      print(
        '🔄 [AudioPlayerManager] End of radio - transitioning to next batch',
      );
      _transitionToNextRadioBatch();

      if (_radioQueue.isNotEmpty) {
        _radioQueueIndex = 0;
        await playSong(
          _radioQueue[_radioQueueIndex],
          source: NavigationSource.AUTOPLAY,
        );
        return;
      }
    }

    // ✅ Priority 5: Load new radio if available
    if (_currentSong != null && _radioQueue.isEmpty) {
      print('📻 [AudioPlayerManager] No radio available, loading new...');
      await _loadRadioInBackground(_currentSong!);

      if (_radioQueue.isNotEmpty) {
        _radioQueueIndex = 0;
        await playSong(
          _radioQueue[_radioQueueIndex],
          source: NavigationSource.AUTOPLAY,
        );
        return;
      }
    }

    // ✅ No more songs available
    print('⚠️ [AudioPlayerManager] No next song available');
  }

  void _checkAndPrefetchRadio() {
    // Only prefetch when playing from radio queue
    if (_radioQueueIndex == -1 || _radioQueue.isEmpty) return;

    // Check if we're at the prefetch threshold (24th song)
    if (_radioQueueIndex == PREFETCH_THRESHOLD - 1 &&
        !_isPrefetchingRadio &&
        _nextRadioQueue.isEmpty) {
      print(
        '🎯 [AudioPlayerManager] Reached song ${_radioQueueIndex + 1}/$RADIO_QUEUE_SIZE - prefetching next batch',
      );

      // Use the current song (24th) as seed for next radio batch
      final seedSong = _radioQueue[_radioQueueIndex];
      _loadRadioInBackground(seedSong, isNextBatch: true);
    }
  }

  void _transitionToNextRadioBatch() {
    if (_nextRadioQueue.isNotEmpty) {
      print('🔄 [AudioPlayerManager] Transitioning to next radio batch');
      _radioQueue = _nextRadioQueue;
      _radioQueueIndex = -1; // Will be set to 0 when first song plays
      _nextRadioQueue = [];
      _governance.clearRadioState(); // Allow new radio to be tracked
    }
  }

  /// Play a song with governance
  /// Play a song with governance
  Future<void> playSong(
    QuickPick song, {
    NavigationSource source = NavigationSource.USER,
  }) async {
    _ensureInitialized();
    _cancelIdleTimer();

    final context = PlaybackContext(
      videoId: song.videoId,
      source: source,
      operation: source == NavigationSource.USER
          ? OperationType.USER_PLAY
          : OperationType.AUTOPLAY,
      isNetworkPlayback: true,
    );

    if (!_governance.shouldProceed(context)) {
      print('⛔ [AudioPlayerManager] Playback blocked by governance');
      return;
    }

    _governance.startOperation(context);

    // Check if same song is playing - do nothing
    if (_isSameSongCurrentlyPlaying(song)) {
      print(
        '🎵 [AudioPlayerManager] Same song already playing - no action taken',
      );
      _governance.completeOperation();
      return;
    }

    try {
      print('🎵 [AudioPlayerManager] Playing new song: ${song.title}');

      // Stop current playback first (different song detected)
      if (_currentVideoId != null) {
        print('⏹️ [AudioPlayerManager] Stopping current playback');
        await _audioPlayer.stop();
      }

      // Add to history for previous button functionality
      if (_currentSong != null &&
          (_playbackHistory.isEmpty ||
              _playbackHistory.last.videoId != _currentSong!.videoId)) {
        _playbackHistory.add(_currentSong!);
        _historyIndex = _playbackHistory.length - 1;
      }

      _currentVideoId = song.videoId;
      _currentSong = song;

      // ✅ NEW: Clear radio if this is a user-initiated play from search/home
      if (source == NavigationSource.USER) {
        print(
          '🔄 [AudioPlayerManager] User-initiated play - clearing old radio',
        );
        _radioQueue.clear();
        _radioQueueIndex = -1;
        _nextRadioQueue.clear();
        _governance.clearRadioState();
      }

      // Get audio URL
      final audioUrl = await _getFreshAudioUrl(song.videoId);
      _currentStreamUrl = audioUrl;
      if (audioUrl == null) {
        throw Exception('Failed to get audio URL for ${song.videoId}');
      }

      print('🔗 [AudioPlayerManager] Got audio URL, setting up player...');

      // Create audio source with metadata
      final audioSource = AudioSource.uri(
        Uri.parse(audioUrl),
        tag: MediaItem(
          id: song.videoId,
          title: song.title,
          artist: song.artists,
          artUri:
              song.thumbnail.isNotEmpty &&
                  (song.thumbnail.startsWith('http://') ||
                      song.thumbnail.startsWith('https://'))
              ? Uri.parse(song.thumbnail)
              : null,
        ),
      );

      await _audioPlayer.setAudioSource(audioSource);
      await _audioPlayer.play();

      print('✅ [AudioPlayerManager] Playback started');

      // Save to last played service
      await LastPlayedService.saveLastPlayed(song);

      // ✅ FIXED: Always load radio for user-initiated plays
      if (source == NavigationSource.USER) {
        print('📻 [AudioPlayerManager] Loading fresh radio for new song');
        await _loadRadioInBackground(song);
      } else if (_governance.shouldLoadRadio(song.videoId) &&
          _radioQueue.isEmpty) {
        await _loadRadioInBackground(song);
      }

      // Check if we should prefetch next radio batch
      _checkAndPrefetchRadio();

      _governance.completeOperation();
    } catch (e, stack) {
      print('❌ [AudioPlayerManager] Error playing song: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      _governance.completeOperation();

      if (_currentSong != null) {
        await _handlePlaybackError(_currentSong!);
      } else {
        rethrow;
      }
    }
  }

  /// Load radio in background
  Future<void> _loadRadioInBackground(
    QuickPick song, {
    bool isNextBatch = false,
  }) async {
    if (_isLoadingRadio || _isPrefetchingRadio) {
      print('⏳ [AudioPlayerManager] Radio already loading');
      return;
    }

    if (isNextBatch) {
      _isPrefetchingRadio = true;
      print('🔄 [AudioPlayerManager] Prefetching NEXT radio batch...');
    } else {
      _isLoadingRadio = true;
      print('📻 [AudioPlayerManager] Loading radio for: ${song.title}');
    }

    try {
      final radioSongs = await _radioService.getRadioForSong(
        videoId: song.videoId,
        title: song.title,
        artist: song.artists,
        limit: RADIO_QUEUE_SIZE,
      );

      if (isNextBatch) {
        // Store in buffer for seamless transition
        _nextRadioQueue = radioSongs;
        print(
          '✅ [AudioPlayerManager] Next radio batch prefetched: ${radioSongs.length} songs',
        );
      } else {
        // Load current radio queue
        _radioQueue = radioSongs;
        _radioQueueIndex = -1;
        _governance.markRadioLoaded(song.videoId);
        print(
          '✅ [AudioPlayerManager] Radio loaded: ${radioSongs.length} songs',
        );
      }
    } catch (e) {
      print('⚠️ [AudioPlayerManager] Radio load failed: $e');
    } finally {
      if (isNextBatch) {
        _isPrefetchingRadio = false;
      } else {
        _isLoadingRadio = false;
      }
    }
  }

  /// (It checks by both videoId AND by title + artist name)
  bool _isSameSongCurrentlyPlaying(QuickPick song) {
    if (_currentSong == null) {
      return false;
    }

    if (_currentSong!.videoId == song.videoId) {
      return true;
    }

    // Check by title and artist name (case-insensitive)
    return _currentSong!.title.toLowerCase() == song.title.toLowerCase() &&
        _currentSong!.artists.toLowerCase() == song.artists.toLowerCase();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    _startIdleTimer(); // Start idle timer when paused
  }

  Future<void> resume() async {
    _cancelIdleTimer(); // Cancel idle timer when resuming

    if (_currentSong != null) {
      await _audioPlayer.play();
    } else {
      print('⚠️ [AudioPlayerManager] No song to resume');
    }
  }

  Future<void> stop() async {
    _cancelIdleTimer();

    if (_audioPlayer.playing) {
      await _audioPlayer.stop();
    }

    _currentVideoId = null;
    _currentSong = null;
    print('🛑 [AudioPlayerManager] Playback stopped and cleared');
  }

  Future<void> _handlePlaybackError(QuickPick song) async {
    print(
      '🔄 [AudioPlayerManager] Handling playback error for ${song.videoId}',
    );
    _urlCache.remove(song.videoId);

    try {
      final audioUrl = await _core.getAudioUrlWithRetry(
        song.videoId,
        maxRetries: 3,
        retryDelay: const Duration(seconds: 2),
      );

      if (audioUrl == null) {
        throw Exception('Failed to get audio URL after retries');
      }

      _urlCache[song.videoId] = _CachedUrl(url: audioUrl);

      final audioSource = AudioSource.uri(
        Uri.parse(audioUrl),
        tag: MediaItem(
          id: song.videoId,
          title: song.title,
          artist: song.artists,
          artUri:
              song.thumbnail.isNotEmpty &&
                  (song.thumbnail.startsWith('http://') ||
                      song.thumbnail.startsWith('https://'))
              ? Uri.parse(song.thumbnail)
              : null,
        ),
      );

      await _audioPlayer.setAudioSource(audioSource);
      await _audioPlayer.play();

      print('✅ [AudioPlayerManager] Retry successful');
    } catch (e) {
      print('❌ [AudioPlayerManager] Retry failed: $e');
      rethrow;
    }
  }

  Future<String?> _getFreshAudioUrl(String videoId) async {
    final cached = _urlCache[videoId];
    if (cached != null && !cached.isExpired) {
      print('⚡ [AudioPlayerManager] Using cached URL');
      return cached.url;
    }

    print('🔄 [AudioPlayerManager] Fetching fresh audio URL...');
    final url = await _core.getAudioUrl(videoId);

    if (url != null) {
      _urlCache[videoId] = _CachedUrl(url: url);
      print('✅ [AudioPlayerManager] URL cached for $videoId');
    } else {
      print('⚠️ [AudioPlayerManager] No URL returned for $videoId');
    }

    return url;
  }

  Future<void> seek(Duration position) => _audioPlayer.seek(position);

  /// Skip to next song - manual queue > radio queue > trigger autoplay
  Future<void> skipToNext() async {
    _cancelIdleTimer();

    final context = PlaybackContext(
      videoId: 'next',
      source: NavigationSource.USER,
      operation: OperationType.USER_NAVIGATE,
    );

    if (!_governance.shouldProceed(context)) {
      return;
    }

    _governance.startOperation(context);

    try {
      if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) {
        _queueIndex++;
        await playSong(_queue[_queueIndex], source: NavigationSource.QUEUE);
      } else if (_radioQueue.isNotEmpty &&
          _radioQueueIndex < _radioQueue.length - 1) {
        _radioQueueIndex++;
        await playSong(
          _radioQueue[_radioQueueIndex],
          source: NavigationSource.AUTOPLAY,
        );

        // Check for prefetch after manual skip
        _checkAndPrefetchRadio();
      } else if (_radioQueue.isNotEmpty &&
          _radioQueueIndex == _radioQueue.length - 1) {
        // At last song - transition to next batch if available
        _transitionToNextRadioBatch();

        if (_radioQueue.isNotEmpty) {
          _radioQueueIndex = 0;
          await playSong(
            _radioQueue[_radioQueueIndex],
            source: NavigationSource.AUTOPLAY,
          );
        } else {
          print('⚠️ [AudioPlayerManager] No next batch, loading new radio');
          if (_currentSong != null) {
            await _loadRadioInBackground(_currentSong!);
            if (_radioQueue.isNotEmpty) {
              _radioQueueIndex = 0;
              await playSong(
                _radioQueue[_radioQueueIndex],
                source: NavigationSource.AUTOPLAY,
              );
            }
          }
        }
      } else if (_currentSong != null) {
        print('📻 [AudioPlayerManager] Loading new radio for next...');
        await _loadRadioInBackground(_currentSong!);

        if (_radioQueue.isNotEmpty) {
          _radioQueueIndex = 0;
          await playSong(
            _radioQueue[_radioQueueIndex],
            source: NavigationSource.AUTOPLAY,
          );
        } else {
          print('⚠️ [AudioPlayerManager] No radio songs available');
        }
      } else {
        print('⚠️ [AudioPlayerManager] No next song available');
      }

      _governance.completeOperation();
    } catch (e) {
      print('❌ [AudioPlayerManager] Skip next error: $e');
      _governance.completeOperation();
    }
  }

  /// Skip to previous song - uses playback history
  Future<void> skipToPrevious() async {
    _cancelIdleTimer();

    final context = PlaybackContext(
      videoId: 'previous',
      source: NavigationSource.USER,
      operation: OperationType.USER_NAVIGATE,
    );

    if (!_governance.shouldProceed(context)) {
      return;
    }

    _governance.startOperation(context);

    try {
      final position = _audioPlayer.position;

      // If more than 3 seconds, restart current song
      if (position.inSeconds > 3) {
        await _audioPlayer.seek(Duration.zero);
        _governance.completeOperation();
        return;
      }

      // Priority 1: Manual Queue
      if (_queue.isNotEmpty && _queueIndex > 0) {
        _queueIndex--;
        await playSong(_queue[_queueIndex], source: NavigationSource.QUEUE);
      }
      // Priority 2: Radio Queue
      else if (_radioQueue.isNotEmpty && _radioQueueIndex > 0) {
        _radioQueueIndex--;
        await playSong(
          _radioQueue[_radioQueueIndex],
          source: NavigationSource.AUTOPLAY,
        );
      }
      // Priority 3: Playback History
      else if (_playbackHistory.isNotEmpty && _historyIndex >= 0) {
        final previousSong = _playbackHistory[_historyIndex];

        // Remove from history so we don't keep going back to same song
        if (_historyIndex > 0) {
          _historyIndex--;
        }

        await playSong(previousSong, source: NavigationSource.USER);
      } else {
        print('⚠️ [AudioPlayerManager] No previous song available');
      }

      _governance.completeOperation();
    } catch (e) {
      print('❌ [AudioPlayerManager] Skip previous error: $e');
      _governance.completeOperation();
    }
  }

  Future<void> addToQueue(QuickPick song) async {
    final context = PlaybackContext(
      videoId: song.videoId,
      source: NavigationSource.QUEUE,
      operation: OperationType.QUEUE_SYNC,
    );

    if (!_governance.shouldProceed(context)) {
      _governance.queueOperation(context);
      return;
    }

    _governance.startOperation(context);
    _queue.add(song);

    // If this is the first item in queue and no song is playing from queue
    if (_queue.length == 1 && _queueIndex == -1) {
      _queueIndex = 0;
    }

    print('➕ [AudioPlayerManager] Added to queue: ${song.title}');
    _governance.completeOperation();
  }

  Future<void> seekForward() async {
    final current = _audioPlayer.position;
    await _audioPlayer.seek(current + const Duration(seconds: 10));
  }

  Future<void> seekBackward() async {
    final current = _audioPlayer.position;
    final newPosition = current - const Duration(seconds: 10);
    await _audioPlayer.seek(
      newPosition.isNegative ? Duration.zero : newPosition,
    );
  }

  void clearCache() {
    _urlCache.clear();
    print('🗑️ [AudioPlayerManager] Cache cleared');
  }

  void clearQueue() {
    _queue.clear();
    _queueIndex = -1;
    _radioQueue.clear();
    _radioQueueIndex = -1;
    _nextRadioQueue.clear(); // NEW: Clear prefetch buffer
    _governance.clearRadioState();
    print('🗑️ [AudioPlayerManager] Queue, radio, and prefetch buffer cleared');
  }

  void clearHistory() {
    _playbackHistory.clear();
    _historyIndex = -1;
    print('🗑️ [AudioPlayerManager] History cleared');
  }

  void setAutoplayEnabled(bool enabled) {
    _autoplayEnabled = enabled;
    if (!enabled) {
      _cancelIdleTimer();
    }
    print(
      '🎵 [AudioPlayerManager] Autoplay ${enabled ? "enabled" : "disabled"}',
    );
  }

  // Getters
  QuickPick? get currentSong => _currentSong;
  bool get isPlaying => _audioPlayer.playing;
  PlayerState get currentState => _audioPlayer.playerState;
  bool get hasSong => _currentSong != null;
  PlaybackContext? get currentGovernanceContext => _governance.currentContext;
  String? get activeRadioSource => _governance.activeRadioSource;
  List<QuickPick> get radioQueue => List.unmodifiable(_radioQueue);
  List<QuickPick> get manualQueue => List.unmodifiable(_queue);
  bool get autoplayEnabled => _autoplayEnabled;
  int get radioQueueIndex => _radioQueueIndex;
  int get queueIndex => _queueIndex;

  bool isSongCurrentlyLoaded(QuickPick song) {
    return _isSameSongCurrentlyPlaying(song);
  }

  void dispose() {
    _cancelIdleTimer();
    _audioPlayer.dispose();
    _urlCache.clear();
    _radioService.dispose();
    _governance.reset();
    _playbackHistory.clear();
    print('👋 [AudioPlayerManager] Disposed');
  }

  bool get isPrefetchingRadio => _isPrefetchingRadio;
  List<QuickPick> get nextRadioQueue => List.unmodifiable(_nextRadioQueue);
}

class _CachedUrl {
  final String url;
  final DateTime timestamp;

  _CachedUrl({required this.url}) : timestamp = DateTime.now();

  bool get isExpired {
    final age = DateTime.now().difference(timestamp);
    return age.inHours >= 5;
  }
}
