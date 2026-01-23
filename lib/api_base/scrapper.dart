import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:vibeflow/api_base/albumartistqp_cache.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/audio_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/models/song_model.dart';

/// FIXED: Multi-client scraper matching Outertune/InnerTune architecture
class YouTubeMusicScraper {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _androidApiKey =
      'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w';
  static const String _musicApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  // ============= MULTIPLE CLIENTS (like Outertune) =============

  static const _clients = [
    // Primary: ANDROID (most reliable from your working code)
    (
      name: 'ANDROID',
      version: '19.09.37',
      code: '3',
      ua: 'com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip',
      needsAuth: false,
    ),
    // Fallback 1: IOS
    (
      name: 'IOS',
      version: '19.09.3',
      code: '5',
      ua: 'com.google.ios.youtube/19.09.3 (iPhone14,3; U; CPU iOS 15_6 like Mac OS X)',
      needsAuth: false,
    ),
    // Fallback 2: ANDROID_TESTSUITE
    (
      name: 'ANDROID_TESTSUITE',
      version: '1.9',
      code: '30',
      ua: 'com.google.android.youtube/1.9 (Linux; U; Android 13; en_US)',
      needsAuth: false,
    ),
  ];

  final Map<String, _CacheEntry> _urlCache = {};
  final int _maxCacheSize = 50;
  final http.Client _httpClient;
  final Duration _timeout;

