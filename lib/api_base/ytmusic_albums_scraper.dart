// lib/api_base/ytmusic_albums_scraper.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/song_model.dart';

/// Scraper for YouTube Music albums using the internal API
class YTMusicAlbumsScraper {
  static const String _baseUrl = 'https://music.youtube.com';
  static const String _apiUrl = '$_baseUrl/youtubei/v1';

  final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.5',
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30',
    'Origin': _baseUrl,
    'Referer': '$_baseUrl/',
  };

  final Map<String, dynamic> _context = {
    'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.20231204.01.00'},
  };

  /// Get trending/popular albums - metadata only
  Future<List<Album>> getTrendingAlbums({int limit = 20}) async {
    try {
      print('🔍 [YTMusicScraper] Fetching trending albums...');

      final response = await _makeRequest(
        endpoint: 'browse',
        body: {'context': _context, 'browseId': 'FEmusic_home'},
      );

      if (response == null) {
        return _getFallbackAlbums();
      }

      final albums = _parseAlbumsFromBrowse(response, limit);

      if (albums.isEmpty) {
        print('⚠️ No albums found, using fallback');
        return _getFallbackAlbums();
      }

      print('✅ [YTMusicScraper] Found ${albums.length} albums');
      return albums;
    } catch (e) {
      print('❌ [YTMusicScraper] Error: $e');
      return _getFallbackAlbums();
    }
  }

  /// Get album details - metadata only (songs list without loading full details)
  Future<Album?> getAlbumDetails(String albumId) async {
    try {
      print('📀 [YTMusicScraper] Fetching album: $albumId');

      final response = await _makeRequest(
        endpoint: 'browse',
        body: {'context': _context, 'browseId': albumId},
      );

      if (response == null) return null;

      // Extract metadata
      final metadata = _extractAlbumMetadata(response, albumId);

      // Extract songs metadata
      final songs = _extractSongsMetadata(response);

      print(
        '✅ [YTMusicScraper] Loaded album "${metadata['title']}" with ${songs.length} songs',
      );

      return Album(
        id: albumId,
        title: metadata['title'] as String,
        artist: metadata['artist'] as String,
        coverArt: metadata['coverArt'] as String?,
        year: metadata['year'] as int? ?? 0,
        songs: songs,
      );
    } catch (e) {
      print('❌ [YTMusicScraper] Error: $e');
      return null;
    }
  }

  /// Search for albums - metadata only
  Future<List<Album>> searchAlbums(String query, {int limit = 20}) async {
    try {
      print('🔍 [YTMusicScraper] Searching albums: "$query"');

      final response = await _makeRequest(
        endpoint: 'search',
        body: {
          'context': _context,
          'query': query,
          'params': 'EgWKAQIYAWoKEAoQAxAEEAkQBQ%3D%3D', // Filter for albums
        },
      );

      if (response == null) return [];

      final albums = _parseAlbumsFromSearch(response, limit);

      print('✅ [YTMusicScraper] Found ${albums.length} albums');
      return albums;
    } catch (e) {
      print('❌ [YTMusicScraper] Search error: $e');
      return [];
    }
  }

  /// Make API request with error handling
  Future<Map<String, dynamic>?> _makeRequest({
    required String endpoint,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/$endpoint'),
        headers: _headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        print('❌ Request failed: ${response.statusCode}');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('❌ Request error: $e');
      return null;
    }
  }

  /// Extract album metadata from response
  Map<String, dynamic> _extractAlbumMetadata(
    Map<String, dynamic> data,
    String albumId,
  ) {
    String title = 'Unknown Album';
    String artist = 'Unknown Artist';
    String? coverArt;
    int? year;

    try {
      // Try different header types
      dynamic header = data['header']?['musicDetailHeaderRenderer'];
      header ??= data['header']?['musicEditablePlaylistDetailHeaderRenderer'];

      if (header != null) {
        // Extract title
        title = _extractText(header['title']) ?? title;

        // Extract artist/subtitle
        artist = _extractText(header['subtitle']) ?? artist;

        // Fallback to owner for playlists
        if (artist == 'Unknown Artist') {
          artist =
              _extractText(header['owner']?['videoOwnerRenderer']?['title']) ??
              artist;
        }

        // Extract thumbnail
        coverArt = _extractBestThumbnail(header['thumbnail']);

        // Extract year from subtitle if available
        year = _extractYear(header['subtitle']);
      }
    } catch (e) {
      print('⚠️ Error extracting metadata: $e');
    }

    return {
      'title': title,
      'artist': artist,
      'coverArt': coverArt,
      'year': year,
    };
  }

  /// Extract songs metadata from response
  List<Song> _extractSongsMetadata(Map<String, dynamic> data) {
    final songs = <Song>[];

    try {
      // Try multiple content paths
      dynamic contents =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];

      contents ??=
          data['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents'];

      if (contents != null && contents is List) {
        for (final section in contents) {
          // Try different shelf types
          var shelf = section['musicShelfRenderer'];
          shelf ??= section['musicPlaylistShelfRenderer'];

          if (shelf == null) continue;

          final items = shelf['contents'] as List?;
          if (items == null) continue;

          for (final item in items) {
            final song = _parseSongMetadata(item);
            if (song != null) {
              songs.add(song);
            }
          }

          if (songs.isNotEmpty) break;
        }
      }
    } catch (e) {
      print('⚠️ Error extracting songs: $e');
    }

    return songs;
  }

  /// Parse albums from browse response
  List<Album> _parseAlbumsFromBrowse(Map<String, dynamic> data, int limit) {
    final albums = <Album>[];

    try {
      final contents =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicCarouselShelfRenderer'];
          if (shelf == null) continue;

          final items = shelf['contents'] as List?;
          if (items == null) continue;

          for (final item in items) {
            if (albums.length >= limit) break;

            final album = _parseAlbumItem(item);
            if (album != null) {
              albums.add(album);
            }
          }

          if (albums.length >= limit) break;
        }
      }
    } catch (e) {
      print('⚠️ Error parsing albums: $e');
    }

    return albums;
  }

  /// Parse albums from search response
  List<Album> _parseAlbumsFromSearch(Map<String, dynamic> data, int limit) {
    final albums = <Album>[];

    try {
      final contents =
          data['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicShelfRenderer'];
          if (shelf == null) continue;

          final items = shelf['contents'] as List?;
          if (items == null) continue;

          for (final item in items) {
            if (albums.length >= limit) break;

            final album = _parseSearchAlbumItem(item);
            if (album != null) {
              albums.add(album);
            }
          }

          if (albums.length >= limit) break;
        }
      }
    } catch (e) {
      print('⚠️ Error parsing search results: $e');
    }

    return albums;
  }

  /// Parse album from carousel item
  Album? _parseAlbumItem(Map<String, dynamic> item) {
    try {
      final albumItem = item['musicTwoRowItemRenderer'];
      if (albumItem == null) return null;

      final browseId =
          albumItem['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;

      if (browseId == null || browseId.isEmpty) return null;

      final title = _extractText(albumItem['title']) ?? 'Unknown Album';
      final artist = _extractText(albumItem['subtitle']) ?? 'Unknown Artist';
      final coverArt = _extractBestThumbnail(
        albumItem['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail'],
      );

      return Album(
        id: browseId,
        title: title,
        artist: artist,
        coverArt: coverArt,
        year: 0,
        songs: [],
      );
    } catch (e) {
      print('⚠️ Error parsing album item: $e');
      return null;
    }
  }

  /// Parse album from search result
  Album? _parseSearchAlbumItem(Map<String, dynamic> item) {
    try {
      final albumItem = item['musicResponsiveListItemRenderer'];
      if (albumItem == null) return null;

      final browseId =
          albumItem['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;

      if (browseId == null) return null;

      final flexColumns = albumItem['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      final title = _extractFlexColumnText(flexColumns[0]) ?? 'Unknown Album';
      final artist = flexColumns.length > 1
          ? _extractFlexColumnText(flexColumns[1]) ?? 'Unknown Artist'
          : 'Unknown Artist';

      final coverArt = _extractBestThumbnail(albumItem['thumbnail']);

      return Album(
        id: browseId,
        title: title,
        artist: artist,
        coverArt: coverArt,
        year: 0,
        songs: [],
      );
    } catch (e) {
      print('⚠️ Error parsing search item: $e');
      return null;
    }
  }

  /// Parse song metadata from item
  Song? _parseSongMetadata(Map<String, dynamic> item) {
    try {
      final songItem = item['musicResponsiveListItemRenderer'];
      if (songItem == null) return null;

      // Extract video ID
      final videoId = songItem['playlistItemData']?['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) return null;

      final flexColumns = songItem['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      // Extract title
      final title = _extractFlexColumnText(flexColumns[0]) ?? 'Unknown';

      // Extract artists
      final artists = <String>[];
      if (flexColumns.length > 1) {
        final artistRuns =
            flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;

        if (artistRuns != null) {
          for (final run in artistRuns) {
            final text = run['text'] as String?;
            if (text != null && text != ' • ' && text != '•') {
              artists.add(text);
            }
          }
        }
      }

      if (artists.isEmpty) artists.add('Unknown Artist');

      // Extract thumbnail
      final thumbnail = _extractBestThumbnail(songItem['thumbnail']) ?? '';

      // Extract duration
      final duration = flexColumns.length > 2
          ? _extractFlexColumnText(flexColumns.last)
          : null;

      return Song(
        videoId: videoId,
        title: title,
        artists: artists,
        thumbnail: thumbnail,
        duration: duration,
        audioUrl: null,
      );
    } catch (e) {
      print('⚠️ Error parsing song: $e');
      return null;
    }
  }

  /// Extract text from runs structure
  String? _extractText(dynamic textObject) {
    try {
      if (textObject == null) return null;

      final runs = textObject['runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        return runs.first['text'] as String?;
      }

      return textObject['simpleText'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Extract text from flex column
  String? _extractFlexColumnText(dynamic column) {
    try {
      final runs =
          column?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
              as List?;
      return runs?.first['text'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Extract best quality thumbnail
  String? _extractBestThumbnail(dynamic thumbnailObject) {
    try {
      if (thumbnailObject == null) return null;

      // Try different thumbnail structures
      var thumbnails =
          thumbnailObject['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;

      thumbnails ??=
          thumbnailObject['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;

      thumbnails ??= thumbnailObject['thumbnails'] as List?;

      if (thumbnails != null && thumbnails.isNotEmpty) {
        final bestThumb = thumbnails.last as Map<String, dynamic>;
        var url = bestThumb['url'] as String?;

        // Enhance quality
        if (url != null && url.contains('=w')) {
          url = url.split('=w')[0] + '=w500-h500';
        }

        return url;
      }
    } catch (e) {
      print('⚠️ Error extracting thumbnail: $e');
    }

    return null;
  }

  /// Extract year from subtitle
  int? _extractYear(dynamic subtitleObject) {
    try {
      final text = _extractText(subtitleObject);
      if (text == null) return null;

      final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(text);
      if (yearMatch != null) {
        return int.tryParse(yearMatch.group(0)!);
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  /// Fallback albums with known good IDs
  List<Album> _getFallbackAlbums() {
    return [
      Album(
        id: 'MPREb_4pL8gzVGOTL',
        title: 'Top Songs - Global',
        artist: 'YouTube Music',
        coverArt: null,
        year: 0,
        songs: [],
      ),
      Album(
        id: 'MPREb_MHhYbECC7a8',
        title: "Today's Hits",
        artist: 'YouTube Music',
        coverArt: null,
        year: 0,
        songs: [],
      ),
      Album(
        id: 'MPREb_YBnj6o4LNCM',
        title: 'Hip Hop Hits',
        artist: 'YouTube Music',
        coverArt: null,
        year: 0,
        songs: [],
      ),
    ];
  }

  /// Dispose resources
  void dispose() {
    // Clean up if needed
  }
}
