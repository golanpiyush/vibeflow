import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

/// Background Audio Handler for persistent playback
/// Handles notification controls, lock screen controls, and background playback
class BackgroundAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final VibeFlowCore _core = VibeFlowCore();
  final RadioService _radioService = RadioService();
  final Map<String, String> _urlCache = {};

  // Current queue and playback state
  final _queue = <MediaItem>[];
  int _currentIndex = 0;

  // Radio queue for autoplay
  final _radioQueue = <MediaItem>[];
  int _radioQueueIndex = -1;
  bool _isLoadingRadio = false;
  String? _lastRadioVideoId;

  BackgroundAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    await _core.initialize();
    _setupAudioPlayer();
    print('✅ [BackgroundAudioHandler] Initialized');
  }

  void _setupAudioPlayer() {
    // Broadcast player state changes
    _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      // Map just_audio states to audio_service states
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
    });

    // Broadcast position updates
    _audioPlayer.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    });

    // Broadcast duration
    _audioPlayer.durationStream.listen((duration) {
      if (duration != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    // Handle playback completion - FIXED: Auto-play next song
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        print('✅ [BackgroundAudioHandler] Song completed, playing next...');
        skipToNext();
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
      print('🎵 [BackgroundAudioHandler] Playing: ${song.title}');

      // Check if same song is already playing - do nothing
      if (mediaItem.value != null && _isSameSong(mediaItem.value!, song)) {
        print(
          '🎵 [BackgroundAudioHandler] Same song already playing - no action taken',
        );
        return;
      }

      // ALWAYS stop current playback before playing a new/different song
      if (_audioPlayer.playing ||
          _audioPlayer.processingState != ProcessingState.idle) {
        print('⏹️ [BackgroundAudioHandler] Stopping current playback');
        await _audioPlayer.stop();
      }

      // Create media item
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

      // Update queue
      _queue.clear();
      _queue.add(newMediaItem);
      _currentIndex = 0;
      queue.add(_queue);
      mediaItem.add(newMediaItem);

      // Get audio URL
      final audioUrl = await _getAudioUrl(song.videoId);
      if (audioUrl == null) {
        throw Exception('Failed to get audio URL');
      }

      // Play audio
      await _audioPlayer.setUrl(audioUrl);
      await play();

      print('✅ [BackgroundAudioHandler] Playback started');

      // Load radio for this song
      _loadRadioInBackground(song);
    } catch (e, stack) {
      print('❌ [BackgroundAudioHandler] Error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
        ),
      );
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

  /// Load radio songs in background
  Future<void> _loadRadioInBackground(QuickPick song) async {
    if (_isLoadingRadio || _lastRadioVideoId == song.videoId) {
      print('⏳ [BackgroundAudioHandler] Radio already loaded for this song');
      return;
    }

    _isLoadingRadio = true;
    _lastRadioVideoId = song.videoId;

    try {
      print('📻 [BackgroundAudioHandler] Loading radio for: ${song.title}');

      final radioSongs = await _radioService.getRadioForSong(
        videoId: song.videoId,
        title: song.title,
        artist: song.artists,
        limit: 25,
      );

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

      _radioQueueIndex = -1; // Reset index
      print(
        '✅ [BackgroundAudioHandler] Radio loaded: ${_radioQueue.length} songs',
      );
    } catch (e) {
      print('⚠️ [BackgroundAudioHandler] Radio load failed: $e');
    } finally {
      _isLoadingRadio = false;
    }
  }

  /// Play a list of songs
  Future<void> playQueue(List<QuickPick> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    try {
      print('🎵 [BackgroundAudioHandler] Playing queue: ${songs.length} songs');

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
      final audioUrl = await _getAudioUrl(songs[_currentIndex].videoId);
      if (audioUrl == null) {
        throw Exception('Failed to get audio URL');
      }

      // Play audio
      await _audioPlayer.setUrl(audioUrl);
      await play();

      print('✅ [BackgroundAudioHandler] Queue playback started');
    } catch (e) {
      print('❌ [BackgroundAudioHandler] Queue error: $e');
    }
  }

  Future<String?> _getAudioUrl(String videoId) async {
    // Check cache
    if (_urlCache.containsKey(videoId)) {
      print('⚡ [BackgroundAudioHandler] Using cached URL');
      return _urlCache[videoId];
    }

    // Fetch new URL
    print('🔄 [BackgroundAudioHandler] Fetching audio URL...');
    final url = await _core.getAudioUrl(videoId);

    if (url != null) {
      _urlCache[videoId] = url;
      print('✅ [BackgroundAudioHandler] URL cached');
    }

    return url;
  }

  // ==================== AUDIO SERVICE CONTROLS ====================

  @override
  Future<void> play() async {
    await _audioPlayer.play();
  }

  @override
  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  @override
  Future<void> stop() async {
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
    print('⏭️ [BackgroundAudioHandler] Skip to next');

    // Priority 1: Manual queue
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      print('▶️ Playing next from manual queue');
      _currentIndex++;
      mediaItem.add(_queue[_currentIndex]);

      final audioUrl = await _getAudioUrl(_queue[_currentIndex].id);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await play();
      }
      return;
    }

    // Priority 2: Radio queue (autoplay)
    if (_radioQueue.isNotEmpty && _radioQueueIndex < _radioQueue.length - 1) {
      print('📻 Playing next from radio queue (autoplay)');
      _radioQueueIndex++;
      mediaItem.add(_radioQueue[_radioQueueIndex]);

      final audioUrl = await _getAudioUrl(_radioQueue[_radioQueueIndex].id);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await play();
      }
      return;
    }

    // Priority 3: Start radio queue if available
    if (_radioQueue.isNotEmpty && _radioQueueIndex == -1) {
      print('📻 Starting radio queue');
      _radioQueueIndex = 0;
      mediaItem.add(_radioQueue[_radioQueueIndex]);

      final audioUrl = await _getAudioUrl(_radioQueue[_radioQueueIndex].id);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await play();
      }
      return;
    }

    print('⚠️ [BackgroundAudioHandler] No next song available');
  }

  @override
  Future<void> skipToPrevious() async {
    print('⏮️ [BackgroundAudioHandler] Skip to previous');

    final position = _audioPlayer.position;

    // If more than 3 seconds into song, restart it
    if (position.inSeconds > 3) {
      print('🔄 Restarting current song');
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    // Priority 1: Manual queue
    if (_queue.isNotEmpty && _currentIndex > 0) {
      print('◀️ Playing previous from manual queue');
      _currentIndex--;
      mediaItem.add(_queue[_currentIndex]);

      final audioUrl = await _getAudioUrl(_queue[_currentIndex].id);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await play();
      }
      return;
    }

    // Priority 2: Radio queue
    if (_radioQueue.isNotEmpty && _radioQueueIndex > 0) {
      print('📻 Playing previous from radio queue');
      _radioQueueIndex--;
      mediaItem.add(_radioQueue[_radioQueueIndex]);

      final audioUrl = await _getAudioUrl(_radioQueue[_radioQueueIndex].id);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await play();
      }
      return;
    }

    print('⚠️ [BackgroundAudioHandler] No previous song available');
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      mediaItem.add(_queue[_currentIndex]);

      final audioUrl = await _getAudioUrl(_queue[_currentIndex].id);
      if (audioUrl != null) {
        await _audioPlayer.setUrl(audioUrl);
        await play();
      }
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
