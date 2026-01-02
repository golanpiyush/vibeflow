// lib/models/album_model.dart
import 'package:vibeflow/models/song_model.dart';

class Album {
  final String id;
  final String title;
  final String artist;
  final String? coverArt;
  final int year;
  final List<Song> songs;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArt,
    required this.year,
    required this.songs,
  });
}
