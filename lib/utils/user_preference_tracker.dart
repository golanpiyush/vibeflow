import 'dart:convert';
import 'package:vibeflow/utils/secure_storage.dart';

/// Tracks user listening patterns and artist preferences
class UserPreferenceTracker {
  static final UserPreferenceTracker _instance =
      UserPreferenceTracker._internal();
  factory UserPreferenceTracker() => _instance;
  UserPreferenceTracker._internal();

  static const String _keyArtistPreferences = 'user_artist_preferences';
  static const String _keySkipHistory = 'user_skip_history';
  static const String _keyCompletedSongs = 'user_completed_songs';

  Map<String, ArtistPreference> _artistPreferences = {};
  final List<SkipEvent> _recentSkips = [];
  Map<String, CompletedSong> _completedSongs = {};

  static const int _maxSkipHistory = 100;

  /// Initialize and load saved preferences
  Future<void> initialize() async {
    await _loadPreferences();
    print('✅ [UserPreferences] Initialized');
  }

  Future<void> _loadPreferences() async {
    try {
      final storage = SecureStorageService();

      final artistJson = await storage.readSecureData(_keyArtistPreferences);
      if (artistJson != null) {
        final Map<String, dynamic> data = json.decode(artistJson);
        _artistPreferences = data.map(
          (key, value) => MapEntry(key, ArtistPreference.fromJson(value)),
        );
        print(
          '📊 [UserPreferences] Loaded ${_artistPreferences.length} artist preferences',
        );
      }

      final skipJson = await storage.readSecureData(_keySkipHistory);
      if (skipJson != null) {
        final List<dynamic> data = json.decode(skipJson);
        _recentSkips.clear();
        _recentSkips.addAll(data.map((e) => SkipEvent.fromJson(e)));
        print('📊 [UserPreferences] Loaded ${_recentSkips.length} skip events');
      }

      final completedJson = await storage.readSecureData(_keyCompletedSongs);
      if (completedJson != null) {
        final Map<String, dynamic> data = json.decode(completedJson);
        _completedSongs = data.map(
          (key, value) => MapEntry(key, CompletedSong.fromJson(value)),
        );
        print(
          '📊 [UserPreferences] Loaded ${_completedSongs.length} completed songs',
        );
      }
    } catch (e) {
      print('❌ [UserPreferences] Error loading: $e');
    }
  }

  Future<void> _savePreferences() async {
    try {
      final storage = SecureStorageService();

      final artistData = _artistPreferences.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      await storage.writeSecureData(
        _keyArtistPreferences,
        json.encode(artistData),
      );

      final recentSkips = _recentSkips.length > _maxSkipHistory
          ? _recentSkips.sublist(_recentSkips.length - _maxSkipHistory)
          : _recentSkips;
      final skipData = recentSkips.map((e) => e.toJson()).toList();
      await storage.writeSecureData(_keySkipHistory, json.encode(skipData));

      final completedData = _completedSongs.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      await storage.writeSecureData(
        _keyCompletedSongs,
        json.encode(completedData),
      );

      print('💾 [UserPreferences] Saved to secure storage');
    } catch (e) {
      print('❌ [UserPreferences] Error saving: $e');
    }
  }

  Future<void> resetAllPreferences() async {
    _artistPreferences.clear();
    _recentSkips.clear();
    _completedSongs.clear();

    final storage = SecureStorageService();
    await storage.deleteSecureData(_keyArtistPreferences);
    await storage.deleteSecureData(_keySkipHistory);
    await storage.deleteSecureData(_keyCompletedSongs);

    print('🗑️ [UserPreferences] Reset all preferences');
  }

  // ── Listen Recording ───────────────────────────────────────────────────────

