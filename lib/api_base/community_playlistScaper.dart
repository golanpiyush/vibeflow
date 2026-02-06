import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vibeflow/api_base/scrapper.dart';
import 'package:vibeflow/models/song_model.dart';

/// Extension for YouTubeMusicScraper to handle community playlists
/// Using Outertune/ViMusic/Innertune technique
extension CommunityPlaylistScraper on YouTubeMusicScraper {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _musicApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  /// Get featured/trending community playlists using proper browse endpoint
  /// User-created playlists like Spotify
  Future<List<CommunityPlaylist>> getCommunityPlaylists({
    int limit = 20,
  }) async {
    try {
      print('🎵 [Playlist] Fetching user-created playlists...');

      // Search for simple, popular user playlists
      final playlists = <CommunityPlaylist>[];

      // Simple search terms that return user playlists
      final queries = [
        'best songs',
        'chill music',
        'party mix',
        'workout',
        'study music',
        'sad songs',
        'happy songs',
        'road trip',
        'love songs',
        'motivation',
        'relaxing',
        'gaming music',
        'bollywood',
        'hindi remix',
        'punjabi songs',
        'english pop',
      ];

      for (final query in queries) {
        if (playlists.length >= limit) break;

        // Search for playlists
        final results = await searchPlaylists(query, limit: 5);
        playlists.addAll(results);
      }

      // Remove duplicates by ID
      final uniquePlaylists = <String, CommunityPlaylist>{};
      for (final playlist in playlists) {
        uniquePlaylists[playlist.id] = playlist;
      }

      final finalList = uniquePlaylists.values.take(limit).toList();
      print('✅ [Playlist] Found ${finalList.length} user playlists');
      return finalList;
    } catch (e, stack) {
      print('❌ [Playlist] Error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      return [];
    }
  }

  /// Get playlists from explore/charts
  Future<List<CommunityPlaylist>> _getExplorePlaylists(int limit) async {
    try {
      final uri = Uri.parse('$_baseUrl/browse?key=$_musicApiKey');

      // Try different browse IDs that work
      final browseIds = [
        'FEmusic_explore', // Explore page
        'FEmusic_charts', // Charts
        'FEmusic_new_releases', // New releases
      ];

      for (final browseId in browseIds) {
        final body = jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20231122.01.00',
              'hl': 'en',
              'gl': 'US',
            },
          },
          'browseId': browseId,
        });

        final response = await _makeRequest(uri, body);
        if (response == null) continue;

        final json = jsonDecode(response.body);
        final playlists = _parseBrowsePlaylists(json, limit);

