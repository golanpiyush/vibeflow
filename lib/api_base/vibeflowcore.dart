import 'package:flutter/material.dart';
import 'package:vibeflow/api_base/innertubeaudio.dart';
import 'package:vibeflow/main.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/managers/vibeflow_engine_logger.dart';
import 'package:vibeflow/services/cacheManager.dart';
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';
import 'package:vibeflow/models/song_model.dart';

/// Core service for VibeFlow.
/// Audio resolution order:
///   1. Cache
///   2. Preferred source (InnerTube OR YtFlutterMusicapi, per [preference])
///   3. Alternate source (auto-override if preferred fails)
class VibeFlowCore {
  static final VibeFlowCore _instance = VibeFlowCore._internal();
  factory VibeFlowCore() => _instance;
  VibeFlowCore._internal();

  YtFlutterMusicapi _ytApi = YtFlutterMusicapi();
  final InnerTubeAudio _innerTube = InnerTubeAudio();
  bool _isInitialized = false;
  final _logger = VibeFlowEngineLogger();

  /// The user's preferred audio source backend.
  /// VibeFlow will always try this first, then auto-override if it fails.
  AudioSourcePreference preference = AudioSourcePreference.innerTube;

  // YouTube URLs typically last 6 hours; we refresh at 5 to be safe.
  static const Duration _cacheExpiryDuration = Duration(hours: 5);

  /// Update the preferred backend. Called by BackgroundAudioHandler when
  /// the user changes the setting in PlayerSettingsPage.
  void setPreference(AudioSourcePreference pref) {
    preference = pref;
    _innerTube.preference = pref;
    print('⚙️ [VibeFlowCore] Audio source preference → ${pref.name}');
  }

