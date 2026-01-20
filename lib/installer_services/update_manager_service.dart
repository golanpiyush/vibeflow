// lib/services/update_manager_service.dart - COMPLETE WITH RESUME SUPPORT
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

enum UpdateStatus { available, upToDate, error }

class UpdateManagerService {
  // 🔧 CONFIGURE WITH YOUR REPOSITORY
  static const String GITHUB_OWNER = 'golanpiyush';
  static const String GITHUB_REPO = 'vibeflow';

  static String get GITHUB_RELEASE_URL =>
      'https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest';

  /// Enhanced check with better logging and architecture detection
  static Future<UpdateCheckResult> checkForUpdate() async {
    try {
      debugPrint('🔍 ========== UPDATE CHECK STARTED ==========');

      // Get current app info using package_info_plus
      final currentInfo = await PackageInfo.fromPlatform();
      final currentVersion = currentInfo.version;
      final currentVersionCode = int.tryParse(currentInfo.buildNumber) ?? 1;

      debugPrint(
        '📱 Current App Version: $currentVersion (build $currentVersionCode)',
      );

      // Detect device architecture
      final arch = await _detectDeviceArchitecture();
      debugPrint('🏗️ Device Architecture: $arch');

      // Fetch latest release from GitHub
      debugPrint('🌐 Fetching from: $GITHUB_RELEASE_URL');

      final dio = Dio();
      final response = await dio.get(
        GITHUB_RELEASE_URL,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'VibeFlow-UpdateChecker',
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      debugPrint('📡 Response Status: ${response.statusCode}');

      // Handle 404 - Repository not found or no releases
      if (response.statusCode == 404) {
        debugPrint('❌ ISSUE: No releases found on GitHub!');
        debugPrint(
          '💡 Solution: Go to https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/new',
        );
        return UpdateCheckResult(
          status: UpdateStatus.error,
          message: 'No releases published yet. Please create a GitHub release.',
        );
      }

      if (response.statusCode != 200) {
        debugPrint('❌ GitHub API Error: ${response.statusCode}');
        return UpdateCheckResult(
          status: UpdateStatus.error,
          message:
              'Failed to check for updates. Status: ${response.statusCode}',
        );
      }

      final data = response.data;
      final tagName = data['tag_name'] as String? ?? '0.0.0';

      debugPrint('🏷️ Latest Release Tag: $tagName');

      // Extract version from tag
      final latestVersion = _extractVersionFromTag(tagName);
      final latestVersionCode = _versionToCode(latestVersion);

      debugPrint(
        '🆕 Latest Version: $latestVersion (code: $latestVersionCode)',
      );
      debugPrint(
        '📊 Current Version: $currentVersion (code: $currentVersionCode)',
      );
      debugPrint(
        '🔢 Version Comparison: $latestVersionCode > $currentVersionCode = ${latestVersionCode > currentVersionCode}',
      );

      // Find compatible APK based on architecture
      final assets = data['assets'] as List? ?? [];
      debugPrint('📦 Total Assets Found: ${assets.length}');

      // Log all available assets
      for (var i = 0; i < assets.length; i++) {
        debugPrint('   Asset $i: ${assets[i]['name']}');
      }

      final compatibleAsset = _findCompatibleAsset(assets, arch);

      if (compatibleAsset == null) {
        debugPrint('❌ No compatible APK found for architecture: $arch');
        debugPrint('💡 Make sure your release includes APK files named like:');
        debugPrint('   - vibeflow_v1.1.0_arm64-v8a_release.apk');
        debugPrint('   - vibeflow_v1.1.0_armeabi-v7a_release.apk');
        debugPrint('   - vibeflow_v1.1.0_universal_release.apk');
        return UpdateCheckResult(
          status: UpdateStatus.error,
          message: 'No compatible APK found. Please check release assets.',
        );
      }

      debugPrint('✅ Compatible APK Found: ${compatibleAsset['name']}');

      // Check if update is available
      // Check if update is available - FIXED LOGIC
      if (latestVersionCode > currentVersionCode) {
        debugPrint('🎉 UPDATE AVAILABLE!');
        debugPrint('   Current: v$currentVersion ($currentVersionCode)');
        debugPrint('   Latest:  v$latestVersion ($latestVersionCode)');

        final updateInfo = UpdateInfo(
          currentVersion: currentVersion,
          currentVersionCode: currentVersionCode,
          latestVersion: latestVersion,
          latestVersionCode: latestVersionCode,
          downloadUrl: compatibleAsset['browser_download_url'],
          releaseNotes: data['body'] ?? 'New update available!',
          fileSize: compatibleAsset['size'] ?? 0,
          releaseName: data['name'] ?? 'VibeFlow $latestVersion',
          publishedAt: data['published_at'] ?? '',
          isPrerelease: data['prerelease'] ?? false,
          assetName: compatibleAsset['name'],
          architecture: arch,
        );

        debugPrint('🔍 ========== UPDATE CHECK COMPLETE ==========');

        return UpdateCheckResult(
          status: UpdateStatus.available,
          message: 'Update available: v$latestVersion',
          updateInfo: updateInfo,
        );
      } else {
        // App is either up-to-date OR newer than GitHub release
        // In BOTH cases, NO UPDATE is needed
        debugPrint('✅ No updates available');
        debugPrint('   Current: v$currentVersion ($currentVersionCode)');
        debugPrint('   GitHub:  v$latestVersion ($latestVersionCode)');
        debugPrint('🔍 ========== UPDATE CHECK COMPLETE ==========');

        return UpdateCheckResult(
          status: UpdateStatus.upToDate,
          message: 'No updates available',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ERROR during update check: $e');
      debugPrint('📋 Stack Trace: $stackTrace');
      debugPrint('🔍 ========== UPDATE CHECK FAILED ==========');

      return UpdateCheckResult(
        status: UpdateStatus.error,
        message: 'Failed to check for updates: ${e.toString()}',
      );
    }
  }

  /// Detect device architecture with better logging
  static Future<String> _detectDeviceArchitecture() async {
    try {
      final abi = await _getAbi();
      debugPrint('🔧 Detected ABI: $abi');

      // Map ABI to simplified architecture names
      const abiMap = {
        'armeabi-v7a': 'armeabi-v7a',
        'arm64-v8a': 'arm64-v8a',
        'x86': 'x86',
        'x86_64': 'x86_64',
      };

      final mappedArch = abiMap[abi] ?? abi;
      debugPrint('🗺️ Mapped Architecture: $mappedArch');
      return mappedArch;
    } catch (e) {
      debugPrint('⚠️ Could not detect architecture: $e');
      debugPrint('   Defaulting to: universal');
      return 'universal';
    }
  }

  /// Get ABI information
  static Future<String> _getAbi() async {
    if (Platform.isAndroid) {
      try {
        // Check CPU ABI through Process
        final result = await Process.run('getprop', ['ro.product.cpu.abi']);
        final abi = (result.stdout as String).trim().toLowerCase();

        debugPrint('🔍 Raw ABI from getprop: $abi');

        if (abi.contains('arm64-v8a') || abi.contains('aarch64')) {
          return 'arm64-v8a';
        } else if (abi.contains('armeabi-v7a')) {
          return 'armeabi-v7a';
        } else if (abi.contains('x86_64')) {
          return 'x86_64';
        } else if (abi.contains('x86')) {
          return 'x86';
        }

        return abi.isNotEmpty ? abi : 'arm64-v8a';
      } catch (e) {
        debugPrint('⚠️ Could not detect ABI via getprop: $e');
      }
    }

    return Platform.isAndroid ? 'arm64-v8a' : 'unknown';
  }

  /// Find compatible APK asset - IMPROVED VERSION
  static Map<String, dynamic>? _findCompatibleAsset(
    List<dynamic> assets,
    String architecture,
  ) {
    debugPrint('🔍 Searching for compatible APK...');
    debugPrint('   Target Architecture: $architecture');

    // First priority: Exact architecture match
    for (final asset in assets) {
      final assetName = asset['name'].toString().toLowerCase();

      if (assetName.endsWith('.apk') &&
          assetName.contains(architecture.toLowerCase())) {
        debugPrint('✅ Found exact match: ${asset['name']}');
        return asset as Map<String, dynamic>;
      }
    }

    debugPrint('   No exact match, looking for universal APK...');

    // Second priority: Universal APK
    for (final asset in assets) {
      final assetName = asset['name'].toString().toLowerCase();

      if (assetName.endsWith('.apk') &&
          (assetName.contains('universal') ||
              assetName.contains('all') ||
              assetName.contains('multi'))) {
        debugPrint('✅ Found universal APK: ${asset['name']}');
        return asset as Map<String, dynamic>;
      }
    }

    debugPrint('   No universal APK, looking for any APK...');

    // Fallback: Any APK file
    for (final asset in assets) {
      final assetName = asset['name'].toString().toLowerCase();
      if (assetName.endsWith('.apk')) {
        debugPrint('⚠️ Using fallback APK: ${asset['name']}');
        return asset as Map<String, dynamic>;
      }
    }

    debugPrint('❌ No APK files found in release assets!');
    return null;
  }

  /// Optimized download using Dio with progress (legacy method - calls resume version)
  static Future<String> downloadUpdate(
    UpdateInfo updateInfo,
    Function(double progress, int downloaded, int total) onProgress,
  ) async {
    return downloadUpdateWithResume(updateInfo, onProgress);
  }

  /// Optimized download with resume support and chunked download
  static Future<String> downloadUpdateWithResume(
    UpdateInfo updateInfo,
    Function(double progress, int downloaded, int total) onProgress,
  ) async {
    try {
      debugPrint('📥 ========== DOWNLOAD STARTED ==========');
      debugPrint('📥 File: ${updateInfo.assetName}');
      debugPrint('📁 Size: ${updateInfo.fileSizeFormatted}');
      debugPrint('🔗 URL: ${updateInfo.downloadUrl}');

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'vibeflow_${updateInfo.latestVersion}_${updateInfo.architecture}.apk';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      // Check if partial download exists
      int downloadedBytes = 0;
      if (await file.exists()) {
        downloadedBytes = await file.length();
        debugPrint(
          '📦 Found partial download: ${formatFileSize(downloadedBytes)}',
        );

        // If file is complete, verify and return
        if (updateInfo.fileSize > 0 && downloadedBytes == updateInfo.fileSize) {
          debugPrint('✅ File already downloaded completely');
          return filePath;
        }
      }

      // Configure Dio with better settings
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
          headers: {'User-Agent': 'VibeFlow-Updater/1.0', 'Accept': '*/*'},
        ),
      );

      // Download with resume support
      await dio.download(
        updateInfo.downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          final totalReceived = downloadedBytes + received;
          final totalSize = total > 0 ? total : updateInfo.fileSize;

          if (totalSize > 0) {
            final progress = totalReceived / totalSize;
            onProgress(progress, totalReceived, totalSize);

            if (received % (512 * 1024) < 8192) {
              debugPrint(
                '📥 Progress: ${(progress * 100).toStringAsFixed(1)}% ($totalReceived / $totalSize bytes)',
              );
            }
          }
        },
        deleteOnError: false, // Don't delete on error to allow resume
        options: Options(
          headers: downloadedBytes > 0
              ? {'Range': 'bytes=$downloadedBytes-'}
              : {},
        ),
      );

      // Verify download
      final finalSize = await file.length();
      debugPrint('✅ Download complete!');
      debugPrint('📁 File path: $filePath');
      debugPrint('📊 Downloaded: ${formatFileSize(finalSize)}');

      if (updateInfo.fileSize > 0 && finalSize != updateInfo.fileSize) {
        debugPrint(
          '⚠️ Size mismatch: Expected ${updateInfo.fileSize}, Got $finalSize',
        );
      }

      // Clean up old downloads (but keep current one)
      await _cleanOldDownloads(tempDir, exclude: fileName);

      debugPrint('📥 ========== DOWNLOAD COMPLETE ==========');
      return filePath;
    } catch (e, stackTrace) {
      debugPrint('❌ Download failed: $e');
      debugPrint('📋 Stack trace: $stackTrace');

      // Don't clean up on error - allow resume
      rethrow;
    }
  }

