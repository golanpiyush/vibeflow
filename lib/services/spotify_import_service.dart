// lib/services/spotify_import_service.dart
// Uses: Backend API (yt-dlp) for Spotify → YouTube conversion

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public data models
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyPlaylistData {
  final String id;
  final String name;
  final String? description;
  final String? coverImageUrl;
  final String ownerName;
  final int totalTracks;
  final Duration totalDuration;
  final DateTime? addedAt;
  final bool? isPublic;
  final List<SpotifyTrackData> tracks;

  const SpotifyPlaylistData({
    required this.id,
    required this.name,
    this.description,
    this.coverImageUrl,
    required this.ownerName,
    required this.totalTracks,
    required this.totalDuration,
    this.addedAt,
    this.isPublic,
    required this.tracks,
  });
}

class SpotifyTrackData {
  final String id; // YouTube video ID
  final String title;
  final List<String> artists;
  final String album;
  final String? albumArtUrl;
  final Duration duration;
  final DateTime? addedAt;
  final int trackNumber;

  const SpotifyTrackData({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    this.albumArtUrl,
    required this.duration,
    this.addedAt,
    required this.trackNumber,
  });
}

enum SpotifyImportError {
  invalidLink,
  notAPlaylist,
  privatePlaylist,
  notFound,
  rateLimited,
  authFailed,
  networkError,
  parseError,
  serverUnavailable,
  unknown,
}

class SpotifyImportException implements Exception {
  final SpotifyImportError error;
  final String message;
  const SpotifyImportException(this.error, this.message);

  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyImportService {
  // Get API URL from environment variable
  static String get _apiBaseUrl {
    final url = dotenv.env['VIBEFLOW_SONG_ID_CONVERTER_SERVER'];
    if (url == null || url.isEmpty) {
      throw Exception('VIBEFLOW_SONG_ID_CONVERTER_SERVER not set in .env file');
    }
    return url;
  }

  // ── URL Validation ──────────────────────────────────────────────────────

  void _validateLink(String input) {
    if (input.contains('spotify.com/track/') ||
        input.contains('spotify:track:')) {
      throw const SpotifyImportException(
        SpotifyImportError.notAPlaylist,
        'That link is a song, not a playlist. Please paste a playlist link.',
      );
    }
    if (input.contains('spotify.com/album/') ||
        input.contains('spotify:album:')) {
      throw const SpotifyImportException(
        SpotifyImportError.notAPlaylist,
        'That link is an album, not a playlist. Please paste a playlist link.',
      );
    }
    if (input.contains('spotify.com/artist/') ||
        input.contains('spotify:artist:')) {
      throw const SpotifyImportException(
        SpotifyImportError.notAPlaylist,
        'That link is an artist page, not a playlist.',
      );
    }
    if (!input.contains('spotify.com/playlist/') &&
        !input.contains('spotify:playlist:')) {
      throw const SpotifyImportException(
        SpotifyImportError.invalidLink,
        'Invalid Spotify link. Paste a link like:\nhttps://open.spotify.com/playlist/...',
      );
    }
  }

  // ── Main Import ─────────────────────────────────────────────────────────

  Future<SpotifyPlaylistData> importPlaylist(
    String link, {
    Function(int current, int total, String trackName)? onProgress,
  }) async {
    _validateLink(link);

    debugPrint('🎵 Importing playlist via backend: $link');
    debugPrint('🌐 Backend URL: $_apiBaseUrl');

    try {
      // Show initial progress
      onProgress?.call(0, 100, 'Connecting to server...');

      // Send Spotify URL to backend
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/playlist'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': link}),
          )
          .timeout(
            const Duration(seconds: 120), // 2 minute timeout
            onTimeout: () {
              throw const SpotifyImportException(
                SpotifyImportError.serverUnavailable,
                'Request timed out. The server may be waking up (Render free tier cold start). Please wait 30 seconds and try again.',
              );
            },
          );

      debugPrint('📡 Response status: ${response.statusCode}');

      // Handle different status codes
      if (response.statusCode == 404) {
        throw const SpotifyImportException(
          SpotifyImportError.notFound,
          'Playlist not found. Check the link and try again.',
        );
      }

      if (response.statusCode == 403) {
        throw const SpotifyImportException(
          SpotifyImportError.privatePlaylist,
          'This playlist is private or restricted.',
        );
      }

      if (response.statusCode == 500) {
        debugPrint('❌ Backend error: ${response.body}');
        throw const SpotifyImportException(
          SpotifyImportError.parseError,
          'Backend error while processing playlist. Please try again.',
        );
      }