  /// Initialize the API (must be called before using any methods).
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      print('🎵 [VibeFlowCore] Initializing...');
      await _ytApi.initialize();
      _isInitialized = true;
      _logger.logInitialization(success: true);
      print('✅ [VibeFlowCore] Initialization complete');
    } catch (e) {
      print('❌ [VibeFlowCore] Initialization failed: $e');
      _logger.logInitialization(success: false);
      rethrow;
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'VibeFlowCore not initialized. Call initialize() first.',
      );
    }
  }

  // ── Real backend dispatch ──────────────────────────────────────────────────

  /// Fetch from a specific source without cache or fallback.
  /// Returns null if that source fails — caller decides what to do next.
  Future<String?> _fetchFromSource(
    String videoId, {
    QuickPick? song,
    required AudioSourcePreference source,
  }) async {
    switch (source) {
      case AudioSourcePreference.innerTube:
        try {
          print('📱 [VibeFlowCore] InnerTube fetching $videoId...');
          final result = await _innerTube.fetchSingle(videoId);
          if (result != null && result.url.isNotEmpty) {
            print(
              '✅ [VibeFlowCore] InnerTube resolved $videoId '
              '(${result.codec} ${result.bitrate ~/ 1000}kbps, '
              'client: ${result.clientUsed})',
            );
            return result.url;
          }
          print('⚠️ [VibeFlowCore] InnerTube returned no URL for $videoId');
          return null;
        } catch (e) {
          print('⚠️ [VibeFlowCore] InnerTube failed for $videoId: $e');
          return null;
        }

      case AudioSourcePreference.ytMusicApi:
        try {
          print('🌐 [VibeFlowCore] YTMusicAPI fetching $videoId...');
          return await _fetchWithAutoReinit(videoId, song: song);
        } catch (e) {
          print('⚠️ [VibeFlowCore] YTMusicAPI failed for $videoId: $e');
          return null;
        }
    }
  }

  // ── Public audio URL API ───────────────────────────────────────────────────

  /// Get audio URL for a video ID.
  /// Resolution order: cache → preferred source → alternate source (override)
  Future<String?> getAudioUrl(String videoId, {QuickPick? song}) async {
    _ensureInitialized();

    final songTitle = song?.title;
    _logger.logFetchStart(videoId, songTitle: songTitle);

    try {
      print('🎵 [VibeFlowCore] Fetching audio URL for: $videoId');
      final audioCache = AudioUrlCache();

      // ── 1. Cache ──────────────────────────────────────────────────────────
      final cachedUrl = await audioCache.getCachedUrl(videoId);
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        final cacheTime = await audioCache.getCacheTime(videoId);
        if (cacheTime != null) {
          final age = DateTime.now().difference(cacheTime);
          if (age < _cacheExpiryDuration) {
            print(
              '⚡ [Cache] Using cached URL for $videoId (age: ${age.inMinutes}m)',
            );
            _logger.logCacheHit(videoId, songTitle: songTitle, age: age);
            _logger.logFetchSuccess(
              videoId,
              songTitle: songTitle,
              source: 'cache',
            );
            return cachedUrl;
          } else {
            print('⏰ [Cache] URL expired for $videoId, fetching fresh...');
            _logger.logCacheExpiry(videoId, songTitle: songTitle, age: age);
            await audioCache.remove(videoId);
          }
        } else {
          print('⚡ [Cache] Using cached URL for $videoId');
          _logger.logCacheHit(videoId, songTitle: songTitle);
          _logger.logFetchSuccess(
            videoId,
            songTitle: songTitle,
            source: 'cache',
          );
          return cachedUrl;
        }
      }

      print('🔄 [VibeFlowCore] Cache miss, fetching fresh URL...');
      _logger.logCacheMiss(videoId, songTitle: songTitle);

      // ── 2. Preferred source ───────────────────────────────────────────────
      final preferredUrl = await _fetchFromSource(
        videoId,
        song: song,
        source: preference,
      );

      if (preferredUrl != null) {
        await _cacheUrl(audioCache, videoId, preferredUrl, song: song);
        _logger.logFetchSuccess(
          videoId,
          songTitle: songTitle,
          source: preference.name,
        );
        return preferredUrl;
      }

      // ── 3. Auto-override to alternate source ──────────────────────────────
      final alternate = preference == AudioSourcePreference.innerTube
          ? AudioSourcePreference.ytMusicApi
          : AudioSourcePreference.innerTube;

      print(
        '⚡ [VibeFlowCore] Preferred (${preference.name}) failed — '
        'auto-overriding to ${alternate.name}',
      );

      final alternateUrl = await _fetchFromSource(
        videoId,
        song: song,
        source: alternate,
      );

      if (alternateUrl != null) {
        await _cacheUrl(audioCache, videoId, alternateUrl, song: song);
        _logger.logFetchSuccess(
          videoId,
          songTitle: songTitle,
          source: '${alternate.name}[override]',
        );
        return alternateUrl;
      }

      print('❌ [VibeFlowCore] All sources exhausted for $videoId');
      _logger.logFetchFailure(
        videoId,
        songTitle: songTitle,
        error: 'all_sources_failed',
      );
      return null;
    } catch (e, stack) {
      print('❌ [VibeFlowCore] Error getting audio URL: $e');
      print('Stack trace: ${stack.toString().split('\n').take(3).join('\n')}');
      _logger.logFetchFailure(
        videoId,
        songTitle: songTitle,
        error: e.toString(),
      );
      await AudioUrlCache().remove(videoId);
      return null;
    }
  }

  /// Force refresh audio URL (bypass cache).
  /// Useful when you get a 403 from an expired URL.
  Future<String?> forceRefreshAudioUrl(
    String videoId, {
    QuickPick? song,
  }) async {
    _ensureInitialized();
    _logger.logForceRefresh(videoId, songTitle: song?.title);

    print('🔄 [VibeFlowCore] Force refreshing audio URL for: $videoId');
    final audioCache = AudioUrlCache();
    await audioCache.remove(videoId);

    // Force-refresh preferred source first
    String? url;

    if (preference == AudioSourcePreference.innerTube) {
      try {
        final result = await _innerTube.fetchSingle(
          videoId,
          forceRefresh: true,
        );
        if (result != null && result.url.isNotEmpty) {
          print(
            '✅ [VibeFlowCore] InnerTube force-refresh succeeded for $videoId',
          );
          url = result.url;
        }
      } catch (e) {
        print('⚠️ [VibeFlowCore] InnerTube force-refresh failed: $e');
      }

      // Override to YTMusicAPI if InnerTube failed
      if (url == null) {
        print('⚡ [VibeFlowCore] Force-refresh override → YTMusicAPI');
        try {
          final response = await _ytApi.getAudioUrlFast(videoId: videoId);
          if (response.success &&
              response.data != null &&
              response.data!.isNotEmpty) {
            url = response.data;
          }
        } catch (e) {
          print('❌ [VibeFlowCore] YTMusicAPI force-refresh failed: $e');
        }
      }
    } else {
      // User prefers YTMusicAPI
      try {
        final response = await _ytApi.getAudioUrlFast(videoId: videoId);
        if (response.success &&
            response.data != null &&
            response.data!.isNotEmpty) {
          print('✅ [VibeFlowCore] YTMusicAPI force-refresh succeeded');
          url = response.data;
        }
      } catch (e) {
        print('⚠️ [VibeFlowCore] YTMusicAPI force-refresh failed: $e');
      }

      // Override to InnerTube if YTMusicAPI failed
      if (url == null) {
        print('⚡ [VibeFlowCore] Force-refresh override → InnerTube');
        try {
          final result = await _innerTube.fetchSingle(
            videoId,
            forceRefresh: true,
          );
          if (result != null && result.url.isNotEmpty) {
            url = result.url;
          }
        } catch (e) {
          print('❌ [VibeFlowCore] InnerTube force-refresh override failed: $e');
        }
      }
    }

    if (url != null) {
      await _cacheUrl(audioCache, videoId, url, song: song);
      _logger.logFetchSuccess(
        videoId,
        songTitle: song?.title,
        source: 'force_refresh',
      );
      return url;
    }

    print('⚠️ [VibeFlowCore] Failed to get fresh URL for $videoId');
    _logger.logFetchFailure(videoId, songTitle: song?.title);
    return null;
  }

  /// Get audio URL with retry logic.
  Future<String?> getAudioUrlWithRetry(
    String videoId, {
    QuickPick? song,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 [VibeFlowCore] Attempt $attempt/$maxRetries for $videoId');
        if (attempt > 1) {
          _logger.logRetry(
            videoId,
            attempt,
            maxRetries,
            songTitle: song?.title,
          );
        }
        final url = await getAudioUrl(videoId, song: song);
        if (url != null && url.isNotEmpty) return url;
        if (attempt < maxRetries) {
          print('⏳ [VibeFlowCore] Retrying in ${retryDelay.inSeconds}s...');
          await Future.delayed(retryDelay);
        }
      } catch (e) {
        print('⚠️ [VibeFlowCore] Attempt $attempt failed: $e');
        if (attempt < maxRetries) await Future.delayed(retryDelay);
      }
    }
    print('❌ [VibeFlowCore] All retry attempts failed for $videoId');
    return null;
  }

  /// Preload audio URLs for a queue using InnerTube's batch resolver.
  Future<void> preloadAudioQueue(List<String> videoIds) async {
    if (videoIds.isEmpty) return;
    print('📦 [VibeFlowCore] Preloading ${videoIds.length} audio URLs...');
    try {
      final results = await _innerTube.fetchBatch(
        videoIds.take(30).toList(),
        concurrency: 5,
      );
      print(
        '✅ [VibeFlowCore] Preloaded ${results.length}/${videoIds.length} URLs',
      );
    } catch (e) {
      print('⚠️ [VibeFlowCore] Preload failed: $e');
    }
  }

  // ── Song enrichment ────────────────────────────────────────────────────────

  Future<Map<String, String>> getAudioUrlsForSongs(List<Song> songs) async {
    final Map<String, String> audioUrls = {};
    print('🎵 [VibeFlowCore] Batch fetching ${songs.length} audio URLs...');
    _logger.logBatchStart(songs.length, 'audio_url_fetch');

    int successCount = 0;
    for (final song in songs) {
      try {
        final url = await getAudioUrl(song.videoId);
        if (url != null) {
          audioUrls[song.videoId] = url;
          successCount++;
        }
      } catch (e) {
        print('⚠️ [VibeFlowCore] Failed to get URL for ${song.videoId}: $e');
      }
    }

    print('✅ [VibeFlowCore] Fetched ${audioUrls.length}/${songs.length} URLs');
    _logger.logBatchComplete(successCount, songs.length, 'audio_url_fetch');
    return audioUrls;
  }

  Future<Song> enrichSongWithAudioUrl(Song song) async {
    _logger.logEnrichmentStart(song.videoId, songTitle: song.title);

    if (song.audioUrl != null && song.audioUrl!.isNotEmpty) {
      _logger.logEnrichmentSuccess(song.videoId, songTitle: song.title);
      return song;
    }

    final audioUrl = await getAudioUrl(song.videoId);
    final enrichedSong = Song(
      videoId: song.videoId,
      title: song.title,
      artists: song.artists,
      thumbnail: song.thumbnail,
      duration: song.duration,
      audioUrl: audioUrl,
    );

    _logger.logEnrichmentSuccess(song.videoId, songTitle: song.title);
    return enrichedSong;
  }

  Future<List<Song>> enrichSongsWithAudioUrls(List<Song> songs) async {
    _logger.logBatchStart(songs.length, 'song_enrichment');
    final enrichedSongs = <Song>[];
    int successCount = 0;

    for (final song in songs) {
      try {
        enrichedSongs.add(await enrichSongWithAudioUrl(song));
        successCount++;
      } catch (e) {
        print('⚠️ [VibeFlowCore] Failed to enrich ${song.title}: $e');
        enrichedSongs.add(song);
      }
    }

    _logger.logBatchComplete(successCount, songs.length, 'song_enrichment');
    return enrichedSongs;
  }

  bool isUrlExpired(Song song) =>
      song.audioUrl == null || song.audioUrl!.isEmpty;

  Future<Song> refreshAudioUrlIfNeeded(Song song) async {
    if (!isUrlExpired(song)) return song;
    print('🔄 [VibeFlowCore] Refreshing audio URL for: ${song.title}');
    return enrichSongWithAudioUrl(song);
  }

  void dispose() {
    _innerTube.dispose();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// YtFlutterMusicapi fetch with auto-reinit on native state loss.
  Future<String?> _fetchWithAutoReinit(
    String videoId, {
    QuickPick? song,
    int attempt = 1,
  }) async {
    try {
      final response = await _ytApi.getAudioUrlFast(videoId: videoId);

      if (response.success &&
          response.data != null &&
          response.data!.isNotEmpty) {
        print('✅ [VibeFlowCore] YtFlutterMusicapi resolved $videoId');
        _logger.logFetchSuccess(
          videoId,
          songTitle: song?.title,
          source: 'YTMusicAPI',
        );
        return response.data;
      }

      print('⚠️ [VibeFlowCore] YtFlutterMusicapi returned no URL for $videoId');
      if (response.error != null) {
        print('⚠️ [VibeFlowCore] Error: ${response.error}');
        _logger.logFetchFailure(
          videoId,
          songTitle: song?.title,
          error: response.error,
        );
      }
      await AudioUrlCache().remove(videoId);
      return null;
    } catch (e) {
      final errStr = e.toString();

      // Native plugin lost its initialized state — reinit and retry once.
      if (attempt == 1 && _isNativeNotInitializedError(errStr)) {
        print(
          '⚠️ [VibeFlowCore] Native API lost state, reinitializing... (attempt $attempt)',
        );
        _isInitialized = false;
        try {
          await initialize();
          print('✅ [VibeFlowCore] Reinitialized, retrying fetch...');
          return await _fetchWithAutoReinit(videoId, song: song, attempt: 2);
        } catch (reinitError) {
          print('❌ [VibeFlowCore] Reinitialization failed: $reinitError');
          return null;
        }
      }

      print('❌ [VibeFlowCore] YtFlutterMusicapi failed (attempt $attempt): $e');
      _logger.logFetchFailure(videoId, songTitle: song?.title, error: errStr);
      await AudioUrlCache().remove(videoId);
      return null;
    }
  }

  Future<void> _cacheUrl(
    AudioUrlCache audioCache,
    String videoId,
    String url, {
    QuickPick? song,
  }) async {
    if (song != null) {
      await audioCache.cache(song, url);
      print('💾 [Cache] Cached URL for: ${song.title}');
    } else {
      await audioCache.cacheByVideoId(videoId, url);
      print('💾 [Cache] Cached URL for videoId: $videoId');
    }
  }

  bool _isNativeNotInitializedError(String error) {
    return error.contains('YTMusic API not initialized') ||
        error.contains('not initialized') ||
        error.contains('IllegalStateException');
  }
}