        if (playlists.isNotEmpty) {
          print('✅ [Playlist] Found ${playlists.length} from $browseId');
          return playlists;
        }
      }

      return [];
    } catch (e) {
      print('❌ [Playlist] Explore error: $e');
      return [];
    }
  }

  /// Search for playlists - SIMPLIFIED for user playlists
  Future<List<CommunityPlaylist>> searchPlaylists(
    String query, {
    int limit = 20,
  }) async {
    try {
      print('🔍 [Playlist] Searching: "$query"');

      final uri = Uri.parse('$_baseUrl/search?key=$_musicApiKey');

      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20231122.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'query': query,
        'params': 'Eg-KAQwIABAAGAAgACgB', // Community playlists filter
      });

      final response = await _makeRequest(uri, body);
      if (response == null) return [];

      final json = jsonDecode(response.body);
      var playlists = _parseSearchPlaylists(
        json,
        limit * 3,
      ); // Get more to filter

      // RELAXED FILTER: Just remove obvious non-playlist content
      playlists = playlists
          .where((p) {
            final titleLower = p.title.toLowerCase();
            final creatorLower = p.creator.toLowerCase();

            // Only exclude obvious auto-generated content
            if (titleLower.contains('music video') ||
                titleLower.contains('official video') ||
                titleLower.contains('mv ') ||
                creatorLower.contains('vevo')) {
              return false;
            }

            // Minimum 5 songs (relaxed from 10)
            if (p.songCount < 5) return false;

            return true;
          })
          .take(limit)
          .toList();

      print('✅ [Playlist] Found ${playlists.length} playlists');
      return playlists;
    } catch (e, stack) {
      print('❌ [Playlist] Search error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      return [];
    }
  }

  /// Get playlist details with all songs
  Future<CommunityPlaylist?> getPlaylistDetails(String playlistId) async {
    try {
      print('📋 [Playlist] Fetching: $playlistId');

      final uri = Uri.parse('$_baseUrl/browse?key=$_musicApiKey');

      // Clean playlist ID
      final cleanId = playlistId.startsWith('VL')
          ? playlistId
          : playlistId.startsWith('RDAMPL')
          ? playlistId
          : 'VL$playlistId';

      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20231122.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'browseId': cleanId,
      });

      final response = await _makeRequest(uri, body);
      if (response == null) return null;

      final json = jsonDecode(response.body);
      final playlist = _parsePlaylistDetails(json, playlistId);

      print('✅ [Playlist] Loaded: ${playlist?.songCount ?? 0} songs');
      return playlist;
    } catch (e, stack) {
      print('❌ [Playlist] Details error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      return null;
    }
  }

  // ============= PARSING METHODS (FIXED) =============

  List<CommunityPlaylist> _parseBrowsePlaylists(
    Map<String, dynamic> json,
    int limit,
  ) {
    final playlists = <CommunityPlaylist>[];

    try {
      // Navigate through the response structure
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents == null) {
        print('⚠️ No contents found in browse response');
        return playlists;
      }

      for (final section in contents) {
        // Try gridRenderer (common for playlists)
        final gridRenderer = section['gridRenderer'];
        if (gridRenderer != null) {
          final items = gridRenderer['items'] as List?;
          if (items != null) {
            for (final item in items) {
              final playlist = _parsePlaylistGridItem(item);
              if (playlist != null) {
                playlists.add(playlist);
                if (playlists.length >= limit) return playlists;
              }
            }
          }
        }

        // Try musicCarouselShelfRenderer
        final carousel = section['musicCarouselShelfRenderer'];
        if (carousel != null) {
          final items = carousel['contents'] as List?;
          if (items != null) {
            for (final item in items) {
              final playlist = _parsePlaylistCarouselItem(item);
              if (playlist != null) {
                playlists.add(playlist);
                if (playlists.length >= limit) return playlists;
              }
            }
          }
        }
      }
    } catch (e, stack) {
      print('⚠️ [Playlist] Parse browse error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
    }

    return playlists;
  }

  List<CommunityPlaylist> _parseSearchPlaylists(
    Map<String, dynamic> json,
    int limit,
  ) {
    final playlists = <CommunityPlaylist>[];

    try {
      // Debug: Print response structure
      print('🔍 [Debug] Parsing search response...');

      final tabs =
          json['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
      if (tabs == null) {
        print('⚠️ [Debug] No tabs found');
        return playlists;
      }

      for (final tab in tabs) {
        final contents =
            tab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (contents == null) continue;

        print('🔍 [Debug] Found ${contents.length} sections');

        for (final section in contents) {
          final musicShelf = section['musicShelfRenderer'];
          if (musicShelf != null) {
            final items = musicShelf['contents'] as List?;
            if (items != null) {
              print('🔍 [Debug] Found ${items.length} items in shelf');

              for (final item in items) {
                final playlist = _parsePlaylistSearchItem(item);
                if (playlist != null) {
                  print(
                    '✅ [Debug] Parsed: ${playlist.title} (${playlist.songCount} songs)',
                  );
                  playlists.add(playlist);
                  if (playlists.length >= limit) return playlists;
                } else {
                  // Debug why it failed
                  final renderer = item['musicResponsiveListItemRenderer'];
                  if (renderer != null) {
                    final browseId =
                        renderer['navigationEndpoint']?['browseEndpoint']?['browseId']
                            as String?;
                    print('⚠️ [Debug] Skipped item with browseId: $browseId');
                  }
                }
              }
            }
          }
        }
      }

      print('🔍 [Debug] Total playlists parsed: ${playlists.length}');
    } catch (e, stack) {
      print('⚠️ [Playlist] Parse search error: $e');
      print('Stack: ${stack.toString().split('\n').take(5).join('\n')}');
    }

    return playlists;
  }

  CommunityPlaylist? _parsePlaylistGridItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicTwoRowItemRenderer'];
      if (renderer == null) return null;

      // Get playlist ID
      final browseId =
          renderer['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;
      if (browseId == null) return null;

      // Skip non-playlist items
      if (!browseId.startsWith('VL') &&
          !browseId.startsWith('RDAMPL') &&
          !browseId.startsWith('PL'))
        return null;

      // Get title
      final title =
          renderer['title']?['runs']?[0]?['text'] as String? ??
          'Unknown Playlist';

      // Get subtitle (creator/song count)
      String creator = 'YouTube Music';
      int songCount = 0;

      final subtitle = renderer['subtitle']?['runs'] as List?;
      if (subtitle != null && subtitle.isNotEmpty) {
        for (final run in subtitle) {
          final text = run['text'] as String?;
          if (text == null) continue;

          // Try to extract song count
          final match = RegExp(r'(\d+)\s*song').firstMatch(text);
          if (match != null) {
            songCount = int.tryParse(match.group(1)!) ?? 0;
          } else if (!text.contains('•') && !text.contains('song')) {
            // First non-separator text is usually creator
            creator = text;
          }
        }
      }

      // Get thumbnail
      String? thumbnail;
      final thumbnails =
          renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = _extractBestThumbnail(thumbnails);
      }

      return CommunityPlaylist(
        id: browseId,
        title: title,
        creator: creator,
        thumbnail: thumbnail,
        songCount: songCount,
      );
    } catch (e) {
      print('⚠️ Parse grid item error: $e');
      return null;
    }
  }

  CommunityPlaylist? _parsePlaylistCarouselItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicTwoRowItemRenderer'];
      if (renderer == null) return null;

      final browseId =
          renderer['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;
      if (browseId == null) return null;

      if (!browseId.startsWith('VL') &&
          !browseId.startsWith('RDAMPL') &&
          !browseId.startsWith('PL'))
        return null;

      final title =
          renderer['title']?['runs']?[0]?['text'] as String? ??
          'Unknown Playlist';

      String creator = 'YouTube Music';
      int songCount = 0;

      final subtitle = renderer['subtitle']?['runs'] as List?;
      if (subtitle != null && subtitle.isNotEmpty) {
        creator = subtitle[0]['text'] as String? ?? 'YouTube Music';

        for (final run in subtitle) {
          final text = run['text'] as String?;
          if (text != null && text.contains('song')) {
            final match = RegExp(r'(\d+)').firstMatch(text);
            if (match != null) {
              songCount = int.tryParse(match.group(1)!) ?? 0;
            }
          }
        }
      }

      String? thumbnail;
      final thumbnails =
          renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = _extractBestThumbnail(thumbnails);
      }

      return CommunityPlaylist(
        id: browseId,
        title: title,
        creator: creator,
        thumbnail: thumbnail,
        songCount: songCount,
      );
    } catch (e) {
      return null;
    }
  }

  CommunityPlaylist? _parsePlaylistSearchItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      final browseId =
          renderer['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;
      if (browseId == null) return null;

      print('🔍 [Parse] BrowseId: $browseId');

      // ✅ FIXED: Accept playlist based on browseId prefix
      // Valid playlist prefixes:
      // - VL* = Standard playlists
      // - RDAMPL* = Auto-generated mixes
      // - RDCLAK* = YouTube Music official playlists
      // - MPSPPPL* = User-created public playlists
      // - PL* = YouTube playlists (also work in YT Music)
      final isValidPlaylist =
          browseId.startsWith('VL') ||
          browseId.startsWith('RDAMPL') ||
          browseId.startsWith('RDCLAK') ||
          browseId.startsWith('MPSPPPL') ||
          browseId.startsWith('PL');

      if (!isValidPlaylist) {
        print('⚠️ [Parse] Invalid playlist prefix: $browseId');
        return null;
      }

      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) {
        print('⚠️ [Parse] No flexColumns');
        return null;
      }

      // Get title from first column
      final title =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']
              as String? ??
          'Unknown Playlist';

      String creator = 'YouTube Music';
      int songCount = 0;

      // Parse second column for creator and song count
      if (flexColumns.length > 1) {
        final runs =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (runs != null && runs.isNotEmpty) {
          for (final run in runs) {
            final text = run['text'] as String?;
            if (text == null) continue;

            // Extract song count
            if (text.toLowerCase().contains('song')) {
              final match = RegExp(r'(\d+)').firstMatch(text);
              if (match != null) {
                songCount = int.tryParse(match.group(1)!) ?? 0;
              }
            }
            // First non-separator, non-"Playlist" text is usually creator
            else if (!text.contains('•') &&
                text.toLowerCase() != 'playlist' &&
                creator == 'YouTube Music') {
              creator = text;
            }
          }
        }
      }

      String? thumbnail;
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = _extractBestThumbnail(thumbnails);
      }

      print('✅ [Parse] Found playlist: $title by $creator ($songCount songs)');

      return CommunityPlaylist(
        id: browseId,
        title: title,
        creator: creator,
        thumbnail: thumbnail,
        songCount: songCount,
      );
    } catch (e, stack) {
      print('⚠️ [Parse] Error: $e');
      print('Stack: ${stack.toString().split('\n').take(2).join('\n')}');
      return null;
    }
  }

  CommunityPlaylist? _parsePlaylistDetails(
    Map<String, dynamic> json,
    String playlistId,
  ) {
    try {
      print('📋 [Debug] Parsing playlist details...');

      String title = 'Unknown Playlist';
      String creator = 'YouTube Music';
      String? thumbnail;
      final songs = <Song>[];

      // TRY METHOD 1: singleColumnBrowseResultsRenderer (most common)
      var contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      // TRY METHOD 2: twoColumnBrowseResultsRenderer (alternative structure)
      if (contents == null) {
        print('🔍 [Debug] Trying twoColumnBrowseResultsRenderer...');
        contents =
            json['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents']
                as List?;

        // Get header info from primaryContents
        if (contents != null) {
          final primaryContents =
              json['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                  as List?;

          if (primaryContents != null && primaryContents.isNotEmpty) {
            final header =
                primaryContents[0]['musicResponsiveHeaderRenderer'] ??
                primaryContents[0]['musicEditablePlaylistDetailHeaderRenderer'];

            if (header != null) {
              title = header['title']?['runs']?[0]?['text'] as String? ?? title;

              final subtitle = header['subtitle']?['runs'] as List?;
              if (subtitle != null && subtitle.isNotEmpty) {
                creator = subtitle[0]['text'] as String? ?? creator;
              }

              final thumbnails =
                  header['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                  header['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                      as List?;
              if (thumbnails != null && thumbnails.isNotEmpty) {
                thumbnail = _extractBestThumbnail(thumbnails);
              }
            }
          }
        }
      }

      // TRY METHOD 3: Direct from header (for some playlist types)
      if (contents == null) {
        print('🔍 [Debug] Trying header in contents...');
        final rawContents =
            json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']
                as Map?;

        if (rawContents != null) {
          final header =
              rawContents['musicResponsiveHeaderRenderer'] ??
              rawContents['musicEditablePlaylistDetailHeaderRenderer'];

          if (header != null) {
            title = header['title']?['runs']?[0]?['text'] as String? ?? title;

            final subtitle = header['subtitle']?['runs'] as List?;
            if (subtitle != null && subtitle.isNotEmpty) {
              creator = subtitle[0]['text'] as String? ?? creator;
            }

            final thumbnails =
                header['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                header['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                    as List?;
            if (thumbnails != null && thumbnails.isNotEmpty) {
              thumbnail = _extractBestThumbnail(thumbnails);
            }
          }

          // Try to get contents from sectionListRenderer
          contents = rawContents['sectionListRenderer']?['contents'] as List?;
        }
      }

      if (contents == null) {
        print('⚠️ [Debug] Could not find contents in any known structure');
        // Print the actual structure for debugging
        print('📋 [Debug] Available keys: ${json['contents']?.keys.toList()}');
        return null;
      }

      print('✅ [Debug] Found ${contents.length} sections in contents');

      // Parse header and songs from contents
      for (var i = 0; i < contents.length; i++) {
        final section = contents[i];

        // Try to get header if we don't have title yet
        if (title == 'Unknown Playlist') {
          final sectionHeader =
              section['musicResponsiveHeaderRenderer'] ??
              section['musicEditablePlaylistDetailHeaderRenderer'];

          if (sectionHeader != null) {
            print('✅ [Debug] Found playlist header in section $i');

            title =
                sectionHeader['title']?['runs']?[0]?['text'] as String? ??
                title;

            final subtitle = sectionHeader['subtitle']?['runs'] as List?;
            if (subtitle != null && subtitle.isNotEmpty) {
              creator = subtitle[0]['text'] as String? ?? creator;
            }

            final thumbnails =
                sectionHeader['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                sectionHeader['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                    as List?;
            if (thumbnails != null && thumbnails.isNotEmpty) {
              thumbnail = _extractBestThumbnail(thumbnails);
            }

            print('📋 [Debug] Title: $title, Creator: $creator');
          }
        }

        // Try different shelf types for songs
        final shelf =
            section['musicPlaylistShelfRenderer'] ??
            section['musicShelfRenderer'] ??
            section['musicCarouselShelfRenderer'];

        if (shelf != null) {
          final items = shelf['contents'] as List?;
          if (items != null) {
            print('✅ [Debug] Section $i: Found ${items.length} song items');

            for (final item in items) {
              final song = _parsePlaylistSongItem(item);
              if (song != null) {
                songs.add(song);
              }
            }
          }
        }
      }

      print('✅ [Debug] Total songs parsed: ${songs.length}');
      print(
        '📋 [Debug] Final - Title: $title, Creator: $creator, Songs: ${songs.length}',
      );

      // Return playlist if we have meaningful data
      if (songs.isNotEmpty || title != 'Unknown Playlist') {
        return CommunityPlaylist(
          id: playlistId,
          title: title,
          creator: creator,
          thumbnail: thumbnail,
          songCount: songs.length,
          songs: songs,
        );
      }

      print('⚠️ [Debug] Failed to parse playlist - no songs or title found');
      return null;
    } catch (e, stack) {
      print('❌ Parse details error: $e');
      print('Stack: ${stack.toString().split('\n').take(5).join('\n')}');
      return null;
    }
  }
  // ============= HELPER METHODS =============

  Future<http.Response?> _makeRequest(Uri uri, String body) async {
    try {
      final response = await http
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
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        print('⚠️ Request failed: ${response.statusCode}');
        return null;
      }

      return response;
    } catch (e) {
      print('⚠️ Request error: $e');
      return null;
    }
  }

  Song? _parsePlaylistSongItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      String? videoId = renderer['playlistItemData']?['videoId'] as String?;
      videoId ??=
          renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;

      if (videoId == null) return null;

      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      final title =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']
              as String? ??
          'Unknown';

      List<String> artists = ['Unknown Artist'];
      if (flexColumns.length > 1) {
        final runs =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (runs != null && runs.isNotEmpty) {
          for (final run in runs) {
            final text = run['text'] as String?;
            if (text != null && text.trim().isNotEmpty && text != '•') {
              artists = [text.trim()];
              break;
            }
          }
        }
      }

      // 🔥 FIX: Better thumbnail extraction with proper fallback
      String thumbnail = '';

      // Try multiple thumbnail sources in priority order
      final thumbnailSources = [
        renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'],
        renderer['thumbnail']?['thumbnails'],
      ];

      for (final source in thumbnailSources) {
        if (source != null && source is List && source.isNotEmpty) {
          thumbnail = _extractBestThumbnail(source);
          if (thumbnail.isNotEmpty) break;
        }
      }

      // 🔥 CRITICAL FIX: Use proper YouTube thumbnail URL format
      if (thumbnail.isEmpty && videoId.isNotEmpty) {
        // Use maxresdefault first, fallback to hqdefault if 404
        thumbnail = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        print('📸 [Thumbnail] Using YouTube fallback for: $title');
      }

      // 🔥 VALIDATE: Ensure no double suffixes
      if (thumbnail.isNotEmpty) {
        // Remove any accidental double formatting
        thumbnail = thumbnail
            .replaceAll(
              '=w540-h540-l90-rj=w540-h540-l90-rj',
              '=w540-h540-l90-rj',
            )
            .replaceAll(
              RegExp(r'\.jpg=w\d+'),
              '.jpg',
            ); // Remove suffix from .jpg URLs
      }

      print(
        '✅ [Parse Song] $title - Thumbnail: ${thumbnail.isNotEmpty ? thumbnail : "EMPTY"}',
      );

      return Song(
        videoId: videoId,
        title: title,
        artists: artists,
        thumbnail: thumbnail,
        duration: null,
        audioUrl: null,
      );
    } catch (e) {
      print('⚠️ [Parse Song] Error: $e');
      return null;
    }
  }

  String _extractBestThumbnail(List<dynamic> thumbnails) {
    for (var i = thumbnails.length - 1; i >= 0; i--) {
      final url = thumbnails[i]['url'] as String?;
      if (url != null && url.isNotEmpty && url.startsWith('http')) {
        // 🔥 FIX: Handle different URL formats correctly

        // If it's already a high-quality ytimg URL with extension, use as-is
        if (url.contains('ytimg.com') &&
            (url.contains('.jpg') || url.contains('.webp'))) {
          // Clean any existing query params first
          final baseUrl = url.split('?')[0];
          // Don't add suffix if it already has an extension
          if (baseUrl.endsWith('.jpg') || baseUrl.endsWith('.webp')) {
            // Return high-quality version without double-formatting
            return baseUrl.replaceAll(
              RegExp(r'(hqdefault|mqdefault|sddefault|maxresdefault)'),
              'hqdefault',
            );
          }
        }

        // For other URLs (music.youtube.com, lh3.googleusercontent.com, etc.)
        // Clean and add proper suffix
        final cleanUrl = url.split('=w')[0].split('?')[0];

        // Don't add suffix if it has a file extension
        if (cleanUrl.endsWith('.jpg') ||
            cleanUrl.endsWith('.webp') ||
            cleanUrl.endsWith('.png')) {
          return cleanUrl;
        }

        // Only add formatting suffix for URLs without extensions
        return '$cleanUrl=w540-h540-l90-rj';
      }
    }
    return '';
  }
}