  YouTubeMusicScraper({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  /// Get audio URL with multi-client fallback
  /// Get audio URL with multi-client fallback
  Future<String?> getAudioUrl(
    String videoId, {
    AudioQuality quality = AudioQuality.high,
    bool forceRefresh = false,
  }) async {
    try {
      print('🎵 [YTScraper] Fetching audio URL: $videoId');

      if (!forceRefresh) {
        final cached = _getCachedUrl(videoId);
        if (cached != null) {
          print('⚡ [YTScraper] Using cached URL');
          return cached.url;
        }
      }

      // Try each client until one works
      for (final client in _clients) {
        print('📱 [YTScraper] Trying ${client.name}...');

        try {
          final url = await _tryClient(videoId, client, quality);
          if (url != null) {
            print('✅ [YTScraper] ${client.name} worked!');
            _cacheUrl(videoId, url);
            return url;
          }
        } catch (e) {
          print('⚠️ [YTScraper] ${client.name} error: $e');
          continue;
        }
      }

      print('❌ [YTScraper] All clients failed');
      return null;
    } catch (e, stack) {
      print('❌ [YTScraper] Fatal error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      return null;
    }
  }

  /// Try to get URL from specific client
  /// Try to get URL from specific client
  /// Try to get URL from specific client
  Future<String?> _tryClient(
    String videoId,
    ({String name, String version, String code, String ua, bool needsAuth})
    client,
    AudioQuality quality,
  ) async {
    final uri = Uri.parse('$_baseUrl/player?key=$_androidApiKey');

    final body = jsonEncode({
      'context': {
        'client': {
          'clientName': client.name,
          'clientVersion': client.version,
          if (client.name == 'ANDROID' || client.name == 'ANDROID_TESTSUITE')
            'androidSdkVersion': 33,
          if (client.name == 'IOS') ...{
            'deviceMake': 'Apple',
            'deviceModel': 'iPhone14,3',
            'osName': 'iPhone',
            'osVersion': '15.6.0.19G71',
          },
          'hl': 'en',
          'gl': 'US',
        },
      },
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    });

    final headers = {
      'Content-Type': 'application/json',
      'User-Agent': client.ua,
      'X-YouTube-Client-Name': client.code,
      'X-YouTube-Client-Version': client.version,
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Accept-Language': 'en-US',
    };

    final response = await _httpClient
        .post(uri, headers: headers, body: body)
        .timeout(_timeout);

    if (response.statusCode != 200) {
      return null;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    // Check playability
    final status = json['playabilityStatus']?['status'];
    if (status != 'OK') {
      print('⚠️ [${client.name}] Not playable: $status');
      return null;
    }

    // Get streaming data
    final streamingData = json['streamingData'] as Map<String, dynamic>?;
    if (streamingData == null) return null;

    // Get audio formats
    final formats =
        (streamingData['adaptiveFormats'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    final audioFormats = formats.where((f) {
      final mime = f['mimeType'] as String?;
      return mime != null && mime.startsWith('audio/') && f.containsKey('url');
    }).toList();

    if (audioFormats.isEmpty) return null;

    // Select best format (prefer opus 251)
    final opus251 = audioFormats.firstWhere(
      (f) => f['itag'] == 251,
      orElse: () => <String, dynamic>{},
    );

    final selectedFormat = opus251.isNotEmpty
        ? opus251
        : (audioFormats..sort((a, b) {
                final ba = (a['bitrate'] as int?) ?? 0;
                final bb = (b['bitrate'] as int?) ?? 0;
                return bb.compareTo(ba);
              }))
              .first;

    print('🎯 [${client.name}] Format: itag=${selectedFormat['itag']}');

    final url = selectedFormat['url'] as String?;

    // Return URL directly without validation - the player will handle any issues
    return url;
  }

  /// Validate URL with HEAD request
  Future<bool> _validateUrl(String url, String userAgent) async {
    try {
      final request = http.Request('HEAD', Uri.parse(url));
      request.headers.addAll({
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
      });

      final response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 5));
      await response.stream.drain();

      final valid = response.statusCode == 200 || response.statusCode == 206;
      print('🧪 [Validation] ${response.statusCode} ${valid ? "✅" : "❌"}');
      return valid;
    } catch (e) {
      print('🧪 [Validation] Error: $e');
      return false;
    }
  }

  /// Get Quick Picks from home feed
  /// Get Quick Picks from home feed with 24-hour cache
  Future<List<Song>> getQuickPicks({
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    try {
      // Try loading from cache first (unless force refresh)
      if (!forceRefresh) {
        final cachedQuickPicks = await AlbumArtistQPCache.loadQuickPicks();
        if (cachedQuickPicks != null && cachedQuickPicks.isNotEmpty) {
          print('⚡ [YTScraper] Using cached Quick Picks');
          // Convert QuickPick to Song
          return cachedQuickPicks
              .map(
                (qp) => Song(
                  videoId: qp.videoId,
                  title: qp.title,
                  artists: [qp.artists],
                  thumbnail: qp.thumbnail,
                  duration: qp.duration,
                  audioUrl: null,
                ),
              )
              .toList();
        }
      }

      print('🎯 [YTScraper] Fetching Quick Picks from API...');

      final uri = Uri.parse('$_baseUrl/browse?key=$_musicApiKey');

      final body = jsonEncode({
        'context': _buildMusicContext(),
        'browseId': 'FEmusic_home',
      });

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Quick Picks failed: ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final songs = _parseQuickPicks(json, limit);

      // Save to cache
      if (songs.isNotEmpty) {
        final quickPicks = songs
            .map(
              (song) => QuickPick(
                videoId: song.videoId,
                title: song.title,
                artists: song.artists.isNotEmpty
                    ? song.artists.first
                    : 'Unknown',
                thumbnail: song.thumbnail,
                duration: song.duration,
              ),
            )
            .toList();

        await AlbumArtistQPCache.saveQuickPicks(quickPicks);
      }

      print('✅ [YTScraper] Found ${songs.length} Quick Picks');
      return songs;
    } catch (e) {
      print('❌ [YTScraper] Quick Picks error: $e');
      return [];
    }
  }

  List<Song> _parseQuickPicks(Map<String, dynamic> json, int limit) {
    final songs = <Song>[];

    try {
      final contents = json['contents'];
      if (contents == null) return songs;

      final singleColumn = contents['singleColumnBrowseResultsRenderer'];
      if (singleColumn == null) return songs;

      final tabs = singleColumn['tabs'] as List?;
      if (tabs == null || tabs.isEmpty) return songs;

      for (final tab in tabs) {
        final tabRenderer = tab['tabRenderer'];
        if (tabRenderer == null) continue;

        final content = tabRenderer['content'];
        if (content == null) continue;

        final sectionListRenderer = content['sectionListRenderer'];
        if (sectionListRenderer == null) continue;

        final sections = sectionListRenderer['contents'] as List?;
        if (sections == null) continue;

        for (
          int sectionIndex = 0;
          sectionIndex < sections.length;
          sectionIndex++
        ) {
          final section = sections[sectionIndex];

          final itemSection = section['itemSectionRenderer'];
          if (itemSection != null) {
            final sectionContents = itemSection['contents'] as List?;
            if (sectionContents != null && sectionContents.isNotEmpty) {
              for (final subItem in sectionContents) {
                final elementRenderer = subItem['elementRenderer'];
                if (elementRenderer != null) {
                  final model =
                      elementRenderer['newElement']?['type']?['componentType']?['model'];
                  if (model != null) {
                    // Handle musicListItemCarouselModel
                    final listCarousel = model['musicListItemCarouselModel'];
                    if (listCarousel != null) {
                      final items = listCarousel['items'] as List?;
                      if (items != null) {
                        for (final item in items) {
                          final song = _parseElementCarouselItem(item);
                          if (song != null) {
                            songs.add(song);
                            if (songs.length >= limit) return songs;
                          }
                        }
                      }
                    }

                    // Handle musicGridItemCarouselModel
                    final gridCarousel = model['musicGridItemCarouselModel'];
                    if (gridCarousel != null) {
                      final shelf = gridCarousel['shelf'];
                      if (shelf != null) {
                        final items = shelf['items'] as List?;
                        if (items != null) {
                          for (final item in items) {
                            final song = _parseElementCarouselItem(item);
                            if (song != null) {
                              songs.add(song);
                              if (songs.length >= limit) return songs;
                            }
                          }
                        }
                      }
                    }
                  }
                  continue;
                }

                // Handle musicCarouselShelfRenderer
                final carousel = subItem['musicCarouselShelfRenderer'];
                if (carousel != null) {
                  final items = carousel['contents'] as List?;
                  if (items != null) {
                    for (final item in items) {
                      final song = _parseCarouselItem(item);
                      if (song != null) {
                        songs.add(song);
                        if (songs.length >= limit) return songs;
                      }
                    }
                  }
                }

                // Handle musicShelfRenderer
                final shelf = subItem['musicShelfRenderer'];
                if (shelf != null) {
                  final items = shelf['contents'] as List?;
                  if (items != null) {
                    for (final item in items) {
                      final song = _parseSongItem(item);
                      if (song != null) {
                        songs.add(song);
                        if (songs.length >= limit) return songs;
                      }
                    }
                  }
                }
              }
            }
            continue;
          }

          // Handle direct musicCarouselShelfRenderer
          final carousel = section['musicCarouselShelfRenderer'];
          if (carousel != null) {
            final items = carousel['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final song = _parseCarouselItem(item);
                if (song != null) {
                  songs.add(song);
                  if (songs.length >= limit) return songs;
                }
              }
            }
          }

          // Handle musicShelfRenderer
          final shelf = section['musicShelfRenderer'];
          if (shelf != null) {
            final items = shelf['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final song = _parseSongItem(item);
                if (song != null) {
                  songs.add(song);
                  if (songs.length >= limit) return songs;
                }
              }
            }
          }
        }
      }
    } catch (e, stack) {
      print('⚠️ [YTScraper] Parse Quick Picks error: $e');
      print('Stack: ${stack.toString().split('\n').take(5).join('\n')}');
    }

    return songs;
  }

  Song? _parseElementCarouselItem(Map<String, dynamic> item) {
    try {
      // Get video ID from onTap navigation
      String? videoId;
      final onTap = item['onTap'];
      if (onTap != null) {
        videoId =
            onTap['innertubeCommand']?['watchEndpoint']?['videoId'] as String?;
      }

      if (videoId == null) return null;

      // Get title
      final titleData = item['title'];
      String title = 'Unknown';
      if (titleData != null) {
        if (titleData is String) {
          title = titleData;
        } else if (titleData is Map && titleData.containsKey('runs')) {
          final runs = titleData['runs'] as List?;
          if (runs != null && runs.isNotEmpty) {
            title = runs[0]['text'] ?? 'Unknown';
          }
        }
      }

      // Get artists from subtitle
      final subtitleData = item['subtitle'];
      List<String> artists = ['Unknown Artist'];
      if (subtitleData != null) {
        if (subtitleData is String) {
          artists = [subtitleData];
        } else if (subtitleData is Map && subtitleData.containsKey('runs')) {
          final runs = subtitleData['runs'] as List?;
          if (runs != null && runs.isNotEmpty) {
            artists = [runs[0]['text'] ?? 'Unknown Artist'];
          }
        }
      }

      // Get high-quality thumbnail - try multiple paths
      String thumbnail = '';

      // Path 1: item['thumbnail']['thumbnails']
      final thumbnailData = item['thumbnail'];
      if (thumbnailData != null && thumbnailData is Map) {
        final thumbnails = thumbnailData['thumbnails'] as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnail = _extractBestThumbnail(thumbnails);
        }
      }

      // Path 2: Try direct image path
      if (thumbnail.isEmpty) {
        final image = item['image'];
        if (image != null && image is Map) {
          final thumbnails = image['thumbnails'] as List?;
          if (thumbnails != null && thumbnails.isNotEmpty) {
            thumbnail = _extractBestThumbnail(thumbnails);
          }
        }
      }

      // Path 3: Try musicThumbnailRenderer
      if (thumbnail.isEmpty) {
        final thumbRenderer = thumbnailData?['musicThumbnailRenderer'];
        if (thumbRenderer != null) {
          final thumbnails = thumbRenderer['thumbnail']?['thumbnails'] as List?;
          if (thumbnails != null && thumbnails.isNotEmpty) {
            thumbnail = _extractBestThumbnail(thumbnails);
          }
        }
      }

      // Fallback: Generate thumbnail from video ID
      if (thumbnail.isEmpty) {
        thumbnail = 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';
        print('⚠️ [YTScraper] Using fallback thumbnail for $videoId');
      }

      return Song(
        videoId: videoId,
        title: title,
        artists: artists,
        thumbnail: thumbnail,
        duration: null,
        audioUrl: null,
      );
    } catch (e) {
      print('⚠️ [YTScraper] Error parsing element carousel item: $e');
      return null;
    }
  }

  Song? _parseCarouselItem(Map<String, dynamic> item) {
    try {
      // Try musicTwoRowItemRenderer first
      var renderer = item['musicTwoRowItemRenderer'];
      if (renderer != null) {
        final videoId =
            renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
                as String?;
        if (videoId == null) return null;

        final title =
            renderer['title']?['runs']?[0]?['text'] as String? ?? 'Unknown';
        final subtitle = renderer['subtitle']?['runs']?[0]?['text'] as String?;
        final artists = subtitle != null ? [subtitle] : ['Unknown Artist'];

        String thumbnail = '';

        // Path 1: thumbnailRenderer
        final thumbnails =
            renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnail = _extractBestThumbnail(thumbnails);
        }

        // Path 2: Direct thumbnail
        if (thumbnail.isEmpty) {
          final directThumbs = renderer['thumbnail']?['thumbnails'] as List?;
          if (directThumbs != null && directThumbs.isNotEmpty) {
            thumbnail = _extractBestThumbnail(directThumbs);
          }
        }

        // Fallback
        if (thumbnail.isEmpty) {
          thumbnail = 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';
          print('⚠️ [YTScraper] Using fallback thumbnail for $videoId');
        }

        return Song(
          videoId: videoId,
          title: title,
          artists: artists,
          thumbnail: thumbnail,
          duration: null,
          audioUrl: null,
        );
      }

      // Try musicResponsiveListItemRenderer (alternative format)
      renderer = item['musicResponsiveListItemRenderer'];
      if (renderer != null) {
        return _parseSongItem(item);
      }

      return null;
    } catch (e) {
      print('⚠️ [YTScraper] Parse carousel item error: $e');
      return null;
    }
  }

  Song? _parseSongItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      // Get video ID
      String? videoId = renderer['playlistItemData']?['videoId'] as String?;
      videoId ??=
          renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;

      if (videoId == null) return null;

      // Get title and artist
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      final title =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']
              as String? ??
          'Unknown';

      List<String> artists = ['Unknown Artist'];
      if (flexColumns.length > 1) {
        final artistText =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']
                as String?;
        if (artistText != null && artistText.isNotEmpty) {
          artists = [artistText];
        }
      }

      String thumbnail = '';

      // Path 1: musicThumbnailRenderer
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = _extractBestThumbnail(thumbnails);
      }

