// lib/providers/download_state_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Tracks which songs are currently being downloaded
class DownloadStateNotifier
    extends StateNotifier<Map<String, DownloadProgress>> {
  DownloadStateNotifier() : super({});

  /// Start tracking a download
  void startDownload(String videoId) {
    state = {
      ...state,
      videoId: DownloadProgress(
        videoId: videoId,
        progress: 0.0,
        isDownloading: true,
      ),
    };
  }

  /// Update download progress
  void updateProgress(String videoId, double progress) {
    if (!state.containsKey(videoId)) return;

    state = {
      ...state,
      videoId: DownloadProgress(
        videoId: videoId,
        progress: progress,
        isDownloading: true,
      ),
    };
  }

  /// Complete download
  void completeDownload(String videoId) {
    final newState = Map<String, DownloadProgress>.from(state);
    newState.remove(videoId);
    state = newState;
  }

  /// Fail download
  void failDownload(String videoId) {
    final newState = Map<String, DownloadProgress>.from(state);
    newState.remove(videoId);
    state = newState;
  }

  /// Check if a song is currently downloading
  bool isDownloading(String videoId) {
    return state.containsKey(videoId);
  }

  /// Get progress for a specific download
  double? getProgress(String videoId) {
    return state[videoId]?.progress;
  }
}

/// Provider for download state
final downloadStateProvider =
    StateNotifierProvider<DownloadStateNotifier, Map<String, DownloadProgress>>(
      (ref) => DownloadStateNotifier(),
    );

/// Model for download progress
class DownloadProgress {
  final String videoId;
  final double progress;
  final bool isDownloading;

  DownloadProgress({
    required this.videoId,
    required this.progress,
    required this.isDownloading,
  });
}
