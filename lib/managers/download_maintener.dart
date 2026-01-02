import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles download maintenance, migrations, and cleanup
class DownloadMaintenanceService {
  static const String _lastMaintenanceKey = 'last_maintenance_date';
  static const Duration _maintenanceInterval = Duration(days: 7);

  /// Run maintenance if needed
  static Future<void> runMaintenanceIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMaintenance = prefs.getString(_lastMaintenanceKey);

    if (lastMaintenance == null) {
      // First time - run maintenance
      await runMaintenance();
      return;
    }

    final lastDate = DateTime.parse(lastMaintenance);
    final now = DateTime.now();

    if (now.difference(lastDate) > _maintenanceInterval) {
      debugPrint('Running scheduled maintenance...');
      await runMaintenance();
    }
  }

  /// Run full maintenance routine
  static Future<MaintenanceReport> runMaintenance() async {
    final prefs = await SharedPreferences.getInstance();
    final report = MaintenanceReport();

    try {
      debugPrint('Starting download maintenance...');

      // Get download directory
      final savedPath = prefs.getString('download_directory_path');
      if (savedPath == null) {
        return report;
      }

      final downloadDir = Directory(savedPath);
      if (!await downloadDir.exists()) {
        return report;
      }

      // Clean up orphaned files
      final orphanedCount = await _cleanOrphanedFiles(downloadDir);
      report.orphanedFilesRemoved = orphanedCount;

      // Verify file integrity
      final corruptedCount = await _verifyAndRemoveCorrupted(downloadDir);
      report.corruptedFilesRemoved = corruptedCount;

      // Clean up empty metadata
      final emptyMetadataCount = await _cleanEmptyMetadata(downloadDir);
      report.emptyMetadataRemoved = emptyMetadataCount;

      // Calculate total storage used
      report.totalStorageUsed = await _calculateStorageUsed(downloadDir);

      // Update last maintenance date
      await prefs.setString(
        _lastMaintenanceKey,
        DateTime.now().toIso8601String(),
      );

      report.success = true;
      debugPrint('Maintenance completed: ${report.toString()}');
    } catch (e) {
      debugPrint('Maintenance error: $e');
      report.success = false;
      report.error = e.toString();
    }

    return report;
  }

  /// Remove files without metadata (orphaned audio/thumbnails)
  static Future<int> _cleanOrphanedFiles(Directory downloadDir) async {
    int removedCount = 0;

    try {
      final files = await downloadDir.list().toList();
      final Set<String> videoIdsWithMetadata = {};

      // First pass: collect all video IDs with metadata
      for (final file in files) {
        if (file is File && file.path.endsWith('_metadata.json')) {
          final filename = file.path.split('/').last;
          final videoId = filename.split('_').first;
          videoIdsWithMetadata.add(videoId);
        }
      }

      // Second pass: remove orphaned files
      for (final file in files) {
        if (file is File && !file.path.endsWith('_metadata.json')) {
          final filename = file.path.split('/').last;
          final videoId = filename.split('_').first;

          if (!videoIdsWithMetadata.contains(videoId)) {
            await file.delete();
            debugPrint('Removed orphaned file: $filename');
            removedCount++;
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning orphaned files: $e');
    }

    return removedCount;
  }

  /// Verify file integrity and remove corrupted files
  static Future<int> _verifyAndRemoveCorrupted(Directory downloadDir) async {
    int removedCount = 0;

    try {
      final files = await downloadDir.list().toList();

      for (final file in files) {
        if (file is File && file.path.endsWith('_metadata.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content);

            // Check if audio file exists and is valid
            final audioPath = json['audioPath'];
            if (audioPath != null) {
              final audioFile = File(audioPath);

              if (!await audioFile.exists()) {
                // Audio file missing - remove metadata
                await file.delete();
                debugPrint(
                  'Removed metadata for missing audio: ${json['title']}',
                );
                removedCount++;
                continue;
              }

              final fileSize = await audioFile.length();
              if (fileSize < 1024) {
                // File too small (corrupted)
                await audioFile.delete();
                await file.delete();

                // Also remove thumbnail if exists
                final thumbnailPath = json['thumbnailPath'];
                if (thumbnailPath != null) {
                  final thumbnailFile = File(thumbnailPath);
                  if (await thumbnailFile.exists()) {
                    await thumbnailFile.delete();
                  }
                }

                debugPrint('Removed corrupted download: ${json['title']}');
                removedCount++;
              }
            }
          } catch (e) {
            // Corrupted metadata - remove it
            await file.delete();
            debugPrint('Removed corrupted metadata file');
            removedCount++;
          }
        }
      }
    } catch (e) {
      debugPrint('Error verifying files: $e');
    }

    return removedCount;
  }

  /// Clean up empty or invalid metadata files
  static Future<int> _cleanEmptyMetadata(Directory downloadDir) async {
    int removedCount = 0;

    try {
      final files = await downloadDir.list().toList();

      for (final file in files) {
        if (file is File && file.path.endsWith('_metadata.json')) {
          try {
            final fileSize = await file.length();

            // Remove if empty or too small
            if (fileSize < 50) {
              await file.delete();
              debugPrint('Removed empty metadata file');
              removedCount++;
              continue;
            }

            // Try to parse and validate
            final content = await file.readAsString();
            final json = jsonDecode(content);

            // Check required fields
            if (json['videoId'] == null ||
                json['title'] == null ||
                json['audioPath'] == null) {
              await file.delete();
              debugPrint('Removed invalid metadata file');
              removedCount++;
            }
          } catch (e) {
            // Invalid JSON - remove
            await file.delete();
            debugPrint('Removed unparseable metadata file');
            removedCount++;
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning empty metadata: $e');
    }

    return removedCount;
  }

  /// Calculate total storage used by downloads
  static Future<int> _calculateStorageUsed(Directory downloadDir) async {
    int totalBytes = 0;

    try {
      final files = await downloadDir.list().toList();

      for (final file in files) {
        if (file is File) {
          totalBytes += await file.length();
        }
      }
    } catch (e) {
      debugPrint('Error calculating storage: $e');
    }

    return totalBytes;
  }

  /// Export downloads metadata for backup
  static Future<String?> exportDownloadsMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('download_directory_path');

      if (savedPath == null) return null;

      final downloadDir = Directory(savedPath);
      if (!await downloadDir.exists()) return null;

      final List<Map<String, dynamic>> allMetadata = [];
      final files = await downloadDir.list().toList();

      for (final file in files) {
        if (file is File && file.path.endsWith('_metadata.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content);
            allMetadata.add(json);
          } catch (e) {
            debugPrint('Error reading metadata for export: $e');
          }
        }
      }

      final exportData = {
        'version': '1.0.0',
        'exportDate': DateTime.now().toIso8601String(),
        'totalDownloads': allMetadata.length,
        'downloads': allMetadata,
      };

      return const JsonEncoder.withIndent('  ').convert(exportData);
    } catch (e) {
      debugPrint('Error exporting metadata: $e');
      return null;
    }
  }

  /// Get download statistics
  static Future<DownloadStats> getDownloadStats() async {
    final stats = DownloadStats();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('download_directory_path');

      if (savedPath == null) return stats;

      final downloadDir = Directory(savedPath);
      if (!await downloadDir.exists()) return stats;

      final files = await downloadDir.list().toList();
      int audioFiles = 0;
      int thumbnails = 0;
      int metadata = 0;
      int totalSize = 0;

      for (final file in files) {
        if (file is File) {
          final fileSize = await file.length();
          totalSize += fileSize;

          if (file.path.endsWith('.m4a') || file.path.endsWith('.mp3')) {
            audioFiles++;
          } else if (file.path.endsWith('.jpg') || file.path.endsWith('.png')) {
            thumbnails++;
          } else if (file.path.endsWith('_metadata.json')) {
            metadata++;
          }
        }
      }

      stats.totalDownloads = metadata;
      stats.audioFiles = audioFiles;
      stats.thumbnails = thumbnails;
      stats.totalStorageBytes = totalSize;
    } catch (e) {
      debugPrint('Error getting stats: $e');
    }

    return stats;
  }
}

/// Report from maintenance run
class MaintenanceReport {
  bool success = false;
  int orphanedFilesRemoved = 0;
  int corruptedFilesRemoved = 0;
  int emptyMetadataRemoved = 0;
  int totalStorageUsed = 0;
  String? error;

  @override
  String toString() {
    return 'MaintenanceReport(success: $success, orphaned: $orphanedFilesRemoved, '
        'corrupted: $corruptedFilesRemoved, empty: $emptyMetadataRemoved, '
        'storage: ${(totalStorageUsed / (1024 * 1024)).toStringAsFixed(2)} MB)';
  }
}

/// Download statistics
class DownloadStats {
  int totalDownloads = 0;
  int audioFiles = 0;
  int thumbnails = 0;
  int totalStorageBytes = 0;

  String get formattedStorage {
    if (totalStorageBytes < 1024 * 1024) {
      return '${(totalStorageBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalStorageBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