      // Path 2: Direct thumbnail
      if (thumbnail.isEmpty) {
        final directThumbs = renderer['thumbnail']?['thumbnails'] as List?;
        if (directThumbs != null && directThumbs.isNotEmpty) {
          thumbnail = _extractBestThumbnail(directThumbs);
        }
      }

      // Fallback
      if (thumbnail.isEmpty) {
        thumbnail = 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';
        print('⚠️ [YTScraper] Using fallback thumbnail for $videoId');
      }

      return Song(
        videoId: videoId,
        title: title,
        artists: artists,
        thumbnail: thumbnail,
        duration: null,
        audioUrl: null,
      );
    } catch (e) {
      print('⚠️ [YTScraper] Parse song item error: $e');
      return null;
    }
  }

  // Add this helper method to extract best thumbnail
  String _extractBestThumbnail(List<dynamic> thumbnails) {
    for (var i = thumbnails.length - 1; i >= 0; i--) {
      final url = thumbnails[i]['url'] as String?;
      if (url != null &&
          url.isNotEmpty &&
          (url.startsWith('http://') || url.startsWith('https://'))) {
        // Clean URL and request high quality
        final cleanUrl = url.split('=w')[0].split('?')[0];
        return '$cleanUrl=w960-h960-l90-rj';
      }
    }
    return '';
  }

  /// Search songs
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    try {
      print('🔍 [YTScraper] Searching: "$query"');

      final uri = Uri.parse('$_baseUrl/search?key=$_musicApiKey');

      final body = jsonEncode({
        'context': _buildMusicContext(),
        'query': query,
        'params': 'EgWKAQIIAWoKEAMQBBAJEAoQBQ%3D%3D',
      });

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Search failed: ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final songs = _parseSearchResults(json, limit);

      print('✅ [YTScraper] Found ${songs.length} songs');
      return songs;
    } catch (e) {
      print('❌ [YTScraper] Search error: $e');
      return [];
    }
  }

  List<Song> _parseSearchResults(Map<String, dynamic> json, int limit) {
    final songs = <Song>[];

    try {
      final tabs =
          json['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
      if (tabs == null) return songs;

      for (final tab in tabs) {
        final contents =
            tab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (contents == null) continue;

        for (final section in contents) {
          final musicShelf = section['musicShelfRenderer'];
          if (musicShelf != null) {
            final items = musicShelf['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final song = _parseSongItem(item);
                if (song != null) {
                  songs.add(song);
                  if (songs.length >= limit) return songs;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ [YTScraper] Parse error: $e');
    }

    return songs;
  }
  // ==============================================================================================================================
  // ==============================================================================================================================

  /// Search albums
  Future<List<Album>> searchAlbums(String query, {int limit = 20}) async {
    try {
      print('🔍 [YTScraper] Searching albums: "$query"');

      final uri = Uri.parse('$_baseUrl/search?key=$_musicApiKey');

      final body = jsonEncode({
        'context': _buildMusicContext(),
        'query': query,
        'params': 'EgWKAQIYAWoKEAMQBBAJEAoQBQ%3D%3D', // Album filter
      });

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Album search failed: ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final albums = _parseAlbumResults(json, limit);

      print('✅ [YTScraper] Found ${albums.length} albums');
      return albums;
    } catch (e) {
      print('❌ [YTScraper] Album search error: $e');
      return [];
    }
  }

  List<Album> _parseAlbumResults(Map<String, dynamic> json, int limit) {
    final albums = <Album>[];

    try {
      // Debug: Print response structure
      print('🔍 Album response keys: ${json.keys}');

      final tabs =
          json['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
      if (tabs == null) {
        print('⚠️ No tabs found in response');
        return albums;
      }

      for (final tab in tabs) {
        final contents =
            tab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (contents == null) continue;

        for (final section in contents) {
          // Try musicShelfRenderer
          final musicShelf = section['musicShelfRenderer'];
          if (musicShelf != null) {
            final items = musicShelf['contents'] as List?;
            if (items != null) {
              print('📦 Found ${items.length} items in musicShelfRenderer');
              for (final item in items) {
                final album = _parseAlbumItem(item);
                if (album != null) {
                  albums.add(album);
                  print('✅ Parsed album: ${album.title}');
                  if (albums.length >= limit) return albums;
                }
              }
            }
          }

          // Also try musicCardShelfRenderer (alternative structure)
          final cardShelf = section['musicCardShelfRenderer'];
          if (cardShelf != null) {
            print('📦 Found musicCardShelfRenderer');
            final album = _parseCardShelfAlbum(cardShelf);
            if (album != null) {
              albums.add(album);
              print('✅ Parsed card album: ${album.title}');
              if (albums.length >= limit) return albums;
            }
          }
        }
      }
    } catch (e, stack) {
      print('⚠️ [YTScraper] Parse album error: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
    }

    return albums;
  }

  Album? _parseCardShelfAlbum(Map<String, dynamic> cardShelf) {
    try {
      // Get browse ID
      final browseId =
          cardShelf['title']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;
      if (browseId == null) return null;

      // Get title
      final title =
          cardShelf['title']?['runs']?[0]?['text'] as String? ??
          'Unknown Album';

      // Get artist
      String artist = 'Unknown Artist';
      final subtitle = cardShelf['subtitle']?['runs'] as List?;
      if (subtitle != null && subtitle.isNotEmpty) {
        artist = subtitle[0]['text'] as String? ?? 'Unknown Artist';
      }

      // Get year
      int year = 0;
      if (subtitle != null) {
        for (final run in subtitle) {
          final text = run['text'] as String?;
          if (text != null) {
            final yearMatch = RegExp(r'(\d{4})').firstMatch(text);
            if (yearMatch != null) {
              year = int.tryParse(yearMatch.group(1)!) ?? 0;
              break;
            }
          }
        }
      }

      // Get thumbnail
      String? coverArt;
      final thumbnails =
          cardShelf['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        coverArt = _extractBestThumbnail(thumbnails);
      }

      return Album(
        id: browseId,
        title: title,
        artist: artist,
        coverArt: coverArt?.isNotEmpty == true ? coverArt : null,
        year: year,
        songs: [],
      );
    } catch (e) {
      print('⚠️ [YTScraper] Parse card album error: $e');
      return null;
    }
  }

  Album? _parseAlbumItem(Map<String, dynamic> item) {
    try {
      // Debug: Print what keys this item has
      print('🔍 Item keys: ${item.keys.toList()}');

      // Try multiple renderer types
      var renderer = item['musicResponsiveListItemRenderer'];

      // Try musicTwoRowItemRenderer (common for albums)
      if (renderer == null) {
        renderer = item['musicTwoRowItemRenderer'];
        if (renderer != null) {
          print('✅ Found musicTwoRowItemRenderer');
          return _parseAlbumFromTwoRowItem(renderer);
        }
      }

      if (renderer == null) {
        print('⚠️ No known renderer found in item');
        return null;
      }

      // Get browse ID (album ID) - try multiple paths
      String? browseId =
          renderer['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;

      // Alternative path
      browseId ??=
          renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchPlaylistEndpoint']?['playlistId']
              as String?;

      if (browseId == null) {
        print('⚠️ No browseId found');
        return null;
      }

      // Get title and artist
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) {
        print('⚠️ No flexColumns found');
        return null;
      }

      final title =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']
              as String? ??
          'Unknown Album';

      String artist = 'Unknown Artist';
      int year = 0;

      if (flexColumns.length > 1) {
        final runs =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (runs != null && runs.isNotEmpty) {
          // First run is usually the artist
          artist = runs[0]['text'] as String? ?? 'Unknown Artist';

          // Try to find year in subsequent runs
          for (final run in runs) {
            final text = run['text'] as String?;
            if (text != null) {
              final yearMatch = RegExp(r'(\d{4})').firstMatch(text);
              if (yearMatch != null) {
                year = int.tryParse(yearMatch.group(1)!) ?? 0;
                break;
              }
            }
          }
        }
      }

      // Get thumbnail - try multiple paths
      String coverArt = '';

      // Path 1: musicThumbnailRenderer
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        coverArt = _extractBestThumbnail(thumbnails);
      }

      // Path 2: Direct thumbnail
      if (coverArt.isEmpty) {
        final directThumbs = renderer['thumbnail']?['thumbnails'] as List?;
        if (directThumbs != null && directThumbs.isNotEmpty) {
          coverArt = _extractBestThumbnail(directThumbs);
        }
      }

      print('📀 Parsed: $title by $artist (ID: $browseId)');

      return Album(
        id: browseId,
        title: title,
        artist: artist,
        coverArt: coverArt.isNotEmpty ? coverArt : null,
        year: year,
        songs: [],
      );
    } catch (e, stack) {
      print('⚠️ [YTScraper] Parse album item error: $e');
      print('Stack: ${stack.toString().split('\n').take(2).join('\n')}');
      return null;
    }
  }

  // New method to parse musicTwoRowItemRenderer
  Album? _parseAlbumFromTwoRowItem(Map<String, dynamic> renderer) {
    try {
      // Get browse ID
      final browseId =
          renderer['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;
      if (browseId == null) {
        print('⚠️ No browseId in TwoRowItem');
        return null;
      }

      // Get title
      final title =
          renderer['title']?['runs']?[0]?['text'] as String? ?? 'Unknown Album';

      // Get artist from subtitle
      String artist = 'Unknown Artist';
      int year = 0;

      final subtitle = renderer['subtitle']?['runs'] as List?;
      if (subtitle != null && subtitle.isNotEmpty) {
        artist = subtitle[0]['text'] as String? ?? 'Unknown Artist';

        // Find year
        for (final run in subtitle) {
          final text = run['text'] as String?;
          if (text != null) {
            final yearMatch = RegExp(r'(\d{4})').firstMatch(text);
            if (yearMatch != null) {
              year = int.tryParse(yearMatch.group(1)!) ?? 0;
              break;
            }
          }
        }
      }

      // Get thumbnail
      String? coverArt;

      // Try thumbnailRenderer path
      final thumbnails =
          renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        coverArt = _extractBestThumbnail(thumbnails);
      }

      // Try direct thumbnail path
      if (coverArt == null || coverArt.isEmpty) {
        final directThumbs = renderer['thumbnail']?['thumbnails'] as List?;
        if (directThumbs != null && directThumbs.isNotEmpty) {
          coverArt = _extractBestThumbnail(directThumbs);
        }
      }

      print('📀 Parsed TwoRow: $title by $artist (ID: $browseId)');

      return Album(
        id: browseId,
        title: title,
        artist: artist,
        coverArt: coverArt?.isNotEmpty == true ? coverArt : null,
        year: year,
        songs: [],
      );
    } catch (e, stack) {
      print('⚠️ Parse TwoRow album error: $e');
      print('Stack: ${stack.toString().split('\n').take(2).join('\n')}');
      return null;
    }
  }

  /// Get album details with songs
  Future<Album?> getAlbumDetails(String browseId) async {
    try {
      print('📀 [YTScraper] Fetching album: $browseId');

      final uri = Uri.parse('$_baseUrl/browse?key=$_musicApiKey');

      final body = jsonEncode({
        'context': _buildMusicContext(),
        'browseId': browseId,
      });

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Album details failed: ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final album = _parseAlbumDetails(json, browseId);

      print('✅ [YTScraper] Album loaded: ${album?.songs.length ?? 0} songs');
      return album;
    } catch (e) {
      print('❌ [YTScraper] Album details error: $e');
      return null;
    }
  }

  Album? _parseAlbumDetails(Map<String, dynamic> json, String browseId) {
    try {
      // Get header info
      final header = json['header']?['musicDetailHeaderRenderer'];
      if (header == null) return null;

      final title =
          header['title']?['runs']?[0]?['text'] as String? ?? 'Unknown Album';

      String artist = 'Unknown Artist';
      int year = 0;

      final subtitle = header['subtitle']?['runs'] as List?;
      if (subtitle != null && subtitle.isNotEmpty) {
        artist = subtitle[0]['text'] as String? ?? 'Unknown Artist';

        // Find year
        for (final run in subtitle) {
          final text = run['text'] as String?;
          if (text != null) {
            final yearMatch = RegExp(r'(\d{4})').firstMatch(text);
            if (yearMatch != null) {
              year = int.tryParse(yearMatch.group(1)!) ?? 0;
              break;
            }
          }
        }
      }

      // Get thumbnail
      String? coverArt;
      final thumbnails =
          header['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        coverArt = _extractBestThumbnail(thumbnails);
      }

      // Get songs
      final songs = <Song>[];
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicShelfRenderer'];
          if (shelf != null) {
            final items = shelf['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final song = _parseSongItem(item);
                if (song != null) {
                  songs.add(song);
                }
              }
            }
          }
        }
      }

      return Album(
        id: browseId,
        title: title,
        artist: artist,
        coverArt: coverArt,
        year: year,
        songs: songs,
      );
    } catch (e) {
      print('⚠️ [YTScraper] Parse album details error: $e');
      return null;
    }
  }

  // ==============================================================================================================================
  // ==============================================================================================================================

  /// Search artists
  Future<List<Artist>> searchArtists(String query, {int limit = 20}) async {
    try {
      print('🔍 [YTScraper] Searching artists: "$query"');

      final uri = Uri.parse('$_baseUrl/search?key=$_musicApiKey');

      final body = jsonEncode({
        'context': _buildMusicContext(),
        'query': query,
        'params': 'EgWKAQIgAWoKEAMQBBAJEAoQBQ%3D%3D', // Artist filter
      });

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Artist search failed: ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final artists = _parseArtistResults(json, limit);

      print('✅ [YTScraper] Found ${artists.length} artists');
      return artists;
    } catch (e) {
      print('❌ [YTScraper] Artist search error: $e');
      return [];
    }
  }

  List<Artist> _parseArtistResults(Map<String, dynamic> json, int limit) {
    final artists = <Artist>[];

    try {
      final tabs =
          json['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
      if (tabs == null) return artists;

      for (final tab in tabs) {
        final contents =
            tab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (contents == null) continue;

        for (final section in contents) {
          final musicShelf = section['musicShelfRenderer'];
          if (musicShelf != null) {
            final items = musicShelf['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final artist = _parseArtistItem(item);
                if (artist != null) {
                  artists.add(artist);
                  if (artists.length >= limit) return artists;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ [YTScraper] Parse artist error: $e');
    }

    return artists;
  }

  Artist? _parseArtistItem(Map<String, dynamic> item) {
    try {
      final renderer = item['musicResponsiveListItemRenderer'];
      if (renderer == null) return null;

      // Get browse ID (artist channel ID)
      final browseId =
          renderer['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;
      if (browseId == null) return null;

      // Get name
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      final name =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text']
              as String? ??
          'Unknown Artist';

      // Get subscribers
      String subscribers = '';
      if (flexColumns.length > 1) {
        final runs =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (runs != null && runs.isNotEmpty) {
          subscribers = runs[0]['text'] as String? ?? '';
        }
      }

      // Get profile image
      String? profileImage;
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        profileImage = _extractBestThumbnail(thumbnails);
      }

      return Artist(
        id: browseId,
        name: name,
        profileImage: profileImage,
        subscribers: subscribers,
      );
    } catch (e) {
      print('⚠️ [YTScraper] Parse artist item error: $e');
      return null;
    }
  }

  /// Get artist details with top songs
  Future<Map<String, dynamic>?> getArtistDetails(String browseId) async {
    try {
      print('👤 [YTScraper] Fetching artist: $browseId');

      final uri = Uri.parse('$_baseUrl/browse?key=$_musicApiKey');

      final body = jsonEncode({
        'context': _buildMusicContext(),
        'browseId': browseId,
      });

      final response = await _httpClient
          .post(uri, headers: _getMusicHeaders(), body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Artist details failed: ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final details = _parseArtistDetails(json, browseId);

      print('✅ [YTScraper] Artist loaded');
      return details;
    } catch (e) {
      print('❌ [YTScraper] Artist details error: $e');
      return null;
    }
  }

  Map<String, dynamic>? _parseArtistDetails(
    Map<String, dynamic> json,
    String browseId,
  ) {
    try {
      // Get header info
      final header =
          json['header']?['musicImmersiveHeaderRenderer'] ??
          json['header']?['musicVisualHeaderRenderer'];
      if (header == null) return null;

      final name =
          header['title']?['runs']?[0]?['text'] as String? ?? 'Unknown Artist';

      String subscribers = '';
      final subtitle =
          header['subscriptionButton']?['subscribeButtonRenderer']?['subscriberCountText']?['runs']?[0]?['text']
              as String?;
      if (subtitle != null) {
        subscribers = subtitle;
      }

      // Get thumbnail
      String? profileImage;
      final thumbnails =
          header['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        profileImage = _extractBestThumbnail(thumbnails);
      }

      final artist = Artist(
        id: browseId,
        name: name,
        profileImage: profileImage,
        subscribers: subscribers,
      );

      // Get top songs
      final songs = <Song>[];
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicShelfRenderer'];
          if (shelf != null) {
            final items = shelf['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final song = _parseSongItem(item);
                if (song != null) {
                  songs.add(song);
                }
              }
            }
          }
        }
      }

      return {'artist': artist, 'topSongs': songs};
    } catch (e) {
      print('⚠️ [YTScraper] Parse artist details error: $e');
      return null;
    }
  }

  // ==============================================================================================================================
  // ==============================================================================================================================

  Map<String, dynamic> _buildMusicContext() {
    return {
      'client': {
        'clientName': 'ANDROID_MUSIC',
        'clientVersion': '6.42.52',
        'androidSdkVersion': 33,
        'hl': 'en',
        'gl': 'US',
      },
    };
  }

  Map<String, String> _getMusicHeaders() {
    return {
      'Content-Type': 'application/json',
      'User-Agent':
          'com.google.android.apps.youtube.music/6.42.52 (Linux; U; Android 13; en_US)',
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Accept-Language': 'en-US',
    };
  }

  _CacheEntry? _getCachedUrl(String videoId) => _urlCache[videoId];

  void _cacheUrl(String videoId, String url) {
    if (_urlCache.length >= _maxCacheSize) {
      final oldest = _urlCache.entries
          .reduce(
            (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b,
          )
          .key;
      _urlCache.remove(oldest);
    }
    _urlCache[videoId] = _CacheEntry(url: url, timestamp: DateTime.now());
  }

  void invalidateCache(String videoId) => _urlCache.remove(videoId);
  void clearCache() => _urlCache.clear();

  void dispose() {
    _urlCache.clear();
    _httpClient.close();
  }
}

class _CacheEntry {
  final String url;
  final DateTime timestamp;
  _CacheEntry({required this.url, required this.timestamp});
  int get age => DateTime.now().difference(timestamp).inSeconds;
}

class ScraperException implements Exception {
  final String message;
  final String videoId;
  ScraperException(this.message, this.videoId);
  @override
  String toString() => 'ScraperException: $message (video: $videoId)';
}
