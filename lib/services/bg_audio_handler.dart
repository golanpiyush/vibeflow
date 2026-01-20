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

BackgroundAudioHandler? _globalAudioHandler;
BackgroundAudioHandler? getAudioHandler() {
  return _globalAudioHandler;
}

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

  // Updated connectivity subscription type
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  bool _wasPlayingBeforeDisconnect = false;
  bool _isUrlExpired = false;
  bool _isShuffleEnabled = false;
  AudioSession? _audioSession;

  // Settings
  bool _resumePlaybackEnabled = false;
  bool _persistentQueueEnabled = false;

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

  // Add this new method to load settings:
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _resumePlaybackEnabled =
          prefs.getBool('resume_playback_enabled') ?? false;
      _persistentQueueEnabled =
          prefs.getBool('persistent_queue_enabled') ?? false;

      print(
        '⚙️ [Settings] Loaded - Resume: $_resumePlaybackEnabled, Queue: $_persistentQueueEnabled',
      );

      // Update custom state
      customState.add({
        ..._safeCustomState(),
        'resume_playback_enabled': _resumePlaybackEnabled,
        'persistent_queue_enabled': _persistentQueueEnabled,
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
      // ADD THESE
      _governor.updatePlayingState(isPlaying);
      _governor.updateProcessingState(processingState);
      // ADD THIS for buffering
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
        print('✅ [BackgroundAudioHandler] Song completed, playing next...');
        skipToNext();
      }
    });

    _audioPlayer.playbackEventStream.listen((event) async {
      if (event.processingState == ProcessingState.idle &&
          event.currentIndex == null &&
          !_audioPlayer.playing) {
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

  /// Play a single song - FIXED VERSION
  Future<void> playSong(QuickPick song) async {
    try {
      print('🎵 [HANDLER] ========== PLAYING SONG ==========');
      print('   Title: ${song.title}');
      print('   Artists: ${song.artists}');
      print('   VideoId: ${song.videoId}');

      _governor.onPlaySong(song.title, song.artists);

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

      // 🔧 FIX: Stop tracking with longer delay
      print('🛑 [HANDLER] Stopping previous tracking...');
      await _tracker.stopTracking();

      // 🔧 FIX: Add delay after stopping tracking
      await Future.delayed(const Duration(milliseconds: 300));

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
      _governor.onLoadingUrl(song.title);
      final audioUrl = await _getAudioUrl(song.videoId, song: song);
      if (audioUrl == null) throw Exception('Failed to get audio URL');

      print('✅ [HANDLER] Audio URL obtained, setting player...');
      await _audioPlayer.setUrl(audioUrl);

      print('▶️ [HANDLER] Starting playback...');
      await _audioPlayer.play();
      print('✅ [HANDLER] Play completed successfully!');

      // 🔧 FIX: Wait for duration to be available before tracking
      print('⏱️ [HANDLER] Waiting for duration...');

      // Wait up to 2 seconds for duration to become available
      int attempts = 0;
      while (_audioPlayer.duration == null && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (_audioPlayer.duration != null) {
        print('✅ [HANDLER] Duration available: ${_audioPlayer.duration}');
      } else {
        print('⚠️ [HANDLER] Duration still null after waiting');
      }

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

  // ==================== FIXED setLoopMode() METHOD ====================
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await _audioPlayer.setLoopMode(mode);
    _governor.onLoopModeChange(mode);
    print('🔁 [LoopMode] Set to: $mode');

    _updateCustomState({'loop_mode': mode.index});
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
  Future<void> toggleLoopMode() async {
    AudioServiceRepeatMode newMode;

    switch (_loopMode) {
      case LoopMode.off:
        newMode = AudioServiceRepeatMode.all;
        break;
      case LoopMode.all:
        newMode = AudioServiceRepeatMode.one;
        break;
      case LoopMode.one:
        newMode = AudioServiceRepeatMode.none;
        break;
    }

    await setRepeatMode(newMode);
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

  Future<void> _loadRadioImmediately(QuickPick song) async {
    if (_isLoadingRadio) {
      print('⏳ [BackgroundAudioHandler] Already loading radio, skipping');
      return;
    }

    _isLoadingRadio = true;
    _lastRadioVideoId = song.videoId;
    _governor.onRadioStart(song.title);
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
        _governor.onRadioQueueEmpty();
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

      if (_isShuffleEnabled) {
        _shuffleRadioQueue();
      }

      _radioQueueIndex = -1;
      print(
        '✅ [BackgroundAudioHandler] Radio loaded: ${_radioQueue.length} songs',
      );
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

  @override
  Future<void> skipToNext() async {
    print('⏭️ Skip to next');
    _governor.onSkipForward();
    await _tracker.stopTracking();

    MediaItem? nextMedia;
    QuickPick? nextSong;

    if (_loopMode == LoopMode.one) {
      final currentMedia = mediaItem.value;
      if (currentMedia != null) {
        print('🔁 [LoopMode] Repeating current song');
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();

        final currentSong = _quickPickFromMediaItem(currentMedia);
        await Future.delayed(const Duration(milliseconds: 300));
        await _tracker.startTracking(currentSong);
        return;
      }
    }

    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      nextMedia = _queue[_currentIndex];
    } else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      nextMedia = _queue[_currentIndex];
      print('🔁 [LoopMode] Looping back to start of queue');
    } else if (_radioQueue.isNotEmpty && _radioQueueIndex == -1) {
      print('📻 Starting radio queue');
      _radioQueueIndex = 0;
      nextMedia = _radioQueue[_radioQueueIndex];
    } else if (_radioQueue.isNotEmpty &&
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

        await Future.delayed(const Duration(milliseconds: 300));
        await _tracker.startTracking(nextSong);
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
}