// ============= MODEL CLASS =============

class CommunityPlaylist {
  final String id;
  final String title;
  final String creator;
  final String? thumbnail;
  final int songCount;
  final List<Song>? songs;

  CommunityPlaylist({
    required this.id,
    required this.title,
    required this.creator,
    this.thumbnail,
    this.songCount = 0,
    this.songs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'creator': creator,
    'thumbnail': thumbnail,
    'songCount': songCount,
    'songs': songs
        ?.map(
          (s) => {
            'videoId': s.videoId,
            'title': s.title,
            'artists': s.artists,
            'thumbnail': s.thumbnail,
          },
        )
        .toList(),
  };

  factory CommunityPlaylist.fromJson(Map<String, dynamic> json) {
    return CommunityPlaylist(
      id: json['id'] as String,
      title: json['title'] as String,
      creator: json['creator'] as String,
      thumbnail: json['thumbnail'] as String?,
      songCount: json['songCount'] as int? ?? 0,
      songs: (json['songs'] as List?)
          ?.map(
            (s) => Song(
              videoId: s['videoId'],
              title: s['title'],
              artists: List<String>.from(s['artists']),
              thumbnail: s['thumbnail'],
              duration: null,
              audioUrl: null,
            ),
          )
          .toList(),
    );
  }
}
