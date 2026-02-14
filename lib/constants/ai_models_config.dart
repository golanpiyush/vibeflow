import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AI Model Configuration for Music Intelligence System
/// Models are accessed via OpenRouter API
/// API key must be stored in .env file as OPENROUTER_API_KEY

class AiModels {
  // Orchestrator: Enforces rules, dispatches tasks, validates responses
  static const String orchestrator = 'anthropic/claude-sonnet-4';

  // Primary Worker: Infers taste, generates playlists
  static const String primaryWorker = 'mistralai/mistral-7b-instruct';

  // Inspector: Validates worker output, has veto authority
  static const String inspector = 'google/gemma-2-9b-it';
}

class SystemPrompts {
  /// System prompt for PRIMARY WORKER AI
  /// This AI infers taste and generates playlists.
  static const String primaryWorker = '''
You are a music taste inference engine.

You do not chat.
You do not explain.
You do not justify.

You receive:
- Verified listening history (already validated by orchestrator)
- A rolling taste buffer from recent listening
- A list of previously recommended songs with timestamps

Rules:
- Recommend EXACTLY 8 songs
- Never repeat a song recommended within the last 7 days
- Prefer album tracks, deep cuts, and culturally respected music
- Avoid viral, chart-driven, or generic algorithmic picks
- Stay within demonstrated genre, era, mood, and energy
- Do NOT hallucinate artists or metadata
- If unsure, omit the song

Output format ONLY:
Title – Artist (Album if known)

No commentary.
No markdown.
No explanations.
''';

  /// System prompt for INSPECTOR AI
  /// This AI validates worker output with veto power.
  static const String inspector = '''
You are a strict inspector with veto power.

You receive:
- User taste profile
- Proposed playlist
- Playlist history for the last 14 days

You must verify ALL:
1. Exactly 8 songs exist
2. No songs repeated from the last 7 days of recommendations
3. Playlist aligns with demonstrated taste
4. No unexplained genre or era deviation
5. No fabricated or hallucinated artists

Rules:
- You may NOT fix anything
- You may NOT suggest alternatives

If ANY rule fails:
Respond ONLY with:
REJECT

If ALL rules pass:
Respond ONLY with:
APPROVE
''';
}

class GatingRules {
  // Minimum unique songs required before AI activation
  static const int minUniqueSongs = 35;

  // Minimum distinct listening days required
  static const int minListeningDays = 7;

  // Exact playlist size
  static const int playlistSize = 8;

  // Maximum repetition window (days)
  static const int repetitionWindowDays = 7;

  // Maximum songs that can repeat within window
  static const int maxRepeatsInWindow = 2;

  // Playlist refresh interval (hours)
  static const int refreshIntervalHours = 24;
}

class ApiConfig {
  /// OpenRouter API endpoint
  static String get baseUrl =>
      dotenv.env['OPENROUTER_BASE_URL'] ?? 'https://openrouter.ai/api/v1';

  /// API Key environment variable name (just the key name, not the value)
  static const String apiKeyEnvVar = 'OPENROUTER_API_KEY';

  /// Request timeout (seconds)
  static int get timeoutSeconds =>
      int.tryParse(dotenv.env['OPENROUTER_TIMEOUT_SECONDS'] ?? '') ?? 60;

  /// Max retries (HARD LOCKED — DO NOT CHANGE)
  static const int maxRetries = 0;
}

enum SystemError {
  insufficientListeningData,
  insufficientListeningDays,
  emptyListeningHistory,
  tasteProfileMissing,
  workerOutputInvalid,
  workerOutputEmpty,
  inspectorRejected,
  apiCallFailed,
  apiTimeout,
  internalError,
}

class SystemErrorMessages {
  static const Map<SystemError, String> messages = {
    SystemError.insufficientListeningData:
        'InternalSystemError: Unique songs < 35',
    SystemError.insufficientListeningDays:
        'InternalSystemError: Listening days < 7',
    SystemError.emptyListeningHistory:
        'InternalSystemError: Listening history empty',
    SystemError.tasteProfileMissing:
        'InternalSystemError: Taste profile buffer missing',
    SystemError.workerOutputInvalid:
        'InternalSystemError: Worker output format invalid',
    SystemError.workerOutputEmpty:
        'InternalSystemError: Worker returned empty response',
    SystemError.inspectorRejected:
        'InternalSystemError: Inspector rejected playlist',
    SystemError.apiCallFailed: 'InternalSystemError: VibeFlowAI call failed',
    SystemError.apiTimeout: 'InternalSystemError: VibeFlowAI timed out',
    SystemError.internalError: 'InternalSystemError: Unknown failure',
  };
}
