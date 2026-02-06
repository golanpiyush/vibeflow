import 'dart:convert';
import 'dart:math';
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

  /// Safe way to check if orchestrator is ready
  static bool get isInitialized => _instance != null;

  static Future<MusicIntelligenceOrchestrator> init() async {
    if (_instance == null) {
      print('📂 [Init] Loading .env file...');
      await dotenv.load(fileName: ".env");

      // 🔍 DEBUG: Check all env variables
      print('📋 [Init] .env variables loaded:');
      dotenv.env.forEach((key, value) {
        if (key.contains('API')) {
          print(
            '  $key = ${value.substring(0, min(20, value.length))}... (${value.length} chars)',
          );
        } else {
          print('  $key = $value');
        }
      });

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
              'max_tokens':
                  1500, // Increased to allow both reasoning and output
              'stream': false,
            }),
          )
          .timeout(Duration(seconds: 60));

      print('📡 [Worker] Response status: ${response.statusCode}');
      print('📡 [Worker] Full response body length: ${response.body.length}');

      if (response.statusCode != 200) {
        print('❌ [Worker] API error: ${response.statusCode}');
        print('❌ [Worker] Response: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      print('📦 [Worker] Decoded JSON keys: ${data.keys.join(", ")}');

      // Check finish reason
      final finishReason = data['choices']?[0]?['finish_reason'];
      print('🏁 [Worker] Finish reason: $finishReason');

      final content = extractAssistantText(data);

      if (content == null) {
        print('❌ [Worker] No extractable text in response');
        print('❌ [Worker] Full response data: $data');
        return null;
      }

      print('📝 [Worker] Raw response received (${content.length} chars)');
      print(
        '📝 [Worker] First 500 chars: ${content.substring(0, min(500, content.length))}',
      );

      final songs = _parseWorkerOutput(content);

      print('🎵 [Worker] Parsed ${songs.length} songs');

      return PlaylistGenerationResult.success(songs);
    } catch (e, stackTrace) {
      print('❌ [Worker] Exception: $e');
      print('❌ [Worker] StackTrace: $stackTrace');
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

    print('📋 [Inspector] Prompt preview:');
    print(userPrompt.substring(0, min(500, userPrompt.length)));

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
              'max_tokens': 100,
              'stream': false,
            }),
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

      if (response.statusCode != 200) {
        print('❌ [Inspector] API error: ${response.statusCode}');
        print('❌ [Inspector] Response: ${response.body}');
        return false;
      }

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;

      if (content == null) {
        print('❌ [Inspector] Null response');
        return false;
      }

      final verdict = content.trim().toUpperCase();
      print('🔍 [Inspector] Full response: $content');
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

    buffer.writeln('Generate EXACTLY ${GatingRules.playlistSize} songs.');

    return buffer.toString();
  }

  String? extractAssistantText(dynamic data) {
    try {
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        print('❌ [Extract] No choices array or empty');
        return null;
      }

      final firstChoice = choices[0];
      if (firstChoice is! Map) {
        print('❌ [Extract] First choice is not a Map');
        return null;
      }

      final message = firstChoice['message'];
      if (message == null) {
        print('❌ [Extract] No message in choice');
        return null;
      }

      final content = message['content'];
      final reasoning = message['reasoning'];

      print('🔍 [Extract] Content type: ${content.runtimeType}');
      print('🔍 [Extract] Content length: ${content?.toString().length ?? 0}');
      print('🔍 [Extract] Has reasoning: ${reasoning != null}');

      // Case 1: Standard content exists and is non-empty
      if (content is String && content.trim().isNotEmpty) {
        final trimmed = content.trim();
        print('✅ [Extract] Extracted string content (${trimmed.length} chars)');
        return trimmed;
      }

      // Case 2: Content is empty but reasoning exists (reasoning model behavior)
      // This happens when the model uses all tokens for reasoning
      if ((content == null || (content is String && content.trim().isEmpty)) &&
          reasoning is String &&
          reasoning.trim().isNotEmpty) {
        print('⚠️ [Extract] Content empty, reasoning present');
        print(
          '⚠️ [Extract] This indicates token limit was reached during reasoning',
        );
        print(
          '⚠️ [Extract] Reasoning preview: ${reasoning.substring(0, min(200, reasoning.length))}',
        );

        // Try to extract songs from reasoning if they're there
        // Sometimes the model includes the list in reasoning
        if (reasoning.contains('–') && reasoning.contains('\n')) {
          print('🔍 [Extract] Attempting to parse songs from reasoning field');
          return reasoning.trim();
        }

        return null;
      }

      // Case 3: OSS / OpenInference structured blocks
      if (content is List) {
        print('📋 [Extract] Content is List with ${content.length} items');
        final buffer = StringBuffer();
        for (var i = 0; i < content.length; i++) {
          final block = content[i];
          if (block is Map) {
            if (block['text'] is String) {
              buffer.writeln(block['text']);
            } else if (block['type'] == 'text' && block['text'] is String) {
              buffer.writeln(block['text']);
            }
          } else if (block is String) {
            buffer.writeln(block);
          }
        }
        final text = buffer.toString().trim();
        if (text.isNotEmpty) {
          print('✅ [Extract] Extracted from List (${text.length} chars)');
          return text;
        }
      }

      // Case 4: Map with text field
      if (content is Map) {
        print(
          '📦 [Extract] Content is Map with keys: ${content.keys.join(", ")}',
        );
        if (content['text'] is String) {
          final text = (content['text'] as String).trim();
          if (text.isNotEmpty) {
            print('✅ [Extract] Extracted from Map.text (${text.length} chars)');
            return text;
          }
        }
      }

      print('❌ [Extract] No valid content found');
      return null;
    } catch (e, stackTrace) {
      print('❌ [Extract] Exception: $e');
      print('❌ [Extract] StackTrace: $stackTrace');
      return null;
    }
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
    for (final rec in profile.previousRecommendations.take(
      GatingRules.playlistSize,
    )) {
      final daysAgo = DateTime.now().difference(rec.timestamp).inDays;
      buffer.writeln(
        '${rec.song.title} – ${rec.song.artist} ($daysAgo days ago)',
      );
    }
    buffer.writeln('');

    buffer.writeln(
      'Verify: Exactly ${GatingRules.playlistSize} songs, no repetition within 7 days, aligns with taste.',
    );

    return buffer.toString();
  }

  /// Parse worker output into song list
  /// Parse worker output into song list
  List<GeneratedSong> _parseWorkerOutput(String rawOutput) {
    final songs = <GeneratedSong>[];
    final lines = rawOutput.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();

      // Skip empty lines
      if (trimmed.isEmpty) continue;

      // Skip lines that don't contain the separator
      if (!trimmed.contains('–')) continue;

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

      // Only add if we have valid title and artist
      if (title.isNotEmpty && artist.isNotEmpty) {
        songs.add(GeneratedSong(title: title, artist: artist, album: album));
      }
    }

    print('🎵 [Parser] Total songs parsed: ${songs.length}');

    // Debug: print all parsed songs
    for (var i = 0; i < songs.length; i++) {
      print('  ${i + 1}. ${songs[i].title} – ${songs[i].artist}');
    }

    return songs;
  }

  /// Validate worker output
  bool _validateWorkerOutput(PlaylistGenerationResult result) {
    final minSongs = GatingRules.playlistSize - 1;
    final maxSongs = GatingRules.playlistSize + 1;

    if (result.songs.length < minSongs || result.songs.length > maxSongs) {
      print(
        '❌ Validation failed: ${result.songs.length} songs (expected ${GatingRules.playlistSize}, allowed ${minSongs}-${maxSongs})',
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

    // Trim if needed
    if (result.songs.length > GatingRules.playlistSize) {
      print(
        '⚠️ Trimming playlist from ${result.songs.length} to ${GatingRules.playlistSize} songs',
      );
      result.songs.removeRange(GatingRules.playlistSize, result.songs.length);
    }

    print('✅ Validation passed: ${result.songs.length} songs');
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
