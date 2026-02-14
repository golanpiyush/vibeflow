// lib/services/spotify_import_service.dart
// Uses: Web scraping of open.spotify.com/embed/playlist/{id}
// Searches YouTube for each Spotify track using youtube_explode_dart

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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
  final String id;
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
  static const _baseEmbedUrl = 'https://open.spotify.com/embed/playlist';
  final YoutubeExplode _ytExplode = YoutubeExplode();

  // ── URL Parsing & Validation ──────────────────────────────────────────────

  String? extractPlaylistId(String input) {
    input = input.trim();

    // spotify:playlist:ID
    final uriMatch = RegExp(
      r'^spotify:playlist:([a-zA-Z0-9]+)$',
    ).firstMatch(input);
    if (uriMatch != null) return uriMatch.group(1);

    // https://open.spotify.com/playlist/ID  (with optional intl prefix)
    final urlMatch = RegExp(
      r'open\.spotify\.com/(?:intl-[a-z-]+/)?playlist/([a-zA-Z0-9]+)',
    ).firstMatch(input);
    if (urlMatch != null) return urlMatch.group(1);

    // Bare 22-char alphanumeric ID
    if (RegExp(r'^[a-zA-Z0-9]{22}$').hasMatch(input)) return input;

    return null;
  }

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
    if (extractPlaylistId(input) == null) {
      throw const SpotifyImportException(
        SpotifyImportError.invalidLink,
        'Invalid Spotify link. Paste a link like:\nhttps://open.spotify.com/playlist/...',
      );
    }
  }

  // ── Main Import ───────────────────────────────────────────────────────────

  // ── Main Import ─────────────────────────────────────────────────────────
  Future<SpotifyPlaylistData> importPlaylist(
    String link, {
    Function(int current, int total, String trackName)? onProgress,
  }) async {
    _validateLink(link);
    final playlistId = extractPlaylistId(link)!;
    debugPrint('🎵 Importing playlist ID: $playlistId');

    // Fetch the embed page and extract JSON data
    final embedUrl = '$_baseEmbedUrl/$playlistId';
    debugPrint('🌐 Fetching embed URL: $embedUrl');
    final response = await _get(embedUrl);
    final htmlContent = response.body;

    // Parse the HTML to find the embedded JSON data
    final playlistData = await _extractPlaylistData(htmlContent, onProgress);
    debugPrint('✅ Successfully parsed playlist data');

    return playlistData;
  }

  // ── NEW: Import with YouTube Video IDs ──────────────────────────────────
  Future<Map<String, String?>> importPlaylistWithYouTube(
    String link, {
    Function(int current, int total, String trackName)? onProgress,
  }) async {
    // Step 1: Get Spotify playlist data
    final playlist = await importPlaylist(link);

    // Step 2: Batch-fetch YouTube video IDs
    debugPrint(
      '🔍 Fetching YouTube video IDs for ${playlist.tracks.length} tracks...',
    );
    final youtubeIds = await _batchFetchYouTubeIds(
      playlist.tracks,
      concurrency: 10, // Adjust based on your needs
      onProgress: onProgress,
    );

    // Step 3: Create mapping: Spotify Track ID -> YouTube Video ID
    final Map<String, String?> trackMapping = {};
    for (int i = 0; i < playlist.tracks.length; i++) {
      trackMapping[playlist.tracks[i].id] = youtubeIds[i];
    }

    debugPrint(
      '✅ Found ${youtubeIds.where((id) => id != null).length}/${playlist.tracks.length} YouTube matches',
    );
    return trackMapping;
  }

  // ── Batch YouTube Search ────────────────────────────────────────────────
  Future<List<String?>> _batchFetchYouTubeIds(
    List<SpotifyTrackData> tracks, {
    int concurrency = 10,
    Function(int current, int total, String trackName)? onProgress,
  }) async {
    final results = <String?>[];

    for (int i = 0; i < tracks.length; i += concurrency) {
      final batch = tracks.skip(i).take(concurrency).toList();

      // Fetch this batch in parallel
      final batchResults = await Future.wait(
        batch.map((track) => _searchYouTubeForTrack(track)),
      );

      results.addAll(batchResults);

      // Report progress
      if (onProgress != null && results.isNotEmpty) {
        final lastTrack = batch.last;
        onProgress(
          results.length,
          tracks.length,
          '${lastTrack.title} - ${lastTrack.artists.join(", ")}',
        );
      }
    }

    return results;
  }

  // ── Search YouTube for Single Track ─────────────────────────────────────
  Future<String?> _searchYouTubeForTrack(SpotifyTrackData track) async {
    try {
      // Build optimized search query
      final query = '${track.artists.join(" ")} ${track.title} audio';
      debugPrint('🔎 Searching: $query');

      final searchResults = await _ytExplode.search.search(query);

      if (searchResults.isEmpty) {
        debugPrint('❌ No results for: ${track.title}');
        return null;
      }

      final videoId = searchResults.first.id.value;
      debugPrint('✅ Found: ${track.title} -> $videoId');
      return videoId;
    } catch (e) {
      debugPrint('❌ Error searching for ${track.title}: $e');
      return null;
    }
  }
  // ── Parse embed page HTML ─────────────────────────────────────────────────

  // ── Parse embed page HTML ─────────────────────────────────────────────────

  Future<SpotifyPlaylistData> _extractPlaylistData(
    String htmlContent,
    Function(int current, int total, String trackName)? onProgress,
  ) async {
    try {
      final document = html_parser.parse(htmlContent);
      final scriptTag = document.getElementById('__NEXT_DATA__');

      if (scriptTag == null) {
        throw const SpotifyImportException(
          SpotifyImportError.parseError,
          'Unable to parse playlist data. The page structure may have changed.',
        );
      }

      final jsonText = scriptTag.text;
      final jsonData = jsonDecode(jsonText) as Map<String, dynamic>;

      final props = jsonData['props'] as Map<String, dynamic>?;
      final pageProps = props?['pageProps'] as Map<String, dynamic>?;
      final state = pageProps?['state'] as Map<String, dynamic>?;
      final data = state?['data'] as Map<String, dynamic>?;
      final entity = data?['entity'] as Map<String, dynamic>?;

      if (entity == null) {
        throw const SpotifyImportException(
          SpotifyImportError.parseError,
          'Unable to extract playlist information.',
        );
      }

      // ═══════════════════════════════════════════════════════════════════════
      // DEBUG: Print the entire entity structure to find the correct paths
      // ═══════════════════════════════════════════════════════════════════════
      debugPrint('🔍 DEBUG: Entity keys: ${entity.keys.toList()}');

      // Check owner fields
      if (entity.containsKey('owner')) {
        debugPrint('🔍 DEBUG: owner = ${entity['owner']}');
      }
      if (entity.containsKey('ownerV2')) {
        debugPrint('🔍 DEBUG: ownerV2 = ${entity['ownerV2']}');
      }
      if (entity.containsKey('authors')) {
        debugPrint('🔍 DEBUG: authors = ${entity['authors']}');
      }

      // Check first track structure
      final trackList = entity['trackList'] as List<dynamic>? ?? [];
      if (trackList.isNotEmpty) {
        final firstTrack = trackList[0] as Map<String, dynamic>;
        debugPrint('🔍 DEBUG: First track keys: ${firstTrack.keys.toList()}');
        debugPrint('🔍 DEBUG: First track data: $firstTrack');
      }
      // ═══════════════════════════════════════════════════════════════════════

      final playlistId = entity['uri']?.toString().split(':').last ?? '';
      final playlistName = entity['name'] as String? ?? 'Untitled Playlist';
      final description = entity['description'] as String?;

      debugPrint('📋 Playlist: $playlistName');

      // Owner extraction with multiple fallbacks
      String ownerName = 'Unknown';

      // Try ownerV2.data.name
      final ownerV2 = entity['ownerV2'] as Map<String, dynamic>?;
      final ownerData = ownerV2?['data'] as Map<String, dynamic>?;
      if (ownerData?['name'] != null) {
        ownerName = ownerData!['name'] as String;
        debugPrint('👤 Owner from ownerV2: $ownerName');
      } else {
        // Try owner.name
        final owner = entity['owner'] as Map<String, dynamic>?;
        if (owner?['name'] != null) {
          ownerName = owner!['name'] as String;
          debugPrint('👤 Owner from owner: $ownerName');
        } else {
          // Try authors[0].name
          final authors = entity['authors'] as List<dynamic>?;
          if (authors != null && authors.isNotEmpty) {
            final firstAuthor = authors.first as Map<String, dynamic>?;
            if (firstAuthor?['name'] != null) {
              ownerName = firstAuthor!['name'] as String;
              debugPrint('👤 Owner from authors: $ownerName');
            }
          }
        }
      }

      // Playlist cover
      final coverArt = entity['coverArt'] as Map<String, dynamic>?;
      final coverSources = coverArt?['sources'] as List<dynamic>?;
      String? coverImageUrl;
      if (coverSources != null && coverSources.isNotEmpty) {
        final largestCover = coverSources.last as Map<String, dynamic>?;
        coverImageUrl = largestCover?['url'] as String?;
      }

      debugPrint('📝 Found ${trackList.length} tracks in playlist');

      // Collect track metadata
      final spotifyTracks = <Map<String, dynamic>>[];

      for (int i = 0; i < trackList.length; i++) {
        try {
          final trackData = trackList[i] as Map<String, dynamic>;

          final trackName = trackData['title'] as String? ?? 'Unknown Title';
          final subtitle = trackData['subtitle'] as String? ?? '';
          final artists = subtitle.isNotEmpty
              ? subtitle.split(',').map((a) => a.trim()).toList()
              : ['Unknown Artist'];
          final durationMs = trackData['duration'] as int? ?? 0;

          // Extract track's album art
          String? trackAlbumArt;
          final trackImage = trackData['image'] as Map<String, dynamic>?;

          if (trackImage != null) {
            debugPrint('🔍 DEBUG: Track $i image structure: $trackImage');
          }

          final trackImageSources = trackImage?['sources'] as List<dynamic>?;
          if (trackImageSources != null && trackImageSources.isNotEmpty) {
            final largestImage =
                trackImageSources.last as Map<String, dynamic>?;
            trackAlbumArt = largestImage?['url'] as String?;
            debugPrint('🖼️ Track $i album art: $trackAlbumArt');
          }

          // Extract album name
          String albumName = 'Unknown Album';
          final metadata = trackData['metadata'] as Map<String, dynamic>?;

          if (metadata != null) {
            debugPrint('🔍 DEBUG: Track $i metadata: $metadata');
          }

          if (metadata?['album_title'] != null) {
            albumName = metadata!['album_title'] as String;
          } else if (metadata?['album'] != null) {
            albumName = metadata!['album'] as String;
          }

          spotifyTracks.add({
            'title': trackName,
            'artists': artists,
            'durationMs': durationMs,
            'albumArt': trackAlbumArt,
            'album': albumName,
            'index': i,
          });
        } catch (e) {
          debugPrint('⚠️ Skipped malformed track at index $i: $e');
          continue;
        }
      }

      // Search YouTube for tracks
      final tracksList = <SpotifyTrackData>[];
      int successCount = 0;
      int failCount = 0;

      for (int i = 0; i < spotifyTracks.length; i++) {
        try {
          final track = spotifyTracks[i];
          final trackName = track['title'] as String;
          final artists = track['artists'] as List<String>;
          final durationMs = track['durationMs'] as int;
          final trackAlbumArt = track['albumArt'] as String?;
          final albumName = track['album'] as String;
          final index = track['index'] as int;

          onProgress?.call(i + 1, spotifyTracks.length, trackName);

          final searchQuery = '$trackName ${artists.join(' ')}';
          debugPrint(
            '🔍 [${i + 1}/${spotifyTracks.length}] Searching: $searchQuery',
          );

          String? youtubeVideoId;
          try {
            final searchResults = await _ytExplode.search.search(searchQuery);

            if (searchResults.isNotEmpty) {
              youtubeVideoId = searchResults.first.id.value;
              debugPrint('   ✅ Found: ${searchResults.first.title}');
              debugPrint('   📹 Video ID: $youtubeVideoId');
              successCount++;
            } else {
              debugPrint('   ⚠️ No search results');
              failCount++;
            }
          } catch (searchError) {
            debugPrint('   ❌ Search failed: $searchError');
            failCount++;
          }

          if (youtubeVideoId == null || youtubeVideoId.isEmpty) {
            debugPrint('   ⏭️ Skipping - no YouTube match');
            continue;
          }

          tracksList.add(
            SpotifyTrackData(
              id: youtubeVideoId,
              title: trackName,
              artists: artists,
              album: albumName,
              albumArtUrl:
                  trackAlbumArt ?? coverImageUrl, // Fallback to playlist cover
              duration: Duration(milliseconds: durationMs),
              addedAt: null,
              trackNumber: index + 1,
            ),
          );
        } catch (e, st) {
          debugPrint('❌ Error processing track: $e');
          debugPrint('   $st');
          failCount++;
          continue;
        }
      }

      final totalDuration = tracksList.fold<Duration>(
        Duration.zero,
        (sum, t) => sum + t.duration,
      );

      debugPrint('🎉 Import complete:');
      debugPrint('   ✅ Success: $successCount tracks');
      debugPrint('   ❌ Failed: $failCount tracks');
      debugPrint('   📊 Total: ${tracksList.length} tracks imported');

      return SpotifyPlaylistData(
        id: playlistId,
        name: playlistName,
        description: description?.isNotEmpty == true ? description : null,
        coverImageUrl: coverImageUrl,
        ownerName: ownerName,
        totalTracks: tracksList.length,
        totalDuration: totalDuration,
        addedAt: null,
        isPublic: true,
        tracks: tracksList,
      );
    } catch (e, st) {
      if (e is SpotifyImportException) rethrow;
      debugPrint('❌ Parse error: $e');
      debugPrint('   $st');
      throw SpotifyImportException(
        SpotifyImportError.parseError,
        'Failed to parse playlist data: ${e.toString()}',
      );
    }
  }

  // ── Shared HTTP helper ────────────────────────────────────────────────────

  Future<http.Response> _get(String url) async {
    try {
      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      };

      final response = await http.get(Uri.parse(url), headers: headers);
      debugPrint('📡 ${response.statusCode} $url');

      if (response.statusCode == 200) return response;

      // Non-200 — throw a typed exception
      debugPrint('❌ HTTP ${response.statusCode}');
      switch (response.statusCode) {
        case 403:
          throw const SpotifyImportException(
            SpotifyImportError.privatePlaylist,
            'This playlist is private or restricted.',
          );
        case 404:
          throw const SpotifyImportException(
            SpotifyImportError.notFound,
            'Playlist not found. Check the link and try again.',
          );
        case 429:
          throw const SpotifyImportException(
            SpotifyImportError.rateLimited,
            'Too many requests. Please wait a moment and try again.',
          );
        default:
          throw SpotifyImportException(
            SpotifyImportError.unknown,
            'Unexpected error (${response.statusCode}). Please try again.',
          );
      }
    } catch (e) {
      if (e is SpotifyImportException) rethrow;
      debugPrint('❌ Network error: $e');
      throw const SpotifyImportException(
        SpotifyImportError.networkError,
        'Network error. Please check your internet connection.',
      );
    }
  }

  // Cleanup
  void dispose() {
    _ytExplode.close();
  }
}
