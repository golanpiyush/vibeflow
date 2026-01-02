import 'package:vibeflow/models/song_model.dart';

class QuickPick {
  final String videoId;
  final String title;
  final String artists;
  final String thumbnail;
  final String? duration;
  bool isFavorite;

  QuickPick({
    required this.videoId,
    required this.title,
    required this.artists,
    required this.thumbnail,
    this.duration,
    this.isFavorite = false,
  });

  // Convert from Song model
  factory QuickPick.fromSong(Song song) {
    return QuickPick(
      videoId: song.videoId,
      title: song.title,
      artists: song.artistsString,
      thumbnail: song.thumbnail,
      duration: song.duration, // ✅ pass-through
    );
  }

  // Convert to Song model
  Song toSong() {
    return Song(
      videoId: videoId,
      title: title,
      artists: artists.split(', '),
      thumbnail: thumbnail,
      duration: duration?.toString(), // Pass directly if types match
    );
  }
}
