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

  // ==================== SONG CONVERSIONS ====================

  factory QuickPick.fromSong(Song song) {
    return QuickPick(
      videoId: song.videoId,
      title: song.title,
      artists: song.artistsString,
      thumbnail: song.thumbnail,
      duration: song.duration,
    );
  }

  Song toSong() {
    return Song(
      videoId: videoId,
      title: title,
      artists: artists.split(', '),
      thumbnail: thumbnail,
      duration: duration,
    );
  }

  // ==================== JSON SERIALIZATION ====================

  factory QuickPick.fromJson(Map<String, dynamic> json) {
    return QuickPick(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      artists: json['artists'] as String,
      thumbnail: json['thumbnail'] as String,
      duration: json['duration'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'videoId': videoId,
      'title': title,
      'artists': artists,
      'thumbnail': thumbnail,
      'duration': duration,
      'isFavorite': isFavorite,
    };
  }
}
