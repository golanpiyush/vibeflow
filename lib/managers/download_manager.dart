import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  static DownloadService get instance => _instance;
  static const String _versionKey = 'download_service_version';
  static const String _lastVersionKey = 'last_app_version';
  static const String _downloadDirKey = 'download_directory_path';
  DownloadService._internal();

  Future<Directory?> _getDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('download_directory_path');

    if (savedPath != null) {
      return Directory(savedPath);
    }

    // Default to app's document directory
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDir.path}/downloads');

    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    await prefs.setString('download_directory_path', downloadDir.path);
    return downloadDir;
  }

  /// 🔄 CHECK AFTER UPDATE - Verify downloads survived update
  static Future<UpdateReport> checkAfterUpdate() async {
    final report = UpdateReport();

    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final lastVersion = prefs.getString(_lastVersionKey);

      debugPrint('🔍 Version check: $lastVersion -> $currentVersion');

      // First launch
      if (lastVersion == null) {
        debugPrint('🆕 First launch detected');
        await prefs.setString(_lastVersionKey, currentVersion);
        report.isFirstLaunch = true;
        return report;
      }

      // Version changed = app was updated
      if (lastVersion != currentVersion) {
        debugPrint('🔄 App updated: $lastVersion -> $currentVersion');
        report.wasUpdated = true;
        report.oldVersion = lastVersion;
        report.newVersion = currentVersion;

        // Verify downloads
        final downloadDir = await instance._getDownloadDirectory();
        if (downloadDir != null && await downloadDir.exists()) {
          final files = await downloadDir.list().toList();
          int validFiles = 0;
          int totalBytes = 0;
          int metadataFiles = 0;

          for (final file in files) {
            if (file is File) {
              if (file.path.endsWith('_metadata.json')) {
                metadataFiles++;
                try {
                  final content = await file.readAsString();
                  final json = jsonDecode(content);
                  final audioPath = json['audioPath'];

                  if (audioPath != null) {
                    final audioFile = File(audioPath);
                    if (await audioFile.exists()) {
                      validFiles++;
                      totalBytes += await audioFile.length();

                      // Check thumbnail
                      final thumbnailPath = json['thumbnailPath'];
                      if (thumbnailPath != null) {
                        final thumbFile = File(thumbnailPath);
                        if (await thumbFile.exists()) {
                          totalBytes += await thumbFile.length();
                        }
                      }
                    }
                  }
                } catch (e) {
                  debugPrint('⚠️ Error reading metadata: $e');
                }
              }
            }
          }

          report.validFiles = validFiles;
          report.totalMetadataFiles = metadataFiles;
          report.totalStorageBytes = totalBytes;

          debugPrint(
            '✅ Downloads verified: $validFiles/$metadataFiles files intact',
          );
          debugPrint('💾 Total storage: ${report.formattedStorage}');
        }

        // Update version
        await prefs.setString(_lastVersionKey, currentVersion);
      } else {
        debugPrint('✅ No app update detected');
      }
    } catch (e) {
      debugPrint('❌ Error checking update: $e');
      report.error = e.toString();
    }

    return report;
  }

  /// Download a song with audio and thumbnail saved locally
  Future<DownloadResult> downloadSong({
    required String videoId,
    required String audioUrl,
    required String title,
    required String artist,
    required String thumbnailUrl,
    Function(double)? onProgress,
  }) async {
    try {
      debugPrint('🔽 Starting download for: $title');

      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null) {
        return DownloadResult(
          success: false,
          message: 'Download directory not set',
        );
      }

      // Create directory if it doesn't exist
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // Use sanitized filename to avoid file system issues
      final sanitizedId = videoId.replaceAll(RegExp(r'[^\w\-]'), '_');
      final audioPath = '${downloadDir.path}/${sanitizedId}_audio.m4a';
      final thumbnailPath = '${downloadDir.path}/${sanitizedId}_thumbnail.jpg';
      final metadataPath = '${downloadDir.path}/${sanitizedId}_metadata.json';

      // Optimize Dio settings for faster downloads
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      // Download audio file with progress tracking
      onProgress?.call(0.1);

      await dio.download(
        audioUrl,
        audioPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = 0.1 + (received / total * 0.6); // 10% to 70%
            onProgress?.call(progress);
          }
        },
      );

      final audioFile = File(audioPath);
      final audioFileSize = await audioFile.length();

      if (audioFileSize < 1024) {
        await audioFile.delete();
        return DownloadResult(
          success: false,
          message: 'Downloaded audio file is corrupted or too small',
        );
      }

      debugPrint(
        '✅ Audio downloaded: ${(audioFileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
      );

      onProgress?.call(0.75);

      // Download thumbnail
      if (thumbnailUrl.isNotEmpty) {
        try {
          await dio.download(
            thumbnailUrl,
            thumbnailPath,
            onReceiveProgress: (received, total) {
              if (total != -1) {
                final progress = 0.75 + (received / total * 0.15); // 75% to 90%
                onProgress?.call(progress);
              }
            },
          );
        } catch (e) {
          debugPrint('⚠️ Thumbnail download failed: $e');
        }
      }

      onProgress?.call(0.95);

      // Save metadata
      final metadata = {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'audioPath': audioPath,
        'thumbnailPath': thumbnailPath,
        'thumbnailUrl': thumbnailUrl,
        'downloadDate': DateTime.now().toIso8601String(),
        'fileSize': audioFileSize,
      };

      final metadataFile = File(metadataPath);
      await metadataFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
      );

      onProgress?.call(1.0);
      debugPrint('🎉 Download completed!');

      return DownloadResult(
        success: true,
        message: 'Download completed',
        filePath: audioPath,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Download error: $e');
      return DownloadResult(success: false, message: 'Download failed: $e');
    }
  }

  /// Get all downloaded songs
  Future<List<DownloadedSong>> getDownloadedSongs() async {
    try {
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null || !await downloadDir.exists()) {
        return [];
      }

      final List<DownloadedSong> songs = [];
      final files = await downloadDir.list().toList();

      for (final file in files) {
        if (file is File && file.path.endsWith('_metadata.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content);

            final audioPath = json['audioPath'] as String?;
            if (audioPath == null || !await File(audioPath).exists()) {
              debugPrint(
                '⚠️ Audio file missing for ${json['title']}, skipping',
              );
              continue;
            }

            songs.add(
              DownloadedSong(
                videoId: json['videoId'],
                title: json['title'],
                artist: json['artist'],
                audioPath: audioPath,
                thumbnailPath: json['thumbnailPath'],
                thumbnailUrl: json['thumbnailUrl'] ?? '',
                downloadDate: DateTime.parse(json['downloadDate']),
                fileSize: json['fileSize'],
              ),
            );
          } catch (e) {
            debugPrint('Error parsing metadata: $e');
          }
        }
      }

      return songs;
    } catch (e) {
      debugPrint('Error getting downloaded songs: $e');
      return [];
    }
  }

  /// Delete a downloaded song
  Future<bool> deleteDownload(String videoId) async {
    try {
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null) return false;

      final sanitizedId = videoId.replaceAll(RegExp(r'[^\w\-]'), '_');
      final audioPath = '${downloadDir.path}/${sanitizedId}_audio.m4a';
      final thumbnailPath = '${downloadDir.path}/${sanitizedId}_thumbnail.jpg';
      final metadataPath = '${downloadDir.path}/${sanitizedId}_metadata.json';

      // Delete all related files
      final audioFile = File(audioPath);
      final thumbnailFile = File(thumbnailPath);
      final metadataFile = File(metadataPath);

      if (await audioFile.exists()) await audioFile.delete();
      if (await thumbnailFile.exists()) await thumbnailFile.delete();
      if (await metadataFile.exists()) await metadataFile.delete();

      debugPrint('🗑️ Deleted download: $videoId');
      return true;
    } catch (e) {
      debugPrint('Error deleting download: $e');
      return false;
    }
  }

  /// Check if a song is downloaded
  Future<bool> isDownloaded(String videoId) async {
    try {
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null) return false;

      final sanitizedId = videoId.replaceAll(RegExp(r'[^\w\-]'), '_');
      final metadataPath = '${downloadDir.path}/${sanitizedId}_metadata.json';

      return await File(metadataPath).exists();
    } catch (e) {
      return false;
    }
  }
}

