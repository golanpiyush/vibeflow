import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/constants/ai_models_config.dart';

/// Music Intelligence Orchestrator
/// This is the ONLY entry point for AI-powered playlist generation.
/// It enforces strict gating rules and orchestrates worker/inspector AIs.
class MusicIntelligenceOrchestrator {
  static MusicIntelligenceOrchestrator? _instance;
  final String _apiKey;

  MusicIntelligenceOrchestrator._(this._apiKey);

  static Future<MusicIntelligenceOrchestrator> init() async {
    if (_instance == null) {
      await dotenv.load(fileName: ".env");
      final apiKey = dotenv.env[ApiConfig.apiKeyEnvVar];

      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('OPENROUTER_API_KEY not found in .env');
      }

      _instance = MusicIntelligenceOrchestrator._(apiKey);
      print('✅ [MusicIntelligence] Orchestrator initialized');
    }
    return _instance!;
  }

  static MusicIntelligenceOrchestrator get instance {
    if (_instance == null) {
      throw StateError('MusicIntelligenceOrchestrator not initialized');
    }
    return _instance!;
  }

  /// PRIMARY ENTRY POINT
  /// Generates a personalized playlist using multi-agent AI system.
  /// Returns null if ANY gating rule fails.
  /// Returns null if ANY AI call fails.
  /// Never retries. Never degrades gracefully.
  Future<PlaylistGenerationResult?> generateDailyPlaylist({
    required ListeningProfile profile,
  }) async {
    print('🎯 [Orchestrator] Starting playlist generation...');

    // GATING RULE 1: Check unique song count
    if (profile.uniqueSongCount < GatingRules.minUniqueSongs) {
      print(
        '❌ [Orchestrator] GATE FAILED: uniqueSongs=${profile.uniqueSongCount}, required=${GatingRules.minUniqueSongs}',
      );
      return PlaylistGenerationResult.error(
        SystemError.insufficientListeningData,
      );
    }

    // GATING RULE 2: Check distinct listening days
    if (profile.distinctListeningDays < GatingRules.minListeningDays) {
      print(
        '❌ [Orchestrator] GATE FAILED: listeningDays=${profile.distinctListeningDays}, required=${GatingRules.minListeningDays}',
      );
      return PlaylistGenerationResult.error(
        SystemError.insufficientListeningDays,
      );
    }

    // GATING RULE 3: Verify listening data exists
    if (profile.listeningHistory.isEmpty) {
      print('❌ [Orchestrator] GATE FAILED: listening history empty');
      return PlaylistGenerationResult.error(SystemError.emptyListeningHistory);
    }

    // GATING RULE 4: Verify taste profile buffer exists
    if (profile.tasteBuffer.isEmpty) {
      print('❌ [Orchestrator] GATE FAILED: taste buffer missing');
      return PlaylistGenerationResult.error(SystemError.tasteProfileMissing);
    }

    // GATING RULE 5: Check refresh interval
    final lastRefresh = await _getLastRefreshTime();
    if (lastRefresh != null) {
      final hoursSinceRefresh = DateTime.now().difference(lastRefresh).inHours;
      if (hoursSinceRefresh < GatingRules.refreshIntervalHours) {
        print(
          '⏳ [Orchestrator] Refresh blocked: only ${hoursSinceRefresh}h since last refresh',
        );
        return PlaylistGenerationResult.tooSoon(hoursSinceRefresh);
      }
    }

    print('✅ [Orchestrator] All gates passed. Proceeding to AI generation.');

    // STEP 1: Call Primary Worker AI
    final workerResponse = await _callPrimaryWorker(profile);
    if (workerResponse == null) {
      print('❌ [Orchestrator] Worker AI returned null');
      return PlaylistGenerationResult.error(SystemError.workerOutputEmpty);
    }

    if (!_validateWorkerOutput(workerResponse)) {
      print('❌ [Orchestrator] Worker output validation failed');
      return PlaylistGenerationResult.error(SystemError.workerOutputInvalid);
    }

    print(
      '✅ [Orchestrator] Worker AI succeeded: ${workerResponse.songs.length} songs',
    );

    // STEP 2: Call Inspector AI
    final inspectorApproved = await _callInspector(profile, workerResponse);
    if (!inspectorApproved) {
      print('❌ [Orchestrator] Inspector REJECTED playlist');
      return PlaylistGenerationResult.error(SystemError.inspectorRejected);
    }

    print('✅ [Orchestrator] Inspector APPROVED playlist');

    // STEP 3: Persist playlist and update refresh time
    await _saveLastRefreshTime();
    await _savePlaylistHistory(workerResponse);

    print('🎉 [Orchestrator] Playlist generation complete');
    return workerResponse;
  }

  /// Call Primary Worker AI (GLM-4.5 Air)
  Future<PlaylistGenerationResult?> _callPrimaryWorker(
    ListeningProfile profile,
  ) async {
    print('🤖 [Worker] Calling GLM-4.5 Air...');

    final userPrompt = _buildWorkerPrompt(profile);

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'com.vibeflow.app',
            },
            body: jsonEncode({
              'model': AiModels.primaryWorker,
              'messages': [
                {'role': 'system', 'content': SystemPrompts.primaryWorker},
                {'role': 'user', 'content': userPrompt},
              ],
              'temperature': 0.7,
              'max_tokens': 2000,
            }),
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

      if (response.statusCode != 200) {
        print('❌ [Worker] API error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;

      if (content == null || content.trim().isEmpty) {
        print('❌ [Worker] Empty response');
        return null;
      }

      print('📝 [Worker] Raw response received (${content.length} chars)');

      // Parse songs from response
      final songs = _parseWorkerOutput(content);

      return PlaylistGenerationResult.success(songs);
    } catch (e) {
      print('❌ [Worker] Exception: $e');
      return null;
    }
  }

  /// Call Inspector AI (Gemma 3n 4B)
  Future<bool> _callInspector(
    ListeningProfile profile,
    PlaylistGenerationResult workerResult,
  ) async {
    print('🔍 [Inspector] Calling Gemma 3n 4B...');

    final userPrompt = _buildInspectorPrompt(profile, workerResult);

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'com.vibeflow.app',
            },
            body: jsonEncode({
              'model': AiModels.inspector,
              'messages': [
                {'role': 'system', 'content': SystemPrompts.inspector},
                {'role': 'user', 'content': userPrompt},
              ],
              'temperature': 0.0, // Deterministic
              'max_tokens': 50,
            }),
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

      if (response.statusCode != 200) {
        print('❌ [Inspector] API error: ${response.statusCode}');
        return false;
      }

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;

      if (content == null) {
        print('❌ [Inspector] Null response');
        return false;
      }

      final verdict = content.trim().toUpperCase();
      print('🔍 [Inspector] Verdict: $verdict');

      return verdict.contains('APPROVE');
    } catch (e) {
      print('❌ [Inspector] Exception: $e');
      return false;
    }
  }

  /// Build prompt for Primary Worker AI
  String _buildWorkerPrompt(ListeningProfile profile) {
    final buffer = StringBuffer();

    buffer.writeln('VERIFIED LISTENING HISTORY:');
    buffer.writeln('Unique songs: ${profile.uniqueSongCount}');
    buffer.writeln('Listening days: ${profile.distinctListeningDays}');
    buffer.writeln('');

    buffer.writeln('RECENT LISTENING (Last 7 days):');
    for (final song in profile.tasteBuffer) {
      buffer.writeln('${song.title} – ${song.artist}');
    }
    buffer.writeln('');

    buffer.writeln('FULL LISTENING HISTORY (Last 30 days):');
    for (final entry in profile.listeningHistory) {
      buffer.writeln(
        '${entry.song.title} – ${entry.song.artist} (${entry.playCount} plays)',
      );
    }
    buffer.writeln('');

    if (profile.previousRecommendations.isNotEmpty) {
      buffer.writeln('PREVIOUSLY RECOMMENDED (Do not repeat within 7 days):');
      for (final rec in profile.previousRecommendations) {
        final daysAgo = DateTime.now().difference(rec.timestamp).inDays;
        buffer.writeln(
          '${rec.song.title} – ${rec.song.artist} ($daysAgo days ago)',
        );
      }
      buffer.writeln('');
    }

    buffer.writeln('Generate EXACTLY 35 songs.');

    return buffer.toString();
  }

  /// Build prompt for Inspector AI
  String _buildInspectorPrompt(
    ListeningProfile profile,
    PlaylistGenerationResult workerResult,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('USER TASTE PROFILE:');
    buffer.writeln('Primary genres: ${profile.inferredGenres.join(", ")}');
    buffer.writeln('Era preference: ${profile.inferredEra}');
    buffer.writeln('Energy level: ${profile.inferredEnergy}');
    buffer.writeln('');

    buffer.writeln('PROPOSED PLAYLIST (${workerResult.songs.length} songs):');
    for (final song in workerResult.songs) {
      buffer.writeln(
        '${song.title} – ${song.artist}${song.album != null ? " (${song.album})" : ""}',
      );
    }
    buffer.writeln('');

    buffer.writeln('PLAYLIST HISTORY (Last 14 days):');
    for (final rec in profile.previousRecommendations.take(35)) {
      final daysAgo = DateTime.now().difference(rec.timestamp).inDays;
      buffer.writeln(
        '${rec.song.title} – ${rec.song.artist} ($daysAgo days ago)',
      );
    }
    buffer.writeln('');

    buffer.writeln(
      'Verify: Exactly 35 songs, no repetition within 7 days, aligns with taste.',
    );

    return buffer.toString();
  }

  /// Parse worker output into song list
  List<GeneratedSong> _parseWorkerOutput(String rawOutput) {
    final songs = <GeneratedSong>[];
    final lines = rawOutput.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Expected format: "Title – Artist (Album)"
      // or: "Title – Artist"

      final parts = trimmed.split('–');
      if (parts.length < 2) continue;

      final title = parts[0].trim();
      final rest = parts.sublist(1).join('–').trim();

      String artist;
      String? album;

      // Check for album in parentheses
      final albumMatch = RegExp(r'\(([^)]+)\)$').firstMatch(rest);
      if (albumMatch != null) {
        album = albumMatch.group(1);
        artist = rest.substring(0, albumMatch.start).trim();
      } else {
        artist = rest;
      }

      if (title.isNotEmpty && artist.isNotEmpty) {
        songs.add(GeneratedSong(title: title, artist: artist, album: album));
      }
    }

    return songs;
  }

  /// Validate worker output
  bool _validateWorkerOutput(PlaylistGenerationResult result) {
    // Must have exactly 35 songs
    if (result.songs.length != GatingRules.playlistSize) {
      print(
        '❌ Validation failed: ${result.songs.length} songs (expected ${GatingRules.playlistSize})',
      );
      return false;
    }

    // All songs must have title and artist
    for (final song in result.songs) {
      if (song.title.isEmpty || song.artist.isEmpty) {
        print('❌ Validation failed: Empty title or artist');
        return false;
      }
    }

    return true;
  }

  /// Persistence helpers
  Future<DateTime?> _getLastRefreshTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_playlist_refresh');
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  Future<void> _saveLastRefreshTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'last_playlist_refresh',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _savePlaylistHistory(PlaylistGenerationResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('playlist_history') ?? [];

    final timestamp = DateTime.now().toIso8601String();
    for (final song in result.songs) {
      history.insert(0, '$timestamp|${song.title}|${song.artist}');
    }

    // Keep only last 500 entries (14 days * 35 songs)
    if (history.length > 500) {
      history.removeRange(500, history.length);
    }

    await prefs.setStringList('playlist_history', history);
  }
}

