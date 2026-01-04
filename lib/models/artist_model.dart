// lib/models/artist_model.dart
class Artist {
  final String id;
  final String name;
  final String? profileImage;
  final String subscribers;

  Artist({
    required this.id,
    required this.name,
    this.profileImage,
    required this.subscribers,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'profileImage': profileImage,
    'subscribers': subscribers,
  };

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: json['id'] as String,
    name: json['name'] as String,
    profileImage: json['profileImage'] as String?,
    subscribers: json['subscribers'] as String,
  );
}
