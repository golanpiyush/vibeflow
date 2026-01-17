import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/providers/RealTimeService.dart';
import 'package:vibeflow/services/cacheManager.dart';
import 'package:vibeflow/widgets/recent_listening_speed_dial.dart';

/// Background Audio Handler for persistent playback
/// Handles notification controls, lock screen controls, and background playback
class BackgroundAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final VibeFlowCore _core = VibeFlowCore();
  final RealtimeListeningTracker _tracker = RealtimeListeningTracker();
  final RadioService _radioService = RadioService();
  final Map<String, String> _urlCache = {};
  final Map<String, DateTime> _urlCacheTime = {};
  static const _cacheExpiry = Duration(hours: 2); // URLs expire after 2 hours

  // Current queue and playback state
  final _queue = <MediaItem>[];
  int _currentIndex = 0;
  LoopMode _loopMode = LoopMode.off;
  // Radio queue for autoplay
  final _radioQueue = <MediaItem>[];
  int _radioQueueIndex = -1;
  bool _isLoadingRadio = false;
  String? _lastRadioVideoId;

  bool _isRefreshingUrl = false;

  BackgroundAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    await _core.initialize();
    _setupAudioPlayer();
    // ✅ NEW: Give tracker access to audio player
    _tracker.setAudioPlayer(_audioPlayer);
    print('✅ [BackgroundAudioHandler] Initialized');
  }

  void _setupAudioPlayer() {
    _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (isPlaying) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: _mapProcessingState(processingState),
          playing: isPlaying,
          updatePosition: _audioPlayer.position,
          bufferedPosition: _audioPlayer.bufferedPosition,
          speed: _audioPlayer.speed,
        ),
      );

      // Handle song completion
      if (processingState == ProcessingState.completed) {
        print('✅ Song completed, stopping tracking');
        _tracker.stopTracking();
      }

      // Handle idle/stopped state
      if (processingState == ProcessingState.idle && !isPlaying) {
        print('⏹️ Player idle/stopped, stopping tracking');
        _tracker.stopTracking();
      }
    });

    _audioPlayer.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    });

    _audioPlayer.durationStream.listen((duration) {
      if (duration != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        print('✅ [BackgroundAudioHandler] Song completed, playing next...');
        skipToNext();
      }
    });
    // Listen for playback errors
    _audioPlayer.playbackEventStream.listen((event) async {
      // Check for errors
      if (event.processingState == ProcessingState.idle &&
          event.currentIndex == null &&
          !_audioPlayer.playing) {
        // This usually indicates an error occurred
        // Try to detect if it was a 403 error by attempting to play
        await _handle403ErrorRecovery();
      }
    });
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Future<void> _handle403ErrorRecovery() async {
    if (_isRefreshingUrl) return;

    final currentMedia = mediaItem.value;
    if (currentMedia == null) return;

    _isRefreshingUrl = true;

    try {
      print(
        '🔄 [Auto-Refresh] Attempting URL refresh for: ${currentMedia.title}',
      );

      // Clear old cached URL
      final audioCache = AudioUrlCache();
      await audioCache.remove(currentMedia.id);

      // Also clear internal cache
      _urlCache.remove(currentMedia.id);
      _urlCacheTime.remove(currentMedia.id);

      // Get fresh URL
      final quickPick = _quickPickFromMediaItem(currentMedia);
      final freshUrl = await _core.getAudioUrl(
        currentMedia.id,
        song: quickPick,
      );

      if (freshUrl != null && freshUrl.isNotEmpty) {
        print('✅ [Auto-Refresh] Got fresh URL, retrying playback...');

        // Retry playback with new URL
        await _audioPlayer.setUrl(freshUrl);
        await _audioPlayer.play();

        // Restart tracking
        await Future.delayed(const Duration(milliseconds: 300));
        await _tracker.startTracking(quickPick);

        print('✅ [Auto-Refresh] Playback resumed successfully');
      } else {
        print('❌ [Auto-Refresh] Failed to get fresh URL');
      }
    } catch (e) {
      print('❌ [Auto-Refresh] Error during refresh: $e');
    } finally {
      _isRefreshingUrl = false;
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    try {
      print('➕ [BackgroundAudioHandler] Adding to queue: ${mediaItem.title}');

      // Add to queue
      _queue.add(mediaItem);
      queue.add(_queue);

      print('✅ Queue now has ${_queue.length} items');
    } catch (e) {
      print('❌ [BackgroundAudioHandler] Error adding to queue: $e');
    }
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    try {
      final index = _queue.indexOf(mediaItem);
      if (index != -1) {
        _queue.removeAt(index);

        // Adjust current index if necessary
        if (_currentIndex >= index && _currentIndex > 0) {
          _currentIndex--;
        }

        queue.add(_queue);
      }
    } catch (e) {
      print('❌ [BackgroundAudioHandler] Error removing from queue: $e');
    }
  }

  // ==================== PUBLIC API ====================

  /// Play a single song

  Future<void> playSong(QuickPick song) async {
    try {
      print('🎵 [HANDLER] ========== PLAYING SONG ==========');
      print('   Title: ${song.title}');
      print('   Artists: ${song.artists}');
      print('   VideoId: ${song.videoId}');

      // Check if same song is already playing
      final currentMedia = mediaItem.value;
      if (currentMedia != null && currentMedia.id == song.videoId) {
        print('🎵 Same song already playing');
        if (!_audioPlayer.playing) {
          await _audioPlayer.play();
          _tracker.resumeTracking();
        }
        return;
      }

      // Stop tracking previous song first
      print('🛑 [HANDLER] Stopping previous tracking...');
      await _tracker.stopTracking();

      // Pause if playing
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      }

      // Clear radio queue
      _radioQueue.clear();
      _radioQueueIndex = -1;
      _lastRadioVideoId = null;
      _isLoadingRadio = false;

      final newMediaItem = MediaItem(
        id: song.videoId,
        title: song.title,
        artist: song.artists,
        artUri:
            song.thumbnail.isNotEmpty &&
                (song.thumbnail.startsWith('http://') ||
                    song.thumbnail.startsWith('https://'))
            ? Uri.parse(song.thumbnail)
            : null,
        duration: song.duration != null
            ? _parseDurationString(song.duration!)
            : null,
      );

      _queue.clear();
      _queue.add(newMediaItem);
      _currentIndex = 0;
      queue.add(_queue);
      mediaItem.add(newMediaItem);

      // Get audio URL with caching
      print('🔍 [HANDLER] Getting audio URL...');
      final audioUrl = await _getAudioUrl(song.videoId, song: song);
      if (audioUrl == null) throw Exception('Failed to get audio URL');

      print('✅ [HANDLER] Audio URL obtained, setting player...');
      await _audioPlayer.setUrl(audioUrl);

      print('▶️ [HANDLER] Starting playback...');
      try {
        unawaited(_audioPlayer.play());
        print('🔥 [DEBUG] Play completed successfully!');
      } catch (playError) {
        print('❌ [HANDLER] Play error: $playError');
        rethrow;
      }

      print('🔥 [DEBUG] After play() - about to wait and track');

      // Wait for playback to actually start
      await Future.delayed(const Duration(milliseconds: 300));

      print('📝 [HANDLER] Starting realtime tracking...');
      await _tracker.startTracking(song);

      print('✅ [HANDLER] ========== PLAYBACK STARTED ==========');

      // Cache and load radio in background
      AudioUrlCache().cache(song, audioUrl);
      _loadRadioImmediately(song);
    } catch (e, stackTrace) {
      print('❌ [HANDLER] Error playing song: $e');
      print('   Stack: $stackTrace');
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
        ),
      );
    }
  }

  /// Handle playback errors with automatic URL refresh for 403 errors
  Future<void> handlePlaybackError(
    String errorMessage,
    String videoId,
    String songTitle, {
    QuickPick? song,
    required Function(String newUrl) onUrlRefreshed,
  }) async {
    print('❌ [HANDLER] Playback error: $errorMessage');

    // Check if it's a 403 error (expired URL)
    if (errorMessage.contains('403') ||
        errorMessage.contains('Response code: 403') ||
        errorMessage.contains('Source error')) {
      print('🔄 [HANDLER] Detected 403 error, refreshing URL...');

      try {
        // Force refresh the audio URL
        final vibeFlowCore = VibeFlowCore();
        final newUrl = await vibeFlowCore.forceRefreshAudioUrl(
          videoId,
          song: song,
        );

        if (newUrl != null && newUrl.isNotEmpty) {
          print('✅ [HANDLER] Got fresh URL, retrying playback...');

          // Call the callback to set the new URL and retry
          onUrlRefreshed(newUrl);

          return;
        } else {
          print('❌ [HANDLER] Failed to get fresh URL');
        }
      } catch (e) {
        print('❌ [HANDLER] Error refreshing URL: $e');
      }
    }

    // If not a 403 error or refresh failed, show error to user
    print('❌ [HANDLER] Unrecoverable error: $errorMessage');
  }

  // Add method to update loop mode
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;

    // Update custom state for UI
    playbackState.add(
      playbackState.value.copyWith(
        processingState: playbackState.value.processingState,
        controls: playbackState.value.controls,
        updatePosition: playbackState.value.updatePosition,
        bufferedPosition: playbackState.value.bufferedPosition,
        speed: playbackState.value.speed,
        queueIndex: playbackState.value.queueIndex,
      ),
    );

    // Update custom state for UI to read
    customState.add({...customState.value, 'loop_mode': mode.index});
  }

  QuickPick _quickPickFromMediaItem(MediaItem media) {
    return QuickPick(
      videoId: media.id,
      title: media.title,
      artists: media.artist ?? '',
      thumbnail: media.artUri?.toString() ?? '',
      duration: media.duration != null
          ? '${media.duration!.inMinutes}:${(media.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
          : null,
    );
  }

  /// 🔥 NEW: Load radio immediately and ensure it's ready for autoplay
  Future<void> _loadRadioImmediately(QuickPick song) async {
    if (_isLoadingRadio) {
      print('⏳ [BackgroundAudioHandler] Already loading radio, skipping');
      return;
    }

    _isLoadingRadio = true;
    _lastRadioVideoId = song.videoId;

    try {
      print('📻 [BackgroundAudioHandler] Fetching radio for: ${song.title}');

      final radioSongs = await _radioService.getRadioForSong(
        videoId: song.videoId,
        title: song.title,
        artist: song.artists,
        limit: 25,
      );

      if (radioSongs.isEmpty) {
        print('⚠️ [BackgroundAudioHandler] No radio songs returned');
        return;
      }

      _radioQueue.clear();
      _radioQueue.addAll(
        radioSongs.map(
          (song) => MediaItem(
            id: song.videoId,
            title: song.title,
            artist: song.artists,
            artUri:
                song.thumbnail.isNotEmpty &&
                    (song.thumbnail.startsWith('http://') ||
                        song.thumbnail.startsWith('https://'))
                ? Uri.parse(song.thumbnail)
                : null,
            duration: song.duration != null
                ? _parseDurationString(song.duration!)
                : null,
          ),
        ),
      );

      _radioQueueIndex = -1; // Ready to start from index 0
      print(
        '✅ [BackgroundAudioHandler] Radio loaded: ${_radioQueue.length} songs',
      );
      print('🎯 [BackgroundAudioHandler] Radio ready for autoplay!');
    } catch (e) {
      print('❌ [BackgroundAudioHandler] Radio load failed: $e');
    } finally {
      _isLoadingRadio = false;
    }
  }

  bool _isSameSong(MediaItem currentMedia, QuickPick song) {
    // Check by videoId
    if (currentMedia.id == song.videoId) {
      return true;
    }

    // Check by title and artist name (case-insensitive)
    final currentTitle = (currentMedia.title ?? '').toLowerCase();
    final currentArtist = (currentMedia.artist ?? '').toLowerCase();
    final songTitle = song.title.toLowerCase();
    final songArtist = song.artists.toLowerCase();

    return currentTitle == songTitle && currentArtist == songArtist;
  }

  /// Play a list of songs
  /// Play a list of songs
  Future<void> playQueue(List<QuickPick> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    try {
      print('🎵 [BackgroundAudioHandler] Playing queue: ${songs.length} songs');

      // Stop tracking current song
      await _tracker.stopTracking();

      // Create media items
      _queue.clear();
      _queue.addAll(
        songs.map(
          (song) => MediaItem(
            id: song.videoId,
            title: song.title,
            artist: song.artists,
            artUri:
                song.thumbnail.isNotEmpty &&
                    (song.thumbnail.startsWith('http://') ||
                        song.thumbnail.startsWith('https://'))
                ? Uri.parse(song.thumbnail)
                : null,
            duration: song.duration != null
                ? _parseDurationString(song.duration!)
                : null,
          ),
        ),
      );

      _currentIndex = startIndex.clamp(0, _queue.length - 1);
      queue.add(_queue);
      mediaItem.add(_queue[_currentIndex]);

      // Get audio URL for first song
      final audioUrl = await _getAudioUrl(
        songs[_currentIndex].videoId,
        song: songs[_currentIndex],
      );

      if (audioUrl == null) {
        throw Exception('Failed to get audio URL');
      }

      // Play audio
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();

      // Wait for playback to start, then track
      await Future.delayed(const Duration(milliseconds: 300));
      await _tracker.startTracking(songs[_currentIndex]);

      print('✅ [BackgroundAudioHandler] Queue playback started');
    } catch (e) {
      print('❌ [BackgroundAudioHandler] Queue error: $e');
    }
  }

  Future<String?> _getAudioUrl(String videoId, {QuickPick? song}) async {
    print('🔍 [_getAudioUrl] Fetching for videoId: $videoId');
    print('   Song: ${song?.title ?? "unknown"}');

    // Check internal cache first (with expiry)
    if (_urlCache.containsKey(videoId) && _urlCacheTime.containsKey(videoId)) {
      final cacheAge = DateTime.now().difference(_urlCacheTime[videoId]!);
      if (cacheAge < _cacheExpiry) {
        print('⚡ [Internal Cache] Using URL (age: ${cacheAge.inMinutes}min)');
        return _urlCache[videoId];
      } else {
        print('🗑️ [Internal Cache] Expired, removing');
        _urlCache.remove(videoId);
        _urlCacheTime.remove(videoId);
      }
    }

    // Fetch fresh URL
    print('🔄 Fetching fresh audio URL from core...');
    try {
      final url = await _core.getAudioUrl(videoId, song: song);

      if (url != null && url.isNotEmpty) {
        // Cache in internal cache
        _urlCache[videoId] = url;
        _urlCacheTime[videoId] = DateTime.now();
        print('✅ URL fetched and cached successfully');
        return url;
      } else {
        print('❌ Core returned null or empty URL');
        return null;
      }
    } catch (e) {
      print('❌ Error fetching audio URL: $e');
      return null;
    }
  }

  // ==================== AUDIO SERVICE CONTROLS ====================

  @override
  Future<void> play() async {
    await _audioPlayer.play();
    _tracker.resumeTracking();
  }

  @override
  Future<void> pause() async {
    await _audioPlayer.pause();
    await _tracker.pauseTracking();
  }

  @override
  Future<void> stop() async {
    await _tracker.stopTracking();
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    print('⏭️ Skip to next');

    // Stop tracking current song
    await _tracker.stopTracking();

    MediaItem? nextMedia;
    QuickPick? nextSong;

    // Priority 1: Manual queue
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      nextMedia = _queue[_currentIndex];
    }
    // Priority 2: Start radio
    else if (_radioQueue.isNotEmpty && _radioQueueIndex == -1) {
      print('📻 Starting radio queue');
      _radioQueueIndex = 0;
      nextMedia = _radioQueue[_radioQueueIndex];
    }
    // Priority 3: Continue radio
    else if (_radioQueue.isNotEmpty &&
        _radioQueueIndex < _radioQueue.length - 1) {
      _radioQueueIndex++;
      nextMedia = _radioQueue[_radioQueueIndex];
    }

    if (nextMedia != null) {
      mediaItem.add(nextMedia);
      nextSong = _quickPickFromMediaItem(nextMedia);

      final audioUrl = await _getAudioUrl(nextMedia.id, song: nextSong);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await _audioPlayer.play();
        _tracker.startTracking(nextSong!);
        return;
      }
    }

    print('⚠️ No next song available');
  }

  @override
  Future<void> skipToPrevious() async {
    print('⏮️ Skip to previous');

    final position = _audioPlayer.position;

    // If more than 3 seconds, restart current song
    if (position.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    // Stop tracking current song FIRST
    await _tracker.stopTracking();

    MediaItem? prevMedia;
    QuickPick? prevSong;

    // Check manual queue first
    if (_queue.isNotEmpty && _currentIndex > 0) {
      _currentIndex--;
      prevMedia = _queue[_currentIndex];
    }
    // Check radio queue
    else if (_radioQueue.isNotEmpty && _radioQueueIndex > 0) {
      _radioQueueIndex--;
      prevMedia = _radioQueue[_radioQueueIndex];
    }

    if (prevMedia != null) {
      mediaItem.add(prevMedia);
      prevSong = _quickPickFromMediaItem(prevMedia);

      final audioUrl = await _getAudioUrl(prevMedia.id, song: prevSong);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await _audioPlayer.play();

        // Wait for playback to start, then track
        await Future.delayed(const Duration(milliseconds: 300));
        await _tracker.startTracking(prevSong);
        return;
      }
    }

    print('⚠️ No previous song');
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _queue.length) {
      print('🎯 Skipping to queue item at index: $index');

      // Stop tracking current song
      await _tracker.stopTracking();

      _currentIndex = index;
      final selectedMedia = _queue[_currentIndex];
      mediaItem.add(selectedMedia);

      final quickPick = _quickPickFromMediaItem(selectedMedia);

      final audioUrl = await _getAudioUrl(selectedMedia.id, song: quickPick);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await _audioPlayer.play();

        // Wait for playback to start, then track
        await Future.delayed(const Duration(milliseconds: 300));
        await _tracker.startTracking(quickPick);
      }
    } else {
      print('⚠️ Invalid queue index: $index (queue length: ${_queue.length})');
    }
  }

  @override
  Future<void> fastForward() async {
    await seek(_audioPlayer.position + const Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    final newPosition = _audioPlayer.position - const Duration(seconds: 10);
    await seek(newPosition.isNegative ? Duration.zero : newPosition);
  }

  // Helper method
  Duration? _parseDurationString(String durationStr) {
    final parts = durationStr.split(':');
    if (parts.length != 2) return null;
    final minutes = int.tryParse(parts[0]) ?? 0;
    final seconds = int.tryParse(parts[1]) ?? 0;
    return Duration(minutes: minutes, seconds: seconds);
  }

  // ==================== GETTERS ====================

  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;
}
