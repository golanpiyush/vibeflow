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
}
