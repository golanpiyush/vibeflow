import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadService {
  static final DownloadService instance = DownloadService._internal();
  factory DownloadService() => instance;

  static const String _currentVersion = '1.0.0';
  static const String _versionKey = 'download_service_version';
  static const String _downloadDirKey = 'download_directory_path';

  // ULTRA OPTIMIZED: Multiple Dio instances for parallel chunks
  late final Dio _mainDio;
  late final List<Dio> _chunkDios;

  final Map<String, CancelToken> _activeDownloads = {};
  final Map<String, DownloadProgress> _downloadProgress = {};

  DownloadService._internal() {
    _initializeDio();
  }

  void _initializeDio() {
    // Main Dio with aggressive settings
    _mainDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 5),
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (status) => status! < 500,
        headers: _getOptimalHeaders(),
      ),
    );

    // Create 4 Dio instances for parallel chunk downloads
    _chunkDios = List.generate(
      4,
      (_) => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(minutes: 30),
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status! < 500,
          headers: _getOptimalHeaders(),
        ),
      ),
    );
  }

  Map<String, String> _getOptimalHeaders() {
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'identity', // CRITICAL: Disable compression for speed
      'Connection': 'keep-alive',
      'DNT': '1',
      'Sec-Fetch-Dest': 'audio',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Ch-Ua':
          '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': '"Windows"',
    };
  }

  Future<Directory> _getDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_downloadDirKey);

    if (savedPath != null) {
      final savedDir = Directory(savedPath);
      if (await savedDir.exists()) return savedDir;
    }

    Directory downloadDir;
    if (Platform.isAndroid) {
      try {
        final externalDir = await getExternalStorageDirectory();
        downloadDir = externalDir != null
            ? Directory('${externalDir.path}/VibeFlow/downloads')
            : Directory(
                '${(await getApplicationDocumentsDirectory()).path}/downloads',
              );
      } catch (e) {
        downloadDir = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/downloads',
        );
      }
    } else {
      downloadDir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/downloads',
      );
    }

    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    await prefs.setString(_downloadDirKey, downloadDir.path);
    await prefs.setString(_versionKey, _currentVersion);
    return downloadDir;
  }

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
    final startTime = DateTime.now();

    try {
      final downloadDir = await _getDownloadDirectory();
      final sanitizedTitle = _sanitizeFilename(title);
      final audioFileName = '${videoId}_$sanitizedTitle.m4a';
      final audioFilePath = path.join(downloadDir.path, audioFileName);

      // Check if already downloaded
      final audioFile = File(audioFilePath);
      if (await audioFile.exists() && await audioFile.length() > 10000) {
        print('✓ Already downloaded: $title');
        return DownloadResult(
          success: true,
          audioPath: audioFilePath,
          thumbnailPath: await _getThumbnailPath(videoId, downloadDir),
          message: 'Already downloaded',
        );
      }

      print('🎵 Starting download: $title');
      _updateProgress(videoId, 0.0, 'Starting...');

      // Download thumbnail (non-blocking)
      String? thumbnailPath;
      _downloadThumbnail(
        videoId: videoId,
        thumbnailUrl: thumbnailUrl,
        downloadDir: downloadDir,
        cancelToken: cancelToken,
      ).then((path) => thumbnailPath = path).catchError((e) {
        debugPrint('Thumbnail failed: $e');
      });

      print('📥 Downloading audio with parallel chunks...');

      // STRATEGY 1: Try parallel chunk download first (fastest)
      bool useParallel = await _supportsRangeRequests(audioUrl);

      if (useParallel) {
        print('⚡ Using parallel chunk download (4 connections)');
        await _parallelChunkDownload(
          url: audioUrl,
          savePath: audioFilePath,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            final progress = total > 0
                ? (received / total) * 0.95 + 0.05
                : 0.05;
            _updateProgress(
              videoId,
              progress,
              'Downloading: ${(progress * 100).toStringAsFixed(1)}%',
            );

            if ((progress * 100).floor() % 5 == 0) {
              print(
                '📊 ${(progress * 100).toStringAsFixed(1)}% (${(received / (1024 * 1024)).toStringAsFixed(2)}/${(total / (1024 * 1024)).toStringAsFixed(2)} MB)',
              );
            }
            onProgress?.call(progress);
          },
        );
      } else {
        // STRATEGY 2: Single connection with optimizations
        print('📡 Using single connection (server doesn\'t support ranges)');
        await _optimizedSingleDownload(
          url: audioUrl,
          savePath: audioFilePath,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            final progress = total > 0
                ? (received / total) * 0.95 + 0.05
                : 0.05;
            _updateProgress(
              videoId,
              progress,
              'Downloading: ${(progress * 100).toStringAsFixed(1)}%',
            );

            if ((progress * 100).floor() % 5 == 0) {
              print(
                '📊 ${(progress * 100).toStringAsFixed(1)}% (${(received / (1024 * 1024)).toStringAsFixed(2)}/${(total / (1024 * 1024)).toStringAsFixed(2)} MB)',
              );
            }
            onProgress?.call(progress);
          },
        );
      }

      final duration = DateTime.now().difference(startTime);
      final fileSize = await File(audioFilePath).length();
      final speedMBps = (fileSize / (1024 * 1024)) / duration.inSeconds;

      print(
        '✅ Complete in ${duration.inSeconds}s (${speedMBps.toStringAsFixed(2)} MB/s)',
      );

      await _saveMetadata(
        videoId: videoId,
        title: title,
        artist: artist,
        audioPath: audioFilePath,
        thumbnailPath: thumbnailPath,
        downloadDir: downloadDir,
      );

      _updateProgress(videoId, 1.0, 'Complete');
      _activeDownloads.remove(videoId);

      return DownloadResult(
        success: true,
        audioPath: audioFilePath,
        thumbnailPath: thumbnailPath,
        message: 'Download complete',
      );
    } catch (e) {
      _activeDownloads.remove(videoId);
      print('❌ Download failed: $e');
      return DownloadResult(success: false, message: 'Failed: $e');
    }
  }

  /// Check if server supports range requests
  Future<bool> _supportsRangeRequests(String url) async {
    try {
      final response = await _mainDio.head(url);
      final acceptRanges = response.headers.value('accept-ranges');
      final contentLength = response.headers.value('content-length');

      // Server must support ranges and have known size
      return acceptRanges == 'bytes' && contentLength != null;
    } catch (e) {
      return false;
    }
  }

  /// PARALLEL CHUNK DOWNLOAD: Download file in 4 parallel chunks
  Future<void> _parallelChunkDownload({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required Function(int, int) onProgress,
  }) async {
    // Get file size
    final headResponse = await _mainDio.head(url);
    final totalSize = int.parse(headResponse.headers.value('content-length')!);

    if (totalSize < 1024 * 1024) {
      // File too small for parallel download
      return _optimizedSingleDownload(
        url: url,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }

    final chunkSize = (totalSize / 4).ceil();
    final file = File(savePath);

    // Create empty file
    final raf = await file.open(mode: FileMode.write);
    await raf.truncate(totalSize);
    await raf.close();

    print('📦 File size: ${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB');
    print(
      '🔀 Downloading 4 chunks of ${(chunkSize / (1024 * 1024)).toStringAsFixed(2)} MB each',
    );

    // Download progress tracking
    final chunkProgress = List<int>.filled(4, 0);
    final completer = Completer<void>();
    int completedChunks = 0;

    // Download chunks in parallel
    for (int i = 0; i < 4; i++) {
      final start = i * chunkSize;
      final end = (i == 3) ? totalSize - 1 : (start + chunkSize - 1);

      _downloadChunk(
        url: url,
        savePath: savePath,
        start: start,
        end: end,
        chunkIndex: i,
        dio: _chunkDios[i],
        cancelToken: cancelToken,
        onProgress: (received) {
          chunkProgress[i] = received;
          final totalReceived = chunkProgress.reduce((a, b) => a + b);
          onProgress(totalReceived, totalSize);
        },
        onComplete: () {
          completedChunks++;
          print('✓ Chunk ${i + 1}/4 complete');
          if (completedChunks == 4) {
            completer.complete();
          }
        },
      ).catchError((e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      });
    }

    await completer.future;
  }

  /// Download a single chunk
  Future<void> _downloadChunk({
    required String url,
    required String savePath,
    required int start,
    required int end,
    required int chunkIndex,
    required Dio dio,
    required CancelToken cancelToken,
    required Function(int) onProgress,
    required Function() onComplete,
  }) async {
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        headers: {'Range': 'bytes=$start-$end'},
        responseType: ResponseType.stream,
        validateStatus: (status) => status == 206 || status == 200,
      ),
    );

    final file = File(savePath);
    final raf = await file.open(mode: FileMode.writeOnly);
    await raf.setPosition(start);

    int received = 0;
    await for (final chunk in response.data!.stream) {
      if (cancelToken.isCancelled) break;
      await raf.writeFrom(chunk);
      received += chunk.length;
      onProgress(received);
    }

    await raf.close();
    onComplete();
  }

  /// OPTIMIZED SINGLE DOWNLOAD: For servers that don't support ranges
  Future<void> _optimizedSingleDownload({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required Function(int, int) onProgress,
  }) async {
    final response = await _mainDio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Accept-Encoding': 'identity', // No compression
        },
      ),
    );

    final totalSize = int.parse(
      response.headers.value('content-length') ?? '0',
    );

    final file = File(savePath);
    final raf = await file.open(mode: FileMode.write);

    try {
      int received = 0;
      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) break;
        await raf.writeFrom(chunk);
        received += chunk.length;
        onProgress(received, totalSize);
      }
    } finally {
      await raf.close();
    }
  }

  Future<String?> _downloadThumbnail({
    required String videoId,
    required String thumbnailUrl,
    required Directory downloadDir,
    required CancelToken cancelToken,
  }) async {
    final thumbnailPath = path.join(
      downloadDir.path,
      '${videoId}_thumbnail.jpg',
    );
    final file = File(thumbnailPath);

    if (await file.exists()) return thumbnailPath;

    await _mainDio.download(
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

  Future<String?> _getThumbnailPath(
    String videoId,
    Directory downloadDir,
  ) async {
    final thumbnailPath = path.join(
      downloadDir.path,
      '${videoId}_thumbnail.jpg',
    );
    return await File(thumbnailPath).exists() ? thumbnailPath : null;
  }

  void cancelDownload(String videoId) {
    final cancelToken = _activeDownloads[videoId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel();
      _activeDownloads.remove(videoId);
      _downloadProgress.remove(videoId);
    }
  }

  DownloadProgress? getProgress(String videoId) => _downloadProgress[videoId];
  bool isDownloading(String videoId) => _activeDownloads.containsKey(videoId);

  Future<List<DownloadedSong>> getDownloadedSongs() async {
    final downloadDir = await _getDownloadDirectory();
    final files = await downloadDir.list().toList();
    final List<DownloadedSong> songs = [];

    for (final file in files) {
      if (file is File && file.path.endsWith('_metadata.json')) {
        try {
          final content = await file.readAsString();
          final json = jsonDecode(content);
          final audioPath = json['audioPath'];

          if (audioPath != null) {
            final audioFile = File(audioPath);
            if (await audioFile.exists()) {
              final fileSize = await audioFile.length();
              if (fileSize > 1024) {
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
              }
            }
          }
        } catch (e) {
          debugPrint('Error reading metadata: $e');
        }
      }
    }

    songs.sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
    return songs;
  }

  Future<bool> deleteDownload(String videoId) async {
    try {
      final downloadDir = await _getDownloadDirectory();
      final files = await downloadDir
          .list()
          .where((f) => f.path.contains(videoId))
          .toList();

      for (final file in files) {
        if (file is File) await file.delete();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  void _updateProgress(String videoId, double progress, String message) {
    _downloadProgress[videoId] = DownloadProgress(
      videoId: videoId,
      progress: progress,
      message: message,
    );
  }

  String _sanitizeFilename(String filename) {
    return filename
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .substring(0, filename.length > 50 ? 50 : filename.length);
  }

  void dispose() {
    for (final token in _activeDownloads.values) {
      if (!token.isCancelled) token.cancel();
    }
    _activeDownloads.clear();
    _downloadProgress.clear();
  }
}

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
  final int fileSize;

  DownloadedSong({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.audioPath,
    this.thumbnailPath,
    required this.downloadDate,
    this.fileSize = 0,
  });

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024)
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
