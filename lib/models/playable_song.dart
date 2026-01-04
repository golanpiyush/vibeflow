// ============================================================================
// SONG MODEL FOR UI/PLAYBACK (WITH AUDIO URL - TEMPORARY)
// ============================================================================

import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

/// UI song model with fresh audio URL (expires in 6 hours)
/// Used for: Current playback, queue, streaming
class PlayableSong {
  final String videoId;
  final String title;
  final List<String> artists;
  final String thumbnail;
  final String? duration;
  final String audioUrl; // ⚠️ Expires in 6 hours - DO NOT SAVE
  final DateTime fetchedAt; // Track when URL was fetched

  PlayableSong({
    required this.videoId,
    required this.title,
    required this.artists,
    required this.thumbnail,
    this.duration,
    required this.audioUrl,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  /// Check if audio URL is still valid (< 5.5 hours old)
  bool get isAudioUrlValid {
    final age = DateTime.now().difference(fetchedAt);
    return age.inHours < 5; // Refresh 30 min before expiry
  }

  /// Convert to your existing QuickPick model
  QuickPick toQuickPick() {
    return QuickPick(
      videoId: videoId,
      title: title,
      artists: artists.join(', '),
      thumbnail: thumbnail,
      duration: duration,
    );
  }

  /// Convert to database model (strips audio URL)
  DbSong toDbSong() {
    return DbSong(
      videoId: videoId,
      title: title,
      artists: artists,
      thumbnail: thumbnail,
      duration: duration,
    );
  }

  String get artistsString => artists.join(', ');

  @override
  String toString() =>
      'PlayableSong(videoId: $videoId, title: $title, urlValid: $isAudioUrlValid)';
}
