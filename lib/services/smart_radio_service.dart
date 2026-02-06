import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/utils/user_preference_tracker.dart';

/// Enhanced radio service with user preference awareness
class SmartRadioService {
  final RadioService _radioService = RadioService();
  final UserPreferenceTracker _preferences = UserPreferenceTracker();

  /// Get radio queue with user preference filtering
  Future<List<QuickPick>> getSmartRadio({
    required String videoId,
    required String title,
    required String artist,
    int limit = 25,
    bool diversifyArtists = false,
  }) async {
    print('📻 [SmartRadio] Getting radio for: $title by $artist');
    print('   Diversify: $diversifyArtists');

    try {
      // Get base radio
      final baseRadio = await _radioService.getRadioForSong(
        videoId: videoId,
        title: title,
        artist: artist,
        limit: limit * 2, // Get more to filter
      );

      if (baseRadio.isEmpty) {
        print('⚠️ [SmartRadio] Base radio returned empty');
        return [];
      }

      print('✅ [SmartRadio] Got ${baseRadio.length} base songs');

      // Filter out disliked artists
      final filtered = baseRadio.where((song) {
        final shouldAvoid = _preferences.shouldAvoidArtist(song.artists);
        if (shouldAvoid) {
          print(
            '   ⏭️ Filtering out: ${song.title} by ${song.artists} (disliked)',
          );
        }
        return !shouldAvoid;
      }).toList();

      print('✅ [SmartRadio] After filtering: ${filtered.length} songs');

      // If diversifying, ensure variety of artists
      if (diversifyArtists) {
        final diversified = _diversifyArtists(filtered, limit);
        print(
          '✅ [SmartRadio] After diversification: ${diversified.length} songs',
        );
        return diversified;
      }

      // Return up to limit
      return filtered.take(limit).toList();
    } catch (e) {
      print('❌ [SmartRadio] Error: $e');
      return [];
    }
  }

  /// Get radio using preferred artists (for refetch after skips)
  Future<List<QuickPick>> getRadioFromPreferredArtists({
    required String currentVideoId,
    int limit = 25,
  }) async {
    print('🎯 [SmartRadio] Getting radio from preferred artists');

    // Get top preferred artists
    final preferredArtists = _preferences.getSuggestedArtists(limit: 5);

    if (preferredArtists.isEmpty) {
      print('⚠️ [SmartRadio] No preferred artists found, using current song');
      return [];
    }

    print('   Using artists: $preferredArtists');

    // Randomly select one artist to base radio on
    preferredArtists.shuffle();
    final seedArtist = preferredArtists.first;

    print('   🌱 Seed artist: $seedArtist');

    try {
      // Get radio based on preferred artist
      // Note: You'll need to implement a method to search for a song by artist
      // For now, we'll use a placeholder approach
      final radio = await _radioService.getRadioForSong(
        videoId: currentVideoId, // Fallback to current
        title: '',
        artist: seedArtist,
        limit: limit,
      );

      print('✅ [SmartRadio] Got ${radio.length} songs from preferred artist');
      return radio;
    } catch (e) {
      print('❌ [SmartRadio] Error getting preferred artist radio: $e');
      return [];
    }
  }

  /// Diversify artists in radio queue
  List<QuickPick> _diversifyArtists(List<QuickPick> songs, int limit) {
    if (songs.length <= limit) return songs;

    final diversified = <QuickPick>[];
    final artistCounts = <String, int>{};

    // First pass: add songs ensuring no artist dominates
    for (final song in songs) {
      if (diversified.length >= limit) break;

      final artistCount = artistCounts[song.artists] ?? 0;

      // Limit: max 3 songs per artist in diversified queue
      if (artistCount < 3) {
        diversified.add(song);
        artistCounts[song.artists] = artistCount + 1;
      }
    }

    // If we still need more songs, add remaining
    if (diversified.length < limit) {
      final remaining = songs
          .where((song) => !diversified.contains(song))
          .take(limit - diversified.length);
      diversified.addAll(remaining);
    }

    return diversified;
  }

  /// Check if we should refetch radio based on skip analysis
  Future<bool> shouldRefetchRadio() async {
    final analysis = _preferences.analyzeRecentSkips(lookbackCount: 4);

    print('📊 [SmartRadio] Skip analysis:');
    print('   Recent skips: ${analysis.recentSkipCount}');
    print('   Should refetch: ${analysis.shouldRefetchRadio}');

    return analysis.shouldRefetchRadio;
  }

  /// Get skip analysis for UI display
  SkipAnalysis getSkipAnalysis() {
    return _preferences.analyzeRecentSkips(lookbackCount: 5);
  }
}

/*
BEHAVIOR MATRIX:

| Source            | Action                  | Radio Behavior                    |
|-------------------|-------------------------|-----------------------------------|
| Search Song A     | Play Search Song B      | ✅ Reload (different song)        |
| Search Song A     | Play Search Song A      | ❌ Keep (same song)               |
| Quick Pick A      | Play Quick Pick B       | ✅ Reload (different pick)        |
| Quick Pick A      | Play Search Song B      | ✅ Reload (different source)      |
| Saved Songs       | Play from list          | ✅ Playlist mode (no radio yet)   |
| Saved Songs       | Playlist ends           | ✅ Load radio from last song      |
| Playlist Song 3/5 | Skip Next               | ✅ Play Song 4, keep playlist     |
| Playlist Song 5/5 | Skip Next/Song ends     | ✅ End playlist, load radio       |
| Radio Song 5/25   | Skip Next               | ✅ Play Song 6, keep radio        |
| Radio Song 5/25   | Select Song 10          | ❌ Keep radio, jump to Song 10    |
| Any Source        | Start new playlist      | ✅ Clear radio, enter playlist    |

KEY POINTS:

1. Always specify sourceType when calling playSong()
2. Use playPlaylistQueue() for playlists and saved songs
3. Playlist mode prevents radio loading until playlist ends
4. Radio only reloads when source or song changes
5. Selecting from radio queue doesn't reload radio
*/
