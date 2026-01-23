import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/album_model.dart';

class AlbumArtistQPCache {
  static const String _quickPicksKey = 'cached_quick_picks';
  static const String _quickPicksTimestampKey = 'cached_quick_picks_timestamp';

  static const String _artistsKey = 'cached_artists';
  static const String _artistsTimestampKey = 'cached_artists_timestamp';

  static const String _albumsKey = 'cached_albums';
  static const String _albumsTimestampKey = 'cached_albums_timestamp';

  static const Duration _cacheDuration = Duration(hours: 24);

  // ==================== QUICK PICKS ====================

  /// Save Quick Picks to cache
  static Future<void> saveQuickPicks(List<QuickPick> quickPicks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = quickPicks.map((qp) => qp.toJson()).toList();
      await prefs.setString(_quickPicksKey, jsonEncode(jsonList));
      await prefs.setInt(
        _quickPicksTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      print('💾 [Cache] Saved ${quickPicks.length} Quick Picks');
    } catch (e) {
      print('❌ [Cache] Error saving Quick Picks: $e');
    }
  }

  /// Load Quick Picks from cache if valid (< 24 hours old)
  static Future<List<QuickPick>?> loadQuickPicks() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if cache exists
      if (!prefs.containsKey(_quickPicksKey) ||
          !prefs.containsKey(_quickPicksTimestampKey)) {
        print('📦 [Cache] No Quick Picks cache found');
        return null;
      }

      // Check if cache is still valid
      final timestamp = prefs.getInt(_quickPicksTimestampKey);
      if (timestamp == null) return null;

      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (cacheAge > _cacheDuration.inMilliseconds) {
        print(
          '⏰ [Cache] Quick Picks cache expired (${Duration(milliseconds: cacheAge).inHours}h old)',
        );
        await clearQuickPicks();
        return null;
      }

      // Load from cache
      final jsonString = prefs.getString(_quickPicksKey);
      if (jsonString == null) return null;

      final jsonList = jsonDecode(jsonString) as List;
      final quickPicks = jsonList
          .map((json) => QuickPick.fromJson(json))
          .toList();

