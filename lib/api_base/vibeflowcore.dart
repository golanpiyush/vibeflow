import 'package:flutter/material.dart';
import 'package:vibeflow/main.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/services/cacheManager.dart';
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';
import 'package:vibeflow/models/song_model.dart';

/// Core service for VibeFlow using yt_flutter_musicapi
class VibeFlowCore {
  static final VibeFlowCore _instance = VibeFlowCore._internal();
  factory VibeFlowCore() => _instance;
  VibeFlowCore._internal();

  YtFlutterMusicapi _ytApi = YtFlutterMusicapi();
  bool _isInitialized = false;

  // Cache expiry duration (YouTube URLs typically last 6 hours)
  static const Duration _cacheExpiryDuration = Duration(hours: 5);

  /// Initialize the API (must be called before using any methods)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🎵 [VibeFlowCore] Initializing YtFlutterMusicapi...');
      await _ytApi.initialize();
      _isInitialized = true;
      print('✅ [VibeFlowCore] Initialization complete');
    } catch (e) {
      print('❌ [VibeFlowCore] Initialization failed: $e');
      rethrow;
    }
  }

  /// Ensure API is initialized before use
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'VibeFlowCore not initialized. Call initialize() first.',
      );
    }
  }

  /// Get audio URLs for multiple songs (batch processing)
  /// Returns a map of videoId -> audioUrl
  Future<Map<String, String>> getAudioUrlsForSongs(List<Song> songs) async {
    final Map<String, String> audioUrls = {};

    print('🎵 [VibeFlowCore] Batch fetching ${songs.length} audio URLs...');

    for (final song in songs) {
      try {
        final url = await getAudioUrl(song.videoId);
        if (url != null) {
          audioUrls[song.videoId] = url;
        }
      } catch (e) {
        print('⚠️ [VibeFlowCore] Failed to get URL for ${song.videoId}: $e');
        continue;
      }
    }

    print(
      '✅ [VibeFlowCore] Successfully fetched ${audioUrls.length}/${songs.length} URLs',
    );
    return audioUrls;
  }

  /// Enrich a Song object with its audio URL
  /// Returns a new Song object with audioUrl populated
  Future<Song> enrichSongWithAudioUrl(Song song) async {
    if (song.audioUrl != null && song.audioUrl!.isNotEmpty) {
      // Already has audio URL
      return song;
    }

    final audioUrl = await getAudioUrl(song.videoId);

    return Song(
      videoId: song.videoId,
      title: song.title,
      artists: song.artists,
      thumbnail: song.thumbnail,
      duration: song.duration,
      audioUrl: audioUrl,
    );
  }

  /// Enrich multiple songs with audio URLs
  /// Returns list of songs with audioUrl populated
  Future<List<Song>> enrichSongsWithAudioUrls(List<Song> songs) async {
    final enrichedSongs = <Song>[];

    for (final song in songs) {
      try {
        final enrichedSong = await enrichSongWithAudioUrl(song);
        enrichedSongs.add(enrichedSong);
      } catch (e) {
        print('⚠️ [VibeFlowCore] Failed to enrich ${song.title}: $e');
        // Add original song even if enrichment fails
        enrichedSongs.add(song);
      }
    }

    return enrichedSongs;
  }

  /// Get audio URL for a video ID using fast method
  /// Returns the direct streaming URL or null if unavailable
  /// Automatically handles cache expiry and refreshes URLs
  Future<String?> getAudioUrl(String videoId, {QuickPick? song}) async {
    _ensureInitialized();

    try {
      print('🎵 [VibeFlowCore] Fetching audio URL for: $videoId');
      final audioCache = AudioUrlCache();

      // Check cache first
      final cachedUrl = await audioCache.getCachedUrl(videoId);
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        // Check if cache is still valid (not expired)
        final cacheTime = await audioCache.getCacheTime(videoId);
        if (cacheTime != null) {
          final age = DateTime.now().difference(cacheTime);
          if (age < _cacheExpiryDuration) {
            print(
              '⚡ [Cache] Using cached URL for $videoId (age: ${age.inMinutes}m)',
            );
            return cachedUrl;
          } else {
            print(
              '⏰ [Cache] URL expired for $videoId (age: ${age.inHours}h), fetching fresh...',
            );
            await audioCache.remove(videoId);
          }
        } else {
          print('⚡ [Cache] Using cached URL for $videoId');
          return cachedUrl;
        }
      }

      print('🔄 [VibeFlowCore] Cache miss, fetching fresh URL...');

      // Use the fast method from yt_flutter_musicapi
      final response = await _ytApi.getAudioUrlFast(videoId: videoId);

      if (response.success &&
          response.data != null &&
          response.data!.isNotEmpty) {
        print('✅ [VibeFlowCore] Got audio URL successfully');

        // Cache the URL if song info is provided
        if (song != null) {
          await audioCache.cache(song, response.data!);
          print('💾 [Cache] Cached URL for: ${song.title}');
        } else {
          // Cache even without song info using videoId
          await audioCache.cacheByVideoId(videoId, response.data!);
          print('💾 [Cache] Cached URL for videoId: $videoId');
        }

        return response.data;
      } else {
        print('⚠️ [VibeFlowCore] No URL returned for $videoId');
        if (response.error != null) {
          print('⚠️ [VibeFlowCore] Error: ${response.error}');
        }

        // Clear bad cache entry
        await audioCache.remove(videoId);
        return null;
      }
    } catch (e, stack) {
      print('❌ [VibeFlowCore] Error getting audio URL: $e');
      print('Stack trace: ${stack.toString().split('\n').take(3).join('\n')}');

      // Clear cache on error
      final audioCache = AudioUrlCache();
      await audioCache.remove(videoId);
      return null;
    }
  }

  /// Get audio URL with retry logic and caching
  /// Useful for handling temporary network issues
  Future<String?> getAudioUrlWithRetry(
    String videoId, {
    QuickPick? song,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 [VibeFlowCore] Attempt $attempt/$maxRetries for $videoId');

        final url = await getAudioUrl(videoId, song: song);
        if (url != null && url.isNotEmpty) {
          return url;
        }

        if (attempt < maxRetries) {
          print('⏳ [VibeFlowCore] Retrying in ${retryDelay.inSeconds}s...');
          await Future.delayed(retryDelay);
        }
      } catch (e) {
        print('⚠️ [VibeFlowCore] Attempt $attempt failed: $e');
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }

    print('❌ [VibeFlowCore] All retry attempts failed for $videoId');
    return null;
  }

  /// Force refresh audio URL (bypass cache)
  /// Useful when you get a 403 error from an expired URL
  Future<String?> forceRefreshAudioUrl(
    String videoId, {
    QuickPick? song,
  }) async {
    _ensureInitialized();

    try {
      print('🔄 [VibeFlowCore] Force refreshing audio URL for: $videoId');

      // Clear old cache
      final audioCache = AudioUrlCache();
      await audioCache.remove(videoId);

      // Fetch fresh URL
      final response = await _ytApi.getAudioUrlFast(videoId: videoId);

      if (response.success &&
          response.data != null &&
          response.data!.isNotEmpty) {
        print('✅ [VibeFlowCore] Got fresh audio URL');

        // Cache the new URL
        if (song != null) {
          await audioCache.cache(song, response.data!);
        } else {
          await audioCache.cacheByVideoId(videoId, response.data!);
        }

        return response.data;
      }

      print('⚠️ [VibeFlowCore] Failed to get fresh URL');
      return null;
    } catch (e) {
      print('❌ [VibeFlowCore] Error force refreshing: $e');
      return null;
    }
  }

  /// Check if audio URL is still valid
  /// Note: URLs from YouTube typically expire after a few hours
  bool isUrlExpired(Song song) {
    // This is a simple check - you might want to add timestamp tracking
    return song.audioUrl == null || song.audioUrl!.isEmpty;
  }

  /// Refresh audio URL for a song if it's expired or missing
  Future<Song> refreshAudioUrlIfNeeded(Song song) async {
    if (!isUrlExpired(song)) {
      return song;
    }

    print('🔄 [VibeFlowCore] Refreshing audio URL for: ${song.title}');
    return await enrichSongWithAudioUrl(song);
  }
}

/// Enhanced VibeFlowCore with error handling and snackbar integration
extension VibeFlowCoreErrorHandling on VibeFlowCore {
  /// Get audio URL with user-friendly error handling
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

  /// Enrich song with error handling
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

  /// Get audio URL with retry and user feedback
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
          // Success on retry
          if (attempt > 1 && context != null) {
            AudioErrorHandler.showSuccess(
              context,
              'Successfully loaded "$songTitle"',
            );
          }
          return url;
        }

        // Last attempt failed
        if (attempt == maxRetries) {
          AudioErrorHandler.showAudioUrlError(context, songTitle);
          return null;
        }

        // Retry delay
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
