class Song {
  final String videoId;
  final String title;
  final List<String> artists;
  final String thumbnail;
  final String? duration;
  String? audioUrl;

  Song({
    required this.videoId,
    required this.title,
    required this.artists,
    required this.thumbnail,
    this.duration,
    this.audioUrl,
  });

  String get artistsString => artists.join(', ');

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'artists': artists,
    'thumbnail': thumbnail,
    'duration': duration,
    'audioUrl': audioUrl,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    videoId: json['videoId'] ?? '',
    title: json['title'] ?? '',
    artists: List<String>.from(json['artists'] ?? []),
    thumbnail: json['thumbnail'] ?? '',
    duration: json['duration'],
    audioUrl: json['audioUrl'],
  );

  @override
  String toString() =>
      'Song(title: $title, artists: $artistsString, id: $videoId)';
}