/// Data models

class ListeningProfile {
  final int uniqueSongCount;
  final int distinctListeningDays;
  final List<ListeningEntry> listeningHistory;
  final List<SongData> tasteBuffer; // Last 7 days
  final List<RecommendationEntry> previousRecommendations;
  final List<String> inferredGenres;
  final String inferredEra;
  final String inferredEnergy;

  ListeningProfile({
    required this.uniqueSongCount,
    required this.distinctListeningDays,
    required this.listeningHistory,
    required this.tasteBuffer,
    required this.previousRecommendations,
    required this.inferredGenres,
    required this.inferredEra,
    required this.inferredEnergy,
  });
}

class ListeningEntry {
  final SongData song;
  final int playCount;
  final DateTime lastPlayed;

  ListeningEntry({
    required this.song,
    required this.playCount,
    required this.lastPlayed,
  });
}

class SongData {
  final String title;
  final String artist;
  final String? album;

  SongData({required this.title, required this.artist, this.album});
}

class RecommendationEntry {
  final SongData song;
  final DateTime timestamp;

  RecommendationEntry({required this.song, required this.timestamp});
}

class GeneratedSong {
  final String title;
  final String artist;
  final String? album;

  GeneratedSong({required this.title, required this.artist, this.album});
}

class PlaylistGenerationResult {
  final bool success;
  final List<GeneratedSong> songs;
  final SystemError? error;
  final int? hoursSinceLastRefresh;

  PlaylistGenerationResult._({
    required this.success,
    required this.songs,
    this.error,
    this.hoursSinceLastRefresh,
  });

  factory PlaylistGenerationResult.success(List<GeneratedSong> songs) {
    return PlaylistGenerationResult._(success: true, songs: songs);
  }

  factory PlaylistGenerationResult.error(SystemError error) {
    return PlaylistGenerationResult._(success: false, songs: [], error: error);
  }

  factory PlaylistGenerationResult.tooSoon(int hoursSinceRefresh) {
    return PlaylistGenerationResult._(
      success: false,
      songs: [],
      hoursSinceLastRefresh: hoursSinceRefresh,
    );
  }

  String get errorMessage {
    if (error != null) {
      return SystemErrorMessages.messages[error]!;
    }
    if (hoursSinceLastRefresh != null) {
      return 'Playlist refresh available in ${24 - hoursSinceLastRefresh!} hours';
    }
    return '';
  }
}
