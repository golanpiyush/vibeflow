import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks user listening patterns and artist preferences
class UserPreferenceTracker {
  static final UserPreferenceTracker _instance =
      UserPreferenceTracker._internal();
  factory UserPreferenceTracker() => _instance;
  UserPreferenceTracker._internal();

  static const String _keyArtistPreferences = 'user_artist_preferences';
  static const String _keySkipHistory = 'user_skip_history';
  // ignore: unused_field
  static const String _keyListenHistory = 'user_listen_history';

  // Artist preference data
  Map<String, ArtistPreference> _artistPreferences = {};

  // Skip tracking
  final List<SkipEvent> _recentSkips = [];
  static const int _maxSkipHistory = 100;

  /// Initialize and load saved preferences
  Future<void> initialize() async {
    await _loadPreferences();
    print('✅ [UserPreferences] Initialized');
  }

  /// Load preferences from storage
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load artist preferences
      final artistJson = prefs.getString(_keyArtistPreferences);
      if (artistJson != null) {
        final Map<String, dynamic> data = json.decode(artistJson);
        _artistPreferences = data.map(
          (key, value) => MapEntry(key, ArtistPreference.fromJson(value)),
        );
        print(
          '📊 [UserPreferences] Loaded ${_artistPreferences.length} artist preferences',
        );
      }

