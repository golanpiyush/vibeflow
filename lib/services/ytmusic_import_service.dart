// lib/services/ytmusic_import_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/constants/theme_colors.dart';

class YTMusicPlaylistData {
  final String id;
  final String name;
  final String? description;
  final String? coverImageUrl;
  final String ownerName;
  final int totalTracks;
  final Duration totalDuration;
  final List<YTMusicTrackData> tracks;
  final DateTime? addedAt;

  YTMusicPlaylistData({
    required this.id,
    required this.name,
    this.description,
    this.coverImageUrl,
    required this.ownerName,
    required this.totalTracks,
    required this.totalDuration,
    required this.tracks,
    this.addedAt,
  });
}

class YTMusicTrackData {
  final String id; // videoId
  final String title;
  final List<String> artists;
  final String? albumArtUrl;
  final Duration duration;
  final DateTime? addedAt;

  YTMusicTrackData({
    required this.id,
    required this.title,
    required this.artists,
    this.albumArtUrl,
    required this.duration,
    this.addedAt,
  });
}

class YTMusicImportException implements Exception {
  final String message;
  YTMusicImportException(this.message);
  @override
  String toString() => 'YTMusicImportException: $message';
}

class YTMusicImportService {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _musicApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _webApiKey = 'AIzaSyDCUpxhZ5MdW6hW1g5Jk2fLWxy3M22axVU';

  final http.Client _httpClient;
  final Duration _timeout;
  final Ref _ref; // Add Riverpod ref for theme access

