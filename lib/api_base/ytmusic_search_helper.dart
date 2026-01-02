// lib/api_base/ytmusic_search_helper.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vibeflow/models/song_model.dart';

/// Dedicated YouTube Music search helper
/// Uses InnerTune/ViMusic approach for accurate music search
class YTMusicSearchHelper {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _musicApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  final http.Client _httpClient;
  final Duration _timeout;

  YTMusicSearchHelper({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  /// Search YouTube Music with proper song filter
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    try {
      print('🔍 [YTMusicSearch] Searching: "$query"');

      final uri = Uri.parse('$_baseUrl/search?key=$_musicApiKey');

      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20231204.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'query': query,
        'params': 'EgWKAQIIAWoOEAMQBBAJEAoQBRAREBA%3D', // Songs filter
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
        print('❌ [YTMusicSearch] Failed: ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final songs = _parseSearchResults(json, limit);

      print('✅ [YTMusicSearch] Found ${songs.length} songs');
      return songs;
    } catch (e, stack) {
      print('❌ [YTMusicSearch] Error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      return [];
    }
  }

  List<Song> _parseSearchResults(Map<String, dynamic> json, int limit) {
    final songs = <Song>[];

    try {
      // Navigate to search results
      final tabs =
          json['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
      if (tabs == null) {
        print('⚠️ No tabs in response');
        return songs;
      }

      for (final tab in tabs) {
        final contents =
            tab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (contents == null) continue;

        for (final section in contents) {
          // Get music shelf
          final shelf = section['musicShelfRenderer'];
          if (shelf == null) continue;

          final items = shelf['contents'] as List?;
          if (items == null) continue;

          for (final item in items) {
            if (songs.length >= limit) return songs;

            final song = _parseMusicItem(item);
            if (song != null) {
              songs.add(song);
            }
          }
        }
      }
    } catch (e, stack) {
      print('⚠️ [YTMusicSearch] Parse error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
    }

    return songs;
  }

  Song? _parseMusicItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      // Extract video ID
      String? videoId;

      // Method 1: From playlistItemData
      videoId = renderer['playlistItemData']?['videoId'] as String?;

      // Method 2: From overlay
      videoId ??=
          renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;

      // Method 3: From navigation endpoint
      videoId ??=
          renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;

      if (videoId == null) return null;

      // Extract title and artists
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      // Column 0: Title
      final titleRuns =
          flexColumns[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
              as List?;
      final title = titleRuns?[0]?['text'] as String? ?? 'Unknown';

      // Column 1: Artist and album info
      String artist = 'Unknown Artist';
      if (flexColumns.length > 1) {
        final subtitleRuns =
            flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
          // First run is typically the artist
          artist = subtitleRuns[0]?['text'] as String? ?? 'Unknown Artist';
        }
      }

      // Extract duration (if available)
      String? durationText;
      if (flexColumns.length > 2) {
        final durationRuns =
            flexColumns
                    .last?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        durationText = durationRuns?[0]?['text'] as String?;
      }

      // Parse duration to seconds
      int? duration;
      if (durationText != null) {
        duration = _parseDuration(durationText);
      }

      // Extract thumbnail
      String thumbnail = '';
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;

      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = _extractBestThumbnail(thumbnails);
      }

      // Fallback thumbnail
      if (thumbnail.isEmpty) {
        thumbnail = 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';
      }

      return Song(
        videoId: videoId,
        title: title,
        artists: [artist],
        thumbnail: thumbnail,
        duration: formatDuration(duration),
        audioUrl: null,
      );
    } catch (e) {
      print('⚠️ [YTMusicSearch] Parse item error: $e');
      return null;
    }
  }

  String _extractBestThumbnail(List thumbnails) {
    // Get highest quality thumbnail
    for (var i = thumbnails.length - 1; i >= 0; i--) {
      final url = thumbnails[i]['url'] as String?;
      if (url != null && url.isNotEmpty) {
        final cleanUrl = url.split('=w')[0].split('?')[0];
        return '$cleanUrl=w960-h960-l90-rj';
      }
    }
    return '';
  }

  int? _parseDuration(String duration) {
    try {
      final parts = duration.split(':').map(int.parse).toList();

      if (parts.length == 2) {
        // MM:SS
        return parts[0] * 60 + parts[1];
      } else if (parts.length == 3) {
        // HH:MM:SS
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  String? formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;

    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _httpClient.close();
  }
}