      // Load skip history
      final skipJson = prefs.getString(_keySkipHistory);
      if (skipJson != null) {
        final List<dynamic> data = json.decode(skipJson);
        _recentSkips.clear();
        _recentSkips.addAll(data.map((e) => SkipEvent.fromJson(e)));
        print('📊 [UserPreferences] Loaded ${_recentSkips.length} skip events');
      }
    } catch (e) {
      print('❌ [UserPreferences] Error loading: $e');
    }
  }

  /// Save preferences to storage
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save artist preferences
      final artistData = _artistPreferences.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      await prefs.setString(_keyArtistPreferences, json.encode(artistData));

      // Save skip history (keep only recent)
      final recentSkips = _recentSkips.length > _maxSkipHistory
          ? _recentSkips.sublist(_recentSkips.length - _maxSkipHistory)
          : _recentSkips;
      final skipData = recentSkips.map((e) => e.toJson()).toList();
      await prefs.setString(_keySkipHistory, json.encode(skipData));

      print('💾 [UserPreferences] Saved to storage');
    } catch (e) {
      print('❌ [UserPreferences] Error saving: $e');
    }
  }

  /// Record that user listened to a song (completed or >30s)
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

    // Normalize artist name
    final normalizedArtist = _normalizeArtistName(artist);

    // Update or create artist preference
    final pref = _artistPreferences.putIfAbsent(
      normalizedArtist,
      () => ArtistPreference(artistName: normalizedArtist),
    );

    pref.totalListens++;
    pref.totalListenTime += listenDuration.inSeconds;
    pref.lastListenTime = DateTime.now();

    // Consider it a "completed" listen if >70% played
    if (listenPercentage >= 70) {
      pref.completedListens++;
    }

    // Update preference score
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

    // Update artist preference
    final pref = _artistPreferences.putIfAbsent(
      normalizedArtist,
      () => ArtistPreference(artistName: normalizedArtist),
    );

    pref.totalSkips++;
    pref.lastSkipTime = DateTime.now();
    pref.updatePreferenceScore();

    // Add to skip history
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

  /// Get top preferred artists
  List<String> getTopArtists({int limit = 10}) {
    final sortedArtists = _artistPreferences.values.toList()
      ..sort((a, b) => b.preferenceScore.compareTo(a.preferenceScore));

    return sortedArtists
        .take(limit)
        .where((pref) => pref.preferenceScore > 0) // Only positive scores
        .map((pref) => pref.artistName)
        .toList();
  }

  /// Get least preferred artists (frequently skipped)
  List<String> getLeastPreferredArtists({int limit = 5}) {
    final sortedArtists = _artistPreferences.values.toList()
      ..sort((a, b) => a.preferenceScore.compareTo(b.preferenceScore));

    return sortedArtists
        .take(limit)
        .where((pref) => pref.preferenceScore < 0) // Only negative scores
        .map((pref) => pref.artistName)
        .toList();
  }

  /// Check if user has been skipping a lot recently (in current session)
  SkipAnalysis analyzeRecentSkips({int lookbackCount = 5}) {
    if (_recentSkips.length < lookbackCount) {
      return SkipAnalysis(
        recentSkipCount: _recentSkips.length,
        isSkippingFrequently: false,
        skippedArtists: [],
        shouldRefetchRadio: false,
      );
    }

    // Get last N skips
    final recentSkips = _recentSkips.sublist(
      _recentSkips.length - lookbackCount,
    );

    // Extract artists
    final skippedArtists = recentSkips
        .map((skip) => skip.artist)
        .toSet()
        .toList();

    // Check if skips happened within a short time frame (indicating frustration)
    final timeWindow = Duration(minutes: 10);
    final oldestSkip = recentSkips.first.timestamp;
    final newestSkip = recentSkips.last.timestamp;
    final timeDiff = newestSkip.difference(oldestSkip);

    final isRapidSkipping = timeDiff < timeWindow;

    print('📊 [SkipAnalysis] Recent skips: ${recentSkips.length}');
    print('   Time window: ${timeDiff.inMinutes} minutes');
    print('   Rapid skipping: $isRapidSkipping');
    print('   Skipped artists: $skippedArtists');

    return SkipAnalysis(
      recentSkipCount: recentSkips.length,
      isSkippingFrequently: isRapidSkipping,
      skippedArtists: skippedArtists,
      shouldRefetchRadio: isRapidSkipping && recentSkips.length >= 3,
      timeSinceFirstSkip: timeDiff,
    );
  }

  /// Get artist preference score (-100 to 100)
  double getArtistScore(String artist) {
    final normalized = _normalizeArtistName(artist);
    return _artistPreferences[normalized]?.preferenceScore ?? 0.0;
  }

  /// Check if artist should be avoided in radio
  bool shouldAvoidArtist(String artist) {
    final score = getArtistScore(artist);
    return score < -20; // Strongly disliked
  }

  /// Get artists user might like (for radio diversification)
  List<String> getSuggestedArtists({int limit = 5}) {
    final topArtists = getTopArtists(limit: limit * 2);

    // Shuffle to add variety
    topArtists.shuffle();

    return topArtists.take(limit).toList();
  }

  /// Clear skip history (for testing or reset)
  Future<void> clearSkipHistory() async {
    _recentSkips.clear();
    await _savePreferences();
    print('🗑️ [UserPreferences] Cleared skip history');
  }

  /// Reset all preferences (for testing)
  Future<void> resetAllPreferences() async {
    _artistPreferences.clear();
    _recentSkips.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyArtistPreferences);
    await prefs.remove(_keySkipHistory);

    print('🗑️ [UserPreferences] Reset all preferences');
  }

  /// Get statistics for debugging
  Map<String, dynamic> getStatistics() {
    return {
      'total_artists_tracked': _artistPreferences.length,
      'total_skips_recorded': _recentSkips.length,
      'top_artists': getTopArtists(limit: 5),
      'least_preferred_artists': getLeastPreferredArtists(limit: 5),
    };
  }

  /// Normalize artist name for consistent tracking
  String _normalizeArtistName(String artist) {
    return artist.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    ); // Normalize whitespace
  }
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
  final List<String> skippedArtists;
  final bool shouldRefetchRadio;
  final Duration? timeSinceFirstSkip;

  SkipAnalysis({
    required this.recentSkipCount,
    required this.isSkippingFrequently,
    required this.skippedArtists,
    required this.shouldRefetchRadio,
    this.timeSinceFirstSkip,
  });
}