  YTMusicImportService({
    required Ref ref, // Make ref required
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout,
       _ref = ref;

  /// Get theme-aware text styles for logging/UI messages
  TextStyle _getThemeAwareTextStyle() {
    final textPrimary = _ref.read(themeTextPrimaryColorProvider);
    return TextStyle(color: textPrimary);
  }

  /// Check if the input is a Spotify link
  bool _isSpotifyLink(String input) {
    return input.contains('spotify.com') ||
        input.contains('open.spotify.com') ||
        input.contains('spoti.fi');
  }

  /// Import a YouTube Music playlist from URL or ID (updated error handling)
  Future<YTMusicPlaylistData> importPlaylist(String input) async {
    try {
      debugPrint('🎵 [YTMusicImport] Importing playlist: $input');

      // Check if user pasted a Spotify link
      if (_isSpotifyLink(input)) {
        throw YTMusicImportException(
          'This is a Spotify playlist link. Please use the Spotify import button instead.',
        );
      }

      // Extract playlist ID from URL if needed
      final playlistId = _extractPlaylistId(input);
      if (playlistId == null) {
        throw YTMusicImportException(
          'Invalid YouTube Music playlist URL or ID',
        );
      }

      debugPrint('🔍 [YTMusicImport] Playlist ID: $playlistId');

      // Get playlist details (with fallback)
      final playlistData = await _fetchPlaylistDetails(playlistId);

      // Even if details fetch fails, continue with tracks
      final name = playlistData?['name'] ?? 'Imported Playlist';
      final description = playlistData?['description'];
      final coverUrl = playlistData?['coverUrl'];
      final owner = playlistData?['owner'] ?? 'Unknown';

      debugPrint('📋 [YTMusicImport] Playlist: "$name" by $owner');

      // Get playlist items (tracks) - this is the critical part
      final tracks = await _fetchPlaylistTracks(playlistId);

      if (tracks.isEmpty) {
        throw YTMusicImportException(
          'No tracks found. Make sure the playlist is public.',
        );
      }

      // Calculate total duration
      final totalDuration = tracks.fold<Duration>(
        Duration.zero,
        (sum, track) => sum + track.duration,
      );

      debugPrint(
        '✅ [YTMusicImport] Successfully imported ${tracks.length} tracks',
      );

      return YTMusicPlaylistData(
        id: playlistId,
        name: name,
        description: description,
        coverImageUrl: coverUrl,
        ownerName: owner,
        totalTracks: tracks.length,
        totalDuration: totalDuration,
        tracks: tracks,
        addedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('❌ [YTMusicImport] Error: $e');
      if (e is YTMusicImportException) rethrow;
      throw YTMusicImportException(
        'Failed to import playlist. Make sure it\'s public and the link is correct.',
      );
    }
  }

  /// Extract playlist ID from various URL formats
  String? _extractPlaylistId(String input) {
    // Handle direct ID
    if (!input.contains('youtube.com') && !input.contains('youtu.be')) {
      return input.trim();
    }

    // YouTube Music URL patterns
    final patterns = [
      RegExp(r'[&?]list=([^&]+)'),
      RegExp(r'/playlist\?list=([^&]+)'),
      RegExp(r'/playlist/([^/?]+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }

  /// Try fetching via Music API
  Future<Map<String, dynamic>?> _tryMusicBrowse(String playlistId) async {
    try {
      final uri = Uri.parse('$_baseUrl/browse?key=$_musicApiKey');

      final body = jsonEncode({
        'context': _buildMusicContext(),
        'browseId': 'VL$playlistId',
      });

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final parsed = _parsePlaylistHeader(json);
        if (parsed != null && parsed['name'] != 'Unknown Playlist') {
          debugPrint('✅ [YTMusicImport] Music API browse succeeded');
          return parsed;
        }
      } else {
        debugPrint(
          '⚠️ [YTMusicImport] Music browse failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Music browse error: $e');
    }
    return null;
  }

  /// Try fetching via Web API as fallback
  Future<Map<String, dynamic>?> _tryWebApi(String playlistId) async {
    try {
      final uri = Uri.parse('$_baseUrl/browse?key=$_webApiKey');

      final body = jsonEncode({
        'context': _buildWebContext(),
        'browseId': 'VL$playlistId',
      });

      final response = await _httpClient
          .post(uri, headers: _getWebHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final parsed = _parseWebPlaylistHeader(json);
        if (parsed != null) {
          debugPrint('✅ [YTMusicImport] Web API succeeded');
          return parsed;
        }
      } else {
        debugPrint('⚠️ [YTMusicImport] Web API failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Web API error: $e');
    }
    return null;
  }

  /// Parse playlist header from web API response
  Map<String, dynamic>? _parseWebPlaylistHeader(Map<String, dynamic> json) {
    try {
      // Try to find playlist info in web response
      final header =
          json['header']?['playlistHeaderRenderer'] ??
          json['sidebar']?['playlistSidebarRenderer'];

      if (header == null) return null;

      // Get title
      String name = 'Unknown Playlist';
      final titleText =
          header['title']?['simpleText'] ??
          header['title']?['runs']?[0]?['text'];
      if (titleText != null) {
        name = titleText;
      }

      // Get owner
      String owner = 'Unknown';
      final ownerText = header['ownerText']?['runs']?[0]?['text'];
      if (ownerText != null) {
        owner = ownerText;
      }

      // Get description
      String? description;
      final descText = header['descriptionText']?['simpleText'];
      if (descText != null && descText.isNotEmpty) {
        description = descText;
      }

      // Get cover
      String? coverUrl;
      final thumbnails =
          header['playlistHeaderBanner']?['heroPlaylistThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        coverUrl = _extractBestThumbnail(thumbnails);
      }

      return {
        'name': name,
        'description': description,
        'owner': owner,
        'coverUrl': coverUrl,
      };
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Parse web header error: $e');
      return null;
    }
  }

  /// Parse playlist header from browse response
  Map<String, dynamic>? _parsePlaylistHeader(Map<String, dynamic> json) {
    try {
      // Debug: Print top-level keys
      debugPrint('🔍 [YTMusicImport] Response keys: ${json.keys.join(", ")}');

      Map<String, dynamic>? header;

      // Path 1: Standard header key
      if (json.containsKey('header')) {
        header =
            json['header']?['musicDetailHeaderRenderer'] ??
            json['header']?['musicEditablePlaylistDetailHeaderRenderer'] ??
            json['header']?['musicVisualHeaderRenderer'] ??
            json['header']?['playlistHeaderRenderer'] ??
            json['header']?['pageHeaderRenderer'];

        if (header != null && header.containsKey('content')) {
          return _parsePageHeaderRenderer(header);
        }
      }

      // Path 2: Look in microformat
      if (json.containsKey('microformat')) {
        final microformat = json['microformat']?['microformatDataRenderer'];
        if (microformat != null) {
          debugPrint('✅ [YTMusicImport] Found microformat data');

          String name = microformat['title'] ?? 'Unknown Playlist';
          String? description = microformat['description'];
          String owner = microformat['familySafe'] == true
              ? 'Unknown'
              : 'Unknown';
          String? coverUrl;

          final thumbnail = microformat['thumbnail']?['thumbnails'];
          if (thumbnail != null && thumbnail.isNotEmpty) {
            coverUrl = _extractBestThumbnail(thumbnail);
          }

          return {
            'name': name,
            'description': description,
            'owner': owner,
            'coverUrl': coverUrl,
          };
        }
      }

      // Path 3: Parse from contents section directly
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null && contents.isNotEmpty) {
        debugPrint('🔍 [YTMusicImport] Checking contents for metadata...');

        for (final section in contents) {
          final shelf =
              section['musicShelfRenderer'] ??
              section['musicPlaylistShelfRenderer'];

          if (shelf != null) {
            String name = 'Unknown Playlist';
            String? description;
            String owner = 'Unknown';
            String? coverUrl;

            final shelfTitle = shelf['title']?['runs']?[0]?['text'];
            if (shelfTitle != null) {
              name = shelfTitle;
            }

            final subtitle = shelf['subtitle']?['runs'];
            if (subtitle != null) {
              for (final run in subtitle) {
                final text = run['text'] as String?;
                if (text != null &&
                    !text.contains('•') &&
                    !text.contains('song') &&
                    text.trim().isNotEmpty) {
                  owner = text.trim();
                  break;
                }
              }
            }

            debugPrint(
              '✅ [YTMusicImport] Parsed from shelf: "$name" by $owner',
            );

            return {
              'name': name,
              'description': description,
              'owner': owner,
              'coverUrl': coverUrl,
            };
          }
        }
      }

      // Path 4: Try sidebar
      final sidebar = json['sidebar']?['playlistSidebarRenderer']?['items'];
      if (sidebar != null && sidebar is List && sidebar.isNotEmpty) {
        final primaryInfo = sidebar[0]['playlistSidebarPrimaryInfoRenderer'];
        if (primaryInfo != null) {
          return _parseSidebarRenderer(primaryInfo);
        }
      }

      debugPrint('❌ [YTMusicImport] No header found in any path');
      return null;
    } catch (e, stackTrace) {
      debugPrint('⚠️ [YTMusicImport] Parse header error: $e');
      debugPrint('Stack: $stackTrace');
      return null;
    }
  }

  /// Extract playlist metadata from shelf contents
  Map<String, dynamic>? _extractMetadataFromShelf(Map<String, dynamic> json) {
    try {
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents == null || contents.isEmpty) return null;

      for (final section in contents) {
        final shelf =
            section['musicShelfRenderer'] ??
            section['musicPlaylistShelfRenderer'];

        if (shelf != null) {
          String name = 'Unknown Playlist';
          String? description;
          String owner = 'Unknown';
          String? coverUrl;

          final titleRuns = shelf['title']?['runs'];
          if (titleRuns != null && titleRuns.isNotEmpty) {
            name = titleRuns[0]['text'] ?? 'Unknown Playlist';
          }

          final subtitleRuns = shelf['subtitle']?['runs'] as List?;
          if (subtitleRuns != null) {
            for (final run in subtitleRuns) {
              final text = run['text'] as String?;
              if (text != null &&
                  !text.contains('•') &&
                  !text.contains('song') &&
                  !text.contains('view') &&
                  text.trim().isNotEmpty) {
                owner = text.trim();
                break;
              }
            }
          }

          return {
            'name': name,
            'description': description,
            'owner': owner,
            'coverUrl': coverUrl,
          };
        }
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Extract metadata error: $e');
      return null;
    }
  }

  /// Fetch playlist metadata (updated to handle both APIs)
  Future<Map<String, dynamic>?> _fetchPlaylistDetails(String playlistId) async {
    try {
      // Strategy 1: Try Music API with browse
      final musicResult = await _tryMusicBrowse(playlistId);
      if (musicResult != null && musicResult['name'] != 'Unknown Playlist') {
        return musicResult;
      }

      // Strategy 2: Try Web API as fallback
      final webResult = await _tryWebApi(playlistId);
      if (webResult != null && webResult['name'] != 'Unknown Playlist') {
        return webResult;
      }

      // Strategy 3: Try to scrape from public URL
      final scrapedResult = await _tryScrapingMetadata(playlistId);
      if (scrapedResult != null) {
        return scrapedResult;
      }

      // Strategy 4: Return minimal data and continue with tracks
      debugPrint('⚠️ [YTMusicImport] Using fallback metadata');
      return {
        'name': 'Imported Playlist',
        'description': null,
        'owner': 'Unknown',
        'coverUrl': null,
      };
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Fetch details error: $e');
      return {
        'name': 'Imported Playlist',
        'description': null,
        'owner': 'Unknown',
        'coverUrl': null,
      };
    }
  }

  /// Try scraping metadata from public YouTube Music page
  Future<Map<String, dynamic>?> _tryScrapingMetadata(String playlistId) async {
    try {
      debugPrint(
        '🔄 [YTMusicImport] Trying to scrape metadata from web page...',
      );

      final url = 'https://music.youtube.com/playlist?list=$playlistId';
      final response = await _httpClient
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept': 'text/html',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return null;
      }

      final html = response.body;

      // Extract title from HTML
      String? name;
      final titleMatch = RegExp(r'"title":\s*"([^"]+)"').firstMatch(html);
      if (titleMatch != null) {
        name = titleMatch.group(1);
      }

      // Extract description
      String? description;
      final descMatch = RegExp(r'"description":\s*"([^"]+)"').firstMatch(html);
      if (descMatch != null) {
        description = descMatch.group(1);
      }

      // Extract owner/author
      String? owner;
      final ownerMatch = RegExp(r'"author":\s*"([^"]+)"').firstMatch(html);
      if (ownerMatch != null) {
        owner = ownerMatch.group(1);
      }

      // Extract thumbnail
      String? coverUrl;
      final thumbMatch = RegExp(
        r'"url":\s*"(https://[^"]*ytimg[^"]+)"',
      ).firstMatch(html);
      if (thumbMatch != null) {
        coverUrl = thumbMatch.group(1)?.replaceAll(r'\u003d', '=');
      }

      if (name != null) {
        debugPrint('✅ [YTMusicImport] Scraped metadata: "$name"');
        return {
          'name': name,
          'description': description,
          'owner': owner ?? 'Unknown',
          'coverUrl': coverUrl,
        };
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Scraping error: $e');
      return null;
    }
  }

  /// Parse pageHeaderRenderer structure
  Map<String, dynamic>? _parsePageHeaderRenderer(Map<String, dynamic> header) {
    try {
      debugPrint('📄 [YTMusicImport] Parsing pageHeaderRenderer');

      final content = header['content']?['pageHeaderViewModel'];
      if (content == null) return null;

      String name = 'Unknown Playlist';
      final titleModel = content['title']?['dynamicTextViewModel']?['text'];
      if (titleModel != null) {
        if (titleModel is Map && titleModel['content'] != null) {
          name = titleModel['content'];
        } else if (titleModel is String) {
          name = titleModel;
        }
      }

      String? description;
      final descModel =
          content['description']?['descriptionPreviewViewModel']?['description']?['content'];
      if (descModel != null) {
        description = descModel;
      }

      String owner = 'Unknown';
      final metadata =
          content['metadata']?['contentMetadataViewModel']?['metadataRows']
              as List?;
      if (metadata != null && metadata.isNotEmpty) {
        final firstRow = metadata[0]['metadataParts'] as List?;
        if (firstRow != null && firstRow.isNotEmpty) {
          final text = firstRow[0]['text']?['content'];
          if (text != null) {
            owner = text;
          }
        }
      }

      String? coverUrl;
      final imageSources =
          content['image']?['contentPreviewImageViewModel']?['image']?['sources']
              as List?;
      if (imageSources != null && imageSources.isNotEmpty) {
        final lastSource = imageSources.last;
        coverUrl = lastSource['url'];
      }

      debugPrint('✅ [YTMusicImport] PageHeader parsed: "$name" by $owner');

      return {
        'name': name,
        'description': description,
        'owner': owner,
        'coverUrl': coverUrl,
      };
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] PageHeader parse error: $e');
      return null;
    }
  }

  /// Parse sidebar renderer structure
  Map<String, dynamic>? _parseSidebarRenderer(Map<String, dynamic> sidebar) {
    try {
      debugPrint('📄 [YTMusicImport] Parsing sidebar renderer');

      String name = 'Unknown Playlist';
      final titleRuns = sidebar['title']?['runs'];
      if (titleRuns != null && titleRuns.isNotEmpty) {
        name = titleRuns[0]['text'] ?? 'Unknown Playlist';
      }

      String owner = 'Unknown';
      final stats = sidebar['stats'] as List?;
      if (stats != null && stats.isNotEmpty) {
        for (final stat in stats) {
          final runs = stat['runs'] as List?;
          if (runs != null && runs.isNotEmpty) {
            final text = runs[0]['text'] as String?;
            if (text != null &&
                !text.contains('song') &&
                !text.contains('view') &&
                text.trim().isNotEmpty) {
              owner = text;
              break;
            }
          }
        }
      }

      String? coverUrl;
      final thumbnails =
          sidebar['thumbnailRenderer']?['playlistVideoThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        coverUrl = _extractBestThumbnail(thumbnails);
      }

      debugPrint('✅ [YTMusicImport] Sidebar parsed: "$name" by $owner');

      return {
        'name': name,
        'description': null,
        'owner': owner,
        'coverUrl': coverUrl,
      };
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Sidebar parse error: $e');
      return null;
    }
  }

  /// Build context for Web API
  Map<String, dynamic> _buildWebContext() {
    return {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20231211.01.00',
        'hl': 'en',
        'gl': 'US',
      },
    };
  }

  /// Get headers for Web API
  Map<String, String> _getWebHeaders() {
    return {
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
    };
  }

  /// Fetch all tracks in playlist
  Future<List<YTMusicTrackData>> _fetchPlaylistTracks(String playlistId) async {
    final tracks = <YTMusicTrackData>[];
    String? continuationToken;
    int pageCount = 0;

    try {
      do {
        pageCount++;
        debugPrint('📄 [YTMusicImport] Fetching page $pageCount...');

        final response = await _fetchPlaylistPage(
          playlistId,
          continuationToken,
        );

        if (response == null) {
          debugPrint('⚠️ [YTMusicImport] Page $pageCount returned null');
          break;
        }

        final pageTracks = _parseTracksFromResponse(response);
        debugPrint(
          '✅ [YTMusicImport] Page $pageCount: ${pageTracks.length} tracks parsed',
        );

        tracks.addAll(pageTracks);

        continuationToken = response['continuationToken'];

        if (continuationToken != null) {
          debugPrint(
            '🔄 [YTMusicImport] Has continuation token, fetching more...',
          );
        }

        if (pageCount >= 20) {
          debugPrint('⚠️ [YTMusicImport] Reached page limit (20), stopping');
          break;
        }
      } while (continuationToken != null && tracks.length < 500);

      debugPrint('📊 [YTMusicImport] Total tracks collected: ${tracks.length}');
      return tracks;
    } catch (e, stackTrace) {
      debugPrint('⚠️ [YTMusicImport] Fetch tracks error: $e');
      debugPrint('Stack: $stackTrace');
      return tracks;
    }
  }

  /// Fetch a single page of playlist tracks
  Future<Map<String, dynamic>?> _fetchPlaylistPage(
    String playlistId,
    String? continuationToken,
  ) async {
    try {
      final uri = continuationToken != null
          ? Uri.parse('$_baseUrl/browse?key=$_musicApiKey')
          : Uri.parse('$_baseUrl/browse?key=$_musicApiKey');

      Map<String, dynamic> body;

      if (continuationToken == null) {
        body = {'context': _buildMusicContext(), 'browseId': 'VL$playlistId'};
      } else {
        body = {
          'context': _buildMusicContext(),
          'continuation': continuationToken,
        };
      }

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: jsonEncode(body))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ [YTMusicImport] Page fetch failed: ${response.statusCode}',
        );

        if (continuationToken == null) {
          return await _fetchPlaylistPageWebFallback(playlistId);
        }
        return null;
      }

      final json = jsonDecode(response.body);
      return _extractPlaylistContents(json);
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Page fetch error: $e');

      if (continuationToken == null) {
        return await _fetchPlaylistPageWebFallback(playlistId);
      }
      return null;
    }
  }

  /// Fallback: Fetch playlist page using Web API
  Future<Map<String, dynamic>?> _fetchPlaylistPageWebFallback(
    String playlistId,
  ) async {
    try {
      debugPrint('🔄 [YTMusicImport] Trying Web API fallback...');

      final uri = Uri.parse('$_baseUrl/browse?key=$_webApiKey');

      final body = jsonEncode({
        'context': _buildWebContext(),
        'browseId': 'VL$playlistId',
      });

      final response = await _httpClient
          .post(uri, headers: _getWebHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return _extractPlaylistContents(json);
      }
    } catch (e) {
      debugPrint('⚠️ [YTMusicImport] Web fallback error: $e');
    }
    return null;
  }

  /// Extract playlist contents from response
  Map<String, dynamic>? _extractPlaylistContents(Map<String, dynamic> json) {
    try {
      debugPrint('🔍 [YTMusicImport] Extracting playlist contents...');

      if (json.containsKey('continuationContents')) {
        debugPrint('📄 [YTMusicImport] Found continuation response');
        final continuation =
            json['continuationContents']['musicPlaylistShelfContinuation'];
        if (continuation != null) {
          final items = continuation['contents'] as List?;
          final nextToken =
              continuation['continuations']?[0]?['nextContinuationData']?['continuation'];
          debugPrint(
            '✅ [YTMusicImport] Continuation: ${items?.length ?? 0} items',
          );
          return {'items': items ?? [], 'continuationToken': nextToken};
        }
      }

      // Path 1: Standard Music structure
      var contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      // Path 2: Two column structure
      if (contents == null) {
        contents =
            json['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents']
                as List?;
      }

      // Path 3: Direct section list
      if (contents == null) {
        contents =
            json['contents']?['sectionListRenderer']?['contents'] as List?;
      }

      if (contents == null) {
        debugPrint('❌ [YTMusicImport] No contents found in any known path');
        return null;
      }

      debugPrint('📂 [YTMusicImport] Found ${contents.length} sections');

      for (var i = 0; i < contents.length; i++) {
        final section = contents[i];

        final shelf =
            section['musicShelfRenderer'] ??
            section['musicPlaylistShelfRenderer'] ??
            section['itemSectionRenderer']?['contents']?[0]?['playlistVideoListRenderer'];

        if (shelf != null) {
          final items = shelf['contents'] as List?;
          final nextToken =
              shelf['continuations']?[0]?['nextContinuationData']?['continuation'];

          if (items != null && items.isNotEmpty) {
            debugPrint(
              '✅ [YTMusicImport] Found shelf with ${items.length} items at section $i',
            );
            return {'items': items, 'continuationToken': nextToken};
          }
        }
      }

      debugPrint('⚠️ [YTMusicImport] No valid shelf found in any section');
      return null;
    } catch (e, stackTrace) {
      debugPrint('⚠️ [YTMusicImport] Extract error: $e');
      debugPrint('Stack: $stackTrace');
      return null;
    }
  }

  /// Parse tracks from a page of items
  List<YTMusicTrackData> _parseTracksFromResponse(Map<String, dynamic> page) {
    final tracks = <YTMusicTrackData>[];
    final items = page['items'] as List? ?? [];

    for (final item in items) {
      final track = _parseTrackItem(item);
      if (track != null) {
        tracks.add(track);
      }
    }

    return tracks;
  }

  /// Parse a single track item
  YTMusicTrackData? _parseTrackItem(Map<String, dynamic> item) {
    try {
      final renderer =
          item['musicResponsiveListItemRenderer'] ??
          item['playlistVideoRenderer'] ??
          item['playlistPanelVideoRenderer'] ??
          item['musicTwoRowItemRenderer'];

      if (renderer == null) {
        debugPrint(
          '⚠️ [YTMusicImport] Unknown item renderer type: ${item.keys.join(", ")}',
        );
        return null;
      }

      String? videoId;

      videoId = renderer['playlistItemData']?['videoId'] as String?;

      if (videoId == null) {
        videoId = renderer['videoId'] as String?;
      }

      if (videoId == null) {
        videoId =
            renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
                as String?;
      }

      if (videoId == null) {
        videoId =
            renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId']
                as String?;
      }

      if (videoId == null) {
        final menuItems = renderer['menu']?['menuRenderer']?['items'] as List?;
        if (menuItems != null) {
          for (final menuItem in menuItems) {
            final serviceEndpoint =
                menuItem['menuNavigationItemRenderer']?['navigationEndpoint']?['watchEndpoint']?['videoId'];
            if (serviceEndpoint != null) {
              videoId = serviceEndpoint;
              break;
            }
          }
        }
      }

      if (videoId == null) {
        debugPrint('⚠️ [YTMusicImport] No video ID found for item');
        return null;
      }

      String title = 'Unknown';

      final titleRuns =
          renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
      if (titleRuns != null && titleRuns.isNotEmpty) {
        title = titleRuns[0]['text'] ?? 'Unknown';
      }

      if (title == 'Unknown') {
        final titleDirect =
            renderer['title']?['runs']?[0]?['text'] ??
            renderer['title']?['simpleText'];
        if (titleDirect != null) {
          title = titleDirect;
        }
      }

      List<String> artists = ['Unknown Artist'];

      if (renderer['flexColumns'] != null &&
          renderer['flexColumns'].length > 1) {
        final artistRuns =
            renderer['flexColumns'][1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (artistRuns != null && artistRuns.isNotEmpty) {
          artists = [];
          for (final run in artistRuns) {
            final text = run['text'] as String?;
            if (text != null && text.trim().isNotEmpty && text != '•') {
              artists.add(text);
              break;
            }
          }
          if (artists.isEmpty) {
            artists = ['Unknown Artist'];
          }
        }
      }

      if (artists.first == 'Unknown Artist') {
        final bylineRuns = renderer['shortBylineText']?['runs'];
        if (bylineRuns != null && bylineRuns.isNotEmpty) {
          final artistText = bylineRuns[0]['text'] as String?;
          if (artistText != null) {
            artists = [artistText];
          }
        }
      }

      String? albumArtUrl;

      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        albumArtUrl = _extractBestThumbnail(thumbnails);
      }

      if (albumArtUrl == null) {
        final directThumbs = renderer['thumbnail']?['thumbnails'] as List?;
        if (directThumbs != null && directThumbs.isNotEmpty) {
          albumArtUrl = _extractBestThumbnail(directThumbs);
        }
      }

      if (albumArtUrl == null || albumArtUrl.isEmpty) {
        albumArtUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      }

      Duration duration = Duration.zero;

      final lengthText =
          renderer['fixedColumns']?[0]?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']?[0]?['text']
              as String?;
      if (lengthText != null) {
        duration = _parseDuration(lengthText);
      }

      if (duration == Duration.zero) {
        final lengthText2 = renderer['lengthText']?['simpleText'] as String?;
        if (lengthText2 != null) {
          duration = _parseDuration(lengthText2);
        }
      }

      return YTMusicTrackData(
        id: videoId,
        title: title,
        artists: artists,
        albumArtUrl: albumArtUrl,
        duration: duration,
        addedAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      debugPrint('⚠️ [YTMusicImport] Parse track error: $e');
      debugPrint('Stack: $stackTrace');
      return null;
    }
  }

  String _extractBestThumbnail(List thumbnails) {
    for (var i = thumbnails.length - 1; i >= 0; i--) {
      final url = thumbnails[i]['url'] as String?;
      if (url != null && url.isNotEmpty) {
        final cleanUrl = url.split('=w')[0].split('?')[0];
        return '$cleanUrl=w960-h960-l90-rj';
      }
    }
    return '';
  }

  /// Parse duration string (e.g., "3:45" or "1:02:30")
  Duration _parseDuration(String durationStr) {
    try {
      final parts = durationStr.split(':').map(int.parse).toList();
      if (parts.length == 3) {
        return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
      } else if (parts.length == 2) {
        return Duration(minutes: parts[0], seconds: parts[1]);
      } else if (parts.length == 1) {
        return Duration(seconds: parts[0]);
      }
    } catch (e) {
      // Invalid format
    }
    return Duration.zero;
  }

  /// Build context for YouTube Music API
  Map<String, dynamic> _buildMusicContext() {
    return {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20250213.01.00',
        'hl': 'en',
        'gl': 'US',
        'platform': 'DESKTOP',
      },
      'user': {'lockedSafetyMode': false},
    };
  }

  /// Get headers for YouTube Music API
  Map<String, String> _getMusicHeaders() {
    return {
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
      'X-Goog-Visitor-Id': 'CgtUWW9tV0FzTVNHRSiM8LG5BjIKCgJVUxIEGgAgWQ%3D%3D',
    };
  }

  void dispose() {
    _httpClient.close();
  }
}
