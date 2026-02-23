import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/api_base/cache_manager.dart';
import 'package:vibeflow/api_base/innertubeaudio.dart';
import 'package:vibeflow/api_base/scrapper.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/api_base/ytradionew.dart';
import 'package:vibeflow/managers/vibeflow_engine_logger.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/providers/RealTimeService.dart';
import 'package:vibeflow/services/audioGoverner.dart';
import 'package:vibeflow/services/cacheManager.dart';
import 'package:vibeflow/services/last_played_service.dart';
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
  final YouTubeMusicScraper _scraper = YouTubeMusicScraper();
  bool _lineByLineLyricsEnabled = false;
  bool get lineByLineLyricsEnabled => _lineByLineLyricsEnabled;
  // final RadioService _radioService = RadioService();
  final NewYTRadio _newradioService = NewYTRadio();
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
  bool _trueRadioEnabled = false;
  AudioSourcePreference _audioSourcePreference =
      AudioSourcePreference.innerTube;

  //Sleep timers
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  Duration? _sleepTimerDuration;

  // Added normalization constants for loudness
  static const double _targetLUFS = -14.0; // Standard loudness target
  static const double _normalizationBoost = 1.0; // Default multiplier

  static const Duration _earlyWarningWindow = Duration(seconds: 15);

  //CrossFade Settings
  // final AudioPlayer _crossfadePlayer = AudioPlayer();
  bool _isCrossfading = false;
  bool _crossfadeEnabled = true;
  Duration _crossfadeDuration = const Duration(seconds: 3);
  DateTime? _crossfadeCompletedAt;

  void setCrossfadeEnabled(bool enabled) {
    _crossfadeEnabled = enabled;
    print('🎚️ [Crossfade] ${enabled ? "Enabled" : "Disabled"}');
    _updateCustomState({'crossfade_enabled': enabled});
  }

  void setCrossfadeDuration(Duration duration) {
    _crossfadeDuration = duration;
    print('🎚️ [Crossfade] Duration set to ${duration.inSeconds}s');
    _updateCustomState({'crossfade_duration': duration.inSeconds});
  }

  // Skip trackers for radio refetch
  int _consecutiveSkipsInRadio = 0;
  int _skipSequenceId = 0;
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
  final _explicitQueue = <MediaItem>[];

  // Gapless Settings
  String? _nextSongUrl;
  MediaItem? _nextSongMedia;
  bool _isPreFetching = false;
  static const Duration _preFetchWindow = Duration(seconds: 8);

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

  // intelligent radio refresher
  final List<DateTime> _rapidSkipTimes = [];
  static const int _rapidSkipThreshold = 5; // 5 skips trigger refresh
  static const Duration _rapidSkipWindow = Duration(seconds: 2);
  bool _isRefreshingDueToRapidSkips = false;

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
      _lineByLineLyricsEnabled =
          prefs.getBool('line_by_line_lyrics_enabled') ?? false;
      _lineByLineLyricsEnabled =
          prefs.getBool('line_by_line_lyrics_enabled') ?? false; // ✅ ADD THIS
      _trueRadioEnabled = prefs.getBool('true_radio_enabled') ?? false;
      final savedSourcePref = prefs.getString('audio_source_preference');
      if (savedSourcePref != null) {
        _audioSourcePreference = AudioSourcePreference.values.firstWhere(
          (e) => e.name == savedSourcePref,
          orElse: () => AudioSourcePreference.innerTube,
        );
      }
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
        'line_by_line_lyrics_enabled': _lineByLineLyricsEnabled, // ✅ ADD THIS
        'true_radio_enabled': _trueRadioEnabled,
      });
    } catch (e) {
      print('❌ [Settings] Error loading settings: $e');
    }
  }

  // Add with other settings methods
  Future<void> setTrueRadioEnabled(bool enabled) async {
    _trueRadioEnabled = enabled;
    print('⚙️ [Settings] True Radio: ${enabled ? "ON" : "OFF"}');

    // Save to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('true_radio_enabled', enabled);
      print('✅ [Settings] True Radio saved to storage');
    } catch (e) {
      print('❌ [Settings] Error saving True Radio: $e');
    }

    customState.add({..._safeCustomState(), 'true_radio_enabled': enabled});
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

      // ✅ NEW: Notify the effects channel about the session ID
      if (_audioSessionId != null) {
        await _reattachAudioEffects();
      }
    } catch (e) {
      print('❌ [AudioEffects] Failed to initialize: $e');
    }
  }

  // ✅ NEW: Re-attach audio effects to current session
  Future<void> _reattachAudioEffects() async {
    try {
      if (_audioSessionId == null) {
        print('⚠️ [AudioEffects] No audio session ID available');
        return;
      }

      const channel = MethodChannel('audio_effects');

      print(
        '🔄 [AudioEffects] Re-attaching effects to session $_audioSessionId',
      );

      final result = await channel.invokeMethod<bool>('reattachEffects', {
        'sessionId': _audioSessionId,
      });

      if (result == true) {
        print('✅ [AudioEffects] Successfully re-attached effects');
      } else {
        print('⚠️ [AudioEffects] Re-attach returned false');
      }
    } catch (e) {
      print('❌ [AudioEffects] Error re-attaching: $e');
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
        print('✅ Song completed, auto-advancing...');
        _governor.onSongCompleted(mediaItem.value?.title ?? 'Unknown');

        // Record listen stats on natural completion
        final completedMedia = mediaItem.value;
        if (completedMedia != null) {
          _userPreferences.recordListen(
            completedMedia.artist ?? 'Unknown Artist',
            completedMedia.title,
            listenDuration: completedMedia.duration ?? Duration.zero,
            totalDuration: completedMedia.duration ?? Duration.zero,
          );
        }

        // Don't auto-advance if crossfade is handling it
        if (_isCrossfading) {
          print('🎚️ [Crossfade] Completion suppressed — crossfade active');
          return;
        }

        // Suppress completion fired shortly after crossfade ended
        if (_crossfadeCompletedAt != null) {
          final msSince = DateTime.now()
              .difference(_crossfadeCompletedAt!)
              .inMilliseconds;
          if (msSince < 2000) {
            print('⏹️ [Completion] Suppressed — ${msSince}ms after crossfade');
            return;
          }
        }

        // ✅ FIX: Force-clear _isChangingSong on natural completion.
        // If crossfade just finished and left _isChangingSong=true, it would
        // block skipToNext() entirely, causing auto-stop after every song.
        if (_isChangingSong) {
          print(
            '⚠️ [Completion] Force-clearing stale _isChangingSong on natural completion',
          );
          _isChangingSong = false;
        }

        final completedVideoId = mediaItem.value?.id;
        print('   Completed videoId: $completedVideoId');

        if (_loopMode == LoopMode.one) {
          print('🔁 [LoopMode.one] Restarting');
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.play();
          return;
        }

        _tracker.stopTracking();
        playbackState.add(playbackState.value.copyWith(playing: true));

        Future.delayed(const Duration(milliseconds: 100), () async {
          final nowPlayingId = mediaItem.value?.id;
          if (nowPlayingId == completedVideoId) {
            print('⏭️ [Completion] Same song still active → skipToNext()');
            await skipToNext();
          } else {
            print(
              '✅ [Completion] Song already changed to $nowPlayingId — no action',
            );
          }
        });
      }

      // With:
      if (processingState == ProcessingState.idle) {
        if (_isCrossfading) {
          print('⏹️ [Idle] Suppressed during crossfade');
          return;
        }
        // ✅ FIX: Suppress idle for 1s after crossfade completes.
        // The old pipeline's stop() can fire idle AFTER _isCrossfading
        // is cleared but while the new song is already playing fine.
        if (_crossfadeCompletedAt != null) {
          final msSinceCrossfade = DateTime.now()
              .difference(_crossfadeCompletedAt!)
              .inMilliseconds;
          if (msSinceCrossfade < 2000) {
            print(
              '⏹️ [Idle] Suppressed — ${msSinceCrossfade}ms after crossfade',
            );
            return;
          }
        }
        print('⏹️ Player idle/stopped, stopping tracking');
        _tracker.stopTracking();
      }
    });

    _audioPlayer.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
      _maybePreFetchNextSong(position);
      _maybeCrossfade(position);
    });

    _audioPlayer.durationStream.listen((duration) {
      // Only update duration — never change title/artist/artwork.
      // Guard: don't emit during an active skip (skipToNext handles its own
      // duration emit with sequence+videoId guards). This prevents the stream
      // from firing a stale duration onto the wrong song mid-skip.
      if (duration != null && mediaItem.value != null && !_isChangingSong) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    _audioPlayer.processingStateStream.listen((state) {
      // Intentionally empty — playerStateStream handles all completion logic.
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

        // ✅ ADD: Prevent crashes from error events
        try {
          if (_isAutoRecovering) {
            print('⏳ [AudioPlayer] Recovery in progress, ignoring error');
            return;
          }

          final errorMessage = e.toString();
          final songTitle = mediaItem.value?.title ?? 'Unknown';

          if (_isRecoverableError(errorMessage)) {
            print(
              '🔄 [AudioPlayer] Recoverable error, starting smart recovery...',
            );
            _handleSmartAutoRecovery();
          } else {
            _governor.onPlaybackError(errorMessage, songTitle);
            _notifyPlaybackError(
              'Playback failed: ${_sanitizeErrorMessage(errorMessage)}',
              isSourceError: false,
            );
          }
        } catch (innerError) {
          // ✅ ADD: Catch any errors in error handler itself
          print('❌ [AudioPlayer] Error in error handler: $innerError');
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

      final freshUrl = await _core.forceRefreshAudioUrl(
        currentMedia.id,
        song: QuickPick(
          videoId: currentMedia.id,
          title: currentMedia.title,
          artists: currentMedia.artist ?? '',
          thumbnail: currentMedia.artUri?.toString() ?? '',
        ),
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

      // Clear queues and all radio state so next playSong() loads fresh
      _queue.clear();
      _radioQueue.clear();
      _radioQueueIndex = -1;
      _isLoadingRadio = false;
      _lastRadioVideoId = null;
      _currentRadioSourceId = null;
      _isChangingSong = false;
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

  Future<void> setLineByLineLyricsEnabled(bool enabled) async {
    _lineByLineLyricsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('line_by_line_lyrics_enabled', enabled);
    print('✅ Line-by-line lyrics ${enabled ? 'enabled' : 'disabled'}');
    _updateCustomState({'line_by_line_lyrics_enabled': enabled});
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    try {
      print('➕ [ExplicitQueue] Adding: ${mediaItem.title}');
      _explicitQueue.add(mediaItem);
      _broadcastExplicitQueue();
      print('✅ Explicit queue now has ${_explicitQueue.length} items');
    } catch (e) {
      print('❌ Error adding to explicit queue: $e');
    }
  }

  void _broadcastExplicitQueue() {
    final data = _explicitQueue
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
    _updateCustomState({
      'explicit_queue': data,
      'explicit_queue_count': data.length,
    });
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

  Future<void> setAudioSourcePreference(
    AudioSourcePreference preference,
  ) async {
    _audioSourcePreference = preference;
    _smartFetcher.preference = preference;
    print('⚙️ [Settings] Audio source preference: ${preference.name}');

    // Propagate to the InnerTubeAudio instance inside VibeFlowCore.
    // If your VibeFlowCore / SmartAudioFetcher exposes the InnerTubeAudio
    // instance, set it there too. Example:
    //   _core.innerTubeAudio.preference = preference;
    //   _smartFetcher.innerTubeAudio.preference = preference;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'audio_source_preference',
        preference.name, // stores 'innerTube' or 'ytMusicApi'
      );
      print('✅ [Settings] Audio source preference saved');
    } catch (e) {
      print('❌ [Settings] Error saving audio source preference: $e');
    }

    _updateCustomState({'audio_source_preference': preference.name});
  }

  // ==================== PUBLIC API ====================

  // FULL UPDATED playSong() METHOD WITH HQ ALBUM ART
  // Replace your existing playSong() method with this complete version

  Future<void> playSong(
    QuickPick song, {
    RadioSourceType sourceType = RadioSourceType.quickPick,
  }) async {
    final engineLogger = VibeFlowEngineLogger();
    if (engineLogger.isBlocked) {
      print(
        '🚫 [playSong] Engine is stopped — blocking playback of ${song.title}',
      );
      return;
    }

    // CROSSFADE CANCEL
    if (_isCrossfading) {
      print('🛑 [Crossfade] Cancelled by user skip');
      _isCrossfading = false;
      _nextSongUrl = null;
      _nextSongMedia = null;
      await _audioPlayer.setVolume(_loudnessNormalizationEnabled ? 0.85 : 1.0);
    }

    // ============================================================
    // SAFETY RESET (FIXED STRUCTURE)
    // ============================================================

    if (_isChangingSong) {
      if (_lastSongChangeTime == null) {
        print('⚠️ [HANDLER] Resetting stale _isChangingSong (no timestamp)');
        _isChangingSong = false;
      } else {
        final timeSinceLastChange = DateTime.now().difference(
          _lastSongChangeTime!,
        );

        // ✅ FIX: Raised from 5s → 12s. Crossfade can take up to 10s (3s fade +
        // network fetch). Resetting at 5s caused crossfade to be interrupted
        // by the very completion event it was supposed to suppress.
        if (timeSinceLastChange.inSeconds > 12) {
          print(
            '⚠️ [HANDLER] Forcing reset - stuck for ${timeSinceLastChange.inSeconds}s',
          );
          _isChangingSong = false;
        } else {
          print('⏳ [HANDLER] Song change already in progress, waiting...');
          await Future.delayed(const Duration(milliseconds: 300));

          if (_isChangingSong) {
            print('❌ [HANDLER] Still changing, aborting');
            return;
          }
        }
      }
    }

    // ✅ CORRECT POSITION (outside safety block)
    _isChangingSong = true;
    _lastSongChangeTime = DateTime.now();

    try {
      print('🎵 [HANDLER] ========== PLAYING SONG ==========');
      print('   Title: ${song.title}');
      print('   VideoId: ${song.videoId}');
      print('   Source Type: $sourceType');

      _governor.onPlaySong(song.title, song.artists);

      // SAME SONG CHECK
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

      // LOADING STATE
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      print('🛑 [HANDLER] Stopping previous playback...');

      if (!_isCrossfading) {
        await _tracker.stopTracking();
      } else {
        print(
          '⏸️ [playSong] Crossfade active — skipping stopTracking to preserve crossfade tracker',
        );
      }
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await _audioPlayer.stop();
      await Future.delayed(const Duration(milliseconds: 100));

      // ============================================================
      // RADIO DECISION LOGIC (UNCHANGED)
      // ============================================================

      bool shouldClearRadio = false;
      bool shouldLoadNewRadio = false;
      String? uiMessage;
      String? uiMessageType;

      if (sourceType == RadioSourceType.radio) {
        uiMessage = 'Radio mode active';
        uiMessageType = 'radio_active';

        final radioPos = _radioQueue.indexWhere(
          (item) => item.id == song.videoId,
        );

        if (radioPos != -1) {
          _radioQueueIndex = radioPos;
        }
      } else if (sourceType == RadioSourceType.playlist) {
        shouldClearRadio = true;
        _isPlayingPlaylist = true;
        _playlistCurrentIndex = 0;

        uiMessage = 'Radio disabled in playlist mode';
        uiMessageType = 'playlist_mode';
      } else if (sourceType == RadioSourceType.communityPlaylist) {
        shouldClearRadio = true;

        uiMessage = 'Loading playlist continuation...';
        uiMessageType = 'community_playlist_loading';
      } else if (sourceType == RadioSourceType.search) {
        final isDifferent = _lastPlayedFromSearch != song.videoId;

        if (isDifferent) {
          shouldClearRadio = true;
          shouldLoadNewRadio = true;
          _lastPlayedFromSearch = song.videoId;
        }

        uiMessage = isDifferent
            ? 'Loading radio from search...'
            : 'Using existing radio queue';

        uiMessageType = isDifferent ? 'loading_search' : 'existing_radio';
      } else if (sourceType == RadioSourceType.quickPick) {
        final isDifferent = _lastPlayedFromQuickPick != song.videoId;

        if (isDifferent) {
          shouldClearRadio = true;
          shouldLoadNewRadio = true;
          _lastPlayedFromQuickPick = song.videoId;
        }

        uiMessage = isDifferent
            ? 'Loading radio from quick pick...'
            : 'Using existing radio queue';

        uiMessageType = isDifferent ? 'loading_quickpick' : 'existing_radio';
      } else if (sourceType == RadioSourceType.savedSongs) {
        final isDifferent = _lastPlayedFromSavedSongs != song.videoId;

        if (isDifferent) {
          shouldClearRadio = true;
          shouldLoadNewRadio = true;
          _lastPlayedFromSavedSongs = song.videoId;
        }

        uiMessage = isDifferent
            ? 'Loading radio from saved songs...'
            : 'Using existing radio queue';

        uiMessageType = isDifferent ? 'loading_saved' : 'existing_radio';
      } else {
        shouldClearRadio = true;
        shouldLoadNewRadio = true;

        uiMessage = 'Loading radio...';
        uiMessageType = 'loading_default';
      }

      _updateCustomState({
        'radio_decision': uiMessage,
        'radio_decision_type': uiMessageType,
        'radio_loading': shouldLoadNewRadio,
        'is_playlist_mode': _isPlayingPlaylist,
      });

      if (shouldClearRadio) {
        _radioQueue.clear();
        _radioQueueIndex = -1;
        _lastRadioVideoId = null;
        _isLoadingRadio = false;
        _currentRadioSourceId = null;
      }

      _currentSourceType = sourceType;

      // ============================================================
      // MEDIA ITEM + AUDIO (unchanged)
      // ============================================================

      final useHqArt =
          sourceType == RadioSourceType.playlist ||
          sourceType == RadioSourceType.communityPlaylist ||
          _isPlayingPlaylist;

      final newMediaItem = await _createMediaItemWithHqArt(
        song,
        useHqArt: useHqArt,
      );

      _queue.clear();
      _queue.add(newMediaItem);
      _currentIndex = 0;
      queue.add(_queue);
      mediaItem.add(newMediaItem);

      String? audioUrl = await _smartFetcher.getAudioUrlSmart(
        song.videoId,
        song: song,
      );

      if (audioUrl == null || audioUrl.isEmpty) {
        audioUrl = await _core.getAudioUrl(song.videoId, song: song);
      }

      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Failed to get audio URL');
      }

      await _audioPlayer.setUrl(audioUrl);
      await Future.delayed(const Duration(milliseconds: 150));
      await _reattachAudioEffects();
      await _audioPlayer.play();

      await _tracker.startTracking(song);
      await LastPlayedService.saveLastPlayed(song);

      AudioUrlCache().cache(song, audioUrl);

      // ============================================================
      // RADIO LOAD (PRIMARY)
      // ============================================================

      if (shouldLoadNewRadio) {
        _currentRadioSourceId = song.videoId;
        // Do NOT set _isLoadingRadio=true here — loadRadioImmediately owns it.
        // Setting it here before the call races with the stale-flag reset inside
        // loadRadioImmediately, which checks (isLoadingRadio && queue.isEmpty).

        _updateCustomState({
          'radio_loading': true,
          'radio_decision': uiMessage,
        });

        unawaited(
          loadRadioImmediately(song)
              .then((_) {
                _updateCustomState({
                  'radio_loading': false,
                  'radio_decision': 'Radio loaded',
                });
                _broadcastRadioState();
              })
              .catchError((e) {
                _updateCustomState({
                  'radio_loading': false,
                  'radio_error': e.toString(),
                });
              }),
        );
      }
      // ============================================================
      // RADIO LOAD (FALLBACK — FIXED)
      // ============================================================
      else if (!shouldClearRadio &&
          _radioQueue.isEmpty &&
          !_isPlayingPlaylist) {
        _currentRadioSourceId = song.videoId;
        _isLoadingRadio = true;

        _updateCustomState({
          'radio_loading': true,
          'radio_decision': 'Loading radio...',
        });

        _isLoadingRadio = false; // resets before starting fresh
        unawaited(
          loadRadioImmediately(song)
              .then((_) {
                _updateCustomState({
                  'radio_loading': false,
                  'radio_decision': 'Radio loaded',
                });

                _broadcastRadioState();
              })
              .catchError((e) {
                _isLoadingRadio = false;

                _updateCustomState({
                  'radio_loading': false,
                  'radio_error': e.toString(),
                });
              }),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error playing song: $e');
      print(stackTrace);

      _isLoadingRadio = false;

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
    final engineLogger = VibeFlowEngineLogger();
    if (engineLogger.isBlocked) {
      print(
        '🚫 [playSongFromRadio] Engine is stopped — blocking ${song.title}',
      );
      return;
    }

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

      if (currentMedia != null) {
        print('🔄 Different song detected:');
        print('   Old: ${currentMedia.title} by ${currentMedia.artist}');
        print('   New: ${song.title} by ${song.artists}');
      }

      // Set loading state
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      print('🛑 [HANDLER] Stopping previous playback...');
      await _tracker.stopTracking();

      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await _audioPlayer.stop();
      await Future.delayed(const Duration(milliseconds: 100));

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

      // ✅ FIX: Update radio queue index BEFORE emitting mediaItem,
      // so any listener that reads queue state sees consistent data.
      final radioIndex = _radioQueue.indexWhere(
        (item) => item.id == song.videoId,
      );

      if (radioIndex != -1) {
        _radioQueueIndex = radioIndex;
        print('✅ [HANDLER] Found in radio queue at index: $_radioQueueIndex');
        print(
          '   Current position: ${_radioQueueIndex + 1}/${_radioQueue.length}',
        );
      } else {
        print('⚠️ [HANDLER] Song NOT found in radio queue — appending');
        _radioQueue.add(newMediaItem);
        _radioQueueIndex = _radioQueue.length - 1;

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

      // ✅ CRITICAL FIX: Emit mediaItem NOW — before the slow _getAudioUrl()
      // network call. This is what updates the UI (title, artist, artwork)
      // immediately. Without this, the old song's data shows until the URL
      // fetch completes (2–5 seconds), which is the exact bug being fixed.
      mediaItem.add(newMediaItem);

      print('🔍 [HANDLER] Getting audio URL...');
      _governor.onLoadingUrl(song.title);

      final audioUrl = await _getAudioUrl(song.videoId, song: song);
      if (audioUrl == null) throw Exception('Failed to get audio URL');

      print('✅ [HANDLER] Audio URL obtained, setting player...');

      try {
        await _audioPlayer.setUrl(audioUrl);
        await Future.delayed(const Duration(milliseconds: 150));
        await _reattachAudioEffects();
      } catch (e) {
        print('❌ [HANDLER] setUrl failed: $e');
        throw Exception('Failed to set audio source: $e');
      }

      print('▶️ [HANDLER] Starting playback...');
      await _audioPlayer.play();

      // Wait for duration to resolve and update mediaItem with it
      int attempts = 0;
      while (_audioPlayer.duration == null && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (_audioPlayer.duration != null) {
        // Only update if this song is still the active one (user may have
        // skipped again during the duration-wait loop).
        if (mediaItem.value?.id == song.videoId) {
          mediaItem.add(newMediaItem.copyWith(duration: _audioPlayer.duration));
        }
      }

      print('📝 [HANDLER] Starting realtime tracking...');
      await _tracker.startTracking(song);
      await LastPlayedService.saveLastPlayed(song);

      print('✅ [HANDLER] ========== PLAYBACK STARTED FROM RADIO ==========');
      print(
        '   Radio queue position: ${_radioQueueIndex + 1}/${_radioQueue.length}',
      );
      print('   Radio source ID: $_currentRadioSourceId');

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

  // 4. The pre-fetch gapless method
  Future<void> _maybePreFetchNextSong(Duration position) async {
    if (_isCrossfading || _isPreFetching) return;
    // ✅ Don't pre-fetch if explicit queue has songs — no crossfade will happen
    if (_explicitQueue.isNotEmpty) return;

    final nextMedia = _peekNextMedia();
    if (nextMedia == null) {
      if (_isLoadingRadio) return;
      if (_radioQueue.isEmpty && !_isLoadingRadio && !_isPlayingPlaylist) {
        final currentMedia = mediaItem.value;
        if (currentMedia != null) {
          print('⚠️ [PreFetch] Radio empty at window, triggering load...');
          final qp = _quickPickFromMediaItem(currentMedia);
          _currentRadioSourceId = currentMedia.id;
          unawaited(loadRadioImmediately(qp));
        }
      }
      return;
    }

    // Already pre-fetched for this exact song — nothing to do
    if (_nextSongMedia?.id == nextMedia.id && _nextSongUrl != null) return;

    // Clear stale pre-fetch if the upcoming song changed
    if (_nextSongMedia?.id != nextMedia.id && _nextSongUrl != null) {
      print(
        '🗑️ [PreFetch] Clearing stale pre-fetch for ${_nextSongMedia?.title}, next is now ${nextMedia.title}',
      );
      _nextSongUrl = null;
      _nextSongMedia = null;
    }

    Duration? duration = _audioPlayer.duration ?? mediaItem.value?.duration;
    if (duration == null || duration == Duration.zero) return;

    final remaining = duration - position;
    if (remaining <= Duration.zero || remaining > _preFetchWindow) return;

    _isPreFetching = true;
    print(
      '🎵 [PreFetch] Fetching next song URL at ${remaining.inSeconds}s remaining: ${nextMedia.title}',
    );

    try {
      final url = await _getAudioUrl(
        nextMedia.id,
        song: _quickPickFromMediaItem(nextMedia),
      );
      if (url != null) {
        _nextSongUrl = url;
        _nextSongMedia = nextMedia;
        print('✅ [PreFetch] URL ready for: ${nextMedia.title}');
      } else {
        print('⚠️ [PreFetch] Could not get URL for: ${nextMedia.title}');
      }
    } catch (e) {
      print('❌ [PreFetch] Error: $e');
    } finally {
      _isPreFetching = false;
    }
  }

  //============================CrossFade======================================================================================
  Future<void> _maybeCrossfade(Duration position) async {
    if (!_crossfadeEnabled || _isCrossfading) return;

    // ✅ Don't crossfade if explicit queue has songs — let skipToNext() handle it normally
    if (_explicitQueue.isNotEmpty) return;

    Duration? duration = _audioPlayer.duration ?? mediaItem.value?.duration;
    if (duration == null || duration == Duration.zero) return;

    final remaining = duration - position;
    if (remaining <= Duration.zero) return;

    if (remaining <= _crossfadeDuration &&
        remaining > const Duration(milliseconds: 500) &&
        _nextSongUrl != null &&
        !_isCrossfading) {
      await _startCrossfade();
    }
  }

  Future<void> _startCrossfade() async {
    if (_nextSongUrl == null || _nextSongMedia == null) return;

    _isCrossfading = true;

    final targetMedia = _nextSongMedia!;
    final targetUrl = _nextSongUrl!;
    _nextSongUrl = null;
    _nextSongMedia = null;

    print('🎚️ [Crossfade] Starting → ${targetMedia.title}');
    mediaItem.add(targetMedia);

    try {
      final baseVolume = _loudnessNormalizationEnabled ? 0.85 : 1.0;
      const steps = 30;
      final stepMs = _crossfadeDuration.inMilliseconds ~/ steps;

      for (int i = 1; i <= steps; i++) {
        await Future.delayed(Duration(milliseconds: stepMs));
        if (!_isCrossfading) {
          await _audioPlayer.setVolume(baseVolume);
          return;
        }
        final progress = i / steps;
        await _audioPlayer.setVolume(baseVolume * (1.0 - progress));
      }

      await _audioPlayer.stop();
      await _audioPlayer.setUrl(targetUrl);
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.setVolume(baseVolume);
      await _audioPlayer.play();

      _currentSourceType = RadioSourceType.radio;
      _advanceQueueIndex();
      _broadcastRadioState();

      final quickPick = _quickPickFromMediaItem(targetMedia);
      await LastPlayedService.saveLastPlayed(quickPick);
      await _reattachAudioEffects();

      if (mediaItem.value?.id == targetMedia.id) {
        await _tracker.stopTracking();
        await _tracker.startTracking(quickPick);
      }

      // ✅ FIX: Clear crossfade flag BEFORE returning so position stream
      // immediately resumes driving _maybePreFetchNextSong and _maybeCrossfade
      // for the new song.
      _isCrossfading = false;
      _crossfadeCompletedAt = DateTime.now();
      print('🎉 [Crossfade] Done: ${targetMedia.title}');

      // ✅ FIX: Re-wire position listener after new audio source is loaded.
      // just_audio reuses the same stream but the pipeline resets on setUrl().
      // Explicitly kick the position stream so prefetch/crossfade resumes.
      _onCrossfadeComplete();
    } catch (e) {
      print('❌ [Crossfade] Failed: $e');
      _isCrossfading = false;
      _nextSongUrl = null;
      _nextSongMedia = null;
      await _audioPlayer.setVolume(_loudnessNormalizationEnabled ? 0.85 : 1.0);
      print('🔄 [Crossfade] Attempting fallback skip after failure');
      await skipToNext();
    }
  }
  // ============================================================
  // FIX 3: Add _onCrossfadeComplete() helper
  // Called after each crossfade to verify position stream is live
  // and reset any stale prefetch state for the new song.
  // ADD this new method to the class:
  // ============================================================

  void _onCrossfadeComplete() {
    // Reset prefetch state so the new song's window is clean
    _nextSongUrl = null;
    _nextSongMedia = null;
    _isPreFetching = false;

    // Verify the player is actually playing after crossfade
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_audioPlayer.playing && !_isCrossfading) {
        print(
          '⚠️ [Crossfade] Player not playing 500ms after crossfade — forcing play()',
        );
        _audioPlayer.play();
      } else {
        print('✅ [Crossfade] Player confirmed playing after crossfade');
      }
    });
  }

  void _advanceQueueIndex() {
    if (_isPlayingPlaylist && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      _playlistCurrentIndex++;
    } else if (_radioQueue.isNotEmpty) {
      if (_radioQueueIndex == -1) {
        _radioQueueIndex = 0;
      } else if (_radioQueueIndex < _radioQueue.length - 1) {
        _radioQueueIndex++;
      }
      _currentSourceType = RadioSourceType.radio;
      _broadcastRadioState();
    }
  }
  //============================CrossFade----Ends======================================================================================

  MediaItem? _peekNextMedia() {
    if (_isPlayingPlaylist && _queue.isNotEmpty) {
      final next = _currentIndex + 1;
      return next < _queue.length ? _queue[next] : null;
    }
    if (_radioQueue.isNotEmpty) {
      if (_radioQueueIndex == -1) return _radioQueue[0]; // ← this should work
      final next = _radioQueueIndex + 1;
      return next < _radioQueue.length ? _radioQueue[next] : null;
    }
    return null;
  }

  // ============================================================================
  // FIXED _loadRadioImmediately() METHOD
  // Replace your existing _loadRadioImmediately() with this
  // ============================================================================

  Future<void> loadRadioImmediately(QuickPick song) async {
    print('📻 [Radio] _loadRadioImmediately called for: ${song.title}');
    print('   VideoId: ${song.videoId}');
    print('   Current _isLoadingRadio: $_isLoadingRadio');
    print('   Current _lastRadioVideoId: $_lastRadioVideoId');
    print('   Current _radioQueue.length: ${_radioQueue.length}');
    print('   Is playlist mode: $_isPlayingPlaylist');
    print('   True Radio enabled: $_trueRadioEnabled');

    // Don't load radio if in playlist mode
    if (_isPlayingPlaylist) {
      print('📋 [Radio] In playlist mode - skipping radio load');
      return;
    }

    // Check if already loading
    if (_isLoadingRadio) {
      if (_radioQueue.isNotEmpty) {
        print('⏳ [Radio] Already loading radio for same context, skipping');
        return;
      } else {
        print(
          '⚠️ [Radio] _isLoadingRadio=true but queue empty — stale flag, resetting',
        );
        _isLoadingRadio = false;
      }
    }

    // ✅ FIX: Only skip if queue is genuinely populated for this exact song.
    // Previously this returned early when _radioQueue had leftover songs from
    // a previous track, meaning the new song's radio was never actually loaded.
    if (_lastRadioVideoId == song.videoId && _radioQueue.length > 1) {
      print(
        '✅ [Radio] Radio already loaded for ${song.videoId} (${_radioQueue.length} songs)',
      );
      _broadcastRadioState();
      return;
    }

    _isLoadingRadio = true;
    _lastRadioVideoId = song.videoId;
    _governor.onRadioStart(song.title);

    print('🔄 [Radio] Starting radio load...');

    try {
      List<QuickPick> radioSongs = [];

      // Try True Radio first if enabled
      if (_trueRadioEnabled) {
        print('📻 [Radio] Using True Radio (NewYTRadio) service...');
        try {
          // Try NewYTRadio first
          radioSongs = await _newradioService
              .getUpNext(song.videoId, limit: 25)
              .timeout(const Duration(seconds: 8));

          print('📻 [Radio] NewYTRadio returned ${radioSongs.length} songs');

          // If NewYTRadio returns empty, throw to trigger fallback
          if (radioSongs.isEmpty) {
            throw Exception('NewYTRadio returned empty list');
          }
        } catch (e) {
          print('⚠️ [Radio] True Radio failed: $e');
          print('🔄 [Radio] Falling back to SmartRadioService...');

          // Fallback to SmartRadioService
          radioSongs = await _smartRadioService
              .getSmartRadio(
                videoId: song.videoId,
                title: song.title,
                artist: song.artists,
                limit: 25,
                diversifyArtists: false,
              )
              .timeout(const Duration(seconds: 8));
        }
      } else {
        // Use classic radio (SmartRadioService)
        print('📻 [Radio] Using classic radio (SmartRadioService)...');
        radioSongs = await _smartRadioService
            .getSmartRadio(
              videoId: song.videoId,
              title: song.title,
              artist: song.artists,
              limit: 25,
              diversifyArtists: false,
            )
            .timeout(const Duration(seconds: 8));
      }

      print('📻 [Radio] Service returned ${radioSongs.length} songs');

      if (radioSongs.isEmpty) {
        print('⚠️ [Radio] No radio songs returned');
        _governor.onRadioQueueEmpty();

        // Try ultimate fallback with SmartRadioService if we haven't already
        if (_trueRadioEnabled && radioSongs.isEmpty) {
          print('🔄 [Radio] Ultimate fallback: SmartRadioService');
          radioSongs = await _smartRadioService.getSmartRadio(
            videoId: song.videoId,
            title: song.title,
            artist: song.artists,
            limit: 25,
            diversifyArtists: false,
          );
        }

        if (radioSongs.isEmpty) {
          _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
          return;
        }
      }

      print(
        '✅ [Radio] Got ${radioSongs.length} songs, converting to MediaItems...',
      );

      _radioQueue.clear();

      int successCount = 0;
      final radioQueueData = <Map<String, dynamic>>[];

      for (final song in radioSongs) {
        try {
          Duration? parsedDuration;
          if (song.duration != null && song.duration!.isNotEmpty) {
            print(
              '🕐 [Radio] Parsing duration for ${song.title}: "${song.duration}"',
            );
            parsedDuration = _parseDurationString(song.duration!);
            print('   Parsed to: $parsedDuration');
          } else {
            print(
              '⚠️ [Radio] Song ${song.title} has no duration: ${song.duration}',
            );
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

        // Rebuild data after shuffle
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

      try {
        _updateCustomState({
          'radio_queue': radioQueueData,
          'radio_queue_count': radioQueueData.length,
          'radio_source': _trueRadioEnabled ? 'true_radio' : 'classic_radio',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final currentState = _safeCustomState();
        final publishedQueue =
            currentState['radio_queue'] as List<dynamic>? ?? [];
        print(
          '✅ [Radio] Verification: customState now has ${publishedQueue.length} songs',
        );

        if (publishedQueue.isEmpty && radioQueueData.isNotEmpty) {
          print('⚠️ [Radio] WARNING: Publishing failed, retrying...');
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
      print(
        '   Radio type: ${_trueRadioEnabled ? "True Radio" : "Classic Radio"}',
      );
      print('   Published to UI: ${radioQueueData.length} songs');
      print('=========================================================');

      await Future.delayed(const Duration(milliseconds: 100));
      _broadcastRadioState();
      print('📡 [Radio] Force broadcasted state after loading');
    } catch (e, stackTrace) {
      print('❌ [Radio] Load failed with exception: $e');
      print('   Stack trace:');
      print(stackTrace.toString().split('\n').take(5).join('\n'));

      _radioQueue.clear();
      _updateCustomState({'radio_queue': [], 'radio_queue_count': 0});
    } finally {
      _isLoadingRadio = false;
      if (_isChangingSong && !_isCrossfading && _lastSongChangeTime != null) {
        final elapsed = DateTime.now().difference(_lastSongChangeTime!);
        if (elapsed.inSeconds > 3) {
          print('⚠️ [Radio] Resetting stuck _isChangingSong flag');
          _isChangingSong = false;
        }
      }
      print('🏁 [Radio] Finished loading');
      print('   Final _radioQueue.length: ${_radioQueue.length}');
      print('   Final _isLoadingRadio: $_isLoadingRadio');
    }
  }

  Future<void> _ensureRadioLoaded(QuickPick song) async {
    if (_isPlayingPlaylist) return;
    if (_radioQueue.isNotEmpty && _lastRadioVideoId == song.videoId) return;
    if (_isLoadingRadio) {
      print('⏳ [EnsureRadio] Already loading, waiting...');
      await _waitForRadioToLoad();
      return;
    }
    print('🔄 [EnsureRadio] Loading radio for: ${song.title}');
    await loadRadioImmediately(song);
  }

  Future<void> _checkAndFetchMoreRadio() async {
    // ✅ Hard guard — only one expansion at a time
    if (_isLoadingRadio) {
      print('⏳ [Radio Expansion] Already loading, skipping');
      return;
    }

    final currentPosition = _radioQueueIndex + 1;
    final queueSize = _radioQueue.length;

    print('📊 [Radio Expansion] Check: Position $currentPosition/$queueSize');

    final positionInBatch = currentPosition % _initialRadioSize;
    final isAtThreshold = positionInBatch == _radioRefetchThreshold;

    if (!isAtThreshold) return;

    print(
      '🎯 [Radio Expansion] Threshold reached at position $currentPosition!',
    );

    if (queueSize >= _maxRadioQueueSize) {
      final nearEnd = currentPosition >= _maxRadioQueueSize - 2;

      if (nearEnd) {
        // ✅ Guard: don't reset if already loading or another reset just happened
        if (_isLoadingRadio) return;

        print('🔄 [Radio Expansion] Near end of max queue, resetting...');

        // ✅ Capture seed BEFORE clearing
        final seedMedia = _radioQueue[_radioQueueIndex];
        final quickPick = _quickPickFromMediaItem(seedMedia);

        // ✅ Set loading flag BEFORE clearing to block any concurrent calls
        _isLoadingRadio = true;
        _radioQueue.clear();
        _radioQueueIndex = -1;
        _lastRadioVideoId = null;
        _currentRadioSourceId = seedMedia.id;
        _isLoadingRadio = false; // loadRadioImmediately will set it again

        await loadRadioImmediately(quickPick);
      }
      return;
    }

    // ✅ Set loading flag immediately to block concurrent rapid-skip calls
    _isLoadingRadio = true;

    final seedSong = _radioQueue[_radioQueueIndex];
    print('🌱 [Radio Expansion] Seed: ${seedSong.title}');

    try {
      final remainingSpace = _maxRadioQueueSize - queueSize;
      final songsToFetch = remainingSpace < _radioBatchSize
          ? remainingSpace
          : _radioBatchSize;

      List<QuickPick> newRadioSongs = [];

      if (_trueRadioEnabled) {
        try {
          newRadioSongs = await _newradioService
              .getUpNext(seedSong.id, limit: songsToFetch)
              .timeout(const Duration(seconds: 6));
          if (newRadioSongs.isEmpty)
            throw Exception('NewYTRadio returned empty');
        } catch (e) {
          print('⚠️ [Radio Expansion] True Radio failed: $e, falling back...');
          newRadioSongs = await _smartRadioService.getSmartRadio(
            videoId: seedSong.id,
            title: seedSong.title,
            artist: seedSong.artist ?? 'Unknown Artist',
            limit: songsToFetch,
            diversifyArtists: false,
          );
        }
      } else {
        newRadioSongs = await _smartRadioService.getSmartRadio(
          videoId: seedSong.id,
          title: seedSong.title,
          artist: seedSong.artist ?? 'Unknown Artist',
          limit: songsToFetch,
          diversifyArtists: false,
        );
      }

      if (newRadioSongs.isEmpty) {
        print('⚠️ [Radio Expansion] No new songs returned');
        return;
      }

      // ✅ Verify queue wasn't wiped by a concurrent operation during await
      if (_radioQueue.isEmpty) {
        print(
          '⚠️ [Radio Expansion] Queue was cleared during fetch — aborting append',
        );
        return;
      }

      int addedCount = 0;
      for (final song in newRadioSongs) {
        try {
          final alreadyExists = _radioQueue.any(
            (item) => item.id == song.videoId,
          );
          if (alreadyExists) continue;

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

          if (_radioQueue.length >= _maxRadioQueueSize) break;
        } catch (e) {
          print('⚠️ [Radio Expansion] Failed to add ${song.title}: $e');
        }
      }

      print(
        '✅ [Radio Expansion] Added $addedCount songs, total: ${_radioQueue.length}',
      );

      final radioQueueData = _radioQueue
          .map(
            (item) => {
              'id': item.id,
              'title': item.title,
              'artist': item.artist ?? 'Unknown Artist',
              'artUri': item.artUri?.toString(),
              'duration': item.duration?.inMilliseconds,
            },
          )
          .toList();

      _updateCustomState({
        'radio_queue': radioQueueData,
        'radio_queue_count': radioQueueData.length,
      });
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

    _updateCustomState({
      'radio_queue': radioQueueData,
      'radio_queue_count': _radioQueue.length,
      'radio_source_type': _trueRadioEnabled ? 'true_radio' : 'classic_radio',
    });

    print(
      '📡 [Radio] Broadcasted radio state: ${_radioQueue.length} songs (${_trueRadioEnabled ? "True Radio" : "Classic"})',
    );
  }

  /// Refresh radio due to rapid skips (5-6 skips in 2 seconds)
  Future<void> _refreshRadioDueToRapidSkips() async {
    if (_isRefreshingDueToRapidSkips || _isLoadingRadio) {
      print('⏳ [RapidRefresh] Already refreshing, skipping');
      return;
    }

    _isRefreshingDueToRapidSkips = true;

    print(
      '⚡ [RapidRefresh] ========== REFRESHING RADIO DUE TO RAPID SKIPS ==========',
    );
    print(
      '   Rapid skips: ${_rapidSkipTimes.length} in last ${_rapidSkipWindow.inSeconds}s',
    );

    // Show UI notification
    _updateCustomState({
      'radio_refetching': true,
      'refetch_reason': 'Finding better music for you...',
      'rapid_refresh': true,
    });

    try {
      // Get current song as seed
      MediaItem? seedMedia;
      QuickPick? seedSong;

      if (_radioQueue.isNotEmpty && _radioQueueIndex >= 0) {
        seedMedia = _radioQueue[_radioQueueIndex];
        seedSong = _quickPickFromMediaItem(seedMedia);
      } else {
        seedMedia = mediaItem.value;
        if (seedMedia != null) {
          seedSong = _quickPickFromMediaItem(seedMedia);
        }
      }

      if (seedSong == null) {
        print('❌ [RapidRefresh] No seed song available');
        return;
      }

      print('🎵 [RapidRefresh] Seed: ${seedSong.title} by ${seedSong.artists}');

      // Get user preferences for diversification
      final preferredArtists = _userPreferences.getSuggestedArtists(limit: 8);
      final skippedArtists = _userPreferences.getRecentSkippedArtists(limit: 5);

      print('📊 [RapidRefresh] Preferred artists: $preferredArtists');
      print('📊 [RapidRefresh] Skipped artists: $skippedArtists');

      // Set loading flag
      _isLoadingRadio = true;

      List<QuickPick> newRadio = [];

      // Try multiple strategies in parallel for fastest results
      final futures = <Future<List<QuickPick>>>[];

      // Strategy 1: Smart radio with diversification (avoid skipped artists)
      futures.add(
        _smartRadioService
            .getSmartRadio(
              videoId: seedSong.videoId,
              title: seedSong.title,
              artist: seedSong.artists is List<String>
                  ? (seedSong.artists as List<String>).join(', ')
                  : seedSong.artists, // Convert to String
              limit: 15,
              diversifyArtists: true,
              avoidArtists: skippedArtists,
            )
            .timeout(const Duration(seconds: 5), onTimeout: () => []),
      );
      // Strategy 2: True Radio if enabled
      if (_trueRadioEnabled) {
        futures.add(
          _newradioService
              .getUpNext(seedSong.videoId, limit: 15)
              .timeout(const Duration(seconds: 5), onTimeout: () => []),
        );
      }

      // Strategy 3: Try a different seed (preferred artist if available)
      if (preferredArtists.isNotEmpty) {
        futures.add(
          _getRadioFromPreferredArtist(
            seedSong,
            preferredArtists.first,
          ).timeout(const Duration(seconds: 5), onTimeout: () => []),
        );
      }

      // Wait for first successful result
      final results = await Future.wait(futures);

      // Take the first non-empty result
      for (final result in results) {
        if (result.isNotEmpty) {
          newRadio = result;
          break;
        }
      }

      // If all failed, use fallback
      if (newRadio.isEmpty) {
        print('⚠️ [RapidRefresh] All strategies failed, using fallback');
        newRadio = await _smartRadioService
            .getSmartRadio(
              videoId: seedSong.videoId,
              title: seedSong.title,
              artist: seedSong.artists,
              limit: 20,
              diversifyArtists: true,
            )
            .timeout(const Duration(seconds: 4), onTimeout: () => []);
      }

      if (newRadio.isEmpty) {
        print('❌ [RapidRefresh] Failed to get new radio');
        _updateCustomState({
          'radio_refetching': false,
          'refetch_failed': true,
          'rapid_refresh': false,
        });
        return;
      }

      print('✅ [RapidRefresh] Got ${newRadio.length} new songs');

      // Replace radio queue (keep current position)
      final currentIndex = _radioQueueIndex;
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
          print('⚠️ [RapidRefresh] Failed to add song: ${song.title}');
        }
      }

      // Restore index (or set to 0 if out of bounds)
      _radioQueueIndex = currentIndex < _radioQueue.length ? currentIndex : 0;

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
        'rapid_refresh': false,
      });

      // Clear success flag after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _updateCustomState({'refetch_success': false});
      });

      // Reset skip counters
      _consecutiveSkipsInRadio = 0;
      _rapidSkipTimes.clear();

      print('🎉 [RapidRefresh] ========== REFRESH COMPLETE ==========');
      print('   New queue size: ${_radioQueue.length}');
      print('   Reset skip counters');
    } catch (e, stackTrace) {
      print('❌ [RapidRefresh] Error: $e');
      print(
        '   Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );

      _updateCustomState({
        'radio_refetching': false,
        'refetch_failed': true,
        'rapid_refresh': false,
      });
    } finally {
      _isLoadingRadio = false;
      _isRefreshingDueToRapidSkips = false;
    }
  }

  /// Helper to get radio from a preferred artist
  /// Helper to get radio from a preferred artist
  Future<List<QuickPick>> _getRadioFromPreferredArtist(
    QuickPick seedSong,
    String preferredArtist,
  ) async {
    print('🎵 [RapidRefresh] Trying preferred artist: $preferredArtist');

    try {
      // Search for the artist to get a seed song
      final searchResults = await _scraper.searchSongs(
        preferredArtist,
        limit: 5,
      );

      if (searchResults.isNotEmpty) {
        final artistSeed = searchResults.first;

        // ✅ FIX: Convert artist string to List<String>
        return await _smartRadioService.getSmartRadio(
          videoId: artistSeed.videoId,
          title: artistSeed.title,
          artist:
              [preferredArtist]
                  as String, // Use preferredArtist as List<String>
          limit: 15,
          diversifyArtists: true,
        );
      }
    } catch (e) {
      print('⚠️ [RapidRefresh] Preferred artist strategy failed: $e');
    }

    return [];
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
          await loadRadioImmediately(quickPick);
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
        await loadRadioImmediately(quickPick);
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
        // final radioSongs = await _radioService.getRadioForSong(
        //   videoId: lastPlaylistSong.videoId,
        //   title: lastPlaylistSong.title,
        //   artist: lastPlaylistSong.artists.join(', '),
        //   limit: 20 - _radioQueue.length,
        // );

        final radioSongs = await _newradioService.getUpNext(
          lastPlaylistSong.videoId,
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
      // ✅ NEW: Re-attach audio effects
      await Future.delayed(const Duration(milliseconds: 100));
      await _reattachAudioEffects();
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
    final engineLogger = VibeFlowEngineLogger();
    if (engineLogger.isBlocked) {
      print(
        '🚫 [_getAudioUrl] Engine is stopped — blocking fetch for $videoId',
      );
      return null;
    }
    print('🔍 [_getAudioUrl] Fetching for videoId: $videoId');
    print('   Song: ${song?.title ?? "unknown"}');

    // Check internal cache first (with expiry)
    // Check internal cache (with expiry)
    if (_urlCache.containsKey(videoId) && _urlCacheTime.containsKey(videoId)) {
      final cacheAge = DateTime.now().difference(_urlCacheTime[videoId]!);
      if (cacheAge < _cacheExpiry) {
        final cachedUrl = _urlCache[videoId]!;
        // ✅ Reject ANDROID client URLs — they 403 in ExoPlayer without matching UA
        if (_isExoPlayerSafeUrl(cachedUrl)) {
          print('⚡ [Internal Cache] Using URL (age: ${cacheAge.inMinutes}min)');
          return cachedUrl;
        } else {
          print(
            '🗑️ [Internal Cache] Rejecting ANDROID client URL, re-fetching',
          );
          _urlCache.remove(videoId);
          _urlCacheTime.remove(videoId);
          await AudioUrlCache().remove(videoId);
        }
      } else {
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

  /// Returns false for ANDROID client URLs that require matching UA headers.
  /// ANDROID_MUSIC and ANDROID_TESTSUITE URLs are UA-agnostic and safe.
  bool _isExoPlayerSafeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // ANDROID client URLs contain 'ratebypass=yes' — these 403 in ExoPlayer
      // ANDROID_MUSIC URLs use 'c=ANDROID_MUSIC' in the URL params
      final client = uri.queryParameters['c'] ?? '';
      final hasRateBypass = uri.queryParameters['ratebypass'] == 'yes';
      if (hasRateBypass && client != 'ANDROID_MUSIC') {
        return false;
      }
      return true;
    } catch (_) {
      return true; // Don't reject if we can't parse
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

    await _connectivitySubscription?.cancel();
    await _audioInterruptionSubscription?.cancel();
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
    _scraper.dispose();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _governor.onSeek(position);
    await _audioPlayer.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    // Cancel any active crossfade first
    if (_isCrossfading) {
      print('🛑 [Crossfade] Cancelled by user skip');
      _isCrossfading = false;
      _nextSongUrl = null;
      _nextSongMedia = null;
      await _audioPlayer.setVolume(_loudnessNormalizationEnabled ? 0.85 : 1.0);
    }

    // ── Rapid-skip guard ──────────────────────────────────────────────────
    // Each skip gets a unique sequence id. Every await checks it; if a newer
    // skip has started, the current one bails out silently, preventing stale
    // async completions from overwriting fresh metadata (the Khwaab→Gul bug).
    final mySeq = ++_skipSequenceId;

    // If a previous skip is still running, force-clear it immediately.
    // The old skip's sequence check (mySeq != _skipSequenceId) will make it
    // bail out at the next await. We do NOT wait or abort — every skip must
    // get through so rapid taps all register.
    if (_isChangingSong) {
      print('⚡ [SKIP] Force-clearing _isChangingSong for seq $mySeq');
      _isChangingSong = false;
    }

    // If a NEWER skip has already started after us, drop this one.
    if (mySeq != _skipSequenceId) {
      print(
        '⏩ [SKIP] Dropping stale skip seq $mySeq (current: $_skipSequenceId)',
      );
      return;
    }

    _isChangingSong = true;
    _lastSongChangeTime = DateTime.now();

    print('⏭️ [SKIP] Skip to next requested (seq $mySeq)');
    _governor.onSkipForward();

    try {
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

          // 🔥 NEW: Track rapid skips
          final now = DateTime.now();
          _rapidSkipTimes.add(now);

          // Remove skips older than the window
          _rapidSkipTimes.removeWhere(
            (time) => now.difference(time) > _rapidSkipWindow,
          );

          print('📊 [SKIP] Consecutive radio skips: $_consecutiveSkipsInRadio');
          print(
            '📊 [SKIP] Rapid skips in last ${_rapidSkipWindow.inSeconds}s: ${_rapidSkipTimes.length}',
          );

          // Check if we've hit the rapid skip threshold
          if (_rapidSkipTimes.length >= _rapidSkipThreshold &&
              !_isRefreshingDueToRapidSkips) {
            print(
              '⚡ [SKIP] RAPID SKIP THRESHOLD REACHED! ${_rapidSkipTimes.length} skips in ${_rapidSkipWindow.inSeconds}s',
            );
            unawaited(_refreshRadioDueToRapidSkips());
          }

          // Fire-and-forget original refetch check
          unawaited(_checkAndRefetchRadioIfNeeded());
        } else {
          _consecutiveSkipsInRadio = 0;
          _rapidSkipTimes.clear(); // Clear rapid skips if not in radio mode
        }
      }

      // Bail if a newer skip arrived during preference tracking
      if (mySeq != _skipSequenceId) {
        print('⏩ [SKIP] Seq $mySeq abandoned after prefs');
        return;
      }

      await _tracker.stopTracking();

      MediaItem? nextMedia;
      QuickPick? nextSong;

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
      print('   Source type: $_currentSourceType');

      // ── Priority 1: PLAYLIST MODE ──────────────────────────────────────
      if (_isPlayingPlaylist && _queue.isNotEmpty) {
        if (_currentIndex < _queue.length - 1) {
          _currentIndex++;
          _playlistCurrentIndex++;
          nextMedia = _queue[_currentIndex];
          print(
            '📋 [SKIP] Next playlist song [${_currentIndex + 1}/${_queue.length}]: ${nextMedia.title}',
          );
          _updateCustomState({'playlist_current_index': _playlistCurrentIndex});
        } else {
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

          if (currentMedia != null) {
            final lastSong = _quickPickFromMediaItem(currentMedia);
            _currentRadioSourceId = currentMedia.id;
            await loadRadioImmediately(lastSong);

            if (mySeq != _skipSequenceId) return;

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
      // ── Priority 2: Explicit user queue (radio mode) ───────────────────
      else if (!_isPlayingPlaylist && _explicitQueue.isNotEmpty) {
        nextMedia = _explicitQueue.removeAt(0);
        _broadcastExplicitQueue();
        print('✅ [SKIP] Playing from explicit queue: ${nextMedia.title}');
        print('   Remaining explicit queue: ${_explicitQueue.length}');
        // Do NOT touch _radioQueueIndex — radio resumes from same position
      }
      // ── Priority 3: Manual queue (non-playlist) ────────────────────────
      else if (!_isPlayingPlaylist &&
          _queue.isNotEmpty &&
          _currentIndex < _queue.length - 1) {
        _currentIndex++;
        nextMedia = _queue[_currentIndex];
        print(
          '✅ [SKIP] Next from manual queue [${_currentIndex + 1}/${_queue.length}]: ${nextMedia.title}',
        );
      }
      // ── Priority 3: Loop all ───────────────────────────────────────────
      else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
        _currentIndex = 0;
        nextMedia = _queue[_currentIndex];
        print('🔁 [LoopMode.all] Looping back to start of manual queue');
      }
      // ── Priority 4: Radio queue ────────────────────────────────────────
      else {
        if (_radioQueue.isEmpty && _isLoadingRadio) {
          print('⏳ [SKIP] Radio still loading, waiting up to 15s...');
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (_isLoadingRadio && DateTime.now().isBefore(deadline)) {
            await Future.delayed(const Duration(milliseconds: 200));
            if (mySeq != _skipSequenceId) return; // newer skip arrived
          }
          print(
            '   Wait done — queue: ${_radioQueue.length}, loading: $_isLoadingRadio',
          );
        }

        if (_radioQueue.isEmpty && !_isLoadingRadio) {
          print('⚠️ [SKIP] Radio empty — fetching now...');
          final seed = mediaItem.value;
          if (seed != null) {
            final qp = _quickPickFromMediaItem(seed);
            _currentRadioSourceId = seed.id;
            await loadRadioImmediately(qp);
          }
          if (mySeq != _skipSequenceId) return;
          print('   After fetch — queue: ${_radioQueue.length}');
        }

        if (_radioQueue.isEmpty) {
          print('❌ [SKIP] Radio still empty after all attempts, stopping');
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.idle,
              playing: false,
            ),
          );
          return;
        }

        if (_radioQueueIndex == -1) {
          print('📻 [SKIP] Starting radio queue (first song)');
          _radioQueueIndex = 0;
          _currentSourceType = RadioSourceType.radio;
        } else if (_radioQueueIndex < _radioQueue.length - 1) {
          _radioQueueIndex++;
          _currentSourceType = RadioSourceType.radio;
          print('📻 [SKIP] Advanced radio to index $_radioQueueIndex');
          unawaited(_checkAndFetchMoreRadio());
        } else if (_loopMode == LoopMode.all) {
          print('🔁 [SKIP] Looping radio queue from start');
          _radioQueueIndex = 0;
          _currentSourceType = RadioSourceType.radio;
        } else {
          print('🛑 [SKIP] End of radio queue, stopping');
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.idle,
              playing: false,
            ),
          );
          return;
        }

        nextMedia = _radioQueue[_radioQueueIndex];
        print(
          '📻 [SKIP] Radio [${_radioQueueIndex + 1}/${_radioQueue.length}]: ${nextMedia.title}',
        );
        _broadcastRadioState();
      }

      if (nextMedia == null) {
        print('❌ [SKIP] No next media selected');
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
            playing: false,
          ),
        );
        return;
      }

      // Sequence check before slow URL fetch
      if (mySeq != _skipSequenceId) {
        print('⏩ [SKIP] Seq $mySeq abandoned before URL fetch');
        return;
      }

      print('🎵 [SKIP] ===== NEXT SONG: ${nextMedia.title} =====');
      nextSong = _quickPickFromMediaItem(nextMedia);

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      // ── Emit mediaItem NOW for instant UI update ──────────────────────
      // Capture targetVideoId here so the post-duration emit can guard itself.
      // This is the fix for the Khwaab→Gul metadata regression: the duration
      // emit below is gated on BOTH the sequence id AND the video id, so a
      // stale async completion from a previous skip can never overwrite fresh
      // metadata with old song data.
      final targetVideoId = nextMedia.id;
      mediaItem.add(nextMedia);

      // Get URL (use pre-fetched if available)
      String? audioUrl;
      if (_nextSongMedia?.id == nextMedia.id && _nextSongUrl != null) {
        print('⚡ [Gapless] Using pre-fetched URL — zero gap!');
        audioUrl = _nextSongUrl;
        _nextSongUrl = null;
        _nextSongMedia = null;
      } else {
        audioUrl = await _getAudioUrl(nextMedia.id, song: nextSong);
      }

      // Sequence check after URL fetch (this is the longest await)
      if (mySeq != _skipSequenceId) {
        print('⏩ [SKIP] Seq $mySeq abandoned after URL fetch — dropping');
        return;
      }

      if (audioUrl == null) {
        print(
          '❌ [SKIP] Failed to get audio URL for ${nextMedia.title}, trying next...',
        );
        _isChangingSong = false;
        unawaited(skipToNext());
        return;
      }

      // Stop old pipeline
      if (_audioPlayer.playing) await _audioPlayer.pause();
      await _audioPlayer.stop();
      await Future.delayed(const Duration(milliseconds: 150));

      // Final sequence check before touching the player
      if (mySeq != _skipSequenceId) {
        print('⏩ [SKIP] Seq $mySeq abandoned before setUrl');
        return;
      }

      try {
        await _audioPlayer.setUrl(audioUrl);
        await _audioPlayer.play();
        Future.delayed(
          const Duration(milliseconds: 100),
          _reattachAudioEffects,
        );
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('Loading interrupted') ||
            msg.contains('interrupted') ||
            msg.contains('Connection aborted') ||
            msg.contains('Connection')) {
          print('⏭️ [SKIP] setUrl interrupted — retrying after brief delay...');
          await Future.delayed(const Duration(milliseconds: 300));
          if (mySeq != _skipSequenceId) return;
          await _audioPlayer.setUrl(audioUrl);
          await _audioPlayer.play();
        } else {
          throw Exception('Failed to set audio source: $e');
        }
      }

      // ── Duration update — double-guarded ─────────────────────────────
      // Guard 1: mySeq == _skipSequenceId  → no newer skip has started
      // Guard 2: mediaItem.value?.id == targetVideoId → player still on this song
      // Both must pass or the emit is dropped. This is what prevents the
      // stale Khwaab metadata from overwriting Gul after a rapid skip.
      int durationAttempts = 0;
      while (_audioPlayer.duration == null && durationAttempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        durationAttempts++;
        if (mySeq != _skipSequenceId) break;
      }

      if (_audioPlayer.duration != null &&
          mySeq == _skipSequenceId &&
          mediaItem.value?.id == targetVideoId) {
        mediaItem.add(nextMedia.copyWith(duration: _audioPlayer.duration));
      }

      if (mySeq != _skipSequenceId) {
        print('⏩ [SKIP] Seq $mySeq: newer skip running — done here');
        return;
      }

      await _tracker.startTracking(nextSong);
      await LastPlayedService.saveLastPlayed(nextSong);

      print('✅ [SKIP] Now playing: ${nextMedia.title} (seq $mySeq)');
    } catch (e, stackTrace) {
      print('❌ [SKIP] Error: $e');
      print(
        '   Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );
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
    } finally {
      // Only clear flag if WE are still the active skip.
      if (mySeq == _skipSequenceId) {
        _isChangingSong = false;
      }
    }
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
    final position = _audioPlayer.position;

    // Over 3s → restart current
    if (position.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      return;
    }

    // Force-clear stale flag just like skipToNext does
    if (_isChangingSong) {
      print('⚡ [PREV] Force-clearing stale _isChangingSong');
      _isChangingSong = false;
    }

    _isChangingSong = true;
    _lastSongChangeTime = DateTime.now();
    ++_skipSequenceId;

    _governor.onSkipBackward(position);

    try {
      await _tracker.stopTracking();

      MediaItem? prevMedia;

      if (_isPlayingPlaylist && _playlistCurrentIndex > 0) {
        _playlistCurrentIndex--;
        _currentIndex = _playlistCurrentIndex;
        prevMedia = _queue[_currentIndex];
        print('📋 [PREV] Playlist → ${prevMedia.title}');
        _updateCustomState({'playlist_current_index': _playlistCurrentIndex});
      } else if (_radioQueue.isNotEmpty && _radioQueueIndex > 0) {
        _radioQueueIndex--;
        prevMedia = _radioQueue[_radioQueueIndex];
        print('📻 [PREV] Radio → index $_radioQueueIndex: ${prevMedia.title}');
        _broadcastRadioState();
      } else if (_radioQueue.isNotEmpty && _radioQueueIndex == 0) {
        prevMedia = _radioQueue[0];
        print('📻 [PREV] At first radio song, restarting: ${prevMedia.title}');
      } else {
        print('⚠️ [PREV] Nothing to go back to, restarting current');
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();
        return;
      }

      if (prevMedia == null) return;

      mediaItem.add(prevMedia);
      final prevSong = _quickPickFromMediaItem(prevMedia);

      final audioUrl = await _getAudioUrl(prevMedia.id, song: prevSong);
      if (audioUrl == null) {
        print('❌ [PREV] No audio URL');
        return;
      }

      await _audioPlayer.setUrl(audioUrl);
      await Future.delayed(const Duration(milliseconds: 100));
      await _reattachAudioEffects();
      await _audioPlayer.play();

      await Future.delayed(const Duration(milliseconds: 300));
      await _tracker.startTracking(prevSong);
      await LastPlayedService.saveLastPlayed(prevSong);

      print('✅ [PREV] Now playing: ${prevMedia.title}');
    } catch (e) {
      print('❌ [PREV] Error: $e');
    } finally {
      _isChangingSong = false;
    }
  }

  Future<void> playPlaylistQueue(
    List<QuickPick> songs, {
    int startIndex = 0,
    String? playlistId,
  }) async {
    if (songs.isEmpty) return;
    final engineLogger = VibeFlowEngineLogger();
    if (engineLogger.isBlocked) {
      print('🚫 [playPlaylistQueue] Engine is stopped — blocking playlist');
      return;
    }
    try {
      print('🎵 [PLAYLIST] ========== PLAYING PLAYLIST ==========');
      print('   Songs: ${songs.length}');
      print('   Start index: $startIndex');
      print('   Playlist ID: $playlistId');
      print('   Will fetch HQ album art for all songs');

      // Store playlist ID and cache songs
      if (playlistId != null) {
        _currentPlaylistId = playlistId;

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

      print('🗑️ [PLAYLIST] Clearing radio (entering playlist mode)');
      _radioQueue.clear();
      _radioQueueIndex = -1;
      _lastRadioVideoId = null;
      _isLoadingRadio = false;
      _currentRadioSourceId = null;
      _currentSourceType = RadioSourceType.playlist;
      _isPlayingPlaylist = true;

      _playlistQueue = songs.map((s) => s.videoId).toList();
      _playlistCurrentIndex = startIndex;

      _updateCustomState({
        'radio_queue': [],
        'radio_queue_count': 0,
        'is_playlist_mode': true,
        'playlist_queue_count': songs.length,
        'playlist_current_index': startIndex,
      });
      // Broadcast playlist songs for queue tab UI
      final playlistData = songs
          .map(
            (s) => {
              'id': s.videoId,
              'title': s.title,
              'artist': s.artists,
              'artUri': s.thumbnail,
              'duration': s.duration != null
                  ? _parseDurationString(s.duration!)?.inMilliseconds
                  : null,
            },
          )
          .toList();
      _updateCustomState({
        'playlist_songs': playlistData,
        'playlist_songs_count': playlistData.length,
      });

      // 🖼️ CREATE MEDIAITEM QUEUE WITH HQ ALBUM ART
      print(
        '🖼️ [PLAYLIST] Fetching HQ album art for ${songs.length} songs...',
      );
      _queue.clear();

      // Fetch HQ art for all songs in parallel (faster than sequential)
      final mediaItemFutures = songs.map((song) async {
        return await _createMediaItemWithHqArt(song, useHqArt: true);
      }).toList();

      // Wait for all MediaItems to be created with HQ art
      final mediaItems = await Future.wait(mediaItemFutures);
      _queue.addAll(mediaItems);

      print(
        '✅ [PLAYLIST] Created ${_queue.length} MediaItems with HQ album art',
      );

      _currentIndex = startIndex.clamp(0, _queue.length - 1);
      queue.add(_queue);

      // Try to find a playable song starting from startIndex
      String? audioUrl;
      int playableIndex = _currentIndex;

      while (playableIndex < songs.length) {
        final candidateSong = songs[playableIndex];
        print(
          '🔍 [PLAYLIST] Trying song ${playableIndex + 1}/${songs.length}: ${candidateSong.title}',
        );
        audioUrl = await _getAudioUrl(
          candidateSong.videoId,
          song: candidateSong,
        );

        if (audioUrl != null && audioUrl.isNotEmpty) {
          print('✅ [PLAYLIST] Got audio URL for: ${candidateSong.title}');
          break;
        }

        print(
          '⏭️ [PLAYLIST] Song unavailable, skipping: ${candidateSong.title}',
        );
        playableIndex++;
      }

      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('No playable songs found in playlist');
      }

      // Update index to the first playable song
      if (playableIndex != _currentIndex) {
        _currentIndex = playableIndex;
        _playlistCurrentIndex = playableIndex;
        print(
          '📋 [PLAYLIST] Adjusted start to index $_currentIndex after skipping unavailable songs',
        );
      }

      // Set current media item AFTER resolving the playable index
      final currentSong = songs[_currentIndex];
      final currentMedia = _queue[_currentIndex];
      mediaItem.add(currentMedia);

      print('🖼️ [PLAYLIST] Current song HQ art: ${currentMedia.artUri}');
      print('   Title: ${currentMedia.title}');
      print('   Artist: ${currentMedia.artist}');

      await _audioPlayer.setUrl(audioUrl);
      // Re-attach audio effects after setting new audio source
      await Future.delayed(const Duration(milliseconds: 100));
      await _reattachAudioEffects();
      await _audioPlayer.play();

      // Wait for duration
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
      await LastPlayedService.saveLastPlayed(currentSong); // ✅ ADD THIS

      print('✅ [PLAYLIST] ========== PLAYBACK STARTED ==========');
      print(
        '   Song ${_currentIndex + 1}/${_queue.length}: ${currentSong.title}',
      );
      print('   HQ Album Art: ${currentMedia.artUri != null ? "YES" : "NO"}');
      print('   Playlist mode active - no radio until playlist ends');
      print('=====================================================');
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
        // ✅ NEW: Re-attach audio effects
        await Future.delayed(const Duration(milliseconds: 100));
        await _reattachAudioEffects();
        await _audioPlayer.play();

        // Wait for playback to start, then track
        await Future.delayed(const Duration(milliseconds: 300));
        await _tracker.startTracking(quickPick);
      }
    } else {
      print('⚠️ Invalid queue index: $index (queue length: ${_queue.length})');
    }
  }

  /// Fetch high-quality album art for a song using the scraper
  Future<Uri?> _fetchHqAlbumArt(String videoId) async {
    try {
      print('🖼️ [HQ Art] Fetching for videoId: $videoId');

      // Use the scraper's getThumbnailUrl method which validates quality levels
      // This method checks maxresdefault -> sddefault -> hqdefault -> mqdefault
      final hqUrl = await _scraper.getThumbnailUrl(videoId);

      if (hqUrl.isNotEmpty) {
        print('✅ [HQ Art] Got HQ URL: ${hqUrl.substring(0, 60)}...');
        return Uri.parse(hqUrl);
      }

      print('⚠️ [HQ Art] Failed to get HQ URL, will use fallback');
      return null;
    } catch (e) {
      print('❌ [HQ Art] Error fetching: $e');
      return null;
    }
  }

  /// Create MediaItem with optional HQ album art fetching
  Future<MediaItem> _createMediaItemWithHqArt(
    QuickPick song, {
    bool useHqArt = false,
  }) async {
    Uri? artUri;

    // Fetch HQ album art if requested (for playlists)
    if (useHqArt) {
      print('🔍 [HQ Art] Fetching for: ${song.title}');
      artUri = await _fetchHqAlbumArt(song.videoId);

      if (artUri != null) {
        print('✅ [HQ Art] Using HQ art for: ${song.title}');
      }
    }

    // Fallback to provided thumbnail if HQ fetch failed or not requested
    if (artUri == null && song.thumbnail.isNotEmpty) {
      if (song.thumbnail.startsWith('http://') ||
          song.thumbnail.startsWith('https://')) {
        artUri = Uri.parse(song.thumbnail);
        print('📷 [HQ Art] Using provided thumbnail for: ${song.title}');
      }
    }

    return MediaItem(
      id: song.videoId,
      title: song.title,
      artist: song.artists,
      artUri: artUri,
      duration: song.duration != null
          ? _parseDurationString(song.duration!)
          : null,
    );
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
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return Duration(minutes: minutes, seconds: seconds);
      } else if (parts.length == 3) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        final seconds = int.tryParse(parts[2]) ?? 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds);
      }
      print('⚠️ [_parseDurationString] Unrecognized format: "$durationStr"');
      return null;
    } catch (e) {
      print('❌ [_parseDurationString] Parse error: $e for "$durationStr"');
      return null;
    }
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

  // ADD these public methods:
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimerDuration = duration;
    _sleepTimerEndTime = DateTime.now().add(duration);

    _updateCustomState({
      'sleep_timer_active': true,
      'sleep_timer_end_ms': _sleepTimerEndTime!.millisecondsSinceEpoch,
    });

    _sleepTimer = Timer(duration, () {
      pause();
      _sleepTimer = null;
      _sleepTimerEndTime = null;
      _updateCustomState({
        'sleep_timer_active': false,
        'sleep_timer_end_ms': null,
        'sleep_timer_fired': true,
      });
      // Clear fired flag after a moment
      Future.delayed(const Duration(seconds: 3), () {
        _updateCustomState({'sleep_timer_fired': false});
      });
    });

    print('😴 [SleepTimer] Set for ${duration.inMinutes} minutes');
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDuration = null;
    _sleepTimerEndTime = null;
    _updateCustomState({
      'sleep_timer_active': false,
      'sleep_timer_end_ms': null,
    });
    print('❌ [SleepTimer] Cancelled');
  }

  String getSleepTimerRemaining() {
    if (_sleepTimerEndTime == null) return '';
    final remaining = _sleepTimerEndTime!.difference(DateTime.now());
    if (remaining.isNegative) return '0 min';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) return '$hours hr $minutes min';
    return '$minutes min';
  }

  // ==================== GETTERS ====================

  AudioSource? get audioSource => _audioPlayer.audioSource;
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
  bool get sleepTimerActive => _sleepTimer != null && _sleepTimer!.isActive;
  bool get isCrossfading => _isCrossfading;
  bool get trueRadioEnabled => _trueRadioEnabled;
  Duration? get currentSleepTimerDuration => _sleepTimerDuration;
  int? get audioSessionId => _audioSessionId;
  AudioSourcePreference get audioSourcePreference => _audioSourcePreference;
}
