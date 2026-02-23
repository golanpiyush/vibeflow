import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';

/// Single source of truth for the currently-playing MediaItem.
///
/// Updates synchronously whenever the handler's mediaItem stream emits —
/// NO debounce, NO delayed closures, NO stale fallbacks.
///
/// Both player screens should read from this instead of maintaining their
/// own `_lastKnownMediaItem` or complex stream guards.
class AudioUISync extends ChangeNotifier {
  AudioUISync._();
  static final AudioUISync instance = AudioUISync._();

  MediaItem? _currentMedia;
  String? _lastEmittedId;
  StreamSubscription<MediaItem?>? _sub;
  bool _initialized = false;

  MediaItem? get currentMedia => _currentMedia;

  /// Call once from main / audio service init.
  void init() {
    if (_initialized) return;
    _initialized = true;

    final handler = getAudioHandler();
    if (handler == null) return;

    // Seed with current value immediately (no async gap).
    _applyMediaItem(handler.mediaItem.value);

    // Listen to every emission — update immediately, no guards.
    _sub = handler.mediaItem.listen(_applyMediaItem);
  }

  void _applyMediaItem(MediaItem? item) {
    if (item == null) return;

    // Always accept if ID changed — this is a new song, update immediately.
    if (item.id != _lastEmittedId) {
      _lastEmittedId = item.id;
      _currentMedia = item;
      notifyListeners();
      return;
    }

    // Same song — only update if meaningful metadata changed (duration, art resolved).
    final changed =
        item.title != _currentMedia?.title ||
        item.artist != _currentMedia?.artist ||
        item.artUri?.toString() != _currentMedia?.artUri?.toString() ||
        item.duration != _currentMedia?.duration;

    if (!changed) return;
    _currentMedia = item;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
