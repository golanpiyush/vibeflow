import 'dart:io';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Holds extracted album colors
class AlbumPalette {
  final Color dominant;
  final Color vibrant;
  final Color muted;

  const AlbumPalette({
    required this.dominant,
    required this.vibrant,
    required this.muted,
  });
}

class AlbumColorGenerator {
  /// Extracts dominant, vibrant & muted colors from an image
  static Future<AlbumPalette> generate({
    required ImageProvider imageProvider,
    Size size = const Size(200, 200),
  }) async {
    final palette = await PaletteGenerator.fromImageProvider(
      imageProvider,
      size: size,
      maximumColorCount: 20,
    );

    return AlbumPalette(
      dominant: palette.dominantColor?.color ?? Colors.black,
      vibrant:
          palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          Colors.white,
      muted:
          palette.mutedColor?.color ??
          palette.darkMutedColor?.color ??
          Colors.grey,
    );
  }

  /// Convenience method for Network images
  static Future<AlbumPalette> fromUrl(String imageUrl) {
    return generate(imageProvider: NetworkImage(imageUrl));
  }

  /// Convenience method for Asset images
  static Future<AlbumPalette> fromAsset(String assetPath) {
    return generate(imageProvider: AssetImage(assetPath));
  }

  /// NEW: Convenience method for File images (local storage)
  static Future<AlbumPalette> fromFile(String filePath) {
    return generate(imageProvider: FileImage(File(filePath)));
  }

  /// NEW: Auto-detect and generate from any source (network, file, or asset)
  static Future<AlbumPalette> fromAnySource(String imagePath) {
    if (imagePath.isEmpty) {
      throw ArgumentError('Image path cannot be empty');
    }

    // Check if it's a local file path
    final isLocalFile =
        imagePath.startsWith('/') ||
        imagePath.startsWith('file://') ||
        (!imagePath.startsWith('http://') && !imagePath.startsWith('https://'));

    if (isLocalFile) {
      final filePath = imagePath.replaceFirst('file://', '');
      return fromFile(filePath);
    } else {
      return fromUrl(imagePath);
    }
  }
}

/// Helper widget to display album art from local file or network
Widget buildAlbumArtImage({
  required String artworkUrl,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  if (artworkUrl.isEmpty) {
    // ignore: cast_from_null_always_fails
    return errorBuilder?.call(null as BuildContext, 'Empty URL', null) ??
        const SizedBox.shrink();
  }

  // Check if it's a local file path
  final isLocalFile =
      artworkUrl.startsWith('/') ||
      artworkUrl.startsWith('file://') ||
      (!artworkUrl.startsWith('http://') && !artworkUrl.startsWith('https://'));

  if (isLocalFile) {
    // Remove 'file://' prefix if present
    final filePath = artworkUrl.replaceFirst('file://', '');
    final file = File(filePath);

    return Image.file(file, fit: fit, errorBuilder: errorBuilder);
  } else {
    // Network image
    return Image.network(artworkUrl, fit: fit, errorBuilder: errorBuilder);
  }
}