class DownloadResult {
  final bool success;
  final String message;
  final String? filePath;

  DownloadResult({required this.success, required this.message, this.filePath});
}

class DownloadedSong {
  final String videoId;
  final String title;
  final String artist;
  final String audioPath;
  final String? thumbnailPath;
  final String thumbnailUrl;
  final DateTime downloadDate;
  final int fileSize;

  DownloadedSong({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.audioPath,
    this.thumbnailPath,
    required this.thumbnailUrl,
    required this.downloadDate,
    required this.fileSize,
  });

  String get formattedFileSize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ============================================================================
// MODELS
// ============================================================================

class DownloadProgress {
  final String videoId;
  final double progress;
  final String message;

  DownloadProgress({
    required this.videoId,
    required this.progress,
    required this.message,
  });
}

/// Report from update check
class UpdateReport {
  bool wasUpdated = false;
  bool isFirstLaunch = false;
  String? oldVersion;
  String? newVersion;
  int validFiles = 0;
  int totalMetadataFiles = 0;
  int totalStorageBytes = 0;
  String? error;

  String get formattedStorage {
    if (totalStorageBytes < 1024 * 1024) {
      return '${(totalStorageBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalStorageBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  String toString() {
    if (isFirstLaunch) return 'First launch';
    if (!wasUpdated) return 'No update';
    return 'Updated $oldVersion → $newVersion: $validFiles files ($formattedStorage)';
  }
}
