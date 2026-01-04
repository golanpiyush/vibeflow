// Playlist model stays the same
class Playlist {
  final int? id;
  final String name;
  final String? description;
  final String? coverImagePath;
  final String coverType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int songCount;
  final int totalDuration;
  final bool isFavorite;
  final int sortOrder;

  Playlist({
    this.id,
    required this.name,
    this.description,
    this.coverImagePath,
    this.coverType = 'mosaic',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.songCount = 0,
    this.totalDuration = 0,
    this.isFavorite = false,
    this.sortOrder = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'cover_image_path': coverImagePath,
      'cover_type': coverType,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'song_count': songCount,
      'total_duration': totalDuration,
      'is_favorite': isFavorite ? 1 : 0,
      'sort_order': sortOrder,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      coverImagePath: map['cover_image_path'] as String?,
      coverType: map['cover_type'] as String? ?? 'mosaic',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      songCount: map['song_count'] as int? ?? 0,
      totalDuration: map['total_duration'] as int? ?? 0,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Playlist copyWith({
    int? id,
    String? name,
    String? description,
    String? coverImagePath,
    String? coverType,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? songCount,
    int? totalDuration,
    bool? isFavorite,
    int? sortOrder,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      coverType: coverType ?? this.coverType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      songCount: songCount ?? this.songCount,
      totalDuration: totalDuration ?? this.totalDuration,
      isFavorite: isFavorite ?? this.isFavorite,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
