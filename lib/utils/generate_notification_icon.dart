// import 'dart:io';
// import 'package:image/image.dart' as img;

// void main() async {
//   final sourceFile = File('assets/icons/logo_unamed.png');
//   if (!await sourceFile.exists()) {
//     print('Source file not found!');
//     return;
//   }

//   // Read the image
//   final image = img.decodeImage(await sourceFile.readAsBytes())!;

//   // Convert to white silhouette
//   for (var y = 0; y < image.height; y++) {
//     for (var x = 0; x < image.width; x++) {
//       final pixel = image.getPixel(x, y);
//       final alpha = pixel.a;
//       if (alpha > 0) {
//         // Set to white with original alpha
//         image.setPixelRgba(x, y, 255, 255, 255, alpha);
//       }
//     }
//   }

//   // Create directories if they don't exist
//   final densities = {
//     'mdpi': 48,
//     'hdpi': 72,
//     'xhdpi': 96,
//     'xxhdpi': 144,
//     'xxxhdpi': 192,
//   };

//   for (var entry in densities.entries) {
//     final dir = Directory('android/app/src/main/res/drawable-${entry.key}');
//     if (!await dir.exists()) {
//       await dir.create(recursive: true);
//     }

//     // Resize image
//     final resized = img.copyResize(
//       image,
//       width: entry.value,
//       height: entry.value,
//     );

//     // Save as PNG
//     final file = File('${dir.path}/ic_notification.png');
//     await file.writeAsBytes(img.encodePng(resized));
//     print('✅ Created: ${file.path}');
//   }

//   print('🎉 Notification icons generated successfully!');
// }
