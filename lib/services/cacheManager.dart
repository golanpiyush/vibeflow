import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

/// Audio URL cache with metadata using SharedPreferences
/// Caches: videoId, audioUrl, title, artists, thumbnail, duration, and timestamp
class AudioUrlCache {
  static const String _prefix = 'audio_cache_';
  static const String _timestampSuffix = '_timestamp';
  static const Duration _cacheExpiry = Duration(hours: 2);

  static AudioUrlCache? _instance;
  SharedPreferences? _prefs;

  AudioUrlCache._();

  factory AudioUrlCache() {
    _instance ??= AudioUrlCache._();
    return _instance!;
  }

  Future<void> _init() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  /// Cache a song with all metadata
  Future<void> cache(QuickPick song, String audioUrl) async {
    await _init();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final baseKey = '${_prefix}${song.videoId}';

    try {
      await _prefs!.setString('${baseKey}_url', audioUrl);
      await _prefs!.setString('${baseKey}_title', song.title);
      await _prefs!.setString('${baseKey}_artists', song.artists);
      await _prefs!.setString('${baseKey}_thumbnail', song.thumbnail);
      await _prefs!.setString('${baseKey}_duration', song.duration ?? '');
      await _prefs!.setInt('${baseKey}_timestamp', timestamp);

      print('💾 Cached: ${song.title} (${audioUrl.length} chars)');
    } catch (e) {
      print('❌ Failed to cache: $e');
    }
  }

  /// Cache by videoId only (when you don't have full song metadata)
  Future<void> cacheByVideoId(String videoId, String audioUrl) async {
    await _init();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final baseKey = '${_prefix}$videoId';

    try {
      await _prefs!.setString('${baseKey}_url', audioUrl);
      await _prefs!.setInt('${baseKey}_timestamp', timestamp);

      print('💾 Cached URL for videoId: $videoId');
    } catch (e) {
      print('❌ Failed to cache by videoId: $e');
    }
  }

  /// Get cached audio URL with metadata
  Future<CachedAudio?> get(String videoId) async {
    await _init();

    final baseKey = '${_prefix}$videoId';
    final timestampKey = '${baseKey}_timestamp';

    // Check if cache exists and is not expired
    final timestamp = _prefs!.getInt(timestampKey);
    if (timestamp == null) return null;

    final cacheAge = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - timestamp,
    );

    if (cacheAge > _cacheExpiry) {
      // Auto-clean expired cache
      await remove(videoId);
      return null;
    }

    final audioUrl = _prefs!.getString('${baseKey}_url');
    if (audioUrl == null || audioUrl.isEmpty) return null;

