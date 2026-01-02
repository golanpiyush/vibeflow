// lib/services/radio_service.dart
import 'package:vibeflow/api_base/ytmusic_search_helper.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

/// Radio Service for fetching related songs using YouTube Music
class RadioService {
  final YTMusicSearchHelper _searchHelper;

  // Cache to prevent duplicate radio loads
  final Map<String, List<QuickPick>> _radioCache = {};
  final int _maxCacheSize = 10;

  RadioService({YTMusicSearchHelper? searchHelper})
    : _searchHelper = searchHelper ?? YTMusicSearchHelper();

  /// Get radio/related songs for a specific song
  Future<List<QuickPick>> getRadioForSong({
    required String videoId,
    required String title,
    required String artist,
    int limit = 25,
    bool forceRefresh = false,
  }) async {
    try {
      // Check cache first
      if (!forceRefresh && _radioCache.containsKey(videoId)) {
        print('⚡ [RadioService] Using cached radio for $videoId');
        return _radioCache[videoId]!;
      }

      print('🔍 [RadioService] Fetching radio for: $title by $artist');

      // Search for similar songs by artist
      final searchResults = await _searchHelper.searchSongs(
        artist,
        limit: limit + 5, // Get extra to filter current song
      );

      // Convert to QuickPick and filter out current song
      final radioSongs = searchResults
          .where((song) => song.videoId != videoId) // Exclude current song
          .take(limit)
          .map(
            (song) => QuickPick(
              videoId: song.videoId,
              title: song.title,
              artists: song.artists.join(', '),
              thumbnail: song.thumbnail,
              duration: song.duration,
            ),
          )
          .toList();

      // Cache the results
      _cacheRadio(videoId, radioSongs);

      print('✅ [RadioService] Found ${radioSongs.length} radio songs');
      return radioSongs;
    } catch (e, stack) {
      print('❌ [RadioService] Error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      return [];
    }
  }

  /// Cache radio results
  void _cacheRadio(String videoId, List<QuickPick> songs) {
    // Limit cache size
    if (_radioCache.length >= _maxCacheSize) {
      _radioCache.remove(_radioCache.keys.first);
    }
    _radioCache[videoId] = songs;
  }

  /// Clear cache for a specific song
  void clearCacheFor(String videoId) {
    _radioCache.remove(videoId);
  }

  /// Clear all cache
  void clearAllCache() {
    _radioCache.clear();
  }

  /// Dispose resources
  void dispose() {
    _searchHelper.dispose();
    _radioCache.clear();
  }

  String? formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;

    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
