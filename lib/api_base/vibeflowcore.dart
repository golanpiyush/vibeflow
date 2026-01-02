import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';
import 'package:vibeflow/models/song_model.dart';

/// Core service for VibeFlow using yt_flutter_musicapi
class VibeFlowCore {
  static final VibeFlowCore _instance = VibeFlowCore._internal();
  factory VibeFlowCore() => _instance;
  VibeFlowCore._internal();

  YtFlutterMusicapi _ytApi = YtFlutterMusicapi();
  bool _isInitialized = false;

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

  /// Get audio URL for a video ID using fast method
  /// Returns the direct streaming URL or null if unavailable
  Future<String?> getAudioUrl(String videoId) async {
    _ensureInitialized();

    try {
      print('🎵 [VibeFlowCore] Fetching audio URL for: $videoId');

      // Use the fast method from yt_flutter_musicapi
      final response = await _ytApi.getAudioUrlFast(videoId: videoId);

      if (response.success &&
          response.data != null &&
          response.data!.isNotEmpty) {
        print('✅ [VibeFlowCore] Got audio URL successfully');
        return response.data;
      } else {
        print('⚠️ [VibeFlowCore] No URL returned for $videoId');
        if (response.error != null) {
          print('⚠️ [VibeFlowCore] Error: ${response.error}');
        }
        return null;
      }
    } catch (e, stack) {
      print('❌ [VibeFlowCore] Error getting audio URL: $e');
      print('Stack trace: ${stack.toString().split('\n').take(3).join('\n')}');
      return null;
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

  /// Get audio URL with retry logic
  /// Useful for handling temporary network issues
  Future<String?> getAudioUrlWithRetry(
    String videoId, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 [VibeFlowCore] Attempt $attempt/$maxRetries for $videoId');

        final url = await getAudioUrl(videoId);
        if (url != null) {
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
