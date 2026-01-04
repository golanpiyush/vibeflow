// lib/services/update_manager_service.dart - ENHANCED VERSION
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibeflow/installer_services/apk_installer_service.dart';
import 'package:dio/dio.dart';

enum UpdateStatus { available, upToDate, error }

class UpdateManagerService {
  // 🔧 CONFIGURE WITH YOUR REPOSITORY
  static const String GITHUB_OWNER = 'golanpiyush';
  static const String GITHUB_REPO = 'vibeflow';

  static String get GITHUB_RELEASE_URL =>
      'https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest';

  /// Enhanced check with architecture detection
  /// Enhanced check with architecture detection and status message
  static Future<UpdateCheckResult> checkForUpdate() async {
    try {
      debugPrint('🔍 Checking for updates from GitHub...');

      // Get current app info using package_info_plus
      final currentInfo = await PackageInfo.fromPlatform();
      final currentVersion = currentInfo.version;
      final currentVersionCode = int.tryParse(currentInfo.buildNumber) ?? 1;

      // Detect device architecture
      final arch = await _detectDeviceArchitecture();
      debugPrint('📱 Device architecture: $arch');

      // Fetch latest release from GitHub
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

      // Handle 404 - Repository not found or no releases
      if (response.statusCode == 404) {
        debugPrint('❌ Repository not found or no releases published');
        return UpdateCheckResult(
          status: UpdateStatus.error,
          message: 'Unable to check for updates. Repository not found.',
        );
      }

      if (response.statusCode != 200) {
        debugPrint('❌ GitHub API error: ${response.statusCode}');
        return UpdateCheckResult(
          status: UpdateStatus.error,
          message: 'Failed to check for updates. Please try again later.',
        );
      }

      final data = response.data;
      final tagName = data['tag_name'] as String? ?? '0.0.0';

      // Extract version from tag
      final latestVersion = _extractVersionFromTag(tagName);
      final latestVersionCode = _versionToCode(latestVersion);

      debugPrint('🆕 Latest version: $latestVersion ($latestVersionCode)');

      // Find compatible APK based on architecture
      final assets = data['assets'] as List? ?? [];
      final compatibleAsset = _findCompatibleAsset(assets, arch);

      if (compatibleAsset == null) {
        debugPrint('❌ No compatible APK found for architecture: $arch');
        return UpdateCheckResult(
          status: UpdateStatus.error,
          message: 'No compatible update found for your device.',
        );
      }

      // Check if update is available
      if (latestVersionCode > currentVersionCode) {
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

        return UpdateCheckResult(
          status: UpdateStatus.available,
          message: 'Update available: v$latestVersion',
          updateInfo: updateInfo,
        );
      } else {
        debugPrint('✅ App is up to date');
        return UpdateCheckResult(
          status: UpdateStatus.upToDate,
          message: 'You\'re using the latest version (v$currentVersion)',
        );
      }
    } catch (e) {
      debugPrint('❌ Error checking for update: $e');
      return UpdateCheckResult(
        status: UpdateStatus.error,
        message:
            'Failed to check for updates. Please check your internet connection.',
      );
    }
  }

  /// Detect device architecture
  static Future<String> _detectDeviceArchitecture() async {
    try {
      final abi = await _getAbi();

      // Map ABI to architecture names
      const abiMap = {
        'armeabi-v7a': 'v7a',
        'arm64-v8a': 'v8a',
        'x86': 'x86',
        'x86_64': 'x86_64',
        'universal': 'universal',
      };

      return abiMap[abi] ?? abi;
    } catch (e) {
      debugPrint('⚠️ Could not detect architecture, defaulting to universal');
      return 'universal';
    }
  }

  /// Get ABI information
  static Future<String> _getAbi() async {
    // Method 1: Use Platform.operatingSystemVersion
    if (Platform.isAndroid) {
      try {
        // Check CPU ABI through Process
        final result = await Process.run('getprop', ['ro.product.cpu.abi']);
        final abi = (result.stdout as String).trim().toLowerCase();

        if (abi.contains('arm64-v8a') || abi.contains('aarch64')) {
          return 'arm64-v8a';
        } else if (abi.contains('armeabi-v7a')) {
          return 'armeabi-v7a';
        } else if (abi.contains('x86_64')) {
          return 'x86_64';
        } else if (abi.contains('x86')) {
          return 'x86';
        }
      } catch (e) {
        debugPrint('⚠️ Could not detect ABI via getprop: $e');
      }
    }

    // Default based on platform
    return Platform.isAndroid ? 'arm64-v8a' : 'unknown';
  }

