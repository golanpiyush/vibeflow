import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadService {
  static final DownloadService instance = DownloadService._internal();
  factory DownloadService() => instance;
  DownloadService._internal();

  // Version management for app updates
  static const String _currentVersion = '1.0.0';
  static const String _versionKey = 'download_service_version';
  static const String _downloadDirKey = 'download_directory_path';

  // Highly optimized Dio instance
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 15),
      sendTimeout: const Duration(minutes: 5),
      receiveDataWhenStatusError: true,
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (status) => status! < 500,
    ),
  );

  // Track active downloads
  final Map<String, CancelToken> _activeDownloads = {};
  final Map<String, DownloadProgress> _downloadProgress = {};

  // Track last print time to avoid console spam
  final Map<String, DateTime> _lastPrintTime = {};

  /// Initialize download directory with persistence across updates
  Future<Directory> _getDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();

    // Check for version mismatch (app update)
    final savedVersion = prefs.getString(_versionKey);
    if (savedVersion != _currentVersion) {
      debugPrint('App updated from $savedVersion to $_currentVersion');
      await _handleAppUpdate(prefs, savedVersion);
    }

    // Try to get saved directory path first
    final savedPath = prefs.getString(_downloadDirKey);

    if (savedPath != null) {
      final savedDir = Directory(savedPath);
      if (await savedDir.exists()) {
        debugPrint('Using existing download directory: $savedPath');
        return savedDir;
      }
    }

    // Create new directory in external/internal storage
    Directory downloadDir;

    if (Platform.isAndroid) {
      // Try external storage first (survives app updates)
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          downloadDir = Directory('${externalDir.path}/VibeFlow/downloads');
        } else {
          // Fallback to app documents
          final appDocDir = await getApplicationDocumentsDirectory();
          downloadDir = Directory('${appDocDir.path}/downloads');
        }
      } catch (e) {
        debugPrint('External storage not available: $e');
        final appDocDir = await getApplicationDocumentsDirectory();
        downloadDir = Directory('${appDocDir.path}/downloads');
      }
    } else {
      // iOS - use documents directory
      final appDocDir = await getApplicationDocumentsDirectory();
      downloadDir = Directory('${appDocDir.path}/downloads');
    }

    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
      debugPrint('Created download directory: ${downloadDir.path}');
    }

    // Save directory path for future use
    await prefs.setString(_downloadDirKey, downloadDir.path);
    await prefs.setString(_versionKey, _currentVersion);

    return downloadDir;
  }

  /// Handle app updates - verify and migrate downloads if needed
  Future<void> _handleAppUpdate(
    SharedPreferences prefs,
    String? oldVersion,
  ) async {
    try {
      debugPrint('Handling app update from $oldVersion to $_currentVersion');

      // Verify existing downloads are still accessible
      final savedPath = prefs.getString(_downloadDirKey);
      if (savedPath != null) {
        final dir = Directory(savedPath);
        if (await dir.exists()) {
          // Verify metadata files are readable
          await _verifyDownloadIntegrity(dir);
          debugPrint('Downloads verified successfully after update');
        }
      }

      // Update version
      await prefs.setString(_versionKey, _currentVersion);
    } catch (e) {
      debugPrint('Error handling app update: $e');
    }
  }

  /// Verify download integrity after updates
  Future<void> _verifyDownloadIntegrity(Directory downloadDir) async {
    try {
      final files = await downloadDir.list().toList();
      int validFiles = 0;
      int corruptedFiles = 0;

      for (final file in files) {
        if (file is File && file.path.endsWith('_metadata.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content);

            // Verify audio file exists
            final audioPath = json['audioPath'];
            if (audioPath != null) {
              final audioFile = File(audioPath);
              if (await audioFile.exists() && await audioFile.length() > 0) {
                validFiles++;
              } else {
                debugPrint('Missing audio for: ${json['title']}');
                corruptedFiles++;
              }
            }
          } catch (e) {
            debugPrint('Corrupted metadata file: ${file.path}');
            corruptedFiles++;
          }
        }
      }

      debugPrint(
        'Download integrity check: $validFiles valid, $corruptedFiles corrupted',
      );
    } catch (e) {
      debugPrint('Error verifying downloads: $e');
    }
  }

  /// Download a song with metadata and audio
  Future<DownloadResult> downloadSong({
    required String videoId,
    required String audioUrl,
    required String title,
    required String artist,
    required String thumbnailUrl,
    Function(double)? onProgress,
  }) async {
    final cancelToken = CancelToken();
    _activeDownloads[videoId] = cancelToken;
    _lastPrintTime[videoId] = DateTime.now();

    final startTime = DateTime.now();

    try {
      final downloadDir = await _getDownloadDirectory();

      // Sanitize filename
      final sanitizedTitle = _sanitizeFilename(title);
      final audioFileName = '${videoId}_$sanitizedTitle.m4a';
      final audioFilePath = path.join(downloadDir.path, audioFileName);

      // Check if already downloaded
      final audioFile = File(audioFilePath);
      if (await audioFile.exists()) {
        final fileSize = await audioFile.length();
        if (fileSize > 0) {
          debugPrint('Song already downloaded: $audioFilePath');
          return DownloadResult(
            success: true,
            audioPath: audioFilePath,
            thumbnailPath: await _getThumbnailPath(videoId, downloadDir),
            message: 'Already downloaded',
          );
        }
      }

      // Update progress
      _updateProgress(videoId, 0.0, 'Starting download...');
      print('🎵 Starting download: $title');

      // Download thumbnail first (small file, quick)
      String? thumbnailPath;
      try {
        thumbnailPath = await _downloadThumbnail(
          videoId: videoId,
          thumbnailUrl: thumbnailUrl,
          downloadDir: downloadDir,
          cancelToken: cancelToken,
        );
        _updateProgress(videoId, 0.05, 'Thumbnail downloaded');
        print('✓ Thumbnail downloaded');
      } catch (e) {
        debugPrint('Thumbnail download failed: $e');
        // Continue even if thumbnail fails
      }

      // Download audio with optimized settings
      print('📥 Downloading audio...');
      int lastReceivedBytes = 0;
      DateTime lastSpeedCheck = DateTime.now();

      await _downloadWithOptimization(
        url: audioUrl,
        savePath: audioFilePath,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          final progress = total > 0 ? (received / total) * 0.95 + 0.05 : 0.05;
          final percentage = (progress * 100).toStringAsFixed(1);
          final receivedMB = (received / (1024 * 1024)).toStringAsFixed(2);
          final totalMB = total > 0
              ? (total / (1024 * 1024)).toStringAsFixed(2)
              : '?';

          _updateProgress(videoId, progress, 'Downloading: $percentage%');

          // Calculate download speed
          final now = DateTime.now();
          final timeDiff = now.difference(lastSpeedCheck).inMilliseconds;

          // Print every 2 seconds or every 10% to avoid spam but show good updates
          final shouldPrint =
              timeDiff > 2000 || (progress * 100).floor() % 10 == 0;

          if (shouldPrint && timeDiff > 0) {
            final bytesDiff = received - lastReceivedBytes;
            final speedMBps = (bytesDiff / timeDiff) * 1000 / (1024 * 1024);

            final speedText = speedMBps >= 1
                ? '${speedMBps.toStringAsFixed(2)} MB/s'
                : '${(speedMBps * 1024).toStringAsFixed(0)} KB/s';

            // Calculate ETA
            String etaText = '';
            if (total > 0 && speedMBps > 0) {
              final remainingBytes = total - received;
              final etaSeconds = (remainingBytes / (1024 * 1024)) / speedMBps;
              if (etaSeconds < 60) {
                etaText = ' | ETA: ${etaSeconds.toStringAsFixed(0)}s';
              } else {
                etaText = ' | ETA: ${(etaSeconds / 60).toStringAsFixed(1)}m';
              }
            }

            print(
              '📊 $percentage% ($receivedMB/$totalMB MB) | Speed: $speedText$etaText',
            );

            lastReceivedBytes = received;
            lastSpeedCheck = now;
            _lastPrintTime[videoId] = now;
          }

          onProgress?.call(progress);
        },
      );

      final downloadDuration = DateTime.now().difference(startTime);
      final fileSize = await File(audioFilePath).length();
      final avgSpeedMBps =
          (fileSize / (1024 * 1024)) / downloadDuration.inSeconds;

      print(
        '✓ Audio download complete in ${downloadDuration.inSeconds}s (Avg: ${avgSpeedMBps.toStringAsFixed(2)} MB/s)',
      );

      // Save metadata
      await _saveMetadata(
        videoId: videoId,
        title: title,
        artist: artist,
        audioPath: audioFilePath,
        thumbnailPath: thumbnailPath,
        downloadDir: downloadDir,
      );

      _updateProgress(videoId, 1.0, 'Download complete');
      _activeDownloads.remove(videoId);
      _lastPrintTime.remove(videoId);

      print('✅ Download completed successfully: $title');

      return DownloadResult(
        success: true,
        audioPath: audioFilePath,
        thumbnailPath: thumbnailPath,
        message: 'Download completed successfully',
      );
    } on DioException catch (e) {
      _activeDownloads.remove(videoId);
      _lastPrintTime.remove(videoId);

      if (e.type == DioExceptionType.cancel) {
        print('❌ Download cancelled: $title');
        return DownloadResult(success: false, message: 'Download cancelled');
      }

      print('❌ Download failed: ${e.message}');
      return DownloadResult(
        success: false,
        message: 'Download failed: ${e.message}',
      );
    } catch (e) {
      _activeDownloads.remove(videoId);
      _lastPrintTime.remove(videoId);
      print('❌ Download error: $e');
      return DownloadResult(success: false, message: 'Download failed: $e');
    }
  }

  /// Optimized download with maximum speed settings
  Future<void> _downloadWithOptimization({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required Function(int, int) onProgress,
  }) async {
    final file = File(savePath);
    int downloadedBytes = 0;

    // Check if partial file exists
    if (await file.exists()) {
      downloadedBytes = await file.length();
      print(
        '📂 Resuming from ${(downloadedBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
      );
    }

    // Maximum speed optimization
    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      deleteOnError: false,
      options: Options(
        headers: {
          if (downloadedBytes > 0) 'Range': 'bytes=$downloadedBytes-',
          'Accept': '*/*',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 15),
        sendTimeout: const Duration(minutes: 5),
        followRedirects: true,
        maxRedirects: 5,
      ),
      onReceiveProgress: (received, total) {
        final totalBytes = total > 0 ? total : received;
        final currentBytes = received + downloadedBytes;
        onProgress(currentBytes, totalBytes + downloadedBytes);
      },
    );
  }

  /// Download thumbnail
  Future<String?> _downloadThumbnail({
    required String videoId,
    required String thumbnailUrl,
    required Directory downloadDir,
    required CancelToken cancelToken,
  }) async {
    final thumbnailFileName = '${videoId}_thumbnail.jpg';
    final thumbnailPath = path.join(downloadDir.path, thumbnailFileName);

    // Check if already exists
    final thumbnailFile = File(thumbnailPath);
    if (await thumbnailFile.exists()) {
      return thumbnailPath;
    }

    await _dio.download(
      thumbnailUrl,
      thumbnailPath,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    return thumbnailPath;
  }

  /// Save metadata to JSON file
  Future<void> _saveMetadata({
    required String videoId,
    required String title,
    required String artist,
    required String audioPath,
    required String? thumbnailPath,
    required Directory downloadDir,
  }) async {
    final metadataFile = File(
      path.join(downloadDir.path, '${videoId}_metadata.json'),
    );

    final metadata = {
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'audioPath': audioPath,
      'thumbnailPath': thumbnailPath,
      'downloadDate': DateTime.now().toIso8601String(),
    };

    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  /// Get thumbnail path if exists
  Future<String?> _getThumbnailPath(
    String videoId,
    Directory downloadDir,
  ) async {
    final thumbnailPath = path.join(
      downloadDir.path,
      '${videoId}_thumbnail.jpg',
    );
    final file = File(thumbnailPath);
    return await file.exists() ? thumbnailPath : null;
  }

  /// Cancel a download
  void cancelDownload(String videoId) {
    final cancelToken = _activeDownloads[videoId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('User cancelled download');
      _activeDownloads.remove(videoId);
      _downloadProgress.remove(videoId);
      _lastPrintTime.remove(videoId);
      print('🛑 Download cancelled: $videoId');
    }
  }

  /// Get download progress
  DownloadProgress? getProgress(String videoId) {
    return _downloadProgress[videoId];
  }

  /// Check if download is active
  bool isDownloading(String videoId) {
    return _activeDownloads.containsKey(videoId);
  }

  /// Get all downloaded songs with integrity check
  Future<List<DownloadedSong>> getDownloadedSongs() async {
    final downloadDir = await _getDownloadDirectory();
    final files = await downloadDir.list().toList();

    final List<DownloadedSong> songs = [];
    final List<File> corruptedFiles = [];

    for (final file in files) {
      if (file is File && file.path.endsWith('_metadata.json')) {
        try {
          final content = await file.readAsString();
          final json = jsonDecode(content);

          // Verify audio file still exists and is valid
          final audioPath = json['audioPath'];
          if (audioPath != null) {
            final audioFile = File(audioPath);

            if (await audioFile.exists()) {
              final fileSize = await audioFile.length();

              // Check if file is not empty (corrupted)
              if (fileSize > 1024) {
                // At least 1KB
                songs.add(
                  DownloadedSong(
                    videoId: json['videoId'] ?? '',
                    title: json['title'] ?? 'Unknown',
                    artist: json['artist'] ?? 'Unknown',
                    audioPath: audioPath,
                    thumbnailPath: json['thumbnailPath'],
                    downloadDate: json['downloadDate'] != null
                        ? DateTime.parse(json['downloadDate'])
                        : DateTime.now(),
                    fileSize: fileSize,
                  ),
                );
              } else {
                debugPrint('Corrupted file detected: $audioPath');
                corruptedFiles.add(file);
              }
            } else {
              debugPrint('Missing audio file: $audioPath');
              corruptedFiles.add(file);
            }
          }
        } catch (e) {
          debugPrint('Error reading metadata: $e');
          corruptedFiles.add(file);
        }
      }
    }

    // Clean up corrupted metadata files
    for (final corruptedFile in corruptedFiles) {
      try {
        await corruptedFile.delete();
        debugPrint('Deleted corrupted metadata: ${corruptedFile.path}');
      } catch (e) {
        debugPrint('Failed to delete corrupted file: $e');
      }
    }

    // Sort by download date (newest first)
    songs.sort((a, b) => b.downloadDate.compareTo(a.downloadDate));

    return songs;
  }

  /// Delete a downloaded song
  Future<bool> deleteDownload(String videoId) async {
    try {
      final downloadDir = await _getDownloadDirectory();

      // Delete audio file
      final audioFiles = await downloadDir
          .list()
          .where((f) => f.path.contains(videoId))
          .toList();

      for (final file in audioFiles) {
        if (file is File) {
          await file.delete();
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error deleting download: $e');
      return false;
    }
  }

  /// Update progress tracking
  void _updateProgress(String videoId, double progress, String message) {
    _downloadProgress[videoId] = DownloadProgress(
      videoId: videoId,
      progress: progress,
      message: message,
    );
  }

  /// Sanitize filename
  String _sanitizeFilename(String filename) {
    return filename
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .substring(0, filename.length > 50 ? 50 : filename.length);
  }

  void dispose() {
    for (final token in _activeDownloads.values) {
      if (!token.isCancelled) {
        token.cancel();
      }
    }
    _activeDownloads.clear();
    _downloadProgress.clear();
    _lastPrintTime.clear();
  }
}

// Models
class DownloadResult {
  final bool success;
  final String? audioPath;
  final String? thumbnailPath;
  final String message;

  DownloadResult({
    required this.success,
    this.audioPath,
    this.thumbnailPath,
    required this.message,
  });
}

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

class DownloadedSong {
  final String videoId;
  final String title;
  final String artist;
  final String audioPath;
  final String? thumbnailPath;
  final DateTime downloadDate;
  final int fileSize; // File size in bytes

  DownloadedSong({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.audioPath,
    this.thumbnailPath,
    required this.downloadDate,
    this.fileSize = 0,
  });

  // Get formatted file size
  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
