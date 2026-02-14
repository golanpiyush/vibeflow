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

      // ✅ FIX: Clean the artist name (remove metadata like "• 2.2B plays")
      final cleanArtist = _cleanArtistName(artist);

      print('🔍 [RadioService] Fetching radio for: $title by $cleanArtist');
      print('   Original artist: $artist');
      print('   Cleaned artist: $cleanArtist');

      // Search for similar songs by artist
      final searchResults = await _searchHelper.searchSongs(
        cleanArtist, // ✅ Use cleaned artist name
        limit: limit + 5, // Get extra to filter current song
      );

      // Convert to QuickPick and filter out current song
      final radioSongs = searchResults
          .where((song) => song.videoId != videoId)
          .take(limit)
          .map((song) {
            print('🎵 [RadioService] Converting: ${song.title}');
            print('   Duration: ${song.duration}'); // ✅ ADD THIS

            return QuickPick(
              videoId: song.videoId,
              title: song.title,
              artists: song.artists.join(', '),
              thumbnail: song.thumbnail,
              duration: song.duration,
            );
          })
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

  // ✅ ADD: Helper method to clean artist name
  String _cleanArtistName(String artist) {
    // Remove everything after bullet point (•)
    if (artist.contains('•')) {
      artist = artist.split('•').first.trim();
    }

    // Remove everything after dash followed by number (like "- 2.2B")
    if (artist.contains(RegExp(r'\s+-\s+[\d.]+[KMB]'))) {
      artist = artist.replaceAll(RegExp(r'\s+-\s+[\d.]+[KMB].*'), '').trim();
    }

    // Remove common metadata patterns
    artist = artist.replaceAll(RegExp(r'\s+plays?$', caseSensitive: false), '');
    artist = artist.replaceAll(RegExp(r'\s+views?$', caseSensitive: false), '');
    artist = artist.replaceAll(
      RegExp(r'\d+[KMB]?\s*(plays?|views?)$', caseSensitive: false),
      '',
    );

    return artist.trim();
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