  /// Record that user listened to a song
  Future<void> recordListen(
    String artist,
    String songTitle, {
    required Duration listenDuration,
    required Duration totalDuration,
  }) async {
    if (artist.isEmpty || artist == 'Unknown Artist') return;

    final listenPercentage = totalDuration.inSeconds > 0
        ? (listenDuration.inSeconds / totalDuration.inSeconds * 100).clamp(
            0,
            100,
          )
        : 0.0;

    final normalizedArtist = _normalizeArtistName(artist);

    final pref = _artistPreferences.putIfAbsent(
      normalizedArtist,
      () => ArtistPreference(artistName: normalizedArtist),
    );

    pref.totalListens++;
    pref.totalListenTime += listenDuration.inSeconds;
    pref.lastListenTime = DateTime.now();

    // Track completed songs (>70% listened = completed)
    if (listenPercentage >= 70) {
      pref.completedListens++;

      final songKey = '${normalizedArtist}__${songTitle.trim().toLowerCase()}';
      final existing = _completedSongs[songKey];
      if (existing != null) {
        existing.playCount++;
        existing.lastPlayedAt = DateTime.now();
        existing.totalListenTime += listenDuration.inSeconds;
      } else {
        _completedSongs[songKey] = CompletedSong(
          title: songTitle,
          artist: normalizedArtist,
          firstPlayedAt: DateTime.now(),
          lastPlayedAt: DateTime.now(),
          playCount: 1,
          totalListenTime: listenDuration.inSeconds,
        );
      }
      print(
        '✅ [UserPreferences] Completed song tracked: $songTitle by $normalizedArtist',
      );
    }

    pref.updatePreferenceScore();

    print('✅ [UserPreferences] Recorded listen: $normalizedArtist');
    print(
      '   Total listens: ${pref.totalListens}, Score: ${pref.preferenceScore.toStringAsFixed(2)}',
    );

    await _savePreferences();
  }

  /// Record that user skipped a song
  Future<void> recordSkip(
    String artist,
    String songTitle, {
    required Duration position,
    required Duration totalDuration,
  }) async {
    if (artist.isEmpty || artist == 'Unknown Artist') return;

    final normalizedArtist = _normalizeArtistName(artist);

    final pref = _artistPreferences.putIfAbsent(
      normalizedArtist,
      () => ArtistPreference(artistName: normalizedArtist),
    );

    pref.totalSkips++;
    pref.lastSkipTime = DateTime.now();
    pref.updatePreferenceScore();

    _recentSkips.add(
      SkipEvent(
        artist: normalizedArtist,
        songTitle: songTitle,
        timestamp: DateTime.now(),
        position: position,
        totalDuration: totalDuration,
      ),
    );

    print('⏭️ [UserPreferences] Recorded skip: $normalizedArtist');
    print(
      '   Total skips: ${pref.totalSkips}, Score: ${pref.preferenceScore.toStringAsFixed(2)}',
    );

    await _savePreferences();
  }

  // ── Artist Getters ─────────────────────────────────────────────────────────

  List<String> getTopArtists({int limit = 10}) {
    final sortedArtists = _artistPreferences.values.toList()
      ..sort((a, b) => b.preferenceScore.compareTo(a.preferenceScore));

    return sortedArtists
        .take(limit)
        .where((pref) => pref.preferenceScore > 0)
        .map((pref) => pref.artistName)
        .toList();
  }

  List<String> getLeastPreferredArtists({int limit = 5}) {
    final sortedArtists = _artistPreferences.values.toList()
      ..sort((a, b) => a.preferenceScore.compareTo(b.preferenceScore));

    return sortedArtists
        .take(limit)
        .where((pref) => pref.preferenceScore < 0)
        .map((pref) => pref.artistName)
        .toList();
  }

  double getArtistScore(String artist) {
    final normalized = _normalizeArtistName(artist);
    return _artistPreferences[normalized]?.preferenceScore ?? 0.0;
  }

  bool shouldAvoidArtist(String artist) {
    return getArtistScore(artist) < -20;
  }

  List<String> getSuggestedArtists({int limit = 5}) {
    final topArtists = getTopArtists(limit: limit * 2);
    topArtists.shuffle();
    return topArtists.take(limit).toList();
  }

  Map<String, double> getArtistScores(List<String> artists) {
    final Map<String, double> scores = {};
    for (final artist in artists) {
      final normalized = _normalizeArtistName(artist);
      scores[artist] = _artistPreferences[normalized]?.preferenceScore ?? 0.0;
    }
    return scores;
  }

