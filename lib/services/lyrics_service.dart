// lib/services/lyrics_service.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/utils/lyrics_provider.dart' as lyrics_provider;
import 'package:vibeflow/utils/settings_provider.dart';

class CachedLyrics {
  final Map<String, dynamic> lyrics;
  final DateTime cachedAt;
  final String source;

  CachedLyrics({
    required this.lyrics,
    required this.cachedAt,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'lyrics': lyrics,
    'cachedAt': cachedAt.toIso8601String(),
    'source': source,
  };

  factory CachedLyrics.fromJson(Map<String, dynamic> json) {
    return CachedLyrics(
      lyrics: json['lyrics'] as Map<String, dynamic>,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      source: json['source'] as String,
    );
  }

  bool isExpired() {
    final now = DateTime.now();
    final difference = now.difference(cachedAt);
    return difference.inHours >= 6; // 6 hours cache duration
  }
}

class LyricsService {
  static const String _cachePrefix = 'lyrics_cache_';
  static const Duration _cacheDuration = Duration(hours: 6);

  final lyrics_provider.LyricsProvider _lyricsProvider;
  final SharedPreferences _prefs;

  LyricsService(this._lyricsProvider, this._prefs);

  String _getCacheKey(String title, String artist) {
    final normalized = '${title.toLowerCase()}_${artist.toLowerCase()}';
    return '$_cachePrefix$normalized';
  }

  Future<Map<String, dynamic>> fetchLyrics({
    required String title,
    required String artist,
    int duration = -1,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _getCacheKey(title, artist);

    // Check cache first
    if (!forceRefresh) {
      final cachedData = _prefs.getString(cacheKey);
      if (cachedData != null) {
        try {
          final cached = CachedLyrics.fromJson(
            json.decode(cachedData) as Map<String, dynamic>,
          );

          if (!cached.isExpired()) {
            print('LYRICS_SERVICE: Using cached lyrics for $title');
            return {
              ...cached.lyrics,
              'from_cache': true,
              'cached_at': cached.cachedAt.toIso8601String(),
            };
          } else {
            print('LYRICS_SERVICE: Cache expired for $title');
          }
        } catch (e) {
          print('LYRICS_SERVICE: Error reading cache: $e');
          await _prefs.remove(cacheKey);
        }
      }
    }

    // Fetch fresh lyrics
    print('LYRICS_SERVICE: Fetching fresh lyrics for $title');
    final result = await _lyricsProvider.fetchLyrics(
      title,
      artist,
      duration: duration,
    );

    // Cache successful results
    if (result['success'] == true) {
      final cached = CachedLyrics(
        lyrics: result,
        cachedAt: DateTime.now(),
        source: result['source'] ?? 'unknown',
      );

      await _prefs.setString(cacheKey, json.encode(cached.toJson()));
      print('LYRICS_SERVICE: Cached lyrics for $title');
    }

    return {...result, 'from_cache': false};
  }

  Future<void> clearCache() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_cachePrefix)) {
        await _prefs.remove(key);
      }
    }
    print('LYRICS_SERVICE: Cache cleared');
  }

  Future<void> clearExpiredCache() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_cachePrefix)) {
        final data = _prefs.getString(key);
        if (data != null) {
          try {
            final cached = CachedLyrics.fromJson(
              json.decode(data) as Map<String, dynamic>,
            );
            if (cached.isExpired()) {
              await _prefs.remove(key);
              print('LYRICS_SERVICE: Removed expired cache: $key');
            }
          } catch (e) {
            await _prefs.remove(key);
          }
        }
      }
    }
  }
}

// Provider for LyricsService
final lyricsServiceProvider = Provider<LyricsService>((ref) {
  final settings = ref.watch(settingsProvider);
  final lyricsProvider = lyrics_provider.LyricsProvider();
  lyricsProvider.selectedSource = settings.lyricsProvider;

  // Get SharedPreferences instance (you'll need to initialize this)
  // For now, we'll create a Future provider
  throw UnimplementedError('Use lyricsServiceFutureProvider instead');
});

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
  return await SharedPreferences.getInstance();
});

final lyricsServiceFutureProvider = FutureProvider<LyricsService>((ref) async {
  final settings = ref.watch(settingsProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);

  final lyricsProvider = lyrics_provider.LyricsProvider();
  lyricsProvider.selectedSource = settings.lyricsProvider;

  final service = LyricsService(lyricsProvider, prefs);

  ref.onDispose(() {
    lyricsProvider.dispose();
  });

  return service;
});