      if (response.statusCode != 200) {
        debugPrint('❌ Unexpected status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        throw SpotifyImportException(
          SpotifyImportError.networkError,
          'Backend error (${response.statusCode}). Please try again.',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Check if there was an error
      if (data.containsKey('error')) {
        throw SpotifyImportException(
          SpotifyImportError.parseError,
          data['error'] as String,
        );
      }

      // Extract playlist info
      final playlistInfo = data['playlist'] as Map<String, dynamic>?;
      if (playlistInfo == null) {
        throw const SpotifyImportException(
          SpotifyImportError.parseError,
          'Invalid response from backend',
        );
      }

      final playlistName =
          playlistInfo['name'] as String? ?? 'Unknown Playlist';
      final playlistId = playlistInfo['id'] as String? ?? '';

      debugPrint('📋 Playlist: $playlistName');

      // Extract tracks
      final results = data['results'] as List<dynamic>? ?? [];
      final tracksList = <SpotifyTrackData>[];
      int skippedCount = 0;

      for (int i = 0; i < results.length; i++) {
        final result = results[i] as Map<String, dynamic>;

        final title = result['title'] as String? ?? 'Unknown';
        final artists =
            (result['artists'] as List?)?.cast<String>() ?? ['Unknown Artist'];

        // Extract YouTube video ID from backend response
        // The backend should return 'videoId' or 'youtubeId'
        String? youtubeId = result['videoId'] as String?;
        youtubeId ??= result['youtubeId'] as String?;

        final success = result['success'] as bool? ?? false;

        // Skip failed tracks or invalid video IDs
        if (!success || youtubeId == null || youtubeId.isEmpty) {
          debugPrint('⏭️ Skipping: $title (${result['error'] ?? 'no match'})');
          skippedCount++;
          continue;
        }

        // ✅ CRITICAL: Validate that this is a real YouTube video ID, not a Spotify ID
        if (youtubeId.startsWith('spotify:') ||
            youtubeId.startsWith('spotify-') ||
            youtubeId.contains('spotify')) {
          debugPrint(
            '⚠️ Skipping: $title - Invalid video ID (still a Spotify ID: $youtubeId)',
          );
          skippedCount++;
          continue;
        }

        // YouTube video IDs are typically 11 characters (basic validation)
        if (youtubeId.length < 10 || youtubeId.length > 15) {
          debugPrint(
            '⚠️ Skipping: $title - Suspicious video ID format: $youtubeId (length: ${youtubeId.length})',
          );
          skippedCount++;
          continue;
        }

        debugPrint('✅ Track ${i + 1}: $title -> YT:$youtubeId');

        tracksList.add(
          SpotifyTrackData(
            id: youtubeId, // ✅ VALIDATED YOUTUBE VIDEO ID
            title: title,
            artists: artists,
            album:
                result['album'] as String? ??
                (artists.isNotEmpty ? artists.first : 'Unknown Album'),
            albumArtUrl: result['albumArt'] as String?,
            duration: Duration(
              seconds: (result['duration'] as num?)?.toInt() ?? 0,
            ),
            addedAt: null,
            trackNumber: i + 1,
          ),
        );
      }

      if (tracksList.isEmpty) {
        throw SpotifyImportException(
          SpotifyImportError.parseError,
          'No tracks could be converted to YouTube videos. Backend may not be returning valid video IDs. Total tracks: ${results.length}, Skipped: $skippedCount',
        );
      }

      final summary = data['summary'] as Map<String, dynamic>?;
      final successful = summary?['successful'] as int? ?? tracksList.length;
      final total = summary?['total'] as int? ?? tracksList.length;

      debugPrint(
        '✅ Import complete: $successful/$total tracks (skipped: $skippedCount)',
      );

      final totalDuration = tracksList.fold<Duration>(
        Duration.zero,
        (sum, t) => sum + t.duration,
      );

      return SpotifyPlaylistData(
        id: playlistId,
        name: playlistName,
        description: playlistInfo['description'] as String?,
        coverImageUrl:
            playlistInfo['coverImageUrl'] as String? ??
            (tracksList.isNotEmpty ? tracksList.first.albumArtUrl : null),
        ownerName: playlistInfo['owner'] as String? ?? 'Spotify User',
        totalTracks: tracksList.length,
        totalDuration: totalDuration,
        addedAt: DateTime.now(),
        isPublic: true,
        tracks: tracksList,
      );
    } on SpotifyImportException {
      rethrow;
    } catch (e, st) {
      debugPrint('❌ Import failed: $e');
      debugPrint('Stack trace: $st');
      throw SpotifyImportException(
        SpotifyImportError.networkError,
        'Failed to import playlist: ${e.toString()}',
      );
    }
  }

  // No cleanup needed (no YoutubeExplode instance)
  void dispose() {}
}
