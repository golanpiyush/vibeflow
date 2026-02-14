import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/api_base/cache_manager.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/providers/RealTimeService.dart';
import 'package:vibeflow/services/audioGoverner.dart';
import 'package:vibeflow/services/cacheManager.dart';
import 'package:vibeflow/services/smart_audio_refetcher.dart';
import 'package:vibeflow/services/smart_radio_service.dart';
import 'package:vibeflow/utils/audio_session_bridge.dart';
import 'package:vibeflow/utils/user_preference_tracker.dart';

BackgroundAudioHandler? _globalAudioHandler;
BackgroundAudioHandler? getAudioHandler() {
  return _globalAudioHandler;
}

enum RadioSourceType {
  none,
  search,
  quickPick,
  playlist,
  communityPlaylist,
  savedSongs,
  radio,
}

/// Background Audio Handler for persistent playback
/// Handles notification controls, lock screen controls, and background playback
class BackgroundAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  int? _audioSessionId;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final VibeFlowCore _core = VibeFlowCore();
  final SmartAudioFetcher _smartFetcher = SmartAudioFetcher();
  final RealtimeListeningTracker _tracker = RealtimeListeningTracker();
  final UserPreferenceTracker _userPreferences = UserPreferenceTracker();
  final SmartRadioService _smartRadioService = SmartRadioService();

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

  // Skip trackers for radio refetch
  int _consecutiveSkipsInRadio = 0;
  DateTime? _lastRadioRefetchTime;
  static const Duration _minTimeBetweenRefetch = Duration(minutes: 3);

  // radio setttings
  String? _currentRadioSourceId;
  String? _lastRadioVideoId;
  RadioSourceType _currentSourceType = RadioSourceType.none;
  String? _lastPlayedFromSearch;
  String? _lastPlayedFromQuickPick;
  String? _lastPlayedFromSavedSongs;
  List<String> _playlistQueue = [];
  int _playlistCurrentIndex = -1;
  bool _isPlayingPlaylist = false;
  String? _currentPlaylistId; // Track current playlist
  final Map<String, List<Song>> _playlistCache = {}; // In-memory playlist cache

  //Refetcher settings
  int _autoRetryCount = 0;
  static const int _maxAutoRetries = 3;
  bool _isAutoRecovering = false;
  bool _isRecoverableError(String error) {
    return error.contains('403') ||
        error.contains('Response code: 403') ||
        error.contains('Source error') ||
        error.contains('HttpDataSource') ||
        error.contains('IOException') ||
        error.contains('Unable to connect') ||
        error.contains('Connection') ||
        error.contains('Network');
  }

  // Current queue and playback state
  final _queue = <MediaItem>[];
  int _currentIndex = 0;
  LoopMode _loopMode = LoopMode.off;

  // Radio queue for autoplay
  final _radioQueue = <MediaItem>[];
  int _radioQueueIndex = -1;
  bool _isLoadingRadio = false;
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
    await _userPreferences.initialize();
    _setupAudioPlayer();
    await _setupAudioSession();
    _setupConnectivityListener();
    _tracker.setAudioPlayer(_audioPlayer);

    // ✅ CLEANUP OLD ACTIVITIES ON STARTUP
    await _tracker.cleanupStaleActivities();

    // Load saved settings
    await _loadSettings();

    print('✅ [BackgroundAudioHandler] Initialized');
    customState.add({
      'radio_queue': [],
      'radio_queue_count': 0,
      'resume_playback_enabled': _resumePlaybackEnabled,
      'persistent_queue_enabled': _persistentQueueEnabled,
      'loudness_normalization_enabled': _loudnessNormalizationEnabled,
    });
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

  /// Set playlist context for smart radio continuation
  Future<void> setPlaylistContext({
    required String playlistId,
    required List<Song> songs,
  }) async {
    print('📋 [Playlist Context] Setting for: $playlistId');
    print('   Songs: ${songs.length}');

    _currentPlaylistId = playlistId;
    _playlistCache[playlistId] = songs;

    // Cache to disk asynchronously (don't await to keep it fast)
    CacheManager.instance
        .cachePlaylistSongs(playlistId, songs)
        .then((_) {
          print('💾 [Playlist Context] Cached to disk');
        })
        .catchError((e) {
          print('⚠️ [Playlist Context] Cache failed: $e');
        });
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

        // ADD THIS: Record completed listen
        final currentMedia = mediaItem.value;
        if (currentMedia != null) {
          _userPreferences.recordListen(
            currentMedia.artist ?? 'Unknown Artist',
            currentMedia.title,
            listenDuration: currentMedia.duration ?? Duration.zero,
            totalDuration: currentMedia.duration ?? Duration.zero,
          );
        }

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
          print('⚠️ [AudioPlayer] Detected potential source error');

          // Only trigger recovery if not already recovering
          if (!_isAutoRecovering) {
            _governor.onPlaybackError(
              'Audio source error',
              mediaItem.value?.title ?? 'Unknown',
            );
            _handleSmartAutoRecovery();
          } else {
            print('⏳ [AudioPlayer] Recovery already in progress, ignoring');
          }
        }
      },
      onError: (Object e, StackTrace st) {
        print('❌ [AudioPlayer] Error event: $e');

        // Only handle if not already recovering
        if (_isAutoRecovering) {
          print('⏳ [AudioPlayer] Recovery in progress, ignoring error');
          return;
        }

        final errorMessage = e.toString();
        final songTitle = mediaItem.value?.title ?? 'Unknown';

        // Check if it's a recoverable error
        if (_isRecoverableError(errorMessage)) {
          print(
            '🔄 [AudioPlayer] Recoverable error, starting smart recovery...',
          );
          _handleSmartAutoRecovery();
        } else {
          // Unrecoverable error
          _governor.onPlaybackError(errorMessage, songTitle);
          _notifyPlaybackError(
            'Playback failed: ${_sanitizeErrorMessage(errorMessage)}',
            isSourceError: false,
          );
        }
      },
    );
  }

  // 🔥 FIXED: Direct URL replacement without re-triggering playSong()
  Future<void> _handleSmartAutoRecovery() async {
    if (_isAutoRecovering) {
      print('⏳ [SmartRecovery] Already recovering, skipping');
      return;
    }
    _isAutoRecovering = true;
    _autoRetryCount++;

    // ✅ NEW: Check if song just started (within 2 seconds)
    final currentMedia = mediaItem.value;
    if (currentMedia != null) {
      final position = _audioPlayer.position;
      if (position.inSeconds < 2) {
        print('⏭️ [SmartRecovery] Song just started (<2s), skipping recovery');
        print('   This might be normal loading delay, not an error');
        return;
      }
    }

    if (_autoRetryCount >= _maxAutoRetries) {
      print('❌ [SmartRecovery] Max retries reached, showing manual retry');
      _autoRetryCount = 0;
      _isAutoRecovering = false;
      _notifyPlaybackError(
        'Unable to recover automatically',
        isSourceError: true,
      );
      return;
    }

    if (currentMedia == null) {
      _isAutoRecovering = false;
      _autoRetryCount = 0;
      return;
    }

    try {
      print('🔄 [SmartRecovery] Attempt ${_autoRetryCount}/$_maxAutoRetries');
      print('   Song: ${currentMedia.title}');

      // Notify UI about auto-retry
      _updateCustomState({
        'playback_error': true,
        'error_message': 'Recovering audio source...',
        'is_source_error': true,
        'auto_retrying': true,
      });

      // 🔥 CRITICAL: Clear all caches
      final audioCache = AudioUrlCache();
      await audioCache.remove(currentMedia.id);
      _urlCache.remove(currentMedia.id);
      _urlCacheTime.remove(currentMedia.id);

      // Get current position to restore after recovery
      final currentPosition = _audioPlayer.position;

      // Use SMART fetcher with 3 parallel attempts
      final quickPick = _quickPickFromMediaItem(currentMedia);
      print('🎯 [SmartRecovery] Using SmartFetcher for ${currentMedia.id}');

      final freshUrl = await _smartFetcher.getAudioUrlSmart(
        currentMedia.id,
        song: quickPick,
      );

      if (freshUrl != null && freshUrl.isNotEmpty) {
        print('✅ [SmartRecovery] Got fresh URL from smart fetcher');
        print('   URL length: ${freshUrl.length} chars');

        // 🔥 CRITICAL FIX: Use try-catch ONLY for setUrl, not the whole block
        try {
          // Set new audio source WITHOUT stopping/pausing first
          print('🔄 [SmartRecovery] Setting new audio source...');
          await _audioPlayer.setUrl(freshUrl);

          // Restore position if it was playing
          if (currentPosition.inSeconds > 0) {
            print(
              '⏩ [SmartRecovery] Restoring position: ${currentPosition.inSeconds}s',
            );
            await _audioPlayer.seek(currentPosition);
          }

          // Start playback
          print('▶️ [SmartRecovery] Starting playback...');
          await _audioPlayer.play();

          // Wait for playback to stabilize
          await Future.delayed(const Duration(milliseconds: 300));

          // Verify playback actually started
          final isPlayingOrReady =
              _audioPlayer.playing ||
              _audioPlayer.processingState == ProcessingState.ready ||
              _audioPlayer.processingState == ProcessingState.buffering;

          if (isPlayingOrReady) {
            print('✅ [SmartRecovery] Playback resumed successfully!');
            _governor.onUrlRefreshSuccess();

            // Resume tracking
            await _tracker.startTracking(quickPick);

            // Cache the new URL
            _urlCache[currentMedia.id] = freshUrl;
            _urlCacheTime[currentMedia.id] = DateTime.now();
            await audioCache.cache(quickPick, freshUrl);

            // Show success notification
            _updateCustomState({
              'playback_error': false,
              'error_message': null,
              'is_source_error': false,
              'auto_retrying': false,
              'recovery_success': true,
            });

            // Clear success flag after 2 seconds
            Future.delayed(const Duration(seconds: 2), () {
              _updateCustomState({'recovery_success': false});
            });

            // Reset retry count on success
            _autoRetryCount = 0;
            _isAutoRecovering = false;

            print('🎉 [SmartRecovery] Recovery complete!');
            return;
          } else {
            print(
              '⚠️ [SmartRecovery] Player state: ${_audioPlayer.processingState}',
            );
            throw Exception(
              'Player not ready after setUrl (state: ${_audioPlayer.processingState})',
            );
          }
        } catch (setUrlError) {
          // This is the actual setUrl error - rethrow to outer catch
          print('❌ [SmartRecovery] setUrl failed: $setUrlError');
          throw setUrlError;
        }
      } else {
        throw Exception('Smart fetcher returned null URL');
      }
    } catch (e) {
      print('❌ [SmartRecovery] Attempt ${_autoRetryCount} failed: $e');

      if (_autoRetryCount < _maxAutoRetries) {
        print('🔄 [SmartRecovery] Will retry in 1.5 seconds...');

        // Clear auto-retry flag temporarily
        _updateCustomState({'auto_retrying': false});

        // Wait longer before retry
        await Future.delayed(const Duration(milliseconds: 1500));
        _isAutoRecovering = false;

        // Retry
        await _handleSmartAutoRecovery();
      } else {
        print('❌ [SmartRecovery] Max retries exhausted');
        _governor.onUrlRefreshFailed();

        _updateCustomState({
          'playback_error': true,
          'error_message': 'Recovery failed. Tap RETRY.',
          'is_source_error': true,
          'auto_retrying': false,
        });

        _isAutoRecovering = false;
        _autoRetryCount = 0;
      }
    }
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

  Future<void> playSong(
    QuickPick song, {
    RadioSourceType sourceType = RadioSourceType.quickPick,
  }) async {
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
      print('   Source Type: $sourceType');
      print('   Current Source Type: $_currentSourceType');

      _governor.onPlaySong(song.title, song.artists);

      // Check if EXACT same song already playing
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
        _isChangingSong = false;
        return;
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

      // ============================================================================
      // CRITICAL: Radio Source Decision Logic
      // ============================================================================
      print('🔍 [HANDLER] ========== RADIO SOURCE ANALYSIS ==========');
      print('   Previous source type: $_currentSourceType');
      print('   New source type: $sourceType');
      print('   Current radio source: $_currentRadioSourceId');
      print('   Radio queue size: ${_radioQueue.length}');
      print('===================================================');

      bool shouldClearRadio = false;
      bool shouldLoadNewRadio = false;
      String? reasonForDecision;

      // Decision tree for radio handling
      if (sourceType == RadioSourceType.radio) {
        // Playing from existing radio queue - keep everything
        print('✅ [DECISION] Playing from radio queue - keeping intact');
        reasonForDecision = 'Playing from radio';
        shouldClearRadio = false;
        shouldLoadNewRadio = false;

        final radioPos = _radioQueue.indexWhere(
          (item) => item.id == song.videoId,
        );
        if (radioPos != -1) {
          _radioQueueIndex = radioPos;
          print('   Updated radio index to: $_radioQueueIndex');
        }
      } else if (sourceType == RadioSourceType.playlist) {
        // Starting playlist - clear radio, don't load new one yet
        print('📋 [DECISION] Starting playlist - clearing radio');
        reasonForDecision = 'Playlist started';
        shouldClearRadio = true;
        shouldLoadNewRadio = false;

        _isPlayingPlaylist = true;
        _playlistCurrentIndex = 0;
        _updateCustomState({'is_playlist_mode': true});
      } else if (sourceType == RadioSourceType.search) {
        // Check if this is a DIFFERENT search result
        final isDifferentSearch = _lastPlayedFromSearch != song.videoId;

        if (isDifferentSearch) {
          print('🔍 [DECISION] New search result - loading new radio');
          reasonForDecision = 'Different search result';
          shouldClearRadio = true;
          shouldLoadNewRadio = true;
          _lastPlayedFromSearch = song.videoId;
        } else {
          print('🔍 [DECISION] Same search result - keeping radio');
          reasonForDecision = 'Same search result';
          shouldClearRadio = false;
          shouldLoadNewRadio = false;
        }
      } else if (sourceType == RadioSourceType.quickPick) {
        // Check if this is a DIFFERENT quick pick
        final isDifferentQuickPick = _lastPlayedFromQuickPick != song.videoId;

        if (isDifferentQuickPick) {
          print('⚡ [DECISION] New quick pick - loading new radio');
          reasonForDecision = 'Different quick pick';
          shouldClearRadio = true;
          shouldLoadNewRadio = true;
          _lastPlayedFromQuickPick = song.videoId;
        } else {
          print('⚡ [DECISION] Same quick pick - keeping radio');
          reasonForDecision = 'Same quick pick';
          shouldClearRadio = false;
          shouldLoadNewRadio = false;
        }
      } else if (sourceType == RadioSourceType.savedSongs) {
        // 🔥 NEW: Saved songs handling
        final isDifferentSavedSong = _lastPlayedFromSavedSongs != song.videoId;

        if (isDifferentSavedSong) {
          print('💾 [DECISION] Different saved song - loading new radio');
          reasonForDecision = 'Different saved song';
          shouldClearRadio = true;
          shouldLoadNewRadio = true;
          _lastPlayedFromSavedSongs = song.videoId;
        } else {
          print('💾 [DECISION] Same saved song - keeping radio');
          reasonForDecision = 'Same saved song';
          shouldClearRadio = false;
          shouldLoadNewRadio = false;
        }
      }

      print('📊 [DECISION RESULT]');
      print('   Reason: $reasonForDecision');
      print('   Clear radio: $shouldClearRadio');
      print('   Load new radio: $shouldLoadNewRadio');
      print('===================================================');

      // Execute decision
      if (shouldClearRadio) {
        print('🗑️ [HANDLER] Clearing old radio');
        _radioQueue.clear();
        _radioQueueIndex = -1;
        _lastRadioVideoId = null;
        _isLoadingRadio = false;
        _currentRadioSourceId = null;

        _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
      }

      // Update current source type
      _currentSourceType = sourceType;

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

      mediaItem.add(newMediaItem);

      print('🔍 [HANDLER] Getting audio URL...');
      _governor.onLoadingUrl(song.title);

      String? audioUrl = await _smartFetcher.getAudioUrlSmart(
        song.videoId,
        song: song,
      );

      if (audioUrl == null || audioUrl.isEmpty) {
        print('⚠️ [HANDLER] SmartFetcher failed, trying direct fetch...');
        try {
          audioUrl = await _core
              .getAudioUrl(song.videoId, song: song)
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          print('❌ [HANDLER] Direct fetch also failed: $e');
        }
      }

      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Failed to get audio URL after all attempts');
      }

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
      print('⏱️ [HANDLER] Waiting for duration...');
      int attempts = 0;
      while (_audioPlayer.duration == null && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (_audioPlayer.duration != null) {
        print('✅ [HANDLER] Duration available: ${_audioPlayer.duration}');
        mediaItem.add(newMediaItem.copyWith(duration: _audioPlayer.duration));
      } else {
        print('⚠️ [HANDLER] Duration still null after waiting');
      }

      print('📝 [HANDLER] Starting realtime tracking...');
      await _tracker.startTracking(song);

      print('✅ [HANDLER] ========== PLAYBACK STARTED ==========');

      // Cache URL
      AudioUrlCache().cache(song, audioUrl);

      // Load radio if decision says so
      if (shouldLoadNewRadio) {
        print('📻 [HANDLER] Loading new radio for: ${song.title}');
        _currentRadioSourceId = song.videoId;

        // 🔥 NEW: Check if this song is from a playlist
        if (sourceType == RadioSourceType.communityPlaylist &&
            _currentPlaylistId != null) {
          print('📋 [HANDLER] Using playlist continuation for radio');
          await _loadRadioFromPlaylistContinuation(_currentPlaylistId!);
        }
      } else if (!shouldClearRadio && _radioQueue.isEmpty) {
        print('📻 [HANDLER] Radio empty, loading...');
        _currentRadioSourceId = song.videoId;
        _loadRadioImmediately(song);
      } else {
        print('📻 [HANDLER] Radio decision: no action needed');
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
    print('   Is playlist mode: $_isPlayingPlaylist');

    // Don't load radio if in playlist mode
    if (_isPlayingPlaylist) {
      print('📋 [Radio] In playlist mode - skipping radio load');
      return;
    }

    // Check if already loading
    if (_isLoadingRadio) {
      print('⏳ [Radio] Already loading radio, skipping');
      return;
    }

    // Check if we already have radio for this exact song
    if (_lastRadioVideoId == song.videoId && _radioQueue.isNotEmpty) {
      print('✅ [Radio] Radio already loaded for ${song.videoId}');
      print('   Queue size: ${_radioQueue.length}');

      // ✅ FIX: Re-publish to UI to ensure it's visible
      final radioQueueData = _radioQueue.map((item) {
        return {
          'id': item.id,
          'title': item.title,
          'artist': item.artist ?? 'Unknown Artist',
          'artUri': item.artUri?.toString(),
          'duration': item.duration?.inMilliseconds,
        };
      }).toList();

      print('📢 [Radio] Re-publishing ${radioQueueData.length} songs to UI');
      _updateCustomState({
        'radio_queue': radioQueueData,
        'radio_queue_count': radioQueueData.length,
      });

      return;
    }

    _isLoadingRadio = true;
    _lastRadioVideoId = song.videoId;
    _governor.onRadioStart(song.title);

    print('🔄 [Radio] Starting radio load...');

    try {
      print('📻 [Radio] Calling SmartRadioService...');

      final radioSongs = await _smartRadioService.getSmartRadio(
        videoId: song.videoId,
        title: song.title,
        artist: song.artists,
        limit: 25,
        diversifyArtists: false,
      );

      print('📻 [Radio] SmartRadioService returned ${radioSongs.length} songs');

      if (radioSongs.isEmpty) {
        print('⚠️ [Radio] No radio songs returned');
        _governor.onRadioQueueEmpty();

        // ✅ FIX: Explicitly set empty state
        _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
        return;
      }

      print(
        '✅ [Radio] Got ${radioSongs.length} songs, converting to MediaItems...',
      );

      _radioQueue.clear();

      int successCount = 0;
      final radioQueueData =
          <Map<String, dynamic>>[]; // ✅ FIX: Build data as we go

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

          // ✅ FIX: Add to data list immediately
          radioQueueData.add({
            'id': mediaItem.id,
            'title': mediaItem.title,
            'artist': mediaItem.artist ?? 'Unknown Artist',
            'artUri': mediaItem.artUri?.toString(),
            'duration': mediaItem.duration?.inMilliseconds,
          });

          successCount++;
        } catch (e) {
          print('⚠️ [Radio] Failed to convert song ${song.title}: $e');
        }
      }

      print(
        '✅ [Radio] Successfully added $successCount MediaItems to _radioQueue',
      );
      print('   _radioQueue.length is now: ${_radioQueue.length}');
      print('   radioQueueData.length is: ${radioQueueData.length}');

      if (_radioQueue.isEmpty || radioQueueData.isEmpty) {
        print('❌ [Radio] CRITICAL ERROR: Queues are empty after adding!');
        _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
        return;
      }

      if (_isShuffleEnabled) {
        print('🔀 [Radio] Shuffling queue...');
        _shuffleRadioQueue();

        // ✅ FIX: Rebuild data after shuffle
        radioQueueData.clear();
        for (final item in _radioQueue) {
          radioQueueData.add({
            'id': item.id,
            'title': item.title,
            'artist': item.artist ?? 'Unknown Artist',
            'artUri': item.artUri?.toString(),
            'duration': item.duration?.inMilliseconds,
          });
        }
      }

      _radioQueueIndex = -1;
      print('   Reset _radioQueueIndex to: $_radioQueueIndex');

      print('📢 [Radio] Publishing to customState...');
      print('   Data to publish: ${radioQueueData.length} songs');

      // ✅ CRITICAL FIX: Ensure data is actually published
      try {
        _updateCustomState({
          'radio_queue': radioQueueData,
          'radio_queue_count': radioQueueData.length,
        });

        // ✅ FIX: Wait a frame to ensure state propagation
        await Future.delayed(const Duration(milliseconds: 50));

        // ✅ FIX: Verify it was published
        final currentState = _safeCustomState();
        final publishedQueue =
            currentState['radio_queue'] as List<dynamic>? ?? [];
        print(
          '✅ [Radio] Verification: customState now has ${publishedQueue.length} songs',
        );

        if (publishedQueue.isEmpty && radioQueueData.isNotEmpty) {
          print('⚠️ [Radio] WARNING: Publishing failed, retrying...');
          // Retry once
          _updateCustomState({
            'radio_queue': radioQueueData,
            'radio_queue_count': radioQueueData.length,
          });
        }
      } catch (e) {
        print('❌ [Radio] Error publishing to customState: $e');
      }

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
      print('🏁 [Radio] Finished loading');
      print('   Final _radioQueue.length: ${_radioQueue.length}');
      print('   Final _isLoadingRadio: $_isLoadingRadio');
    }
  }

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

      print('✅ [Radio] Loaded ${_radioQueue.length} radio songs');

      // ✅ FIX: Broadcast the custom state immediately after loading
      _broadcastRadioState();
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

  // ✅ ADD: Helper method to broadcast radio state
  void _broadcastRadioState() {
    final radioQueueData = _radioQueue
        .map(
          (item) => {
            'id': item.id,
            'title': item.title,
            'artist': item.artist ?? 'Unknown Artist',
            'artUri': item.artUri?.toString() ?? '',
            'duration': item.duration?.inMilliseconds,
          },
        )
        .toList();

    customState.add({
      'radio_queue': radioQueueData,
      'radio_queue_count': _radioQueue.length,
      'resume_playback_enabled': _resumePlaybackEnabled,
      'persistent_queue_enabled': _persistentQueueEnabled,
      'loudness_normalization_enabled': _loudnessNormalizationEnabled,
    });

    print('📡 [Radio] Broadcasted radio state: ${_radioQueue.length} songs');
  }

  /// Load radio from playlist continuation
  Future<void> _loadRadioFromPlaylistContinuation(String playlistId) async {
    print('📋 [Playlist Radio] Loading from playlist: $playlistId');

    try {
      // Check cache first
      List<Song>? playlistSongs = _playlistCache[playlistId];

      // If not in memory, try disk cache
      if (playlistSongs == null || playlistSongs.isEmpty) {
        print('💾 [Playlist Radio] Loading from disk cache...');
        final cacheManager = CacheManager.instance;
        playlistSongs = await cacheManager.getCachedPlaylistSongs(playlistId);

        if (playlistSongs.isNotEmpty) {
          _playlistCache[playlistId] = playlistSongs;
          print(
            '✅ [Playlist Radio] Loaded ${playlistSongs.length} songs from cache',
          );
        }
      }

      if (playlistSongs == null || playlistSongs.isEmpty) {
        print('⚠️ [Playlist Radio] No cached songs, using normal radio');
        // Fallback to normal radio
        final currentMedia = mediaItem.value;
        if (currentMedia != null) {
          final quickPick = _quickPickFromMediaItem(currentMedia);
          await _loadRadioImmediately(quickPick);
        }
        return;
      }

      // Get current song index in playlist
      final currentMedia = mediaItem.value;
      if (currentMedia == null) return;

      final currentIndex = playlistSongs.indexWhere(
        (s) => s.videoId == currentMedia.id,
      );

      if (currentIndex == -1) {
        print('⚠️ [Playlist Radio] Current song not found in playlist');
        return;
      }

      // Get remaining songs from playlist (after current)
      final remainingSongs = playlistSongs.sublist(
        (currentIndex + 1).clamp(0, playlistSongs.length),
      );

      print(
        '✅ [Playlist Radio] Found ${remainingSongs.length} remaining songs',
      );

      if (remainingSongs.isEmpty) {
        print('📻 [Playlist Radio] No more playlist songs, using normal radio');
        final quickPick = _quickPickFromMediaItem(currentMedia);
        await _loadRadioImmediately(quickPick);
        return;
      }

      // Convert to MediaItems for radio queue
      _radioQueue.clear();

      for (final song in remainingSongs.take(20)) {
        // Limit to 20 songs
        try {
          final mediaItem = MediaItem(
            id: song.videoId,
            title: song.title,
            artist: song.artists.join(', '),
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
        } catch (e) {
          print('⚠️ [Playlist Radio] Failed to add song: ${song.title}');
        }
      }

      // If playlist songs < 20, supplement with normal radio
      if (_radioQueue.length < 20) {
        print(
          '🔄 [Playlist Radio] Supplementing with ${20 - _radioQueue.length} radio songs',
        );

        final lastPlaylistSong = remainingSongs.last;
        final radioSongs = await _radioService.getRadioForSong(
          videoId: lastPlaylistSong.videoId,
          title: lastPlaylistSong.title,
          artist: lastPlaylistSong.artists.join(', '),
          limit: 20 - _radioQueue.length,
        );

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
          } catch (e) {
            print('⚠️ [Playlist Radio] Failed to add radio song');
          }
        }
      }

      _radioQueueIndex = -1;

      print(
        '✅ [Playlist Radio] Loaded ${_radioQueue.length} songs (playlist continuation)',
      );

      // Broadcast to UI
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
        'radio_source': 'playlist_continuation',
      });
    } catch (e, stack) {
      print('❌ [Playlist Radio] Error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
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

    // Use SMART fetcher with 3 parallel attempts
    print('🔄 Fetching fresh audio URL using SmartFetcher...');
    try {
      String? url = await _smartFetcher.getAudioUrlSmart(videoId, song: song);

      // Fallback to direct fetch if SmartFetcher fails
      if (url == null || url.isEmpty) {
        print('⚠️ SmartFetcher failed, trying direct fetch as fallback...');
        url = await _core
            .getAudioUrl(videoId, song: song)
            .timeout(const Duration(seconds: 10));
      }

      if (url != null && url.isNotEmpty) {
        // Cache in internal cache
        _urlCache[videoId] = url;
        _urlCacheTime[videoId] = DateTime.now();
        print('✅ URL fetched and cached successfully');
        return url;
      } else {
        print('❌ All fetch attempts returned null or empty URL');
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

    // ADD THIS: Reset skip counter when user manually resumes
    if (_radioQueue.isNotEmpty && _radioQueueIndex >= 0) {
      _consecutiveSkipsInRadio = 0;
    }

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

    // ✅ CRITICAL: Stop tracking BEFORE disposing player
    await _tracker.stopTracking();
    await Future.delayed(
      const Duration(milliseconds: 200),
    ); // Ensure DB update completes

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
    print('⏭️ [SKIP] Skip to next requested');
    _governor.onSkipForward();

    // Track skip for preferences
    final currentMedia = mediaItem.value;
    if (currentMedia != null) {
      final position = _audioPlayer.position;
      final duration = currentMedia.duration ?? Duration.zero;

      await _userPreferences.recordSkip(
        currentMedia.artist ?? 'Unknown Artist',
        currentMedia.title,
        position: position,
        totalDuration: duration,
      );

      if (_radioQueue.isNotEmpty && _radioQueueIndex >= 0) {
        _consecutiveSkipsInRadio++;
        print('📊 [SKIP] Consecutive radio skips: $_consecutiveSkipsInRadio');
        await _checkAndRefetchRadioIfNeeded();
      } else {
        _consecutiveSkipsInRadio = 0;
      }
    }

    await _tracker.stopTracking();

    MediaItem? nextMedia;
    QuickPick? nextSong;

    // Handle LoopMode.one
    if (_loopMode == LoopMode.one) {
      print('🔁 [LoopMode.one] Restarting current song');
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      return;
    }

    print('📊 [SKIP] Current state:');
    print('   Manual queue: ${_queue.length} songs, index: $_currentIndex');
    print(
      '   Radio queue: ${_radioQueue.length} songs, index: $_radioQueueIndex',
    );
    print('   Playlist mode: $_isPlayingPlaylist');
    print('   Playlist index: $_playlistCurrentIndex/${_playlistQueue.length}');
    print('   Source type: $_currentSourceType');

    // ============================================================================
    // UPDATED PRIORITY SYSTEM
    // ============================================================================

    // Priority 1: PLAYLIST MODE - follow playlist queue first
    if (_isPlayingPlaylist && _queue.isNotEmpty) {
      if (_currentIndex < _queue.length - 1) {
        // More songs in playlist
        _currentIndex++;
        _playlistCurrentIndex++;
        nextMedia = _queue[_currentIndex];
        print(
          '📋 [SKIP] Next playlist song [${_currentIndex + 1}/${_queue.length}]: ${nextMedia.title}',
        );

        _updateCustomState({'playlist_current_index': _playlistCurrentIndex});
      } else {
        // Playlist finished - exit playlist mode and load radio
        print('✅ [SKIP] Playlist finished! Transitioning to radio...');
        _isPlayingPlaylist = false;
        _playlistQueue.clear();
        _playlistCurrentIndex = -1;
        _currentSourceType = RadioSourceType.radio;

        _updateCustomState({
          'is_playlist_mode': false,
          'playlist_queue_count': 0,
          'playlist_current_index': -1,
        });

        // Load radio from last playlist song
        if (currentMedia != null) {
          print(
            '📻 [SKIP] Loading radio from playlist end: ${currentMedia.title}',
          );
          final lastSong = _quickPickFromMediaItem(currentMedia);
          _currentRadioSourceId = currentMedia.id;
          await _loadRadioImmediately(lastSong);

          // Wait for radio to load
          await _waitForRadioToLoad();

          if (_radioQueue.isNotEmpty) {
            _radioQueueIndex = 0;
            nextMedia = _radioQueue[_radioQueueIndex];
            print(
              '📻 [SKIP] Starting radio after playlist: ${nextMedia.title}',
            );
          } else {
            print('⚠️ [SKIP] Radio failed to load after playlist');
            playbackState.add(
              playbackState.value.copyWith(
                processingState: AudioProcessingState.idle,
                playing: false,
              ),
            );
            return;
          }
        }
      }
    }
    // Priority 2: Manual queue (non-playlist)
    else if (!_isPlayingPlaylist &&
        _queue.isNotEmpty &&
        _currentIndex < _queue.length - 1) {
      _currentIndex++;
      nextMedia = _queue[_currentIndex];
      print(
        '✅ [SKIP] Next from manual queue [${_currentIndex + 1}/${_queue.length}]: ${nextMedia.title}',
      );
    }
    // Priority 3: Loop all - restart manual queue
    else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      nextMedia = _queue[_currentIndex];
      print('🔁 [LoopMode.all] Looping back to start of manual queue');
    }
    // Priority 4: Start radio queue (first time)
    else if (_radioQueue.isNotEmpty && _radioQueueIndex == -1) {
      print('📻 [SKIP] Starting radio queue (first song)');
      _radioQueueIndex = 0;
      nextMedia = _radioQueue[_radioQueueIndex];
      _currentSourceType = RadioSourceType.radio;
      print('   Playing: ${nextMedia.title}');
    }
    // Priority 5: Continue in radio queue
    else if (_radioQueue.isNotEmpty &&
        _radioQueueIndex >= 0 &&
        _radioQueueIndex < _radioQueue.length - 1) {
      _radioQueueIndex++;
      nextMedia = _radioQueue[_radioQueueIndex];
      print(
        '📻 [SKIP] Next from radio queue [${_radioQueueIndex + 1}/${_radioQueue.length}]: ${nextMedia.title}',
      );

      // Check if approaching end of radio - fetch more
      await _checkAndFetchMoreRadio();
    }
    // Priority 6: End of radio queue
    else if (_radioQueue.isNotEmpty &&
        _radioQueueIndex >= _radioQueue.length - 1) {
      print('⚠️ [SKIP] End of radio queue reached');
      if (_loopMode == LoopMode.all) {
        _radioQueueIndex = 0;
        nextMedia = _radioQueue[_radioQueueIndex];
        print('🔁 [SKIP] Looping radio queue from start');
      } else {
        print('🛑 [SKIP] No loop mode, stopping playback');
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
            playing: false,
          ),
        );
        return;
      }
      _broadcastRadioState();
    }

    // ============================================================================
    // PLAY THE NEXT SONG
    // ============================================================================

    if (nextMedia != null) {
      print('🎵 [SKIP] ========== NEXT SONG SELECTED ==========');
      print('   Song: ${nextMedia.title}');
      print('   Source: ${_getSourceDescription()}');
      print('===================================================');

      nextSong = _quickPickFromMediaItem(nextMedia);

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      mediaItem.add(nextMedia);

      try {
        print('🔍 [SKIP] Getting audio URL...');
        final audioUrl = await _getAudioUrl(nextMedia.id, song: nextSong);

        if (audioUrl == null) {
          throw Exception('Failed to get audio URL for ${nextMedia.title}');
        }

        print('✅ [SKIP] Got audio URL, setting player...');

        try {
          await _audioPlayer.setUrl(audioUrl);
        } catch (e) {
          throw Exception('Failed to set audio source: $e');
        }

        print('▶️ [SKIP] Starting playback...');
        await _audioPlayer.play();

        await Future.delayed(const Duration(milliseconds: 300));

        print('📝 [SKIP] Starting tracking...');
        await _tracker.startTracking(nextSong);

        print('✅ [SKIP] Successfully playing: ${nextMedia.title}');

        return;
      } catch (e, stackTrace) {
        print('❌ [SKIP] Error playing next song: $e');
        print('   Stack: $stackTrace');

        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );

        _notifyPlaybackError(
          'Failed to skip: ${e.toString()}',
          isSourceError: true,
        );
        return;
      }
    }

    // No next song available
    print('❌ [SKIP] No next song available');
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  // Add this helper method:
  String _getSourceDescription() {
    if (_isPlayingPlaylist) {
      return 'Playlist (${_playlistCurrentIndex + 1}/${_playlistQueue.length})';
    } else if (_radioQueueIndex >= 0) {
      return 'Radio queue (${_radioQueueIndex + 1}/${_radioQueue.length})';
    } else if (_currentIndex >= 0) {
      return 'Manual queue (${_currentIndex + 1}/${_queue.length})';
    }
    return 'Unknown';
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

  Future<void> playPlaylistQueue(
    List<QuickPick> songs, {
    int startIndex = 0,
    String? playlistId, // ADD THIS PARAMETER
  }) async {
    if (songs.isEmpty) return;

    try {
      print('🎵 [PLAYLIST] ========== PLAYING PLAYLIST ==========');
      print('   Songs: ${songs.length}');
      print('   Start index: $startIndex');
      print('   Playlist ID: $playlistId');

      // 🔥 NEW: Store playlist ID and cache songs
      if (playlistId != null) {
        _currentPlaylistId = playlistId;

        // Convert QuickPick to Song for caching
        final songsToCache = songs
            .map(
              (qp) => Song(
                videoId: qp.videoId,
                title: qp.title,
                artists: [qp.artists],
                thumbnail: qp.thumbnail,
                duration: qp.duration,
                audioUrl: null,
              ),
            )
            .toList();

        _playlistCache[playlistId] = songsToCache;

        // Cache to disk asynchronously
        CacheManager.instance.cachePlaylistSongs(playlistId, songsToCache);

        print('💾 [PLAYLIST] Cached ${songs.length} songs for continuation');
      }

      _governor.onPlaylistStart(songs.length);

      // Stop current playback
      await _tracker.stopTracking();
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await _audioPlayer.stop();
      await Future.delayed(const Duration(milliseconds: 100));

      // 🔥 CRITICAL: Clear radio and mark playlist mode
      print('🗑️ [PLAYLIST] Clearing radio (entering playlist mode)');
      _radioQueue.clear();
      _radioQueueIndex = -1;
      _lastRadioVideoId = null;
      _isLoadingRadio = false;
      _currentRadioSourceId = null;
      _currentSourceType = RadioSourceType.playlist;
      _isPlayingPlaylist = true;

      // Store playlist order
      _playlistQueue = songs.map((s) => s.videoId).toList();
      _playlistCurrentIndex = startIndex;

      _updateCustomState({
        'radio_queue': [],
        'radio_queue_count': 0,
        'is_playlist_mode': true,
        'playlist_queue_count': songs.length,
        'playlist_current_index': startIndex,
      });

      // Convert songs to MediaItems
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

      final currentSong = songs[_currentIndex];
      final currentMedia = _queue[_currentIndex];

      mediaItem.add(currentMedia);

      print(
        '🔍 [PLAYLIST] Getting audio URL for song ${_currentIndex + 1}/${songs.length}...',
      );

      final audioUrl = await _getAudioUrl(
        currentSong.videoId,
        song: currentSong,
      );
      if (audioUrl == null) {
        throw Exception('Failed to get audio URL');
      }

      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();

      int attempts = 0;
      while (_audioPlayer.duration == null && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (_audioPlayer.duration != null) {
        mediaItem.add(currentMedia.copyWith(duration: _audioPlayer.duration));
      }

      await Future.delayed(const Duration(milliseconds: 300));
      await _tracker.startTracking(currentSong);

      print(
        '✅ [PLAYLIST] Playing song ${_currentIndex + 1}/${_queue.length}: ${currentSong.title}',
      );
      print('   Playlist mode active - no radio until playlist ends');
      print('===================================================');
    } catch (e, stackTrace) {
      print('❌ [PLAYLIST] Error: $e');
      print('   Stack: $stackTrace');

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ),
      );

      _notifyPlaybackError(
        'Failed to play playlist: ${e.toString()}',
        isSourceError: true,
      );
    }
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

  /// Check if user has been skipping too much and refetch radio with different artists
  Future<void> _checkAndRefetchRadioIfNeeded() async {
    // Don't refetch if:
    // 1. Not enough skips yet (need at least 3)
    // 2. Recently refetched (wait at least 3 minutes)
    // 3. Already loading radio
    // 4. In playlist mode

    if (_consecutiveSkipsInRadio < 3) {
      print(
        '📊 [RadioRefetch] Not enough skips yet ($_consecutiveSkipsInRadio/3)',
      );
      return;
    }

    if (_isLoadingRadio) {
      print('⏳ [RadioRefetch] Already loading radio');
      return;
    }

    final isPlaylistMode = _safeCustomState()['is_playlist_mode'] == true;
    if (isPlaylistMode) {
      print('📋 [RadioRefetch] In playlist mode, skipping refetch');
      return;
    }

    // Check time since last refetch
    if (_lastRadioRefetchTime != null) {
      final timeSinceRefetch = DateTime.now().difference(
        _lastRadioRefetchTime!,
      );
      if (timeSinceRefetch < _minTimeBetweenRefetch) {
        print(
          '⏰ [RadioRefetch] Too soon since last refetch (${timeSinceRefetch.inMinutes}min ago)',
        );
        return;
      }
    }

    print('🎯 [RadioRefetch] ========== REFETCHING RADIO ==========');
    print('   Reason: $_consecutiveSkipsInRadio consecutive skips');
    print('   Current radio source: $_currentRadioSourceId');

    // Get skip analysis
    final analysis = _userPreferences.analyzeRecentSkips(lookbackCount: 5);
    print('📊 [RadioRefetch] Skip analysis:');
    print('   Recent skips: ${analysis.recentSkipCount}');
    print('   Skipped artists: ${analysis.skippedArtists}');
    print('   Should refetch: ${analysis.shouldRefetchRadio}');

    if (!analysis.shouldRefetchRadio) {
      print('✅ [RadioRefetch] Analysis says no refetch needed');
      return;
    }

    // Show notification to user
    _updateCustomState({
      'radio_refetching': true,
      'refetch_reason': 'Finding better music for you...',
    });

    try {
      _isLoadingRadio = true;
      _lastRadioRefetchTime = DateTime.now();

      // Get preferred artists for radio
      final preferredArtists = _userPreferences.getSuggestedArtists(limit: 5);

      print('🎵 [RadioRefetch] Using preferred artists: $preferredArtists');

      List<QuickPick> newRadio = [];

      if (preferredArtists.isNotEmpty) {
        // Try getting radio from preferred artists
        print('🔄 [RadioRefetch] Fetching from preferred artists...');

        // Pick a random preferred artist as seed
        preferredArtists.shuffle();
        final seedArtist = preferredArtists.first;

        // Get current song to use as fallback seed
        final currentSong = _radioQueue.isNotEmpty && _radioQueueIndex >= 0
            ? _quickPickFromMediaItem(_radioQueue[_radioQueueIndex])
            : null;

        if (currentSong != null) {
          // Get smart radio with diversification
          newRadio = await _smartRadioService.getSmartRadio(
            videoId: currentSong.videoId,
            title: currentSong.title,
            artist: seedArtist, // Use preferred artist
            limit: 25,
            diversifyArtists: true,
          );
        }
      }

      // Fallback: use current song if no preferred artists or failed
      if (newRadio.isEmpty && _radioQueue.isNotEmpty && _radioQueueIndex >= 0) {
        print(
          '🔄 [RadioRefetch] Fallback: using current song with diversification',
        );
        final currentMedia = _radioQueue[_radioQueueIndex];
        final currentSong = _quickPickFromMediaItem(currentMedia);

        newRadio = await _smartRadioService.getSmartRadio(
          videoId: currentSong.videoId,
          title: currentSong.title,
          artist: currentSong.artists,
          limit: 25,
          diversifyArtists: true, // Ensure variety
        );
      }

      if (newRadio.isEmpty) {
        print('❌ [RadioRefetch] Failed to get new radio');
        _updateCustomState({'radio_refetching': false, 'refetch_failed': true});
        return;
      }

      print('✅ [RadioRefetch] Got ${newRadio.length} new songs');

      // Replace radio queue with new songs
      _radioQueue.clear();

      for (final song in newRadio) {
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
        } catch (e) {
          print('⚠️ [RadioRefetch] Failed to add song: ${song.title}');
        }
      }

      // Reset radio index to start
      _radioQueueIndex = -1;

      // Update UI
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
        'radio_refetching': false,
        'refetch_success': true,
      });

      // Clear success flag after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _updateCustomState({'refetch_success': false});
      });

      // Reset skip counter
      _consecutiveSkipsInRadio = 0;

      print('🎉 [RadioRefetch] ========== REFETCH COMPLETE ==========');
      print('   New queue size: ${_radioQueue.length}');
      print('   Reset skip counter');
      print('=====================================================');
    } catch (e, stackTrace) {
      print('❌ [RadioRefetch] Error: $e');
      print(
        '   Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );

      _updateCustomState({'radio_refetching': false, 'refetch_failed': true});
    } finally {
      _isLoadingRadio = false;
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
    try {
      print('📝 [CustomState] Updating with keys: ${updates.keys.toList()}');

      if (updates.containsKey('radio_queue')) {
        final queue = updates['radio_queue'] as List?;
        print('   Radio queue update: ${queue?.length ?? 0} songs');
      }

      if (!customState.hasValue) {
        print('   Creating new customState');
        customState.add(updates);
      } else {
        final current = _safeCustomState();
        print(
          '   Merging with existing customState (${current.keys.length} keys)',
        );
        final merged = {...current, ...updates};
        customState.add(merged);

        // ✅ FIX: Verify the update was applied
        if (updates.containsKey('radio_queue')) {
          final verifyState = _safeCustomState();
          final verifyQueue = verifyState['radio_queue'] as List?;
          print(
            '   Verification: customState now has ${verifyQueue?.length ?? 0} songs',
          );
        }
      }
    } catch (e) {
      print('❌ [CustomState] Update error: $e');
      // Fallback: try direct add
      try {
        customState.add(updates);
      } catch (e2) {
        print('❌ [CustomState] Fallback also failed: $e2');
      }
    }
  }

  /// Clear playlist context
  void clearPlaylistContext() {
    print('🗑️ [Playlist Context] Clearing');
    _currentPlaylistId = null;
    _playlistCache.clear();
  }

  Map<String, dynamic> _safeCustomState() {
    try {
      if (!customState.hasValue) {
        return <String, dynamic>{};
      }

      final current = customState.value;
      if (current is Map<String, dynamic>) {
        return Map<String, dynamic>.from(current); // ✅ FIX: Create copy
      }

      print(
        '⚠️ [CustomState] Value is not Map<String, dynamic>: ${current.runtimeType}',
      );
      return <String, dynamic>{};
    } catch (e) {
      print('❌ [CustomState] Error reading: $e');
      return <String, dynamic>{};
    }
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
