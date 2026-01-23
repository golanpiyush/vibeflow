import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/services/audioGoverner.dart';
import 'package:vibeflow/services/sync_services/musicIntelligence.dart';

/// Builds a ListeningProfile from AudioGovernor thought history
/// This is the bridge between passive listening tracking and AI intelligence
class ListeningProfileBuilder {
  static ListeningProfileBuilder? _instance;

  ListeningProfileBuilder._();

  static ListeningProfileBuilder get instance {
    _instance ??= ListeningProfileBuilder._();
    return _instance!;
  }

  /// Build a complete listening profile from AudioGovernor
  /// Returns null if insufficient data exists
  Future<ListeningProfile?> buildProfile() async {
    print('📊 [ProfileBuilder] Building listening profile...');

    final governor = AudioGovernor.instance;
    final thoughts = governor.allThoughts;

    if (thoughts.isEmpty) {
      print('❌ [ProfileBuilder] No thought history available');
      return null;
    }

    // Extract listening data from thoughts
    final listeningData = _extractListeningData(thoughts);

    if (listeningData.isEmpty) {
      print('❌ [ProfileBuilder] No valid listening data in thoughts');
      return null;
    }

    // Calculate unique songs
    final uniqueSongs = _countUniqueSongs(listeningData);
    print('📊 [ProfileBuilder] Unique songs: $uniqueSongs');

    // Calculate distinct listening days
    final distinctDays = _countDistinctDays(listeningData);
    print('📊 [ProfileBuilder] Distinct days: $distinctDays');

    // Build taste buffer (last 7 days)
    final tasteBuffer = _buildTasteBuffer(listeningData);
    print('📊 [ProfileBuilder] Taste buffer: ${tasteBuffer.length} songs');

    // Build full listening history (last 30 days)
    final history = _buildListeningHistory(listeningData);
    print('📊 [ProfileBuilder] History entries: ${history.length}');

    // Load previous recommendations
    final previousRecs = await _loadPreviousRecommendations();
    print(
      '📊 [ProfileBuilder] Previous recommendations: ${previousRecs.length}',
    );

    // Infer taste characteristics
    final genres = _inferGenres(listeningData);
    final era = _inferEra(listeningData);
    final energy = _inferEnergy(listeningData);

    print('📊 [ProfileBuilder] Inferred genres: ${genres.join(", ")}');
    print('📊 [ProfileBuilder] Inferred era: $era');
    print('📊 [ProfileBuilder] Inferred energy: $energy');

    return ListeningProfile(
      uniqueSongCount: uniqueSongs,
      distinctListeningDays: distinctDays,
      listeningHistory: history,
      tasteBuffer: tasteBuffer,
      previousRecommendations: previousRecs,
      inferredGenres: genres,
      inferredEra: era,
      inferredEnergy: energy,
    );
  }

  /// Extract listening data from AudioGovernor thoughts
  Map<String, _ListeningRecord> _extractListeningData(
    List<AudioThought> thoughts,
  ) {
    final records = <String, _ListeningRecord>{};

    for (final thought in thoughts) {
      // Only process song-related thoughts
      if (!_isSongThought(thought.type)) continue;

      final song = thought.context['song'] as String?;
      final artist = thought.context['artist'] as String?;

      if (song == null || song.isEmpty) continue;

      final key = '${song.toLowerCase()}|${artist?.toLowerCase() ?? 'unknown'}';

      if (!records.containsKey(key)) {
        records[key] = _ListeningRecord(
          title: song,
          artist: artist ?? 'Unknown Artist',
          timestamps: [],
        );
      }

      records[key]!.timestamps.add(thought.timestamp);
    }

    return records;
  }

  bool _isSongThought(String type) {
    return [
      'starting_fresh',
      'resuming',
      'song_completed',
      'skip_forward',
      'skip_backward',
      'paused_mid_song',
    ].contains(type);
  }

  int _countUniqueSongs(Map<String, _ListeningRecord> data) {
    return data.length;
  }

  int _countDistinctDays(Map<String, _ListeningRecord> data) {
    final days = <String>{};

    for (final record in data.values) {
      for (final timestamp in record.timestamps) {
        final dateKey = '${timestamp.year}-${timestamp.month}-${timestamp.day}';
        days.add(dateKey);
      }
    }

    return days.length;
  }

  List<SongData> _buildTasteBuffer(Map<String, _ListeningRecord> data) {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final recentSongs = <SongData>[];

    for (final record in data.values) {
      final recentPlays = record.timestamps
          .where((t) => t.isAfter(cutoff))
          .toList();

      if (recentPlays.isNotEmpty) {
        recentSongs.add(SongData(title: record.title, artist: record.artist));
      }
    }

    // Sort by most recent first
    recentSongs.sort((a, b) {
      final aRecord = data.values.firstWhere((r) => r.title == a.title);
      final bRecord = data.values.firstWhere((r) => r.title == b.title);
      final aLatest = aRecord.timestamps.reduce((a, b) => a.isAfter(b) ? a : b);
      final bLatest = bRecord.timestamps.reduce((a, b) => a.isAfter(b) ? a : b);
      return bLatest.compareTo(aLatest);
    });

    return recentSongs.take(50).toList();
  }

  List<ListeningEntry> _buildListeningHistory(
    Map<String, _ListeningRecord> data,
  ) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final entries = <ListeningEntry>[];

    for (final record in data.values) {
      final recentPlays = record.timestamps
          .where((t) => t.isAfter(cutoff))
          .toList();

      if (recentPlays.isEmpty) continue;

      final lastPlayed = recentPlays.reduce((a, b) => a.isAfter(b) ? a : b);

      entries.add(
        ListeningEntry(
          song: SongData(title: record.title, artist: record.artist),
          playCount: recentPlays.length,
          lastPlayed: lastPlayed,
        ),
      );
    }

    // Sort by play count descending
    entries.sort((a, b) => b.playCount.compareTo(a.playCount));

    return entries.take(100).toList();
  }

  Future<List<RecommendationEntry>> _loadPreviousRecommendations() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('playlist_history') ?? [];

    final recommendations = <RecommendationEntry>[];

    for (final entry in history) {
      final parts = entry.split('|');
      if (parts.length < 3) continue;

      final timestamp = DateTime.tryParse(parts[0]);
      if (timestamp == null) continue;

      // Only keep last 14 days
      final age = DateTime.now().difference(timestamp).inDays;
      if (age > 14) continue;

      recommendations.add(
        RecommendationEntry(
          song: SongData(title: parts[1], artist: parts[2]),
          timestamp: timestamp,
        ),
      );
    }

    return recommendations;
  }

  /// Infer genres from listening patterns
  /// This is a simple heuristic - could be enhanced with metadata
  List<String> _inferGenres(Map<String, _ListeningRecord> data) {
    // For now, return placeholder
    // In production, you'd analyze artist metadata, song characteristics, etc.
    return ['Alternative', 'Rock', 'Electronic'];
  }

  /// Infer era preference
  String _inferEra(Map<String, _ListeningRecord> data) {
    // Placeholder - would analyze release years
    return '2000s-2020s';
  }

  /// Infer energy level preference
  String _inferEnergy(Map<String, _ListeningRecord> data) {
    // Placeholder - would analyze BPM, intensity patterns
    return 'Medium-High';
  }
}

class _ListeningRecord {
  final String title;
  final String artist;
  final List<DateTime> timestamps;

  _ListeningRecord({
    required this.title,
    required this.artist,
    required this.timestamps,
  });
}
