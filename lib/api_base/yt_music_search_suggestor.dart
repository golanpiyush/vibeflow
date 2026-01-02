// lib/api_base/ytmusic_suggestions_helper.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// YouTube Music search suggestions and history manager
/// Provides real-time search suggestions and persists search history
class YTMusicSuggestionsHelper {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _musicApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _historyKey = 'ytmusic_search_history';
  static const int _maxHistoryItems = 20;

  final http.Client _httpClient;
  final Duration _timeout;

  YTMusicSuggestionsHelper({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  /// Get search suggestions from YouTube Music
  Future<List<String>> getSuggestions(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      print('💡 [YTMusicSuggestions] Getting suggestions for: "$query"');

      final uri = Uri.parse(
        '$_baseUrl/music/get_search_suggestions?key=$_musicApiKey',
      );

      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20231204.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'input': query,
      });

      final response = await _httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept': '*/*',
              'Accept-Language': 'en-US,en;q=0.9',
              'Origin': 'https://music.youtube.com',
              'Referer': 'https://music.youtube.com/',
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        print('❌ [YTMusicSuggestions] Failed: ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = _parseSuggestions(json);

      print('✅ [YTMusicSuggestions] Found ${suggestions.length} suggestions');
      return suggestions;
    } catch (e) {
      print('❌ [YTMusicSuggestions] Error: $e');
      return [];
    }
  }

  List<String> _parseSuggestions(Map<String, dynamic> json) {
    final suggestions = <String>[];

    try {
      final contents = json['contents'] as List?;
      if (contents == null) return suggestions;

      for (final item in contents) {
        final renderer = item['searchSuggestionsSectionRenderer'];
        if (renderer == null) continue;

        final suggestionItems = renderer['contents'] as List?;
        if (suggestionItems == null) continue;

        for (final suggestionItem in suggestionItems) {
          final suggestion = suggestionItem['searchSuggestionRenderer'];
          if (suggestion == null) continue;

          final runs = suggestion['suggestion']?['runs'] as List?;
          if (runs == null) continue;

          // Concatenate all text runs to form the complete suggestion
          final text = runs
              .map((run) => run['text'] as String?)
              .where((text) => text != null)
              .join('');

          if (text.isNotEmpty) {
            suggestions.add(text);
          }
        }
      }
    } catch (e) {
      print('⚠️ [YTMusicSuggestions] Parse error: $e');
    }

    return suggestions;
  }

  /// Save a search query to history
  Future<void> saveToHistory(String query) async {
    if (query.trim().isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final history = await getSearchHistory();

      // Remove if already exists (to move to top)
      history.remove(query);

      // Add to beginning
      history.insert(0, query);

      // Limit history size
      if (history.length > _maxHistoryItems) {
        history.removeRange(_maxHistoryItems, history.length);
      }

      // Save to persistent storage
      await prefs.setStringList(_historyKey, history);
      print('💾 [YTMusicSuggestions] Saved to history: "$query"');
    } catch (e) {
      print('❌ [YTMusicSuggestions] Error saving history: $e');
    }
  }

  /// Get search history
  Future<List<String>> getSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_historyKey) ?? [];
    } catch (e) {
      print('❌ [YTMusicSuggestions] Error loading history: $e');
      return [];
    }
  }

  /// Clear a specific item from history
  Future<void> removeFromHistory(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = await getSearchHistory();

      history.remove(query);
      await prefs.setStringList(_historyKey, history);

      print('🗑️ [YTMusicSuggestions] Removed from history: "$query"');
    } catch (e) {
      print('❌ [YTMusicSuggestions] Error removing from history: $e');
    }
  }

  /// Clear all search history
  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
      print('🗑️ [YTMusicSuggestions] History cleared');
    } catch (e) {
      print('❌ [YTMusicSuggestions] Error clearing history: $e');
    }
  }

  /// Get combined suggestions (history + API suggestions)
  Future<List<SearchSuggestion>> getCombinedSuggestions(String query) async {
    final results = <SearchSuggestion>[];

    // Get search history
    final history = await getSearchHistory();

    // If query is empty, return only history
    if (query.trim().isEmpty) {
      return history
          .map((text) => SearchSuggestion(text: text, isHistory: true))
          .toList();
    }

    // Filter history based on query
    final filteredHistory = history
        .where((item) => item.toLowerCase().contains(query.toLowerCase()))
        .take(5)
        .map((text) => SearchSuggestion(text: text, isHistory: true));

    results.addAll(filteredHistory);

    // Get API suggestions
    final suggestions = await getSuggestions(query);
    final apiSuggestions = suggestions
        .where((item) => !history.contains(item)) // Avoid duplicates
        .map((text) => SearchSuggestion(text: text, isHistory: false));

    results.addAll(apiSuggestions);

    return results;
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Model for search suggestions with metadata
class SearchSuggestion {
  final String text;
  final bool isHistory;

  SearchSuggestion({required this.text, required this.isHistory});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchSuggestion &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'SearchSuggestion(text: $text, isHistory: $isHistory)';
}