  /// Clean old download files (with exclusion support)
  static Future<void> _cleanOldDownloads(
    Directory tempDir, {
    String? exclude,
  }) async {
    try {
      final files = await tempDir.list().toList();
      final now = DateTime.now();
      int cleaned = 0;

      for (final file in files) {
        if (file is File && file.path.contains('vibeflow_')) {
          // Skip the file we want to exclude
          if (exclude != null && file.path.endsWith(exclude)) {
            continue;
          }

          final stat = await file.stat();
          final age = now.difference(stat.modified);

          if (age > const Duration(hours: 24)) {
            await file.delete();
            cleaned++;
          }
        }
      }

      if (cleaned > 0) {
        debugPrint('🗑️ Cleaned $cleaned old download file(s)');
      }
    } catch (e) {
      debugPrint('⚠️ Error cleaning old downloads: $e');
    }
  }

  /// Extract version number from Git tag (e.g., "v1.2.3" -> "1.2.3")
  static String _extractVersionFromTag(String tag) {
    final version = tag.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final versionPattern = RegExp(r'^\d+\.\d+\.\d+');

    if (versionPattern.hasMatch(version)) {
      return version;
    }

    debugPrint('⚠️ Invalid version format: $tag, using as-is');
    return version;
  }

  /// Convert version string to comparable integer code
  /// Example: "1.2.3" -> 10203, "2.0.10" -> 20010
  static int _versionToCode(String version) {
    try {
      final parts = version.split('.');

      if (parts.length >= 3) {
        final major = int.tryParse(parts[0]) ?? 0;
        final minor = int.tryParse(parts[1]) ?? 0;
        final patch = int.tryParse(parts[2]) ?? 0;

        // Format: MAJOR * 10000 + MINOR * 100 + PATCH
        final code = (major * 10000) + (minor * 100) + patch;
        return code;
      }

      debugPrint('⚠️ Invalid version format: $version');
      return 0;
    } catch (e) {
      debugPrint('❌ Error parsing version: $e');
      return 0;
    }
  }