  bool hasStronglyDislikedArtists(List<String> artists) {
    return artists.any((a) => shouldAvoidArtist(a));
  }

  // ── Completed Songs Getters ────────────────────────────────────────────────

  /// Most played songs by play count
  List<CompletedSong> getMostPlayedSongs({int limit = 10}) {
    final songs = _completedSongs.values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return songs.take(limit).toList();
  }

  /// Most played artists by total completed listen count
  List<MapEntry<String, int>> getMostPlayedArtists({int limit = 10}) {
    final Map<String, int> artistPlays = {};
    for (final song in _completedSongs.values) {
      artistPlays[song.artist] =
          (artistPlays[song.artist] ?? 0) + song.playCount;
    }
    final sorted = artistPlays.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Recently played songs by last play date
  List<CompletedSong> getRecentlyPlayedSongs({int limit = 10}) {
    final songs = _completedSongs.values.toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    return songs.take(limit).toList();
  }

  int get totalUniqueSongsCompleted => _completedSongs.length;

  bool hasCompletedSong(String title, String artist) {
    final key =
        '${_normalizeArtistName(artist)}__${title.trim().toLowerCase()}';
    return _completedSongs.containsKey(key);
  }

  Map<String, dynamic> getCompletedSongsStats() {
    final total = _completedSongs.length;
    final totalPlays = _completedSongs.values.fold(
      0,
      (sum, s) => sum + s.playCount,
    );
    final totalTime = _completedSongs.values.fold(
      0,
      (sum, s) => sum + s.totalListenTime,
    );
    return {
      'unique_songs': total,
      'total_plays': totalPlays,
      'total_listen_time_seconds': totalTime,
      'most_played': getMostPlayedSongs(
        limit: 3,
      ).map((s) => '${s.title} (${s.playCount}x)').toList(),
      'top_artists': getMostPlayedArtists(
        limit: 3,
      ).map((e) => '${e.key} (${e.value}x)').toList(),
    };
  }

  // ── Skip Analysis ──────────────────────────────────────────────────────────

  List<String> getRecentSkippedArtists({int limit = 5, Duration? timeWindow}) {
    try {
      if (_recentSkips.isEmpty) return [];

      final window = timeWindow ?? const Duration(hours: 1);
      final now = DateTime.now();

      final recentSkipsInWindow = _recentSkips
          .where((skip) => now.difference(skip.timestamp) <= window)
          .toList();

      if (recentSkipsInWindow.isEmpty) return [];

      final Map<String, int> skipCounts = {};
      for (final skip in recentSkipsInWindow) {
        skipCounts[skip.artist] = (skipCounts[skip.artist] ?? 0) + 1;
      }

      final sortedArtists = skipCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final result = sortedArtists.take(limit).map((e) => e.key).toList();
      print(
        '📊 [UserPreferences] Recent skipped artists (last ${window.inHours}h): $result',
      );
      return result;
    } catch (e) {
      print('❌ [UserPreferences] Error getting recent skipped artists: $e');
      return [];
    }
  }

  List<String> getWeightedSkippedArtists({int limit = 5}) {
    try {
      if (_recentSkips.isEmpty) return [];

      final now = DateTime.now();
      final Map<String, double> skipScores = {};

      for (final skip in _recentSkips) {
        final ageInHours = now.difference(skip.timestamp).inHours;
        final recencyWeight = 1.0 / (1 + ageInHours / 24);
        skipScores[skip.artist] =
            (skipScores[skip.artist] ?? 0) + recencyWeight;
      }

      final sortedArtists = skipScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedArtists.take(limit).map((e) => e.key).toList();
    } catch (e) {
      print('❌ [UserPreferences] Error getting weighted skipped artists: $e');
      return [];
    }
  }

  List<String> getImmediateSkippedArtists({int limit = 3}) {
    return getRecentSkippedArtists(
      limit: limit,
      timeWindow: const Duration(minutes: 15),
    );
  }

  SkipAnalysis analyzeRecentSkips({
    int lookbackCount = 5,
    Duration rapidSkipWindow = const Duration(minutes: 2),
  }) {
    if (_recentSkips.isEmpty) {
      return SkipAnalysis(
        recentSkipCount: 0,
        isSkippingFrequently: false,
        skippedArtists: [],
        shouldRefetchRadio: false,
      );
    }

    final recentSkips = _recentSkips.length > lookbackCount
        ? _recentSkips.sublist(_recentSkips.length - lookbackCount)
        : _recentSkips.toList();

    final skippedArtists = recentSkips.map((s) => s.artist).toSet().toList();

    final Map<String, int> skipCountByArtist = {};
    for (final skip in recentSkips) {
      skipCountByArtist[skip.artist] =
          (skipCountByArtist[skip.artist] ?? 0) + 1;
    }

    Duration? timeSpan;
    Duration? shortestGap;
    double totalSkipPosition = 0;

    if (recentSkips.length >= 2) {
      timeSpan = recentSkips.last.timestamp.difference(
        recentSkips.first.timestamp,
      );

      for (int i = 1; i < recentSkips.length; i++) {
        final gap = recentSkips[i].timestamp.difference(
          recentSkips[i - 1].timestamp,
        );
        if (shortestGap == null || gap < shortestGap) shortestGap = gap;
      }
    }

    for (final skip in recentSkips) {
      totalSkipPosition += skip.position.inSeconds;
    }
    final avgSkipPosition = recentSkips.isEmpty
        ? 0.0
        : totalSkipPosition / recentSkips.length;

    final isRapidSkipping =
        recentSkips.length >= 3 &&
        timeSpan != null &&
        timeSpan <= rapidSkipWindow;
    final isBurstSkipping =
        recentSkips.length >= 2 &&
        shortestGap != null &&
        shortestGap <= const Duration(seconds: 10);

    final shouldRefetch =
        isRapidSkipping ||
        (isBurstSkipping && recentSkips.length >= 3) ||
        (recentSkips.length >= 5 &&
            timeSpan != null &&
            timeSpan <= const Duration(minutes: 5)) ||
        (avgSkipPosition < 10 && recentSkips.length >= 4);

    print(
      '📊 [SkipAnalysis] ${recentSkips.length} skips, rapid: $isRapidSkipping, burst: $isBurstSkipping, refetch: $shouldRefetch',
    );

    return SkipAnalysis(
      recentSkipCount: recentSkips.length,
      isSkippingFrequently: isRapidSkipping || isBurstSkipping,
      isBurstSkipping: isBurstSkipping,
      isRapidSkipping: isRapidSkipping,
      skippedArtists: skippedArtists,
      skipCountByArtist: skipCountByArtist,
      shouldRefetchRadio: shouldRefetch,
      timeSinceFirstSkip: timeSpan,
      shortestSkipGap: shortestGap,
      averageSkipPosition: avgSkipPosition,
      uniqueArtistsSkipped: skippedArtists.length,
    );
  }

  Future<void> clearSkipHistory() async {
    _recentSkips.clear();
    await _savePreferences();
    print('🗑️ [UserPreferences] Cleared skip history');
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> getStatistics() {
    return {
      'total_artists_tracked': _artistPreferences.length,
      'total_skips_recorded': _recentSkips.length,
      'top_artists': getTopArtists(limit: 5),
      'least_preferred_artists': getLeastPreferredArtists(limit: 5),
      'completed_songs': getCompletedSongsStats(),
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _normalizeArtistName(String artist) {
    return artist.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isUserFrustrated(
    int skipCount,
    bool isBurst,
    bool isRapid,
    double avgPosition,
  ) {
    if (isBurst && skipCount >= 3) return true;
    if (isRapid && skipCount >= 4) return true;
    if (avgPosition < 15 && skipCount >= 3) return true;
    if (skipCount >= 6) return true;
    return false;
  }
}

// ── Models ─────────────────────────────────────────────────────────────────

class CompletedSong {
  final String title;
  final String artist;
  final DateTime firstPlayedAt;
  DateTime lastPlayedAt;
  int playCount;
  int totalListenTime; // in seconds

  CompletedSong({
    required this.title,
    required this.artist,
    required this.firstPlayedAt,
    required this.lastPlayedAt,
    this.playCount = 1,
    this.totalListenTime = 0,
  });

  String get formattedListenTime {
    final hours = totalListenTime ~/ 3600;
    final minutes = (totalListenTime % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'first_played_at': firstPlayedAt.toIso8601String(),
    'last_played_at': lastPlayedAt.toIso8601String(),
    'play_count': playCount,
    'total_listen_time': totalListenTime,
  };

  factory CompletedSong.fromJson(Map<String, dynamic> json) => CompletedSong(
    title: json['title'],
    artist: json['artist'],
    firstPlayedAt: DateTime.parse(json['first_played_at']),
    lastPlayedAt: DateTime.parse(json['last_played_at']),
    playCount: json['play_count'] ?? 1,
    totalListenTime: json['total_listen_time'] ?? 0,
  );
}

/// Artist preference data
class ArtistPreference {
  final String artistName;
  int totalListens;
  int completedListens;
  int totalSkips;
  int totalListenTime; // in seconds
  DateTime? lastListenTime;
  DateTime? lastSkipTime;
  double preferenceScore;

  ArtistPreference({
    required this.artistName,
    this.totalListens = 0,
    this.completedListens = 0,
    this.totalSkips = 0,
    this.totalListenTime = 0,
    this.lastListenTime,
    this.lastSkipTime,
    this.preferenceScore = 0.0,
  });

  /// Calculate preference score based on listening behavior
  /// Score range: -100 (strongly disliked) to +100 (strongly liked)
  void updatePreferenceScore() {
    // Base score from listens vs skips
    final listenWeight = totalListens * 10;
    final completedWeight = completedListens * 5; // Bonus for completed
    final skipPenalty = totalSkips * 15; // Skips hurt more

    double score = (listenWeight + completedWeight - skipPenalty).toDouble();

    // Time decay: reduce impact of old data
    final now = DateTime.now();
    if (lastListenTime != null) {
      final daysSinceLastListen = now.difference(lastListenTime!).inDays;
      final decayFactor =
          1.0 / (1 + daysSinceLastListen / 30); // Decay over 30 days
      score *= decayFactor;
    }

    // Normalize to -100 to +100 range
    preferenceScore = score.clamp(-100, 100);
  }

  Map<String, dynamic> toJson() => {
    'artist_name': artistName,
    'total_listens': totalListens,
    'completed_listens': completedListens,
    'total_skips': totalSkips,
    'total_listen_time': totalListenTime,
    'last_listen_time': lastListenTime?.toIso8601String(),
    'last_skip_time': lastSkipTime?.toIso8601String(),
    'preference_score': preferenceScore,
  };

  factory ArtistPreference.fromJson(Map<String, dynamic> json) =>
      ArtistPreference(
        artistName: json['artist_name'],
        totalListens: json['total_listens'] ?? 0,
        completedListens: json['completed_listens'] ?? 0,
        totalSkips: json['total_skips'] ?? 0,
        totalListenTime: json['total_listen_time'] ?? 0,
        lastListenTime: json['last_listen_time'] != null
            ? DateTime.parse(json['last_listen_time'])
            : null,
        lastSkipTime: json['last_skip_time'] != null
            ? DateTime.parse(json['last_skip_time'])
            : null,
        preferenceScore: json['preference_score'] ?? 0.0,
      );
}

/// Skip event data
class SkipEvent {
  final String artist;
  final String songTitle;
  final DateTime timestamp;
  final Duration position;
  final Duration totalDuration;

  SkipEvent({
    required this.artist,
    required this.songTitle,
    required this.timestamp,
    required this.position,
    required this.totalDuration,
  });

  Map<String, dynamic> toJson() => {
    'artist': artist,
    'song_title': songTitle,
    'timestamp': timestamp.toIso8601String(),
    'position': position.inSeconds,
    'total_duration': totalDuration.inSeconds,
  };

  factory SkipEvent.fromJson(Map<String, dynamic> json) => SkipEvent(
    artist: json['artist'],
    songTitle: json['song_title'],
    timestamp: DateTime.parse(json['timestamp']),
    position: Duration(seconds: json['position']),
    totalDuration: Duration(seconds: json['total_duration']),
  );
}

/// Analysis of recent skip behavior
class SkipAnalysis {
  final int recentSkipCount;
  final bool isSkippingFrequently;
  final bool isBurstSkipping;
  final bool isRapidSkipping;
  final List<String> skippedArtists;
  final Map<String, int> skipCountByArtist;
  final bool shouldRefetchRadio;
  final Duration? timeSinceFirstSkip;
  final Duration? shortestSkipGap;
  final double averageSkipPosition; // in seconds
  final int uniqueArtistsSkipped;

  SkipAnalysis({
    required this.recentSkipCount,
    required this.isSkippingFrequently,
    this.isBurstSkipping = false,
    this.isRapidSkipping = false,
    required this.skippedArtists,
    Map<String, int>? skipCountByArtist,
    required this.shouldRefetchRadio,
    this.timeSinceFirstSkip,
    this.shortestSkipGap,
    this.averageSkipPosition = 0,
    int? uniqueArtistsSkipped,
  }) : skipCountByArtist = skipCountByArtist ?? {},
       uniqueArtistsSkipped = uniqueArtistsSkipped ?? skippedArtists.length;

  /// Get a human-readable description of the skip pattern
  String get description {
    final parts = <String>[];

    if (recentSkipCount > 0) {
      parts.add('$recentSkipCount skips');
    }

    if (isBurstSkipping) {
      parts.add('BURST');
    }

    if (isRapidSkipping) {
      parts.add('RAPID');
    }

    if (timeSinceFirstSkip != null) {
      parts.add('over ${timeSinceFirstSkip!.inSeconds}s');
    }

    if (shortestSkipGap != null && shortestSkipGap!.inSeconds < 10) {
      parts.add('gap: ${shortestSkipGap!.inSeconds}s');
    }

    if (skipCountByArtist.isNotEmpty) {
      final topSkipped = skipCountByArtist.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (topSkipped.isNotEmpty) {
        final top = topSkipped.first;
        parts.add('top: ${top.key} (${top.value}x)');
      }
    }

    return parts.join(' · ');
  }

  /// Check if the skip pattern suggests user is frustrated
  bool get isFrustrated {
    // User is likely frustrated if:
    // 1. Burst skipping (multiple skips within seconds)
    // 2. Rapid skipping (many skips in short window)
    // 3. Skipping early in songs (average skip position < 15s)
    // 4. Skipping many different artists in a row

    if (isBurstSkipping) return true;
    if (isRapidSkipping && recentSkipCount >= 4) return true;
    if (averageSkipPosition < 15 && recentSkipCount >= 3) return true;
    if (uniqueArtistsSkipped >= 4 && recentSkipCount >= 5) return true;

    return false;
  }

  /// Get the most frequently skipped artist
  String? get mostSkippedArtist {
    if (skipCountByArtist.isEmpty) return null;

    return skipCountByArtist.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  /// Convert to JSON for logging/debugging
  Map<String, dynamic> toJson() => {
    'recentSkipCount': recentSkipCount,
    'isSkippingFrequently': isSkippingFrequently,
    'isBurstSkipping': isBurstSkipping,
    'isRapidSkipping': isRapidSkipping,
    'skippedArtists': skippedArtists,
    'skipCountByArtist': skipCountByArtist,
    'shouldRefetchRadio': shouldRefetchRadio,
    'timeSinceFirstSkip': timeSinceFirstSkip?.inSeconds,
    'shortestSkipGap': shortestSkipGap?.inSeconds,
    'averageSkipPosition': averageSkipPosition,
    'uniqueArtistsSkipped': uniqueArtistsSkipped,
    'isFrustrated': isFrustrated,
    'mostSkippedArtist': mostSkippedArtist,
  };
}