      print(
        '✅ [Cache] Loaded ${quickPicks.length} Quick Picks (${Duration(milliseconds: cacheAge).inHours}h old)',
      );
      return quickPicks;
    } catch (e) {
      print('❌ [Cache] Error loading Quick Picks: $e');
      return null;
    }
  }

  /// Clear Quick Picks cache
  static Future<void> clearQuickPicks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_quickPicksKey);
    await prefs.remove(_quickPicksTimestampKey);
    print('🧹 [Cache] Cleared Quick Picks cache');
  }

  // ==================== ARTISTS ====================

  /// Save Artists to cache
  static Future<void> saveArtists(List<Artist> artists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = artists.map((artist) => artist.toJson()).toList();
      await prefs.setString(_artistsKey, jsonEncode(jsonList));
      await prefs.setInt(
        _artistsTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      print('💾 [Cache] Saved ${artists.length} Artists');
    } catch (e) {
      print('❌ [Cache] Error saving Artists: $e');
    }
  }

  /// Load Artists from cache if valid (< 24 hours old)
  static Future<List<Artist>?> loadArtists() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if cache exists
      if (!prefs.containsKey(_artistsKey) ||
          !prefs.containsKey(_artistsTimestampKey)) {
        print('📦 [Cache] No Artists cache found');
        return null;
      }

      // Check if cache is still valid
      final timestamp = prefs.getInt(_artistsTimestampKey);
      if (timestamp == null) return null;

      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (cacheAge > _cacheDuration.inMilliseconds) {
        print(
          '⏰ [Cache] Artists cache expired (${Duration(milliseconds: cacheAge).inHours}h old)',
        );
        await clearArtists();
        return null;
      }

      // Load from cache
      final jsonString = prefs.getString(_artistsKey);
      if (jsonString == null) return null;

      final jsonList = jsonDecode(jsonString) as List;
      final artists = jsonList.map((json) => Artist.fromJson(json)).toList();

      print(
        '✅ [Cache] Loaded ${artists.length} Artists (${Duration(milliseconds: cacheAge).inHours}h old)',
      );
      return artists;
    } catch (e) {
      print('❌ [Cache] Error loading Artists: $e');
      return null;
    }
  }

  /// Clear Artists cache
  static Future<void> clearArtists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_artistsKey);
    await prefs.remove(_artistsTimestampKey);
    print('🧹 [Cache] Cleared Artists cache');
  }

  // ==================== ALBUMS ====================

  /// Save Albums to cache
  static Future<void> saveAlbums(List<Album> albums) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = albums.map((album) => album.toJson()).toList();
      await prefs.setString(_albumsKey, jsonEncode(jsonList));
      await prefs.setInt(
        _albumsTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      print('💾 [Cache] Saved ${albums.length} Albums');
    } catch (e) {
      print('❌ [Cache] Error saving Albums: $e');
    }
  }

  /// Load Albums from cache if valid (< 24 hours old)
  static Future<List<Album>?> loadAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if cache exists
      if (!prefs.containsKey(_albumsKey) ||
          !prefs.containsKey(_albumsTimestampKey)) {
        print('📦 [Cache] No Albums cache found');
        return null;
      }

      // Check if cache is still valid
      final timestamp = prefs.getInt(_albumsTimestampKey);
      if (timestamp == null) return null;

      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (cacheAge > _cacheDuration.inMilliseconds) {
        print(
          '⏰ [Cache] Albums cache expired (${Duration(milliseconds: cacheAge).inHours}h old)',
        );
        await clearAlbums();
        return null;
      }

      // Load from cache
      final jsonString = prefs.getString(_albumsKey);
      if (jsonString == null) return null;

      final jsonList = jsonDecode(jsonString) as List;
      final albums = jsonList.map((json) => Album.fromJson(json)).toList();

      print(
        '✅ [Cache] Loaded ${albums.length} Albums (${Duration(milliseconds: cacheAge).inHours}h old)',
      );
      return albums;
    } catch (e) {
      print('❌ [Cache] Error loading Albums: $e');
      return null;
    }
  }

  /// Clear Albums cache
  static Future<void> clearAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_albumsKey);
    await prefs.remove(_albumsTimestampKey);
    print('🧹 [Cache] Cleared Albums cache');
  }

  // ==================== UTILITIES ====================

  /// Clear all caches
  static Future<void> clearAll() async {
    await clearQuickPicks();
    await clearArtists();
    await clearAlbums();
    print('🧹 [Cache] Cleared all caches');
  }

  /// Check cache status for all types
  static Future<Map<String, dynamic>> getCacheStatus() async {
    final prefs = await SharedPreferences.getInstance();

    final qpTimestamp = prefs.getInt(_quickPicksTimestampKey);
    final artistsTimestamp = prefs.getInt(_artistsTimestampKey);
    final albumsTimestamp = prefs.getInt(_albumsTimestampKey);

    final now = DateTime.now().millisecondsSinceEpoch;

    return {
      'quickPicks': {
        'exists': qpTimestamp != null,
        'age': qpTimestamp != null
            ? Duration(milliseconds: now - qpTimestamp)
            : null,
        'valid':
            qpTimestamp != null &&
            (now - qpTimestamp) < _cacheDuration.inMilliseconds,
      },
      'artists': {
        'exists': artistsTimestamp != null,
        'age': artistsTimestamp != null
            ? Duration(milliseconds: now - artistsTimestamp)
            : null,
        'valid':
            artistsTimestamp != null &&
            (now - artistsTimestamp) < _cacheDuration.inMilliseconds,
      },
      'albums': {
        'exists': albumsTimestamp != null,
        'age': albumsTimestamp != null
            ? Duration(milliseconds: now - albumsTimestamp)
            : null,
        'valid':
            albumsTimestamp != null &&
            (now - albumsTimestamp) < _cacheDuration.inMilliseconds,
      },
    };
  }
}