  /// Format file size to human-readable format
  static String formatFileSize(int bytes) {
    if (bytes < 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    final formattedSize = suffixIndex == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(2);

    return '$formattedSize ${suffixes[suffixIndex]}';
  }
}

class UpdateCheckResult {
  final UpdateStatus status;
  final String message;
  final UpdateInfo? updateInfo;

  UpdateCheckResult({
    required this.status,
    required this.message,
    this.updateInfo,
  });
}

class UpdateInfo {
  final String currentVersion;
  final int currentVersionCode;
  final String latestVersion;
  final int latestVersionCode;
  final String downloadUrl;
  final String releaseNotes;
  final int fileSize;
  final String releaseName;
  final String publishedAt;
  final bool isPrerelease;
  final String assetName;
  final String architecture;

  UpdateInfo({
    required this.currentVersion,
    required this.currentVersionCode,
    required this.latestVersion,
    required this.latestVersionCode,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.fileSize,
    required this.releaseName,
    required this.publishedAt,
    required this.isPrerelease,
    required this.assetName,
    required this.architecture,
  });

  bool get isUpdateAvailable => latestVersionCode > currentVersionCode;

  String get fileSizeFormatted => UpdateManagerService.formatFileSize(fileSize);

  String get publishedDate {
    try {
      final date = DateTime.parse(publishedAt);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  String get formattedReleaseNotes {
    return releaseNotes
        .replaceAll('# ', '## ')
        .replaceAll('* ', '• ')
        .replaceAll('## ', '\n## ')
        .replaceAll('  ', '\n\n')
        .trim();
  }
}
