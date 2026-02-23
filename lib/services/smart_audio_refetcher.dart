import 'dart:async';
import 'package:vibeflow/api_base/innertubeaudio.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';

/// Fetches audio URLs with 3 parallel attempts, returning as soon as the
/// first one succeeds. Duplicate calls for the same videoId share one
/// in-flight request instead of firing redundant network calls.
///
/// Respects [AudioSourcePreference] — set [preference] to control which
/// backend is tried first. VibeFlow will auto-override to the other backend
/// if the preferred one exhausts all attempts.
class SmartAudioFetcher {
  final VibeFlowCore _core = VibeFlowCore();
  YtFlutterMusicapi _ytApi = YtFlutterMusicapi();

  /// Mirrors the user's preference from BackgroundAudioHandler.
  /// Set this whenever the user changes their search engine setting.
  AudioSourcePreference preference = AudioSourcePreference.innerTube;

  // In-flight deduplication: videoId → future
  final Map<String, Future<String?>> _inFlight = {};

  Future<String?> getAudioUrlSmart(String videoId, {QuickPick? song}) async {
    final existing = _inFlight[videoId];
    if (existing != null) {
      print('🔗 [SmartFetcher] Joining in-flight request for $videoId');
      return existing;
    }

    final future = _fetchWithRace(videoId, song: song)
        .catchError((_) => null as String?)
        .whenComplete(() {
          _inFlight.remove(videoId);
        });

    _inFlight[videoId] = future;
    return future;
  }

  Future<String?> _fetchWithRace(String videoId, {QuickPick? song}) async {
    print('🎯 [SmartFetcher] Starting parallel fetch for: $videoId');
    print('   Preferred source: ${preference.name}');

    // ── Phase 1: preferred source (3 staggered attempts) ─────────────────
    final preferredUrl = await _raceAttempts(
      videoId,
      song: song,
      sourceLabel: preference.name,
      fetchFn: (videoId, song) =>
          _fetchFromPreference(videoId, song, preference),
    );

    if (preferredUrl != null) return preferredUrl;

    // ── Phase 2: auto-override to alternate source ────────────────────────
    final alternate = preference == AudioSourcePreference.innerTube
        ? AudioSourcePreference.ytMusicApi
        : AudioSourcePreference.innerTube;

    print(
      '⚡ [SmartFetcher] Preferred source (${preference.name}) exhausted — '
      'auto-overriding to ${alternate.name}',
    );

    final alternateUrl = await _raceAttempts(
      videoId,
      song: song,
      sourceLabel: alternate.name,
      fetchFn: (videoId, song) =>
          _fetchFromPreference(videoId, song, alternate),
    );

    if (alternateUrl == null) {
      print('❌ [SmartFetcher] Both sources exhausted for $videoId');
    }

    return alternateUrl;
  }

  /// Fires [totalAttempts] staggered calls to [fetchFn] and returns the first
  /// non-null result, or null if all fail.
  Future<String?> _raceAttempts(
    String videoId, {
    QuickPick? song,
    required String sourceLabel,
    required Future<String?> Function(String, QuickPick?) fetchFn,
    int totalAttempts = 3,
  }) async {
    final completer = Completer<String?>();
    int completedCount = 0;
    bool resolved = false;

    const delays = [0, 150, 300];
    final names = [
      '$sourceLabel-PRIMARY',
      '$sourceLabel-BACKUP-1',
      '$sourceLabel-BACKUP-2',
    ];

    for (int i = 0; i < totalAttempts; i++) {
      Future.delayed(Duration(milliseconds: delays[i]), () async {
        if (completer.isCompleted || resolved) {
          print('⏭️ [SmartFetcher] ${names[i]} skipped — already resolved');
          return;
        }

        try {
          print('🔄 [SmartFetcher] ${names[i]} fetching...');

          final url = await fetchFn(videoId, song).timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print('⏱️ [SmartFetcher] ${names[i]} timed out');
              return null;
            },
          );

          if (url != null && url.isNotEmpty) {
            if (!_isExoPlayerSafeUrl(url)) {
              print(
                '🚫 [SmartFetcher] ${names[i]} returned unsafe ANDROID URL — rejecting',
              );
            } else if (!completer.isCompleted) {
              resolved = true;
              print(
                '✅ [SmartFetcher] ${names[i]} got URL (length: ${url.length})',
              );
              completer.complete(url);
            } else {
              print(
                '⏭️ [SmartFetcher] ${names[i]} succeeded but winner already set',
              );
            }
          } else {
            print('⚠️ [SmartFetcher] ${names[i]} returned null/empty');
          }
        } catch (e) {
          print('❌ [SmartFetcher] ${names[i]} failed: $e');
        } finally {
          if (++completedCount >= totalAttempts && !completer.isCompleted) {
            print(
              '❌ [SmartFetcher] All $totalAttempts $sourceLabel attempts failed',
            );
            completer.complete(null);
          }
        }
      });
    }

    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        print('❌ [SmartFetcher] $sourceLabel global timeout');
        if (!completer.isCompleted) completer.complete(null);
        return null;
      },
    );
  }

  /// Dispatch to the right backend based on [pref].
  Future<String?> _fetchFromPreference(
    String videoId,
    QuickPick? song,
    AudioSourcePreference pref,
  ) async {
    switch (pref) {
      case AudioSourcePreference.innerTube:
        // VibeFlowCore already uses InnerTube under the hood.
        return _core.getAudioUrl(videoId, song: song);

      case AudioSourcePreference.ytMusicApi:
        try {
          print('🌐 [SmartFetcher] YTMusicAPI fetching $videoId');

          final response = await _ytApi.getAudioUrlFast(videoId: videoId);

          if (response.success &&
              response.data != null &&
              response.data!.isNotEmpty) {
            print('✅ [SmartFetcher] YTMusicAPI resolved $videoId');
            return response.data;
          }

          print('⚠️ [SmartFetcher] YTMusicAPI returned no URL for $videoId');
          return null;
        } catch (e) {
          print('❌ [SmartFetcher] YTMusicAPI failed for $videoId: $e');
          return null;
        }
    }
  }

  /// Returns false for ANDROID client URLs that require a matching UA header.
  bool _isExoPlayerSafeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final client = uri.queryParameters['c'] ?? '';
      final hasRateBypass = uri.queryParameters['ratebypass'] == 'yes';
      if (hasRateBypass && client != 'ANDROID_MUSIC') return false;
      return true;
    } catch (_) {
      return true;
    }
  }
}
