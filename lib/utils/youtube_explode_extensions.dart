import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Extension to get high quality thumbnails from ThumbnailSet
extension ThumbnailSetExtension on List<Thumbnail> {
  String get highResUrl {
    if (isEmpty) return '';

    // Sort by resolution (width * height) and get the highest
    final sorted = [...this];
    sorted.sort((a, b) {
      final aRes = (a.width ?? 0) * (a.height ?? 0);
      final bRes = (b.width ?? 0) * (b.height ?? 0);
      return bRes.compareTo(aRes);
    });

    return sorted.first.url.toString();
  }
}

/// Extension to safely parse duration strings
extension DurationStringExtension on String? {
  int? get inSeconds {
    if (this == null || this!.isEmpty) return null;

    try {
      final parts = this!.split(':').map(int.parse).toList();

      if (parts.length == 2) {
        // MM:SS format
        return parts[0] * 60 + parts[1];
      } else if (parts.length == 3) {
        // HH:MM:SS format
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