  /// Find compatible APK asset based on architecture
  static Map<String, dynamic>? _findCompatibleAsset(
    List<dynamic> assets,
    String architecture,
  ) {
    // Priority order for architecture matching
    final List<String> architecturePatterns = [
      architecture,
      'universal',
      'noarch',
      'multi',
      'all',
    ];

    // Common APK naming patterns
    final List<String> apkPatterns = [
      'app-release',
      'release',
      'vibeflow',
      '.apk',
    ];

    for (final pattern in architecturePatterns) {
      for (final asset in assets) {
        final assetName = asset['name'].toString().toLowerCase();

        // Check if it's an APK
        final isApk = assetName.endsWith('.apk');

        // Check architecture pattern
        final hasArchPattern = assetName.contains(pattern.toLowerCase());

        // Check for common APK naming
        final hasApkPattern = apkPatterns.any((p) => assetName.contains(p));

        if (isApk && (hasArchPattern || pattern == 'universal')) {
          debugPrint('✅ Found compatible APK: ${asset['name']}');
          return asset as Map<String, dynamic>;
        }
      }
    }

    // Fallback: Any APK
    for (final asset in assets) {
      final assetName = asset['name'].toString().toLowerCase();
      if (assetName.endsWith('.apk')) {
        debugPrint('⚠️ Using fallback APK: ${asset['name']}');
        return asset as Map<String, dynamic>;
      }
    }

    return null;
  }

  /// Optimized download using Dio with progress
  static Future<String> downloadUpdate(
    UpdateInfo updateInfo,
    Function(double progress, int downloaded, int total) onProgress,
  ) async {
    try {
      debugPrint('📥 Starting download: ${updateInfo.assetName}');
      debugPrint('📁 Size: ${updateInfo.fileSizeFormatted}');
      debugPrint('📥 URL: ${updateInfo.downloadUrl}');

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/vibeflow_${updateInfo.latestVersion}_${updateInfo.architecture}.apk';
      final file = File(filePath);

      // Clean up previous downloads
      await _cleanOldDownloads(tempDir);

      // Configure Dio with better settings
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          headers: {'User-Agent': 'VibeFlow-Updater/1.0', 'Accept': '*/*'},
        ),
      );

      // Download with progress
      await dio.download(
        updateInfo.downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress(progress, received, total);

            if (received % (1024 * 1024) < 1024) {
              // Log every MB
              debugPrint(
                '📥 Download: ${(progress * 100).toStringAsFixed(1)}%',
              );
            }
          }
        },
        deleteOnError: true,
      );

      // Verify download
      final downloadedSize = await file.length();
      if (downloadedSize != updateInfo.fileSize && updateInfo.fileSize > 0) {
        debugPrint(
          '⚠️ Size mismatch: $downloadedSize vs ${updateInfo.fileSize}',
        );
      }

      debugPrint('✅ Download complete: $filePath');
      debugPrint(
        '📁 Final size: ${UpdateManagerService.formatFileSize(downloadedSize)}',
      );

      return filePath;
    } catch (e) {
      debugPrint('❌ Download failed: $e');

      // Clean up partial download
      try {
        final tempDir = await getTemporaryDirectory();
        final files = await tempDir.list().toList();
        for (final file in files) {
          if (file.path.contains('vibeflow_')) {
            await file.delete();
          }
        }
      } catch (_) {}

      rethrow;
    }
  }

  /// Clean old download files
  static Future<void> _cleanOldDownloads(Directory tempDir) async {
    try {
      final files = await tempDir.list().toList();
      final now = DateTime.now();

      for (final file in files) {
        if (file is File && file.path.contains('vibeflow_')) {
          final stat = await file.stat();
          final age = now.difference(stat.modified);

          if (age > const Duration(hours: 1)) {
            await file.delete();
            debugPrint('🗑️ Cleaned old file: ${file.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error cleaning old downloads: $e');
    }
  }

  /// Extract version number from Git tag (e.g., "v1.2.3" -> "1.2.3")
  static String _extractVersionFromTag(String tag) {
    // Remove 'v' prefix if present
    final version = tag.replaceFirst(RegExp(r'^v', caseSensitive: false), '');

    // Validate format (should be x.y.z)
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
        // Supports up to 99.99.99
        return (major * 10000) + (minor * 100) + patch;
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

    // Format with appropriate decimal places
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

// Update the UpdateInfo class
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
    // Basic markdown formatting for display
    return releaseNotes
        .replaceAll('# ', '## ')
        .replaceAll('* ', '• ')
        .replaceAll('## ', '\n## ')
        .replaceAll('  ', '\n\n')
        .trim();
  }
}
