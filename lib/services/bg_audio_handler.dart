import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/providers/RealTimeService.dart';
import 'package:vibeflow/services/audioGoverner.dart';
import 'package:vibeflow/services/cacheManager.dart';
import 'package:vibeflow/utils/audio_session_bridge.dart';

BackgroundAudioHandler? _globalAudioHandler;
BackgroundAudioHandler? getAudioHandler() {
  return _globalAudioHandler;
}

/// Background Audio Handler for persistent playback
/// Handles notification controls, lock screen controls, and background playback
class BackgroundAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  int? _audioSessionId;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final VibeFlowCore _core = VibeFlowCore();
  final RealtimeListeningTracker _tracker = RealtimeListeningTracker();
  final RadioService _radioService = RadioService();
  final Map<String, String> _urlCache = {};
  final Map<String, DateTime> _urlCacheTime = {};
  static const _cacheExpiry = Duration(hours: 2); // URLs expire after 2 hours

  // Updated connectivity subscription type
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  bool _wasPlayingBeforeDisconnect = false;
  bool _isUrlExpired = false;
  bool _isShuffleEnabled = false;
  AudioSession? _audioSession;
  DateTime? _lastSongChangeTime;

  // Settings
  bool _resumePlaybackEnabled = false;
  bool _persistentQueueEnabled = false;
  bool _loudnessNormalizationEnabled = false;

  // Added normalization constants for loudness
  static const double _targetLUFS = -14.0; // Standard loudness target
  static const double _normalizationBoost = 1.0; // Default multiplier

  // Current queue and playback state
  final _queue = <MediaItem>[];
  int _currentIndex = 0;
  LoopMode _loopMode = LoopMode.off;

  // Radio queue for autoplay
  final _radioQueue = <MediaItem>[];
  int _radioQueueIndex = -1;
  bool _isLoadingRadio = false;
  String? _lastRadioVideoId;
  String? _currentRadioSourceId;
  bool _isRefreshingUrl = false;
  bool _isChangingSong = false;
  // Radio SETTINGS
  static const int _initialRadioSize = 20;
  static const int _radioRefetchThreshold = 18; // Fetch more at song #18
  static const int _maxRadioQueueSize = 75;
  static const int _radioBatchSize = 20;

  final AudioGovernor _governor = AudioGovernor.instance;

  BackgroundAudioHandler() {
    _globalAudioHandler = this;
    _init();
  }

  // In the BackgroundAudioHandler class, update the init method:
  Future<void> _init() async {
    await _core.initialize();
    _setupAudioPlayer();
    await _setupAudioSession();
    _setupConnectivityListener();
    _tracker.setAudioPlayer(_audioPlayer);

    // Load saved settings
    await _loadSettings();

    print('✅ [BackgroundAudioHandler] Initialized');
  }

  // In bg_audio_handler.dart, update _loadSettings:
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _resumePlaybackEnabled =
          prefs.getBool('resume_playback_enabled') ?? false;
      _persistentQueueEnabled =
          prefs.getBool('persistent_queue_enabled') ?? false;
      _loudnessNormalizationEnabled =
          prefs.getBool('loudness_normalization_enabled') ?? false; // ADD THIS

      print(
        '⚙️ [Settings] Loaded - Resume: $_resumePlaybackEnabled, Queue: $_persistentQueueEnabled, Normalization: $_loudnessNormalizationEnabled',
      );

      // Apply normalization if enabled
      if (_loudnessNormalizationEnabled) {
        await _audioPlayer.setVolume(0.85); // Normalized volume
      }

      customState.add({
        ..._safeCustomState(),
        'resume_playback_enabled': _resumePlaybackEnabled,
        'persistent_queue_enabled': _persistentQueueEnabled,
        'loudness_normalization_enabled':
            _loudnessNormalizationEnabled, // ADD THIS
      });
    } catch (e) {
      print('❌ [Settings] Error loading settings: $e');
    }
  }

  // ==================== AUDIO SESSION SETUP ====================
  // Replace your entire _setupAudioSession method with this enhanced version

  // Replace your entire _setupAudioSession method with this enhanced version

  Future<void> _setupAudioSession() async {
    try {
      _audioSession = await AudioSession.instance;

      await _audioSession!.configure(const AudioSessionConfiguration.music());

      print('🎧 [AudioSession] Configured for music playback');

      // Handle audio interruptions (calls, alarms, etc.)
      _audioInterruptionSubscription = _audioSession!.interruptionEventStream
          .listen((event) {
            _handleAudioInterruption(event);
          });

      // Handle headphones being UNPLUGGED (becoming noisy)
      _audioSession!.becomingNoisyEventStream.listen((_) {
        print('🔇 [AudioSession] Audio becoming noisy (headphones unplugged)');
        _governor.onHeadphonesUnplugged();
        // Only set flag if currently playing
        if (_audioPlayer.playing) {
          print('   Setting _wasPlayingBeforeDisconnect = true');
          _wasPlayingBeforeDisconnect = true;
          pause();
        } else {
          print('   Not playing, setting _wasPlayingBeforeDisconnect = false');
          _wasPlayingBeforeDisconnect = false;
        }
      });

      // Listen for audio device changes (headphones connected/disconnected)
      _audioSession!.devicesChangedEventStream.listen((event) {
        print('🎧 [AudioSession] Devices changed');
        print(
          '   Added: ${event.devicesAdded.map((d) => '${d.name} (${d.type})').join(", ")}',
        );
        print(
          '   Removed: ${event.devicesRemoved.map((d) => '${d.name} (${d.type})').join(", ")}',
        );

        // ============= DEVICE ADDED LOGIC =============
        final hasNewAudioDevice = event.devicesAdded.any(
          (device) =>
              device.type == AudioDeviceType.bluetoothA2dp ||
              device.type == AudioDeviceType.bluetoothLe ||
              device.type == AudioDeviceType.bluetoothSco ||
              device.type == AudioDeviceType.wiredHeadphones ||
              device.type == AudioDeviceType.wiredHeadset,
        );
        // ADD THIS

        if (hasNewAudioDevice) {
          print('✅ [AudioSession] New audio device detected!');
          print('   📊 Current state:');
          print('      Resume setting: $_resumePlaybackEnabled');
          print('      Was playing before: $_wasPlayingBeforeDisconnect');
          print('      Has media: ${mediaItem.value != null}');
          print('      Has audio source: ${_audioPlayer.audioSource != null}');
          print('      Player state: ${_audioPlayer.processingState}');
          print('      Currently playing: ${_audioPlayer.playing}');
          // ADD THIS
          final isHeadphones = event.devicesAdded.any(
            (d) =>
                d.type == AudioDeviceType.wiredHeadphones ||
                d.type == AudioDeviceType.wiredHeadset,
          );

          final isBluetooth = event.devicesAdded.any(
            (d) =>
                d.type == AudioDeviceType.bluetoothA2dp ||
                d.type == AudioDeviceType.bluetoothLe,
          );

          if (isHeadphones) {
            _governor.onHeadphonesConnected(
              _wasPlayingBeforeDisconnect && _resumePlaybackEnabled,
            );
          } else if (isBluetooth) {
            _governor.onBluetoothConnected();
          }
          // Check ALL conditions
          if (!_resumePlaybackEnabled) {
            print('   ⏸️ Resume setting is OFF - not resuming');
            return;
          }

          if (!_wasPlayingBeforeDisconnect) {
            print('   ⏸️ Was not playing before disconnect - not resuming');
            return;
          }

          // If we get here, both conditions are true
          print('   ✅ All conditions met, attempting to resume...');

          // Check player state
          final currentMedia = mediaItem.value;
          final hasAudioSource = _audioPlayer.audioSource != null;
          final isIdle = _audioPlayer.processingState == ProcessingState.idle;
          final isAlreadyPlaying = _audioPlayer.playing;

          // CRITICAL FIX: If player says "playing" but has no audio source, it's lying
          if (isAlreadyPlaying && !hasAudioSource) {
            print(
              '   ⚠️ Player claims to be playing but has no audio source - treating as stopped',
            );
          } else if (isAlreadyPlaying && hasAudioSource) {
            print('   ℹ️ Already playing with audio source, no need to resume');
            _wasPlayingBeforeDisconnect = false;
            return;
          }

          if (currentMedia != null && hasAudioSource && !isIdle) {
            print('   🎵 Valid audio loaded, resuming in 500ms...');
            Future.delayed(const Duration(milliseconds: 500), () {
              if (!_audioPlayer.playing && _wasPlayingBeforeDisconnect) {
                print('   ▶️ RESUMING PLAYBACK NOW');
                play();
                _wasPlayingBeforeDisconnect = false;
              } else {
                print('   ⏸️ State changed during delay, not resuming');
              }
            });
          } else if (currentMedia != null) {
            // Has media but no audio source or is idle - need to reload
            print('   🔄 Has media but audio source lost, reloading...');
            final quickPick = _quickPickFromMediaItem(currentMedia);

            Future.delayed(const Duration(milliseconds: 500), () async {
              if (_wasPlayingBeforeDisconnect) {
                print('   🎵 RELOADING AND PLAYING SONG');
                await playSong(quickPick);
                _wasPlayingBeforeDisconnect = false;
              }
            });
          } else {
            print('   ⚠️ Cannot resume:');
            print('      Has media: ${currentMedia != null}');
            print('      Has audio source: $hasAudioSource');
            print('      Not idle: ${!isIdle}');
            print('   User needs to manually start playback');
            _wasPlayingBeforeDisconnect = false;
          }
        }

        // ============= DEVICE REMOVED LOGIC =============
        final hasRemovedAudioDevice = event.devicesRemoved.any(
          (device) =>
              device.type == AudioDeviceType.bluetoothA2dp ||
              device.type == AudioDeviceType.bluetoothLe ||
              device.type == AudioDeviceType.bluetoothSco ||
              device.type == AudioDeviceType.wiredHeadphones ||
              device.type == AudioDeviceType.wiredHeadset,
        );

        if (hasRemovedAudioDevice) {
          print('🎧 [AudioSession] Audio device removed');
          if (_audioPlayer.playing) {
            print('   Was playing, setting flag and pausing');
            _wasPlayingBeforeDisconnect = true;
            pause();
          } else {
            print('   Was not playing, no action needed');
          }
        }
      });
    } catch (e) {
      print('❌ [AudioSession] Setup failed: $e');
    }

    _initializeAudioEffects();
  }

  Future<void> _initializeAudioEffects() async {
    try {
      // Get audio session ID
      _audioSessionId = await AudioSessionBridge.getAudioSessionId();
      print('🎛️ [AudioEffects] Initialized with session ID: $_audioSessionId');
    } catch (e) {
      print('❌ [AudioEffects] Failed to initialize: $e');
    }
  }

  // Also update the _handleAudioInterruption method with better logging
  void _handleAudioInterruption(AudioInterruptionEvent event) {
    print('🎧 [AudioInterruption] Type: ${event.type}, Begin: ${event.begin}');

    if (event.begin) {
      _governor.onAudioInterruption(event.type.toString().split('.').last);
      // Interruption started
      switch (event.type) {
        case AudioInterruptionType.duck:
          print('🔉 [AudioInterruption] Ducking audio (lowering volume)');
          _audioPlayer.setVolume(0.3);
          break;

        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          print('⏸️ [AudioInterruption] Pausing playback');
          if (_audioPlayer.playing) {
            print('   Setting _wasPlayingBeforeDisconnect = true');
            _wasPlayingBeforeDisconnect = true;
            pause();
          } else {
            print(
              '   Not playing, setting _wasPlayingBeforeDisconnect = false',
            );
            _wasPlayingBeforeDisconnect = false;
          }
          break;
      }
    } else {
      _governor.onInterruptionEnded(
        _resumePlaybackEnabled && _wasPlayingBeforeDisconnect,
      );
      // Interruption ended
      if (event.type == AudioInterruptionType.duck) {
        print('🔊 [AudioInterruption] Restoring volume');
        _audioPlayer.setVolume(1.0);
      } else if (event.type == AudioInterruptionType.pause) {
        print('📊 [AudioInterruption] Ended - checking if should resume:');
        print('   Resume setting: $_resumePlaybackEnabled');
        print('   Was playing before: $_wasPlayingBeforeDisconnect');

        if (_resumePlaybackEnabled && _wasPlayingBeforeDisconnect) {
          print('▶️ [AudioInterruption] Auto-resuming');
          play();
          _wasPlayingBeforeDisconnect = false;
        } else if (!_resumePlaybackEnabled) {
          print('⏸️ [AudioInterruption] Not resuming - setting disabled');
        } else {
          print('⏸️ [AudioInterruption] Not resuming - was not playing');
        }
      }
    }
  }

  // ==================== CONNECTIVITY LISTENER (FIXED) ====================
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      // Handle list of connectivity results
      if (results.isNotEmpty) {
        _handleConnectivityChange(results.first);
      }
    });
  }

  Future<void> _handleConnectivityChange(ConnectivityResult result) async {
    print('🔌 [Connectivity] Changed to: $result');
    // ADD THIS
    if (result == ConnectivityResult.none) {
      _governor.onConnectionLost();
    } else {
      _governor.onConnectionRestored();
    }
    // Only auto-resume if setting is enabled
    if (!_resumePlaybackEnabled) {
      print('⏸️ [Connectivity] Resume disabled in settings');
      return;
    }

    if (_wasPlayingBeforeDisconnect && !_audioPlayer.playing) {
      final currentMedia = mediaItem.value;
      if (currentMedia != null && result != ConnectivityResult.none) {
        print('📶 [Connectivity] Connection restored, resuming playback...');
        await play();
      }
    }
  }

  // ==================== HELPER METHOD (ADDED) ====================
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

  void _setupAudioPlayer() {
    _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      _governor.updatePlayingState(isPlaying);
      _governor.updateProcessingState(processingState);

      if (processingState == ProcessingState.buffering) {
        _governor.onBuffering();
      }

      // Track playback state for auto-resume
      if (isPlaying) {
        _wasPlayingBeforeDisconnect = true;
      }

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

      if (processingState == ProcessingState.completed) {
        print('✅ Song completed, stopping tracking');
        _governor.onSongCompleted(mediaItem.value?.title ?? 'Unknown');
        _tracker.stopTracking();
      }

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
        print('✅ [BackgroundAudioHandler] Song completed');

        // Handle loop mode BEFORE calling skipToNext
        if (_loopMode == LoopMode.one) {
          print('🔁 [LoopMode.one] Restarting current song');
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.play();
          return; // Don't call skipToNext
        }

        print('⏭️ [BackgroundAudioHandler] Playing next...');
        skipToNext();
      }
    });

    // Listen for player errors with UI notification
    _audioPlayer.playbackEventStream.listen(
      (event) {
        // Check for errors in the event
        if (event.processingState == ProcessingState.idle &&
            !_audioPlayer.playing &&
            _audioPlayer.duration == null &&
            mediaItem.value != null) {
          // This indicates a source error occurred
          print('⚠️ [AudioPlayer] Detected potential source error');
          _governor.onPlaybackError(
            'Audio source error',
            mediaItem.value?.title ?? 'Unknown',
          );
          _notifyPlaybackError(
            'Audio source error detected',
            isSourceError: true,
          );
          _handle403ErrorRecovery();
        }
      },
      onError: (Object e, StackTrace st) {
        // This catches actual error events
        print('❌ [AudioPlayer] Error event: $e');
        print('   Stack trace: $st');

        final errorMessage = e.toString();
        final songTitle = mediaItem.value?.title ?? 'Unknown';

        // Notify governor about the error
        if (errorMessage.contains('403') ||
            errorMessage.contains('Response code: 403') ||
            errorMessage.contains('Source error')) {
          print('🔴 [AudioPlayer] 403 Error detected - notifying governor');
          _governor.on403Error();
          _notifyPlaybackError(
            'Stream expired (403). Tap RETRY to refresh.',
            isSourceError: true,
          );
          _handle403ErrorRecovery();
        } else if (errorMessage.contains('Unable to connect') ||
            errorMessage.contains('Connection')) {
          _governor.onPlaybackError(errorMessage, songTitle);
          _notifyPlaybackError(
            'Connection error. Check your internet.',
            isSourceError: false,
          );
        } else if (errorMessage.contains('HttpDataSource') ||
            errorMessage.contains('IOException')) {
          _governor.onPlaybackError(errorMessage, songTitle);
          _notifyPlaybackError('Network error occurred', isSourceError: true);
        } else {
          // Generic playback error
          _governor.onPlaybackError(errorMessage, songTitle);
          _notifyPlaybackError(
            'Playback failed: ${_sanitizeErrorMessage(errorMessage)}',
            isSourceError: true,
          );
        }
      },
    );
  }

  // In BackgroundAudioHandler class, add this public method:
  Future<void> stopImmediately() async {
    print('🚨 [BackgroundAudioHandler] Immediate stop requested');
    try {
      // Stop tracking
      await _tracker.stopTracking();

      // Stop audio player
      await _audioPlayer.stop();

      // Clear queues
      _queue.clear();
      _radioQueue.clear();
      queue.add([]);
      mediaItem.add(null);

      // Update playback state
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
          controls: [],
        ),
      );

      print('✅ [BackgroundAudioHandler] Immediate stop completed');
    } catch (e) {
      print('❌ [BackgroundAudioHandler] Error during immediate stop: $e');
    }
  }

  // Helper method to sanitize error messages for user display
  String _sanitizeErrorMessage(String error) {
    // Remove technical stack traces and make user-friendly
    if (error.contains('ExoPlaybackException')) {
      return 'Media playback error';
    }
    if (error.contains('SourceException')) {
      return 'Audio source error';
    }
    if (error.length > 100) {
      return error.substring(0, 97) + '...';
    }
    return error;
  }

  // Notify UI about playback errors
  void _notifyPlaybackError(String message, {bool isSourceError = false}) {
    print('📢 [Error Notification] $message (Source error: $isSourceError)');

    _updateCustomState({
      'playback_error': true,
      'error_message': message,
      'is_source_error': isSourceError,
      'error_timestamp': DateTime.now().millisecondsSinceEpoch,
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
    _governor.on403Error();
    final currentMedia = mediaItem.value;
    if (currentMedia == null) return;

    _isRefreshingUrl = true;
    _isUrlExpired = true;

    _updateCustomState({'url_expired': true, 'refreshing_url': true});

    try {
      print('🔄 [Auto-Refresh] URL expired, refreshing in background...');

      final audioCache = AudioUrlCache();
      await audioCache.remove(currentMedia.id);
      _urlCache.remove(currentMedia.id);
      _urlCacheTime.remove(currentMedia.id);

      final quickPick = _quickPickFromMediaItem(currentMedia);
      final freshUrl = await _core.getAudioUrl(
        currentMedia.id,
        song: quickPick,
      );

      if (freshUrl != null && freshUrl.isNotEmpty) {
        print('✅ [Auto-Refresh] Fresh URL obtained in background');
        _governor.onUrlRefreshSuccess();
        await _audioPlayer.setUrl(freshUrl);
        await _audioPlayer.play();

        await Future.delayed(const Duration(milliseconds: 300));
        await _tracker.startTracking(quickPick);

        _isUrlExpired = false;

        _updateCustomState({'url_expired': false, 'refreshing_url': false});

        print('✅ [Auto-Refresh] Playback resumed');
      } else {
        print('❌ [Auto-Refresh] Failed to get fresh URL');
        _updateCustomState({
          'url_expired': true,
          'refreshing_url': false,
          'refresh_failed': true,
        });
      }
    } catch (e) {
      print('❌ [Auto-Refresh] Error: $e');
      _updateCustomState({
        'url_expired': true,
        'refreshing_url': false,
        'refresh_failed': true,
      });
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
      _governor.onQueueAdd(mediaItem.title, _queue.length);
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
        _governor.onQueueRemove(mediaItem.title, _queue.length);

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

  Future<void> playSong(QuickPick song) async {
    // Safety: Force reset if last change was more than 5 seconds ago
    if (_isChangingSong && _lastSongChangeTime != null) {
      final timeSinceLastChange = DateTime.now().difference(
        _lastSongChangeTime!,
      );
      if (timeSinceLastChange.inSeconds > 5) {
        print(
          '⚠️ [HANDLER] Forcing reset - stuck for ${timeSinceLastChange.inSeconds}s',
        );
        _isChangingSong = false;
      }
    }

    // Prevent rapid concurrent calls
    if (_isChangingSong) {
      print('⏳ [HANDLER] Song change already in progress, waiting...');
      await Future.delayed(const Duration(milliseconds: 200));
      if (_isChangingSong) {
        print('❌ [HANDLER] Still changing after 200ms, aborting');
        return;
      }
    }

    _isChangingSong = true;
    _lastSongChangeTime = DateTime.now();

    try {
      print('🎵 [HANDLER] ========== PLAYING SONG ==========');
      print('   Title: ${song.title}');
      print('   VideoId: ${song.videoId}');

      _governor.onPlaySong(song.title, song.artists);

      // Check if same song is already playing
      // Check if EXACT same song is already playing (match by videoId AND title AND artist)
      final currentMedia = mediaItem.value;
      if (currentMedia != null &&
          currentMedia.id == song.videoId &&
          currentMedia.title == song.title &&
          currentMedia.artist == song.artists) {
        print('🎵 Exact same song already playing');
        if (!_audioPlayer.playing) {
          await _audioPlayer.play();
          _tracker.resumeTracking();
        }
        return;
      }

      // If videoId matches but title/artist different, it's a different version - continue playing
      if (currentMedia != null && currentMedia.id == song.videoId) {
        print(
          '🎵 Same videoId but different song (${song.title} vs ${currentMedia.title}) - playing new version',
        );
      }

      // CRITICAL: Set loading state IMMEDIATELY
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      print('🛑 [HANDLER] Stopping previous playback...');

      // CRITICAL: Stop in correct order
      await _tracker.stopTracking();
      await Future.delayed(const Duration(milliseconds: 100));

      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await _audioPlayer.stop();
      await Future.delayed(const Duration(milliseconds: 100));

      // 🔥 CRITICAL: Only clear radio if user explicitly selected a NEW source
      // Don't clear if they're just playing from the existing radio queue
      final isPlayingFromRadio = _radioQueue.any(
        (item) => item.id == song.videoId,
      );
      final isFirstSongInNewRadio = _currentRadioSourceId == null;
      final isDifferentSource =
          !isPlayingFromRadio &&
          _currentRadioSourceId != song.videoId &&
          !isFirstSongInNewRadio;

      print('🔍 [HANDLER] Source analysis:');
      print('   Is from radio: $isPlayingFromRadio');
      print('   Current source: $_currentRadioSourceId');
      print('   New song: ${song.videoId}');
      print('   Is different source: $isDifferentSource');

      if (isDifferentSource) {
        print('🗑️ [HANDLER] NEW SOURCE - Clearing old radio');
        print('   Old source: $_currentRadioSourceId');
        print('   New source: ${song.videoId}');

        _radioQueue.clear();
        _radioQueueIndex = -1;
        _lastRadioVideoId = null;
        _isLoadingRadio = false;
        _currentRadioSourceId = song.videoId;
        _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
      } else if (isPlayingFromRadio) {
        print('✅ [HANDLER] Playing from EXISTING radio, keeping intact');
        print('   Radio source: $_currentRadioSourceId');
        print(
          '   Song position in radio: ${_radioQueue.indexWhere((item) => item.id == song.videoId) + 1}/${_radioQueue.length}',
        );

        // 🔥 UPDATE radio index when playing from existing radio
        final radioPos = _radioQueue.indexWhere(
          (item) => item.id == song.videoId,
        );
        if (radioPos != -1) {
          _radioQueueIndex = radioPos;
          print('   Updated radio index to: $_radioQueueIndex');
        }
      }

      // Create new media item
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

      // Update queue and media item
      _queue.clear();
      _queue.add(newMediaItem);
      _currentIndex = 0;
      queue.add(_queue);

      // CRITICAL: Update mediaItem BEFORE getting audio URL
      mediaItem.add(newMediaItem);

      print('🔍 [HANDLER] Getting audio URL...');
      _governor.onLoadingUrl(song.title);

      final audioUrl = await _getAudioUrl(song.videoId, song: song);
      if (audioUrl == null) throw Exception('Failed to get audio URL');

      print('✅ [HANDLER] Audio URL obtained, setting player...');

      // CRITICAL: Set audio source with proper error handling
      try {
        await _audioPlayer.setUrl(audioUrl);
      } catch (e) {
        print('❌ [HANDLER] setUrl failed: $e');
        throw Exception('Failed to set audio source: $e');
      }

      print('▶️ [HANDLER] Starting playback...');
      await _audioPlayer.play();

      // Wait for duration
      print('⏱️ [HANDLER] Waiting for duration...');
      int attempts = 0;
      while (_audioPlayer.duration == null && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (_audioPlayer.duration != null) {
        print('✅ [HANDLER] Duration available: ${_audioPlayer.duration}');
        // Update mediaItem with duration
        mediaItem.add(newMediaItem.copyWith(duration: _audioPlayer.duration));
      } else {
        print('⚠️ [HANDLER] Duration still null after waiting');
      }

      print('📝 [HANDLER] Starting realtime tracking...');
      await _tracker.startTracking(song);

      print('✅ [HANDLER] ========== PLAYBACK STARTED ==========');

      // Cache URL
      AudioUrlCache().cache(song, audioUrl);

      // Load radio if needed
      final shouldLoadRadio = isDifferentSource || _radioQueue.isEmpty;

      if (shouldLoadRadio) {
        print('📻 [HANDLER] Loading radio (New source: $isDifferentSource)');
        _loadRadioImmediately(song);
      }
    } catch (e, stackTrace) {
      print('❌ [HANDLER] Error playing song: $e');
      print('   Stack: $stackTrace');

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ),
      );

      _notifyPlaybackError(
        'Failed to play: ${e.toString()}',
        isSourceError: true,
      );
    } finally {
      _isChangingSong = false;
    }
  }

  Future<bool> hardRefetchCurrentUrl() async {
    try {
      final currentMedia = mediaItem.value;
      if (currentMedia == null) {
        print('❌ [Hard Refetch] No current media item');
        return false;
      }

      print('🔄 [Hard Refetch] Forcing URL refresh for: ${currentMedia.title}');
      _governor.onUrlRefreshAttempt();

      // Clear all caches
      final audioCache = AudioUrlCache();
      await audioCache.remove(currentMedia.id);
      _urlCache.remove(currentMedia.id);
      _urlCacheTime.remove(currentMedia.id);

      // Get fresh URL
      final quickPick = _quickPickFromMediaItem(currentMedia);
      final freshUrl = await _core.getAudioUrl(
        currentMedia.id,
        song: quickPick,
      );

      if (freshUrl == null || freshUrl.isEmpty) {
        print('❌ [Hard Refetch] Failed to get fresh URL');
        _governor.onUrlRefreshFailed();
        return false;
      }

      print('✅ [Hard Refetch] Got fresh URL, setting audio source...');

      // Set new audio source
      await _audioPlayer.setUrl(freshUrl);
      await _audioPlayer.play();

      // Wait for playback to stabilize
      await Future.delayed(const Duration(milliseconds: 300));

      // Resume tracking
      await _tracker.startTracking(quickPick);

      // Cache the new URL
      _urlCache[currentMedia.id] = freshUrl;
      _urlCacheTime[currentMedia.id] = DateTime.now();
      await audioCache.cache(quickPick, freshUrl);

      // Clear error state
      _updateCustomState({
        'playback_error': false,
        'error_message': null,
        'is_source_error': false,
      });

      _governor.onUrlRefreshSuccess();
      print('✅ [Hard Refetch] Playback resumed successfully');
      return true;
    } catch (e) {
      print('❌ [Hard Refetch] Error: $e');
      _governor.onUrlRefreshFailed();
      return false;
    }
  }

  void clearPlaybackError() {
    _updateCustomState({
      'playback_error': false,
      'error_message': null,
      'is_source_error': false,
    });
  }

  Future<void> playSongFromRadio(QuickPick song) async {
    // Prevent concurrent song changes
    if (_isChangingSong) {
      print('⏳ [HANDLER] Song change already in progress, queuing...');
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isChangingSong) {
        print('❌ [HANDLER] Still changing, aborting duplicate request');
        return;
      }
    }

    _isChangingSong = true;

    try {
      print('🎵 [HANDLER] ========== PLAYING FROM RADIO ==========');
      print('   Title: ${song.title}');
      print('   VideoId: ${song.videoId}');

      _governor.onPlaySong(song.title, song.artists);

      // Check if EXACT same song is already playing
      final currentMedia = mediaItem.value;
      if (currentMedia != null &&
          currentMedia.id == song.videoId &&
          currentMedia.title == song.title &&
          currentMedia.artist == song.artists) {
        print('🎵 Same song already playing: ${song.title} by ${song.artists}');

        if (!_audioPlayer.playing) {
          print('   ▶️ Resuming paused playback');
          await _audioPlayer.play();
          _tracker.resumeTracking();
        } else {
          print('   ✅ Already playing, no action needed');
        }

        _isChangingSong = false;
        return;
      }

      // Different song - log what changed
      if (currentMedia != null) {
        print('🔄 Different song detected:');
        print('   Old: ${currentMedia.title} by ${currentMedia.artist}');
        print('   New: ${song.title} by ${song.artists}');
      }

      // CRITICAL: Set loading state IMMEDIATELY
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      print('🛑 [HANDLER] Stopping previous playback...');

      await _tracker.stopTracking();
      await Future.delayed(const Duration(milliseconds: 100));

      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await _audioPlayer.stop();
      await Future.delayed(const Duration(milliseconds: 100));

      print('✅ [HANDLER] Playing from radio source: $_currentRadioSourceId');

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

      // 🔥 CRITICAL FIX: Find the song in radio queue and update index
      final radioIndex = _radioQueue.indexWhere(
        (item) => item.id == song.videoId,
      );

      if (radioIndex != -1) {
        _radioQueueIndex = radioIndex;
        print('✅ [HANDLER] Found in radio queue at index: $_radioQueueIndex');
        print(
          '   Current position: ${_radioQueueIndex + 1}/${_radioQueue.length}',
        );
        print(
          '   Next skip will play: ${_radioQueueIndex + 1 < _radioQueue.length ? _radioQueue[_radioQueueIndex + 1].title : "End of queue"}',
        );
      } else {
        print('⚠️ [HANDLER] Song NOT found in radio queue!');
        print('   This should not happen - adding to end of queue');
        _radioQueue.add(newMediaItem);
        _radioQueueIndex = _radioQueue.length - 1;

        // Update UI with new queue
        final radioQueueData = _radioQueue.map((item) {
          return {
            'id': item.id,
            'title': item.title,
            'artist': item.artist ?? 'Unknown Artist',
            'artUri': item.artUri?.toString(),
            'duration': item.duration?.inMilliseconds,
          };
        }).toList();

        _updateCustomState({
          'radio_queue': radioQueueData,
          'radio_queue_count': radioQueueData.length,
        });
      }

      // Update manual queue
      if (_queue.isEmpty) {
        _queue.add(newMediaItem);
        _currentIndex = 0;
      } else {
        final existingIndex = _queue.indexWhere(
          (item) => item.id == song.videoId,
        );
        if (existingIndex != -1) {
          _currentIndex = existingIndex;
        } else {
          _queue.add(newMediaItem);
          _currentIndex = _queue.length - 1;
        }
      }

      queue.add(_queue);

      // 🔥 CRITICAL FIX: Update mediaItem BEFORE getting URL
      // This prevents metadata mismatch
      mediaItem.add(newMediaItem);

      // Small delay to ensure UI updates
      await Future.delayed(const Duration(milliseconds: 50));

      print('🔍 [HANDLER] Getting audio URL...');
      _governor.onLoadingUrl(song.title);

      final audioUrl = await _getAudioUrl(song.videoId, song: song);
      if (audioUrl == null) throw Exception('Failed to get audio URL');

      print('✅ [HANDLER] Audio URL obtained, setting player...');

      try {
        await _audioPlayer.setUrl(audioUrl);
      } catch (e) {
        print('❌ [HANDLER] setUrl failed: $e');
        throw Exception('Failed to set audio source: $e');
      }

      print('▶️ [HANDLER] Starting playback...');
      await _audioPlayer.play();

      // Wait for duration
      int attempts = 0;
      while (_audioPlayer.duration == null && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (_audioPlayer.duration != null) {
        mediaItem.add(newMediaItem.copyWith(duration: _audioPlayer.duration));
      }

      print('📝 [HANDLER] Starting realtime tracking...');
      await _tracker.startTracking(song);

      print('✅ [HANDLER] ========== PLAYBACK STARTED FROM RADIO ==========');
      print(
        '   Radio queue position: ${_radioQueueIndex + 1}/${_radioQueue.length}',
      );
      print('   Radio source ID: $_currentRadioSourceId');

      // Cache URL but DON'T reload radio
      AudioUrlCache().cache(song, audioUrl);
    } catch (e, stackTrace) {
      print('❌ [HANDLER] Error playing from radio: $e');
      print('   Stack: $stackTrace');

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ),
      );

      _notifyPlaybackError(
        'Failed to play: ${e.toString()}',
        isSourceError: true,
      );
    } finally {
      _isChangingSong = false;
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

  // ==================== FIXED setLoopMode() METHOD ====================
  // In BackgroundAudioHandler class, update the setLoopMode method:
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;

    // Sync with audio player
    await _audioPlayer.setLoopMode(mode);

    // Also sync with AudioService repeat mode
    switch (mode) {
      case LoopMode.off:
        await super.setRepeatMode(AudioServiceRepeatMode.none);
        break;
      case LoopMode.one:
        await super.setRepeatMode(AudioServiceRepeatMode.one);
        break;
      case LoopMode.all:
        await super.setRepeatMode(AudioServiceRepeatMode.all);
        break;
    }

    _governor.onLoopModeChange(mode);
    print('🔁 [LoopMode] Set to: $mode');

    _updateCustomState({'loop_mode': mode.index});
  }

  Future<void> _setLoopMode(LoopMode mode) async {
    print('🔄 [Handler] Applying loop mode: $mode');

    // Update just_audio
    await _audioPlayer.setLoopMode(
      mode == LoopMode.one
          ? LoopMode.one
          : mode == LoopMode.all
          ? LoopMode.all
          : LoopMode.off,
    );

    // 🔥 Update customState so UI can react
    final current = Map<String, dynamic>.from(customState.value ?? {});
    current['loop_mode'] = mode.index;

    customState.add(current);
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'set_loop_mode':
        final index = extras?['loop_mode'] as int? ?? 0;
        final mode = LoopMode.values[index];
        await _setLoopMode(mode);
        return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    _isShuffleEnabled = enabled;

    print('🔀 [Shuffle] ${enabled ? "Enabled" : "Disabled"}');
    if (enabled) {
      _governor.onShuffleEnabled();
    } else {
      _governor.onShuffleDisabled();
    }
    _updateCustomState({'shuffle_enabled': enabled});

    if (enabled && _radioQueue.isNotEmpty) {
      _shuffleRadioQueue();
    }
  }

  // Helper method for UI
  Future<void> toggleShuffleMode() async {
    final newMode = _isShuffleEnabled
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    await setShuffleMode(newMode);
  }

  void _shuffleRadioQueue() {
    if (_radioQueue.isEmpty) return;

    final random = Random();
    for (var i = _radioQueue.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = _radioQueue[i];
      _radioQueue[i] = _radioQueue[j];
      _radioQueue[j] = temp;
    }

    // Update custom state with shuffled queue
    final radioQueueData = _radioQueue.map((item) {
      return {
        'id': item.id,
        'title': item.title,
        'artist': item.artist ?? 'Unknown Artist',
        'artUri': item.artUri?.toString(),
        'duration': item.duration?.inMilliseconds,
      };
    }).toList();

    _updateCustomState({
      'radio_queue': radioQueueData,
      'radio_queue_count': radioQueueData.length,
    });

    print('🔀 [Radio] Queue shuffled: ${_radioQueue.length} songs');
  }

  // ==================== FIXED LOOP MODE METHOD ====================
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    LoopMode loopMode;

    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        loopMode = LoopMode.off;
        break;
      case AudioServiceRepeatMode.one:
        loopMode = LoopMode.one;
        break;
      case AudioServiceRepeatMode.all:
        loopMode = LoopMode.all;
        break;
      default:
        loopMode = LoopMode.off;
    }

    _loopMode = loopMode;
    await _audioPlayer.setLoopMode(loopMode);

    print('🔁 [LoopMode] Set to: $loopMode');

    _updateCustomState({'loop_mode': loopMode.index});
  }

  // Helper method for UI
  // Helper method for UI - fix the logic
  Future<void> toggleLoopMode() async {
    LoopMode newMode;

    switch (_loopMode) {
      case LoopMode.off:
        newMode = LoopMode.all;
        break;
      case LoopMode.all:
        newMode = LoopMode.one;
        break;
      case LoopMode.one:
        newMode = LoopMode.off;
        break;
      default:
        newMode = LoopMode.off;
    }

    await setLoopMode(newMode);
  }

  // ==================== SETTINGS METHODS ====================
  // Update the setResumePlaybackEnabled method:
  Future<void> setResumePlaybackEnabled(bool enabled) async {
    _resumePlaybackEnabled = enabled;
    print('⚙️ [Settings] Resume playback: ${enabled ? "ON" : "OFF"}');

    // Save to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('resume_playback_enabled', enabled);
      print('✅ [Settings] Resume playback saved to storage');
    } catch (e) {
      print('❌ [Settings] Error saving resume playback: $e');
    }

    customState.add({
      ..._safeCustomState(),
      'resume_playback_enabled': enabled,
    });
  }

  Future<void> setPersistentQueueEnabled(bool enabled) async {
    _persistentQueueEnabled = enabled;
    print('⚙️ [Settings] Persistent queue: ${enabled ? "ON" : "OFF"}');

    // Save to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('persistent_queue_enabled', enabled);
      print('✅ [Settings] Persistent queue saved to storage');
    } catch (e) {
      print('❌ [Settings] Error saving persistent queue: $e');
    }

    customState.add({
      ..._safeCustomState(),
      'persistent_queue_enabled': enabled,
    });
  }

  Future<void> setLoudnessNormalizationEnabled(bool enabled) async {
    _loudnessNormalizationEnabled = enabled;
    print('⚙️ [Settings] Loudness normalization: ${enabled ? "ON" : "OFF"}');

    // Apply normalization
    if (enabled) {
      await _audioPlayer.setVolume(0.85); // Normalized volume level
      print('🔊 [Normalization] Applied normalized volume: 0.85');
    } else {
      await _audioPlayer.setVolume(1.0); // Full volume
      print('🔊 [Normalization] Reset to full volume: 1.0');
    }

    // Save to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loudness_normalization_enabled', enabled);
      print('✅ [Settings] Loudness normalization saved to storage');
    } catch (e) {
      print('❌ [Settings] Error saving loudness normalization: $e');
    }

    customState.add({
      ..._safeCustomState(),
      'loudness_normalization_enabled': enabled,
    });
  }

  // ============================================================================
  // FIXED _loadRadioImmediately() METHOD
  // Replace your existing _loadRadioImmediately() with this
  // ============================================================================

  Future<void> _loadRadioImmediately(QuickPick song) async {
    print('📻 [Radio] _loadRadioImmediately called for: ${song.title}');
    print('   VideoId: ${song.videoId}');
    print('   Current _isLoadingRadio: $_isLoadingRadio');
    print('   Current _lastRadioVideoId: $_lastRadioVideoId');
    print('   Current _radioQueue.length: ${_radioQueue.length}');

    // Layer 1: Check if already loading
    if (_isLoadingRadio) {
      print('⏳ [Radio] Already loading radio, skipping');
      return;
    }

    // Layer 2: Check if we already have radio for this exact song
    if (_lastRadioVideoId == song.videoId && _radioQueue.isNotEmpty) {
      print('✅ [Radio] Radio already loaded for ${song.videoId}');
      print('   Queue size: ${_radioQueue.length}');

      // 🔥 CRITICAL FIX: Re-publish to UI to ensure both players see it
      final radioQueueData = _radioQueue.map((item) {
        return {
          'id': item.id,
          'title': item.title,
          'artist': item.artist ?? 'Unknown Artist',
          'artUri': item.artUri?.toString(),
          'duration': item.duration?.inMilliseconds,
        };
      }).toList();

      _updateCustomState({
        'radio_queue': radioQueueData,
        'radio_queue_count': radioQueueData.length,
      });

      return;
    }

    // Continue with rest of the method (unchanged)...
    _isLoadingRadio = true;
    _lastRadioVideoId = song.videoId;
    _governor.onRadioStart(song.title);

    print('🔄 [Radio] Starting radio load...');

    try {
      print('📻 [Radio] Calling RadioService.getRadioForSong...');

      final radioSongs = await _radioService.getRadioForSong(
        videoId: song.videoId,
        title: song.title,
        artist: song.artists,
        limit: 25,
      );

      print('📻 [Radio] RadioService returned ${radioSongs.length} songs');

      if (radioSongs.isEmpty) {
        print('⚠️ [Radio] No radio songs returned');
        _governor.onRadioQueueEmpty();
        _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
        return;
      }

      print(
        '✅ [Radio] Got ${radioSongs.length} songs, converting to MediaItems...',
      );

      _radioQueue.clear();

      int successCount = 0;
      for (final song in radioSongs) {
        try {
          final mediaItem = MediaItem(
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

          _radioQueue.add(mediaItem);
          successCount++;
        } catch (e) {
          print('⚠️ [Radio] Failed to convert song ${song.title}: $e');
        }
      }

      print(
        '✅ [Radio] Successfully added $successCount MediaItems to _radioQueue',
      );
      print('   _radioQueue.length is now: ${_radioQueue.length}');

      if (_radioQueue.isEmpty) {
        print(
          '❌ [Radio] CRITICAL ERROR: _radioQueue is still empty after adding!',
        );
        _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
        return;
      }

      if (_isShuffleEnabled) {
        print('🔀 [Radio] Shuffling queue...');
        _shuffleRadioQueue();
      }

      _radioQueueIndex = -1;
      print('   Reset _radioQueueIndex to: $_radioQueueIndex');

      print('📢 [Radio] Publishing to customState...');

      final radioQueueData = _radioQueue.map((item) {
        return {
          'id': item.id,
          'title': item.title,
          'artist': item.artist ?? 'Unknown Artist',
          'artUri': item.artUri?.toString(),
          'duration': item.duration?.inMilliseconds,
        };
      }).toList();

      print('   radioQueueData.length: ${radioQueueData.length}');

      _updateCustomState({
        'radio_queue': radioQueueData,
        'radio_queue_count': radioQueueData.length,
      });

      print('✅ [Radio] ========== RADIO LOADED SUCCESSFULLY ==========');
      print('   Total songs: ${_radioQueue.length}');
      print('   Radio source: $_currentRadioSourceId');
      print('   Published to UI: ${radioQueueData.length} songs');
      print('=========================================================');
    } catch (e, stackTrace) {
      print('❌ [Radio] Load failed with exception: $e');
      print('   Stack trace:');
      print(stackTrace.toString().split('\n').take(5).join('\n'));

      _radioQueue.clear();
      _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
    } finally {
      _isLoadingRadio = false;
      print('🏁 [Radio] Finished loading (success or fail)');
      print('   Final _radioQueue.length: ${_radioQueue.length}');
      print('   Final _isLoadingRadio: $_isLoadingRadio');
    }
  } // ============================================================================
  // INTELLIGENT RADIO QUEUE EXPANSION
  // ============================================================================

  Future<void> _checkAndFetchMoreRadio() async {
    // Don't fetch if already loading
    if (_isLoadingRadio) {
      print('⏳ [Radio Expansion] Already loading, skipping');
      return;
    }

    final currentPosition = _radioQueueIndex + 1; // Human-readable position
    final queueSize = _radioQueue.length;

    print('📊 [Radio Expansion] Check: Position $currentPosition/$queueSize');

    // Calculate which "batch" we're in (every 20 songs = 1 batch)
    final currentBatch = (currentPosition / _initialRadioSize).floor();
    final positionInBatch = currentPosition % _initialRadioSize;

    print('   Batch: $currentBatch, Position in batch: $positionInBatch');

    // Trigger condition: At song #18 of any batch (18, 38, 58, etc.)
    final isAtThreshold = positionInBatch == _radioRefetchThreshold;

    if (!isAtThreshold) {
      return; // Not at threshold yet
    }

    print(
      '🎯 [Radio Expansion] Threshold reached at position $currentPosition!',
    );

    // Check if we've hit max queue size (75 songs)
    if (queueSize >= _maxRadioQueueSize) {
      print(
        '⚠️ [Radio Expansion] Max queue size reached ($queueSize/$_maxRadioQueueSize)',
      );
      print('   Will clear and restart on next threshold');

      // Check if we're near the end (song 73+)
      final nearEnd = currentPosition >= _maxRadioQueueSize - 2;

      if (nearEnd) {
        print(
          '🔄 [Radio Expansion] Near end of max queue, preparing to reset...',
        );

        // Get the CURRENT song to base new radio on
        final currentSong = _radioQueue[_radioQueueIndex];

        // Clear everything and fetch fresh
        _radioQueue.clear();
        _radioQueueIndex = -1;
        _lastRadioVideoId = null;
        _currentRadioSourceId = currentSong.id;

        print(
          '🗑️ [Radio Expansion] Cleared queue, fetching fresh 20 based on: ${currentSong.title}',
        );

        final quickPick = _quickPickFromMediaItem(currentSong);
        await _loadRadioImmediately(quickPick);

        return;
      }

      return; // Don't fetch more if at max but not near end
    }

    // Get the current song (the 18th, 38th, 58th, etc.)
    final seedSong = _radioQueue[_radioQueueIndex];

    print(
      '🌱 [Radio Expansion] Using seed song: ${seedSong.title} by ${seedSong.artist}',
    );
    print('   Fetching $_radioBatchSize more songs...');

    _isLoadingRadio = true;

    try {
      // Calculate how many songs we can actually add
      final remainingSpace = _maxRadioQueueSize - queueSize;
      final songsToFetch = remainingSpace < _radioBatchSize
          ? remainingSpace
          : _radioBatchSize;

      print(
        '   Can add $songsToFetch songs (${queueSize} + $songsToFetch = ${queueSize + songsToFetch})',
      );

      // Fetch more radio songs based on current song
      final newRadioSongs = await _radioService.getRadioForSong(
        videoId: seedSong.id,
        title: seedSong.title,
        artist: seedSong.artist ?? 'Unknown Artist',
        limit: songsToFetch,
      );

      if (newRadioSongs.isEmpty) {
        print('⚠️ [Radio Expansion] No new songs returned');
        return;
      }

      print('✅ [Radio Expansion] Got ${newRadioSongs.length} new songs');

      // Convert to MediaItems and APPEND to existing queue
      int addedCount = 0;
      for (final song in newRadioSongs) {
        try {
          // Skip if song already exists in queue (avoid duplicates)
          final alreadyExists = _radioQueue.any(
            (item) => item.id == song.videoId,
          );
          if (alreadyExists) {
            print('   ⏭️ Skipping duplicate: ${song.title}');
            continue;
          }

          final mediaItem = MediaItem(
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

          _radioQueue.add(mediaItem);
          addedCount++;

          // Stop if we hit max size
          if (_radioQueue.length >= _maxRadioQueueSize) {
            print('   🛑 Reached max queue size, stopping');
            break;
          }
        } catch (e) {
          print('   ⚠️ Failed to add song ${song.title}: $e');
        }
      }

      print('✅ [Radio Expansion] Added $addedCount new songs');
      print('   New queue size: ${_radioQueue.length}/$_maxRadioQueueSize');

      // Update UI with expanded queue
      final radioQueueData = _radioQueue.map((item) {
        return {
          'id': item.id,
          'title': item.title,
          'artist': item.artist ?? 'Unknown Artist',
          'artUri': item.artUri?.toString(),
          'duration': item.duration?.inMilliseconds,
        };
      }).toList();

      _updateCustomState({
        'radio_queue': radioQueueData,
        'radio_queue_count': radioQueueData.length,
      });

      print('🎉 [Radio Expansion] ========== EXPANSION COMPLETE ==========');
      print('   Total queue: ${_radioQueue.length} songs');
      print('   Current position: ${_radioQueueIndex + 1}');
      print('   Remaining: ${_radioQueue.length - _radioQueueIndex - 1} songs');
      print('===========================================================');
    } catch (e, stackTrace) {
      print('❌ [Radio Expansion] Failed: $e');
      print(
        '   Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );
    } finally {
      _isLoadingRadio = false;
    }
  }
  // ============================================================================
  // HELPER: Verify radio queue is actually populated
  // ============================================================================

  Future<void> _waitForRadioToLoad() async {
    print('⏳ [Radio] Waiting for radio to load...');

    int attempts = 0;
    const maxAttempts = 30; // 3 seconds max wait

    while (_isLoadingRadio && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;

      if (attempts % 10 == 0) {
        print('   Still waiting... (${attempts * 100}ms)');
      }
    }

    if (_isLoadingRadio) {
      print('⚠️ [Radio] Timeout waiting for radio to load');
    } else {
      print('✅ [Radio] Radio loading completed');
      print('   Final queue size: ${_radioQueue.length}');
    }
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
        _governor.onCacheHit(cacheAge.inMinutes);
        return _urlCache[videoId];
      } else {
        print('🗑️ [Internal Cache] Expired, removing');
        _urlCache.remove(videoId);
        _urlCacheTime.remove(videoId);
      }
    }
    _governor.onCacheMiss();
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
    _governor.onResume(_audioPlayer.position);
    await _audioPlayer.play();
    _tracker.resumeTracking();
  }

  @override
  Future<void> pause() async {
    _governor.onPause(_audioPlayer.position);
    await _audioPlayer.pause();
    await _tracker.pauseTracking();
  }

  @override
  Future<void> stop() async {
    _governor.onStop();
    await _tracker.stopTracking();
    await _connectivitySubscription?.cancel();
    await _audioInterruptionSubscription?.cancel();
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _governor.onSeek(position);
    await _audioPlayer.seek(position);
  }

  // ============================================================================
  // FIXED skipToNext() METHOD
  // Replace your existing skipToNext() with this complete implementation
  // ============================================================================

  @override
  Future<void> skipToNext() async {
    print('⏭️ [SKIP] Skip to next requested');
    _governor.onSkipForward();

    // CRITICAL: Check radio queue status BEFORE stopping tracking
    print('📊 [SKIP] Current state:');
    print('   Manual queue: ${_queue.length} songs, index: $_currentIndex');
    print(
      '   Radio queue: ${_radioQueue.length} songs, index: $_radioQueueIndex',
    );
    print('   Loop mode: $_loopMode');

    await _tracker.stopTracking();

    MediaItem? nextMedia;
    QuickPick? nextSong;

    // Handle LoopMode.one - restart current song
    if (_loopMode == LoopMode.one) {
      print('🔁 [LoopMode.one] Restarting current song');
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      return;
    }

    // ============================================================================
    // PRIORITY SYSTEM FOR NEXT SONG SELECTION
    // ============================================================================

    // Priority 1: Check manual queue (has more songs)
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      nextMedia = _queue[_currentIndex];
      print(
        '✅ [SKIP] Next from manual queue [${_currentIndex + 1}/${_queue.length}]: ${nextMedia.title}',
      );
    }
    // Priority 2: Loop all - restart manual queue
    else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      nextMedia = _queue[_currentIndex];
      print('🔁 [LoopMode.all] Looping back to start of manual queue');
    }
    // Priority 3: Start radio queue (first time)
    else if (_radioQueue.isNotEmpty && _radioQueueIndex == -1) {
      print('📻 [SKIP] Starting radio queue (first song)');
      _radioQueueIndex = 0;
      nextMedia = _radioQueue[_radioQueueIndex];
      print('   Playing: ${nextMedia.title}');
    }
    // Priority 3.5: Wait for radio if it's loading
    else if (_radioQueue.isEmpty && _isLoadingRadio) {
      print('⏳ [SKIP] Radio is loading, waiting...');

      // Wait up to 3 seconds for radio to load
      int attempts = 0;
      while (_isLoadingRadio && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      print(
        '✅ [SKIP] Radio loading completed, queue size: ${_radioQueue.length}',
      );

      // Try again now that radio might be loaded
      if (_radioQueue.isNotEmpty) {
        _radioQueueIndex = 0;
        nextMedia = _radioQueue[_radioQueueIndex];
        print('📻 [SKIP] Now starting radio queue: ${nextMedia.title}');
      }
    }
    // Priority 4: Continue in radio queue
    // Priority 4: Continue in radio queue
    else if (_radioQueue.isNotEmpty &&
        _radioQueueIndex >= 0 &&
        _radioQueueIndex < _radioQueue.length - 1) {
      _radioQueueIndex++;
      nextMedia = _radioQueue[_radioQueueIndex];
      print(
        '📻 [SKIP] Next from radio queue [${_radioQueueIndex + 1}/${_radioQueue.length}]: ${nextMedia.title}',
      );

      // 🔥 CRITICAL: Check if we need to fetch more radio songs
      await _checkAndFetchMoreRadio();
    }

    // ADD this debug logging right after the above section:

    if (nextMedia != null) {
      print('🎵 [SKIP] ========== NEXT SONG SELECTED ==========');
      print('   Song: ${nextMedia.title}');
      print(
        '   Source: ${_radioQueueIndex >= 0 ? "Radio queue" : "Manual queue"}',
      );
      print('   Radio index: ${_radioQueueIndex + 1}/${_radioQueue.length}');
      print('   Manual index: ${_currentIndex + 1}/${_queue.length}');
      print('===================================================');
    }
    // Priority 5: End of radio queue reached
    else if (_radioQueue.isNotEmpty &&
        _radioQueueIndex >= _radioQueue.length - 1) {
      print('⚠️ [SKIP] End of radio queue reached');
      // Could optionally loop radio or stop
      if (_loopMode == LoopMode.all) {
        _radioQueueIndex = 0;
        nextMedia = _radioQueue[_radioQueueIndex];
        print('🔁 [SKIP] Looping radio queue from start');
      } else {
        print('🛑 [SKIP] No loop mode, stopping playback');
        // Set idle state and stop
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
            playing: false,
          ),
        );
        return;
      }
    }

    // ============================================================================
    // PLAY THE NEXT SONG
    // ============================================================================

    if (nextMedia != null) {
      print('🎵 [SKIP] Playing next song: ${nextMedia.title}');

      nextSong = _quickPickFromMediaItem(nextMedia);

      // CRITICAL: Set loading state FIRST (fixes play/pause icon)
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      // Update media item
      mediaItem.add(nextMedia);

      try {
        // Get audio URL
        print('🔍 [SKIP] Getting audio URL...');
        final audioUrl = await _getAudioUrl(nextMedia.id, song: nextSong);

        if (audioUrl == null) {
          throw Exception('Failed to get audio URL for ${nextMedia.title}');
        }

        print('✅ [SKIP] Got audio URL, setting player...');

        // Set audio source
        try {
          await _audioPlayer.setUrl(audioUrl);
        } catch (e) {
          throw Exception('Failed to set audio source: $e');
        }

        // Start playback
        print('▶️ [SKIP] Starting playback...');
        await _audioPlayer.play();

        // Wait for audio to stabilize
        await Future.delayed(const Duration(milliseconds: 300));

        // Start tracking
        print('📝 [SKIP] Starting tracking...');
        await _tracker.startTracking(nextSong);

        print('✅ [SKIP] Successfully playing: ${nextMedia.title}');
        return;
      } catch (e, stackTrace) {
        print('❌ [SKIP] Error playing next song: $e');
        print('   Stack: $stackTrace');

        // Set error state
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );

        // Notify user
        _notifyPlaybackError(
          'Failed to skip: ${e.toString()}',
          isSourceError: true,
        );
        return;
      }
    }

    // ============================================================================
    // NO NEXT SONG AVAILABLE - DIAGNOSTIC LOGGING
    // ============================================================================

    print('❌ [SKIP] ========== NO NEXT SONG AVAILABLE ==========');
    print(
      '   Manual queue: ${_queue.length} songs (current index: $_currentIndex)',
    );
    print(
      '   Radio queue: ${_radioQueue.length} songs (current index: $_radioQueueIndex)',
    );
    print('   Loop mode: $_loopMode');
    print('   Current radio source: $_currentRadioSourceId');
    print('   Last radio video ID: $_lastRadioVideoId');
    print('   Is loading radio: $_isLoadingRadio');
    print('   Current media: ${mediaItem.value?.title ?? "null"}');
    print('   Current media ID: ${mediaItem.value?.id ?? "null"}');

    if (_radioQueue.isEmpty && !_isLoadingRadio) {
      print('   ❌ CRITICAL ISSUE: Radio queue is EMPTY and NOT loading!');
      print('   This means:');
      print('      1. Radio never loaded for this song, OR');
      print('      2. Radio was cleared incorrectly, OR');
      print('      3. Radio load failed silently');

      // Try to force load radio now
      final currentMedia = mediaItem.value;
      if (currentMedia != null) {
        print('   🔄 Attempting emergency radio load...');
        final emergencySong = _quickPickFromMediaItem(currentMedia);
        _loadRadioImmediately(emergencySong);

        // Wait a bit
        await Future.delayed(const Duration(seconds: 2));

        if (_radioQueue.isNotEmpty) {
          print(
            '   ✅ Emergency radio load succeeded! Queue: ${_radioQueue.length}',
          );
          _radioQueueIndex = 0;
          nextMedia = _radioQueue[_radioQueueIndex];

          // Continue with playback
          print('🎵 [SKIP] Playing emergency radio song: ${nextMedia!.title}');
          nextSong = _quickPickFromMediaItem(nextMedia);

          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.loading,
              playing: false,
            ),
          );

          mediaItem.add(nextMedia);

          try {
            final audioUrl = await _getAudioUrl(nextMedia.id, song: nextSong);
            if (audioUrl != null) {
              await _audioPlayer.setUrl(audioUrl);
              await _audioPlayer.play();
              await Future.delayed(const Duration(milliseconds: 300));
              await _tracker.startTracking(nextSong);
              print('✅ [SKIP] Emergency playback successful!');
              return;
            }
          } catch (e) {
            print('❌ [SKIP] Emergency playback failed: $e');
          }
        } else {
          print('   ❌ Emergency radio load also failed');
        }
      }
    }

    if (_radioQueue.isEmpty && _isLoadingRadio) {
      print('   ⏳ TIMING ISSUE: Radio is still loading');
      print('   User skipped before radio finished loading');
    }

    if (_radioQueue.isNotEmpty) {
      print('   ⚠️ LOGIC ISSUE: Radio queue exists but logic failed!');
      print('   This should never happen with the new priority system');
      print('   First 3 radio songs:');
      for (int i = 0; i < _radioQueue.length.clamp(0, 3); i++) {
        print('      [$i] ${_radioQueue[i].title}');
      }
    }

    print('=====================================================');

    // Set idle state
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
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
    _governor.onSkipBackward(position);
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
    _governor.onFastForward();
    await seek(_audioPlayer.position + const Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    _governor.onRewind();
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

  // Add this helper method at the end of the class (before getters):
  void _updateCustomState(Map<String, dynamic> updates) {
    if (!customState.hasValue) {
      customState.add(updates);
    } else {
      customState.add({..._safeCustomState(), ...updates});
    }
  }

  Map<String, dynamic> _safeCustomState() {
    if (!customState.hasValue) {
      return <String, dynamic>{};
    }

    final current = customState.value;
    if (current is Map<String, dynamic>) return current;
    return <String, dynamic>{};
  }

  // ==================== GETTERS ====================

  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;
  bool get isUrlExpired => _isUrlExpired;
  bool get isShuffleEnabled => _isShuffleEnabled;
  LoopMode get currentLoopMode => _loopMode;
  bool get resumePlaybackEnabled => _resumePlaybackEnabled;
  bool get persistentQueueEnabled => _persistentQueueEnabled;
  bool get loudnessNormalizationEnabled => _loudnessNormalizationEnabled;
  int? get audioSessionId => _audioSessionId;
}
