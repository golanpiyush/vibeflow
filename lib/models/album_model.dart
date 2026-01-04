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

  // In Album model class (album_model.dart)
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'coverArt': coverArt,
    'year': year,
    'songs': songs.map((song) => song.toJson()).toList(),
  };

  factory Album.fromJson(Map<String, dynamic> json) => Album(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    coverArt: json['coverArt'] as String?,
    year: json['year'] as int,
    songs: (json['songs'] as List).map((item) => Song.fromJson(item)).toList(),
  );
}