// ── Error handling extension ───────────────────────────────────────────────

extension VibeFlowCoreErrorHandling on VibeFlowCore {
  Future<String?> getAudioUrlWithErrorHandling(
    String videoId,
    String songTitle,
    BuildContext? context,
  ) async {
    try {
      final url = await getAudioUrlWithRetry(videoId);
      if (url == null || url.isEmpty) {
        AudioErrorHandler.showAudioUrlError(context, songTitle);
        return null;
      }
      return url;
    } catch (e) {
      print('❌ [VibeFlowCore] Critical error: $e');
      AudioErrorHandler.showNetworkError(context);
      return null;
    }
  }

  Future<Song?> enrichSongWithErrorHandling(
    Song song,
    BuildContext? context,
  ) async {
    try {
      final enrichedSong = await enrichSongWithAudioUrl(song);
      if (enrichedSong.audioUrl == null || enrichedSong.audioUrl!.isEmpty) {
        AudioErrorHandler.showAudioUrlError(context, song.title);
        return null;
      }
      return enrichedSong;
    } catch (e) {
      print('❌ [VibeFlowCore] Enrichment failed: $e');
      AudioErrorHandler.showNetworkError(context);
      return null;
    }
  }

  Future<String?> getAudioUrlWithUserFeedback(
    String videoId,
    String songTitle,
    BuildContext? context, {
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final url = await getAudioUrl(videoId);
        if (url != null && url.isNotEmpty) {
          if (attempt > 1 && context != null) {
            AudioErrorHandler.showSuccess(
              context,
              'Successfully loaded "$songTitle"',
            );
          }
          return url;
        }
        if (attempt == maxRetries) {
          AudioErrorHandler.showAudioUrlError(context, songTitle);
          return null;
        }
        await Future.delayed(Duration(seconds: attempt));
      } catch (e) {
        if (attempt == maxRetries) {
          AudioErrorHandler.showNetworkError(context);
          return null;
        }
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    return null;
  }
}