    return CachedAudio(
      videoId: videoId,
      audioUrl: audioUrl,
      title: _prefs!.getString('${baseKey}_title') ?? '',
      artists: _prefs!.getString('${baseKey}_artists') ?? '',
      thumbnail: _prefs!.getString('${baseKey}_thumbnail') ?? '',
      duration: _prefs!.getString('${baseKey}_duration') ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      age: cacheAge,
    );
  }

  /// Get only the cached URL (optimized for VibeFlowCore)
  Future<String?> getCachedUrl(String videoId) async {
    await _init();

    final baseKey = '${_prefix}$videoId';
    final timestampKey = '${baseKey}_timestamp';

    final timestamp = _prefs!.getInt(timestampKey);
    if (timestamp == null) return null;

    final cacheAge = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - timestamp,
    );

    if (cacheAge > _cacheExpiry) {
      await remove(videoId);
      return null;
    }

    final url = _prefs!.getString('${baseKey}_url');

    // Validate URL is not empty
    if (url == null || url.isEmpty) {
      await remove(videoId);
      return null;
    }

    return url;
  }

  /// Get cache timestamp for a videoId
  Future<DateTime?> getCacheTime(String videoId) async {
    await _init();

    final baseKey = '${_prefix}$videoId';
    final timestampKey = '${baseKey}_timestamp';

    final timestamp = _prefs!.getInt(timestampKey);
    if (timestamp == null) return null;

    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Get cache age in hours
  Future<int?> getCacheAgeInHours(String videoId) async {
    final cacheTime = await getCacheTime(videoId);
    if (cacheTime == null) return null;

    final age = DateTime.now().difference(cacheTime);
    return age.inHours;
  }

  /// Get cache age in minutes
  Future<int?> getCacheAgeInMinutes(String videoId) async {
    final cacheTime = await getCacheTime(videoId);
    if (cacheTime == null) return null;

    final age = DateTime.now().difference(cacheTime);
    return age.inMinutes;
  }

  /// Get cached QuickPick with audioUrl
  Future<QuickPick?> getCachedQuickPick(String videoId) async {
    await _init();

    final baseKey = '${_prefix}$videoId';
    final timestampKey = '${baseKey}_timestamp';

    final timestamp = _prefs!.getInt(timestampKey);
    if (timestamp == null) return null;

    final cacheAge = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - timestamp,
    );

    if (cacheAge > _cacheExpiry) {
      await remove(videoId);
      return null;
    }

    final audioUrl = _prefs!.getString('${baseKey}_url');
    if (audioUrl == null || audioUrl.isEmpty) {
      await remove(videoId);
      return null;
    }

    final title = _prefs!.getString('${baseKey}_title') ?? '';
    final artists = _prefs!.getString('${baseKey}_artists') ?? '';
    final thumbnail = _prefs!.getString('${baseKey}_thumbnail') ?? '';
    final duration = _prefs!.getString('${baseKey}_duration');

    return QuickPick(
      videoId: videoId,
      title: title,
      artists: artists,
      thumbnail: thumbnail,
      duration: duration?.isNotEmpty == true ? duration : null,
    );
  }

  /// Check if a videoId is cached and valid
  Future<bool> hasValidCache(String videoId) async {
    await _init();

    final baseKey = '${_prefix}$videoId';
    final timestampKey = '${baseKey}_timestamp';

    final timestamp = _prefs!.getInt(timestampKey);
    if (timestamp == null) return false;

    final cacheAge = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - timestamp,
    );

    if (cacheAge > _cacheExpiry) {
      await remove(videoId);
      return false;
    }

    final url = _prefs!.getString('${baseKey}_url');
    return url != null && url.isNotEmpty;
  }

  /// Check if cache is expired (older than specified duration)
  Future<bool> isCacheExpired(
    String videoId, {
    Duration maxAge = const Duration(hours: 2),
  }) async {
    final cacheTime = await getCacheTime(videoId);
    if (cacheTime == null) return true;

    final age = DateTime.now().difference(cacheTime);
    return age > maxAge;
  }

  /// Remove a specific cache entry (PUBLIC - async)
  Future<void> remove(String videoId) async {
    await _init();

    final baseKey = '${_prefix}$videoId';
    final keysToRemove = [
      '${baseKey}_url',
      '${baseKey}_title',
      '${baseKey}_artists',
      '${baseKey}_thumbnail',
      '${baseKey}_duration',
      '${baseKey}_timestamp',
    ];

    for (final key in keysToRemove) {
      await _prefs!.remove(key);
    }

    print('🗑️ Removed cache for: $videoId');
  }

  /// Clear all cached audio data
  Future<void> clearAll() async {
    await _init();

    final keys = _prefs!
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList();

    for (final key in keys) {
      await _prefs!.remove(key);
    }

    print('🧹 Cleared all audio cache (${keys.length} items)');
  }

  /// Get all cached audio entries
  Future<List<CachedAudio>> getAllCached() async {
    await _init();

    final List<CachedAudio> cachedAudios = [];

    // Get all timestamp keys
    final allKeys = _prefs!.getKeys();
    final timestampKeys = allKeys.where(
      (key) => key.endsWith(_timestampSuffix),
    );

    for (final timestampKey in timestampKeys) {
      final videoId = timestampKey
          .replaceAll(_prefix, '')
          .replaceAll(_timestampSuffix, '');

      final cached = await get(videoId);
      if (cached != null) {
        cachedAudios.add(cached);
      }
    }

    // Sort by most recently cached
    cachedAudios.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return cachedAudios;
  }

  /// Get cache size information
  Future<CacheStats> getStats() async {
    await _init();

    final allCached = await getAllCached();
    final totalSize = await _estimateCacheSize();

    return CacheStats(
      count: allCached.length,
      totalSizeBytes: totalSize,
      oldest: allCached.isNotEmpty ? allCached.last.timestamp : null,
      newest: allCached.isNotEmpty ? allCached.first.timestamp : null,
    );
  }

  /// Clean expired cache entries
  Future<int> cleanExpired() async {
    await _init();

    final allCached = await getAllCached();
    int removedCount = 0;

    for (final cached in allCached) {
      if (cached.age > _cacheExpiry) {
        await remove(cached.videoId);
        removedCount++;
      }
    }

    if (removedCount > 0) {
      print('🧹 Cleaned $removedCount expired cache entries');
    }

    return removedCount;
  }

  /// Estimate total cache size in bytes (rough estimate)
  Future<int> _estimateCacheSize() async {
    await _init();

    int totalSize = 0;
    final allCached = await getAllCached();

    for (final cached in allCached) {
      totalSize += cached.audioUrl.length * 2;
      totalSize += cached.title.length * 2;
      totalSize += cached.artists.length * 2;
      totalSize += cached.thumbnail.length * 2;
      totalSize += cached.duration.length * 2;
    }

    return totalSize;
  }
}

/// Data class for cached audio with metadata
class CachedAudio {
  final String videoId;
  final String audioUrl;
  final String title;
  final String artists;
  final String thumbnail;
  final String duration;
  final DateTime timestamp;
  final Duration age;

  CachedAudio({
    required this.videoId,
    required this.audioUrl,
    required this.title,
    required this.artists,
    required this.thumbnail,
    required this.duration,
    required this.timestamp,
    required this.age,
  });

  /// Convert to QuickPick object
  QuickPick toQuickPick() {
    return QuickPick(
      videoId: videoId,
      title: title,
      artists: artists,
      thumbnail: thumbnail,
      duration: duration.isNotEmpty ? duration : null,
    );
  }

  /// Check if cache is still valid
  bool get isValid => age.inHours < 2;

  @override
  String toString() {
    return 'CachedAudio{videoId: $videoId, title: $title, artists: $artists, age: ${age.inMinutes}min}';
  }
}

/// Cache statistics
class CacheStats {
  final int count;
  final int totalSizeBytes;
  final DateTime? oldest;
  final DateTime? newest;

  CacheStats({
    required this.count,
    required this.totalSizeBytes,
    this.oldest,
    this.newest,
  });

  double get totalSizeMB => totalSizeBytes / (1024 * 1024);
  Duration? get ageRange =>
      newest != null && oldest != null ? newest!.difference(oldest!) : null;

  @override
  String toString() {
    return 'CacheStats{count: $count, size: ${totalSizeMB.toStringAsFixed(2)}MB, '
        'range: ${ageRange?.inHours ?? 0} hours}';
  }
}
