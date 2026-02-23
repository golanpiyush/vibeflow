// lib/services/audio_service.dart
// Fully fixed version: loopModeStream crash & null-safety

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:just_audio/just_audio.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';

class AudioServices {
  static AudioServices? _instance;
  static BackgroundAudioHandler? _audioHandler;

  String? _currentStreamUrl;
  String? get currentAudioUrl => _currentStreamUrl;

  AudioServices._();

  static Future<AudioServices> init() async {
    if (_instance == null) {
      _instance = AudioServices._();

      // ✅ FIXED: Use proper notification icon
      final handler = await audio_service.AudioService.init(
        builder: () => BackgroundAudioHandler(),
        config: audio_service.AudioServiceConfig(
          androidNotificationChannelId: 'com.vibeflow.audio',
          androidNotificationChannelName: 'VibeFlow Music',
          androidNotificationOngoing: false,
          androidNotificationIcon: 'drawable/ic_logo_notification',
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: false,
        ),
      );

      _audioHandler = handler;
      print('✅ [AudioService] Initialized with notification icon');
    }
    return _instance!;
  }

  static AudioServices get instance {
    if (_instance == null) {
      throw StateError(
        'AudioService not initialized. Call AudioService.init() first.',
      );
    }
    return _instance!;
  }

  static BackgroundAudioHandler get handler {
    if (_audioHandler == null) {
      throw StateError('AudioHandler not initialized.');
    }
    return _audioHandler!;
  }

  // ───────── Playback Controls ─────────
  Future<void> playSongFromRadio(QuickPick song) async {
    final handler = AudioServices.handler;
    await handler.playSongFromRadio(song);
  }

  Future<void> playSong(QuickPick song) async {
    await handler.playSong(song);
  }

  Future<void> playQueue(List<QuickPick> songs, {int startIndex = 0}) async {
    await handler.playQueue(songs, startIndex: startIndex);
  }

  Future<void> playPause() async {
    if (handler.isPlaying) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> pause() async => await handler.pause();
  Future<void> play() async => await handler.play();
  Future<void> stop() async => await handler.stop();
  Future<void> seek(Duration position) async => await handler.seek(position);
  Future<void> skipToNext() async => await handler.skipToNext();
  Future<void> skipToPrevious() async => await handler.skipToPrevious();
  Future<void> fastForward() async => await handler.fastForward();
  Future<void> rewind() async => await handler.rewind();

  Future<void> setLoopMode(LoopMode loopMode) async {
    await AudioServices.handler.customAction('set_loop_mode', {
      'loop_mode': loopMode.index,
    });
  }

  void setCrossfadeEnabled(bool enabled) {
    AudioServices.handler.setCrossfadeEnabled(enabled);
  }

  // ───────── Loop Mode Stream (FIXED) ─────────
  Stream<LoopMode> get loopModeStream => handler.customState.stream.map((
    state,
  ) {
    // Safe null-check + fallback to LoopMode.off
    final index = (state as Map<String, dynamic>?)?['loop_mode'] as int? ?? 0;
    if (index < 0 || index >= LoopMode.values.length) return LoopMode.off;
    return LoopMode.values[index];
  }).distinct(); // avoid duplicate rebuilds

  // ───────── Queue Helpers ─────────
  Future<void> addToQueue(QuickPick song) async {
    try {
      final mediaItem = audio_service.MediaItem(
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

      await handler.addQueueItem(mediaItem);
      print('✅ Added to queue: ${song.title}');
    } catch (e) {
      print('❌ Error adding to queue: $e');
      rethrow;
    }
  }

  Duration? _parseDurationString(String durationStr) {
    final parts = durationStr.split(':');
    if (parts.length != 2) return null;
    final minutes = int.tryParse(parts[0]) ?? 0;
    final seconds = int.tryParse(parts[1]) ?? 0;
    return Duration(minutes: minutes, seconds: seconds);
  }

  // ───────── Streams ─────────
  Stream<audio_service.MediaItem?> get mediaItemStream => handler.mediaItem;
  Stream<audio_service.PlaybackState> get playbackStateStream =>
      handler.playbackState;
  Stream<Duration> get positionStream => handler.positionStream;
  Stream<Duration?> get durationStream => handler.durationStream;

  // ───────── Getters ─────────
  bool get isPlaying => handler.isPlaying;
  Duration get position => handler.position;
  Duration? get duration => handler.duration;
  audio_service.MediaItem? get currentMediaItem => handler.mediaItem.value;
}
