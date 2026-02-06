import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

class SmartAudioFetcher {
  final VibeFlowCore _core = VibeFlowCore();

  /// Fetches audio URL with 3 parallel attempts, returns first successful one
  Future<String?> getAudioUrlSmart(String videoId, {QuickPick? song}) async {
    print('🎯 [SmartFetcher] Starting parallel fetch for: $videoId');

    // Create 3 parallel fetch attempts with staggered delays
    final futures = <Future<String?>>[];

    // Attempt 1: Primary (immediate)
    futures.add(_attemptFetch(videoId, song: song, attemptName: 'PRIMARY'));

    // Attempt 2: Backup with 150ms delay
    futures.add(
      Future.delayed(
        const Duration(milliseconds: 150),
        () => _attemptFetch(videoId, song: song, attemptName: 'BACKUP-1'),
      ),
    );

    // Attempt 3: Backup with 300ms delay
    futures.add(
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _attemptFetch(videoId, song: song, attemptName: 'BACKUP-2'),
      ),
    );

    try {
      // Wait for all attempts to complete
      final results = await Future.wait(
        futures,
        eagerError: false, // Don't stop on first error
      );

      // Find first non-null result
      for (var i = 0; i < results.length; i++) {
        if (results[i] != null && results[i]!.isNotEmpty) {
          print('✅ [SmartFetcher] Success from attempt ${i + 1}');
          return results[i];
        }
      }

      print('❌ [SmartFetcher] All 3 attempts failed');
      return null;
    } catch (e) {
      print('❌ [SmartFetcher] Error: $e');
      return null;
    }
  }

  Future<String?> _attemptFetch(
    String videoId, {
    QuickPick? song,
    required String attemptName,
  }) async {
    try {
      print('🔄 [SmartFetcher] $attemptName fetching...');

      // Add timeout to prevent hanging
      final url = await _core
          .getAudioUrl(videoId, song: song)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print('⏱️ [SmartFetcher] $attemptName timed out');
              return null;
            },
          );

      if (url != null && url.isNotEmpty) {
        print('✅ [SmartFetcher] $attemptName got URL (length: ${url.length})');
        return url;
      }

      print('⚠️ [SmartFetcher] $attemptName returned null');
      return null;
    } catch (e) {
      print('❌ [SmartFetcher] $attemptName failed: $e');
      return null;
    }
  }
}
