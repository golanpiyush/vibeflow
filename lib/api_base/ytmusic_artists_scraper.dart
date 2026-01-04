// lib/api_base/ytmusic_artists_scraper.dart
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:vibeflow/api_base/cache_manager.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/models/album_model.dart';

/// Music genres supported by the scraper
enum MusicGenre {
  pop,
  rock,
  rap,
  edm,
  jazz,
  country,
  rnb,
  indie,
  metal,
  classical,
}

/// Scraper for YouTube Music artists using the internal API
class YTMusicArtistsScraper {
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

  final Random _random = Random();
  final CacheManager _cacheManager = CacheManager.instance;
  final Map<String, ArtistDetails> _artistDetailsCache = {};
  final Map<String, List<Artist>> _genreArtistsCache = {};
  List<Artist>? _trendingArtistsCache;

  /// Get random artists from different genres
  Future<List<Artist>> getRandomArtists({int count = 50}) async {
    try {
      print('🎲 [YTMusicArtistsScraper] Fetching $count random artists...');

      // Get artists from multiple genres and shuffle
      final allArtists = <Artist>[];
      final genres = MusicGenre.values.toList()..shuffle(_random);

      for (final genre in genres.take(5)) {
        final artists = await getArtistsByGenre(genre, limit: 10);
        allArtists.addAll(artists);
        if (allArtists.length >= count * 2) break;
      }

      // Shuffle and return requested count
      allArtists.shuffle(_random);
      final randomArtists = allArtists.take(count).toList();

      print(
        '✅ [YTMusicArtistsScraper] Found ${randomArtists.length} random artists',
      );
      return randomArtists;
    } catch (e) {
      print('❌ [YTMusicArtistsScraper] Error getting random artists: $e');
      return _getFallbackArtists();
    }
  }

  /// Get trending artists with caching
  Future<List<Artist>> getTrendingArtists({int limit = 50}) async {
    try {
      // Check memory cache first
      if (_trendingArtistsCache != null && _trendingArtistsCache!.isNotEmpty) {
        print('📦 Using cached trending artists');
        return _trendingArtistsCache!.take(limit).toList();
      }

      // Check disk cache
      final cachedData = await _cacheManager.get<List<Artist>>(
        'trending_artists',
      );
      if (cachedData != null && cachedData.isNotEmpty) {
        print('💾 Using disk cached trending artists');
        _trendingArtistsCache = cachedData;
        return cachedData.take(limit).toList();
      }

      print('🔍 [YTMusicArtistsScraper] Fetching trending artists...');

      // Fetch artists from multiple popular genres
      final allArtists = <Artist>[];
      final seenIds = <String>{};

      final popularGenres = [
        MusicGenre.pop,
        MusicGenre.rap,
        MusicGenre.rock,
        MusicGenre.edm,
        MusicGenre.rnb,
      ];

      for (final genre in popularGenres) {
        final genreArtists = await getArtistsByGenre(
          genre,
          limit: (limit ~/ popularGenres.length) + 5,
        );

        for (final artist in genreArtists) {
          if (!seenIds.contains(artist.id)) {
            seenIds.add(artist.id);
            allArtists.add(artist);
          }
        }

        if (allArtists.length >= limit) break;
      }

      allArtists.shuffle(_random);
      final trendingArtists = allArtists.take(limit).toList();

      if (trendingArtists.isEmpty) {
        print('⚠️ No artists found, using fallback');
        return _getFallbackArtists();
      }

      // Cache the results
      _trendingArtistsCache = trendingArtists;
      await _cacheManager.set('trending_artists', trendingArtists);

      print(
        '✅ [YTMusicArtistsScraper] Found ${trendingArtists.length} artists',
      );
      return trendingArtists;
    } catch (e) {
      print('❌ [YTMusicArtistsScraper] Error: $e');
      return _getFallbackArtists();
    }
  }

  /// Get artists by specific genre with HQ images and subscriber counts
  /// Get artists by genre with caching
  Future<List<Artist>> getArtistsByGenre(
    MusicGenre genre, {
    int limit = 50,
  }) async {
    final genreKey = genre.toString();

    try {
      // Check memory cache first
      if (_genreArtistsCache.containsKey(genreKey)) {
        final cached = _genreArtistsCache[genreKey]!;
        if (cached.isNotEmpty) {
          print('📦 Using cached $genreKey artists');
          return cached.take(limit).toList();
        }
      }

      // Check disk cache
      final cacheKey = 'artists_genre_$genreKey';
      final cachedData = await _cacheManager.get<List<Artist>>(cacheKey);
      if (cachedData != null && cachedData.isNotEmpty) {
        print('💾 Using disk cached $genreKey artists');
        _genreArtistsCache[genreKey] = cachedData;
        return cachedData.take(limit).toList();
      }

      final genreName = _getGenreName(genre);
      print('🎵 [YTMusicArtistsScraper] Fetching $genreName artists...');

      final searchQuery = '$genreName music artists';
      final response = await _makeRequest(
        endpoint: 'search',
        body: {
          'context': _context,
          'query': searchQuery,
          'params': 'EgWKAQIgAWoKEAoQAxAEEAkQBQ%3D%3D',
        },
      );

      if (response == null) {
        return _getGenreFallbackArtists(genre);
      }

      final artists = _parseArtistsFromSearch(response, limit);

      if (artists.isEmpty) {
        print('⚠️ No artists found for $genreName, using fallback');
        return _getGenreFallbackArtists(genre);
      }

      // Cache the results
      _genreArtistsCache[genreKey] = artists;
      await _cacheManager.set(cacheKey, artists);

      print(
        '✅ [YTMusicArtistsScraper] Found ${artists.length} $genreName artists',
      );
      return artists;
    } catch (e) {
      print('❌ [YTMusicArtistsScraper] Error getting $genre artists: $e');
      return _getGenreFallbackArtists(genre);
    }
  }

  /// Get artists by multiple genres (user selections)
  Future<List<Artist>> getArtistsByGenres(
    List<MusicGenre> genres, {
    int artistsPerGenre = 50,
  }) async {
    try {
      print(
        '🎨 [YTMusicArtistsScraper] Fetching artists from ${genres.length} genres...',
      );

      final allArtists = <Artist>[];
      final seenIds = <String>{};

      for (final genre in genres) {
        final genreArtists = await getArtistsByGenre(
          genre,
          limit: artistsPerGenre,
        );

        // Add only unique artists
        for (final artist in genreArtists) {
          if (!seenIds.contains(artist.id)) {
            seenIds.add(artist.id);
            allArtists.add(artist);
          }
        }
      }

      print(
        '✅ [YTMusicArtistsScraper] Found ${allArtists.length} unique artists',
      );
      return allArtists;
    } catch (e) {
      print('❌ [YTMusicArtistsScraper] Error getting multi-genre artists: $e');
      return [];
    }
  }

  /// Get artist details with caching
  Future<ArtistDetails?> getArtistDetails(String artistId) async {
    try {
      // Check memory cache first
      if (_artistDetailsCache.containsKey(artistId)) {
        print('📦 Using cached artist details for $artistId');
        return _artistDetailsCache[artistId];
      }

      // Check disk cache
      final cacheKey = 'artist_details_$artistId';
      final cachedData = await _cacheManager.get<ArtistDetails>(cacheKey);
      if (cachedData != null) {
        print('💾 Using disk cached artist details for $artistId');
        _artistDetailsCache[artistId] = cachedData;
        return cachedData;
      }

      print('🎤 [YTMusicArtistsScraper] Fetching artist: $artistId');

      final response = await _makeRequest(
        endpoint: 'browse',
        body: {'context': _context, 'browseId': artistId},
      );

      if (response == null) return null;

      final artistData = _extractArtistMetadata(response, artistId);
      final topSongs = _extractTopSongs(response, artistData['name'] as String);
      final albums = _extractArtistAlbums(response);

      print(
        '✅ [YTMusicArtistsScraper] Loaded artist "${artistData['name']}" with ${topSongs.length} songs and ${albums.length} albums',
      );

      final details = ArtistDetails(
        artist: Artist(
          id: artistId,
          name: artistData['name'] as String,
          profileImage: artistData['profileImage'] as String?,
          subscribers: artistData['subscribers'] as String,
        ),
        topSongs: topSongs,
        albums: albums,
      );

      // Cache the results
      _artistDetailsCache[artistId] = details;
      await _cacheManager.set(cacheKey, details);

      return details;
    } catch (e) {
      print('❌ [YTMusicArtistsScraper] Error: $e');
      return null;
    }
  }

  /// Search for artists - metadata only
  Future<List<Artist>> searchArtists(String query, {int limit = 20}) async {
    try {
      print('🔍 [YTMusicArtistsScraper] Searching artists: "$query"');

      final response = await _makeRequest(
        endpoint: 'search',
        body: {
          'context': _context,
          'query': query,
          'params': 'EgWKAQIgAWoKEAoQAxAEEAkQBQ%3D%3D', // Filter for artists
        },
      );

      if (response == null) return [];

      final artists = _parseArtistsFromSearch(response, limit);

      print('✅ [YTMusicArtistsScraper] Found ${artists.length} artists');
      return artists;
    } catch (e) {
      print('❌ [YTMusicArtistsScraper] Search error: $e');
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
        print('Response body: ${response.body.substring(0, 200)}...');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('❌ Request error: $e');
      return null;
    }
  }

  /// Extract artist metadata from response
  Map<String, dynamic> _extractArtistMetadata(
    Map<String, dynamic> data,
    String artistId,
  ) {
    String name = 'Unknown Artist';
    String? profileImage;
    String subscribers = 'Artist';

    try {
      // Try different header types
      var header = data['header']?['musicImmersiveHeaderRenderer'];
      header ??= data['header']?['musicVisualHeaderRenderer'];

      if (header != null) {
        // Extract name
        name = _extractText(header['title']) ?? name;

        // Extract subscribers
        try {
          final subscriberText =
              header['subscriptionButton']?['subscribeButtonRenderer']?['subscriberCountText'];
          subscribers = _extractText(subscriberText) ?? subscribers;
        } catch (e) {
          // Try alternative path
          final descriptionText = header['description'];
          final extracted = _extractText(descriptionText);
          if (extracted != null && extracted.contains('subscriber')) {
            subscribers = extracted;
          }
        }

        // Extract profile image
        profileImage = _extractBestThumbnail(header['thumbnail']);

        // Enhance artist profile image quality
        if (profileImage != null && profileImage.contains('=s')) {
          profileImage =
              profileImage.split('=s')[0] + '=s500-c-k-c0x00ffffff-no-rj';
        }
      }
    } catch (e) {
      print('⚠️ Error extracting artist metadata: $e');
    }

    return {
      'name': name,
      'profileImage': profileImage,
      'subscribers': subscribers,
    };
  }

  /// Extract top songs from artist page
  List<Song> _extractTopSongs(Map<String, dynamic> data, String artistName) {
    final songs = <Song>[];

    try {
      final contents =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          // Try different shelf types
          var shelf = section['musicShelfRenderer'];
          shelf ??= section['musicCarouselShelfRenderer'];

          if (shelf == null) continue;

          // Check if this is a songs section
          final shelfTitle = _extractText(shelf['title']);
          final isTopSongs =
              shelfTitle?.toLowerCase().contains('song') ??
              shelfTitle?.toLowerCase().contains('top') ??
              false;

          final items = shelf['contents'] as List?;
          if (items == null) continue;

          for (final item in items) {
            final song = _parseSongMetadata(item, artistName);
            if (song != null) {
              songs.add(song);
              if (songs.length >= 10) break;
            }
          }

          // If we found songs in a "songs" or "top" shelf, stop
          if (songs.isNotEmpty && isTopSongs) break;
        }
      }
    } catch (e) {
      print('⚠️ Error extracting songs: $e');
    }

    return songs;
  }

  /// Extract artist albums from response
  List<Album> _extractArtistAlbums(Map<String, dynamic> data) {
    final albums = <Album>[];

    try {
      final contents =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicCarouselShelfRenderer'];
          if (shelf == null) continue;

          // Check if this is an albums section
          final shelfTitle = _extractText(shelf['title']);
          final isAlbums = shelfTitle?.toLowerCase().contains('album') ?? false;

          if (!isAlbums) continue;

          final items = shelf['contents'] as List?;
          if (items == null) continue;

          for (final item in items) {
            final album = _parseAlbumMetadata(item);
            if (album != null) {
              albums.add(album);
            }
          }

          // Stop after finding albums section
          if (albums.isNotEmpty) break;
        }
      }
    } catch (e) {
      print('⚠️ Error extracting albums: $e');
    }

    return albums;
  }

  /// Parse artists from browse response
  List<Artist> _parseArtistsFromBrowse(Map<String, dynamic> data, int limit) {
    final artists = <Artist>[];

    try {
      final contents =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          // Try different shelf types
          var shelf = section['musicCarouselShelfRenderer'];
          shelf ??= section['musicShelfRenderer'];

          if (shelf == null) continue;

          final items = shelf['contents'] as List?;
          if (items == null) continue;

          for (final item in items) {
            if (artists.length >= limit) break;

            final artist = _parseArtistItem(item);
            if (artist != null) {
              artists.add(artist);
            }
          }

          if (artists.length >= limit) break;
        }
      }
    } catch (e) {
      print('⚠️ Error parsing artists: $e');
    }

    return artists;
  }

  /// Parse artists from search response
  List<Artist> _parseArtistsFromSearch(Map<String, dynamic> data, int limit) {
    final artists = <Artist>[];

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
            if (artists.length >= limit) break;

            final artist = _parseSearchArtistItem(item);
            if (artist != null) {
              artists.add(artist);
            }
          }

          if (artists.length >= limit) break;
        }
      }
    } catch (e) {
      print('⚠️ Error parsing search results: $e');
    }

    return artists;
  }

  /// Parse artist from carousel/browse item
  Artist? _parseArtistItem(Map<String, dynamic> item) {
    try {
      var artistItem = item['musicTwoRowItemRenderer'];
      artistItem ??= item['musicResponsiveListItemRenderer'];

      if (artistItem == null) return null;

      final browseId =
          artistItem['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;

      // Only include artist channels (start with UC)
      if (browseId == null || !browseId.startsWith('UC')) return null;

      // Extract name
      String name = 'Unknown Artist';
      final titleText = _extractText(artistItem['title']);
      if (titleText != null) {
        name = titleText;
      } else {
        // Try flex columns format
        final flexColumns = artistItem['flexColumns'] as List?;
        if (flexColumns != null && flexColumns.isNotEmpty) {
          name = _extractFlexColumnText(flexColumns[0]) ?? name;
        }
      }

      // Extract subscribers
      String subscribers = 'Artist';
      final subtitle = artistItem['subtitle'];
      if (subtitle != null) {
        final runs = subtitle['runs'] as List?;
        if (runs != null) {
          for (final run in runs) {
            final text = run['text'] as String?;
            if (text != null && _isSubscriberText(text)) {
              subscribers = text;
              break;
            }
          }
        }
      } else {
        // Try flex columns format
        final flexColumns = artistItem['flexColumns'] as List?;
        if (flexColumns != null && flexColumns.length > 1) {
          final subRuns =
              flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                  as List?;
          if (subRuns != null) {
            for (final run in subRuns) {
              final text = run['text'] as String?;
              if (text != null && _isSubscriberText(text)) {
                subscribers = text;
                break;
              }
            }
          }
        }
      }

      // Extract profile image
      var profileImage = _extractBestThumbnail(
        artistItem['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail'],
      );
      profileImage ??= _extractBestThumbnail(artistItem['thumbnail']);

      // Enhance profile image quality
      if (profileImage != null && profileImage.contains('=s')) {
        profileImage =
            profileImage.split('=s')[0] + '=s500-c-k-c0x00ffffff-no-rj';
      }

      return Artist(
        id: browseId,
        name: name,
        profileImage: profileImage,
        subscribers: subscribers,
      );
    } catch (e) {
      print('⚠️ Error parsing artist item: $e');
      return null;
    }
  }

  /// Parse artist from search result
  Artist? _parseSearchArtistItem(Map<String, dynamic> item) {
    try {
      final artistItem = item['musicResponsiveListItemRenderer'];
      if (artistItem == null) return null;

      final browseId =
          artistItem['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;

      // Only include artist channels
      if (browseId == null || !browseId.startsWith('UC')) return null;

      final flexColumns = artistItem['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      // Extract name
      final name = _extractFlexColumnText(flexColumns[0]) ?? 'Unknown Artist';

      // Extract subscribers
      String subscribers = 'Artist';
      if (flexColumns.length > 1) {
        final subtitleRuns =
            flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        if (subtitleRuns != null) {
          for (final run in subtitleRuns) {
            final text = run['text'] as String?;
            if (text != null && _isSubscriberText(text)) {
              subscribers = text;
              break;
            }
          }
        }
      }

      // Extract profile image
      var profileImage = _extractBestThumbnail(artistItem['thumbnail']);

      // Enhance quality
      if (profileImage != null && profileImage.contains('=s')) {
        profileImage =
            profileImage.split('=s')[0] + '=s500-c-k-c0x00ffffff-no-rj';
      }

      return Artist(
        id: browseId,
        name: name,
        profileImage: profileImage,
        subscribers: subscribers,
      );
    } catch (e) {
      print('⚠️ Error parsing search artist: $e');
      return null;
    }
  }

  /// Parse song metadata from item
  Song? _parseSongMetadata(Map<String, dynamic> item, String artistName) {
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

      // Extract thumbnail
      final thumbnail = _extractBestThumbnail(songItem['thumbnail']) ?? '';

      // Extract duration
      final duration = flexColumns.length > 2
          ? _extractFlexColumnText(flexColumns.last)
          : null;

      return Song(
        videoId: videoId,
        title: title,
        artists: [artistName],
        thumbnail: thumbnail,
        duration: duration,
        audioUrl: null,
      );
    } catch (e) {
      print('⚠️ Error parsing song: $e');
      return null;
    }
  }

  /// Parse album metadata from item
  Album? _parseAlbumMetadata(Map<String, dynamic> item) {
    try {
      final albumItem = item['musicTwoRowItemRenderer'];
      if (albumItem == null) return null;

      final browseId =
          albumItem['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String?;

      if (browseId == null || browseId.isEmpty) return null;

      final title = _extractText(albumItem['title']) ?? 'Unknown Album';
      final subtitle = _extractText(albumItem['subtitle']) ?? '';

      // Extract year from subtitle if present
      int? year;
      final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(subtitle);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(0)!);
      }

      final coverArt = _extractBestThumbnail(
        albumItem['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail'],
      );

      return Album(
        id: browseId,
        title: title,
        artist: subtitle.split('•').first.trim(),
        coverArt: coverArt,
        year: year ?? 0,
        songs: [],
      );
    } catch (e) {
      print('⚠️ Error parsing album: $e');
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

        // Enhance quality for regular thumbnails
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

  /// Check if text contains subscriber information
  bool _isSubscriberText(String text) {
    return text.contains('subscriber') ||
        text.contains('M subscribers') ||
        text.contains('K subscribers') ||
        (text.contains('M') && !text.contains('•')) ||
        (text.contains('K') && !text.contains('•'));
  }

  /// Get genre name for search
  String _getGenreName(MusicGenre genre) {
    switch (genre) {
      case MusicGenre.pop:
        return 'popular pop';
      case MusicGenre.rock:
        return 'popular rock';
      case MusicGenre.rap:
        return 'top hip hop rap';
      case MusicGenre.edm:
        return 'top edm electronic';
      case MusicGenre.jazz:
        return 'popular jazz';
      case MusicGenre.country:
        return 'top country';
      case MusicGenre.rnb:
        return 'top r&b soul';
      case MusicGenre.indie:
        return 'popular indie alternative';
      case MusicGenre.metal:
        return 'popular metal';
      case MusicGenre.classical:
        return 'popular classical';
    }
  }

  /// Fallback artists with known good IDs
  List<Artist> _getFallbackArtists() {
    return [
      Artist(
        id: 'UCN1hnUccO4FD5WfM7ithXaw',
        name: 'Maroon 5',
        profileImage: null,
        subscribers: '39.5M subscribers',
      ),
      Artist(
        id: 'UCqECaJ8Gagnn7YCbPEzWH6g',
        name: 'Taylor Swift',
        profileImage: null,
        subscribers: '62M subscribers',
      ),
      Artist(
        id: 'UC-J-KZfRV8c13fOCkhXdLiQ',
        name: 'Ed Sheeran',
        profileImage: null,
        subscribers: '54.5M subscribers',
      ),
      Artist(
        id: 'UCbulh9WdLtEXiooRcYK7SWw',
        name: 'The Weeknd',
        profileImage: null,
        subscribers: '37.3M subscribers',
      ),
      Artist(
        id: 'UCHkj014U2CQ2Nv0UZeYpE_A',
        name: 'Imagine Dragons',
        profileImage: null,
        subscribers: '29.8M subscribers',
      ),
      Artist(
        id: 'UC0C-w0YjGpqDXGB8IHb662A',
        name: 'Ariana Grande',
        profileImage: null,
        subscribers: '54M subscribers',
      ),
      Artist(
        id: 'UC_-lkd5iACZzJ4zE_GOeUXw',
        name: 'Eminem',
        profileImage: null,
        subscribers: '58M subscribers',
      ),
      Artist(
        id: 'UCa10nxShhzNrCE1o2ZOPztg',
        name: 'Marshmello',
        profileImage: null,
        subscribers: '57M subscribers',
      ),
    ];
  }

  /// Get genre-specific fallback artists
  List<Artist> _getGenreFallbackArtists(MusicGenre genre) {
    switch (genre) {
      case MusicGenre.pop:
        return [
          Artist(
            id: 'UCqECaJ8Gagnn7YCbPEzWH6g',
            name: 'Taylor Swift',
            profileImage: null,
            subscribers: '62M subscribers',
          ),
          Artist(
            id: 'UC0C-w0YjGpqDXGB8IHb662A',
            name: 'Ariana Grande',
            profileImage: null,
            subscribers: '54M subscribers',
          ),
          Artist(
            id: 'UCN1hnUccO4FD5WfM7ithXaw',
            name: 'Maroon 5',
            profileImage: null,
            subscribers: '39.5M subscribers',
          ),
        ];
      case MusicGenre.rock:
        return [
          Artist(
            id: 'UCHkj014U2CQ2Nv0UZeYpE_A',
            name: 'Imagine Dragons',
            profileImage: null,
            subscribers: '29.8M subscribers',
          ),
        ];
      case MusicGenre.rap:
        return [
          Artist(
            id: 'UC_-lkd5iACZzJ4zE_GOeUXw',
            name: 'Eminem',
            profileImage: null,
            subscribers: '58M subscribers',
          ),
        ];
      case MusicGenre.edm:
        return [
          Artist(
            id: 'UCa10nxShhzNrCE1o2ZOPztg',
            name: 'Marshmello',
            profileImage: null,
            subscribers: '57M subscribers',
          ),
        ];
      default:
        return _getFallbackArtists();
    }
  }

  /// Get comprehensive artist details - all songs, albums, and singles
  Future<ArtistDetailsExtended?> getArtistDetailsExtended(
    String artistId,
  ) async {
    try {
      print(
        '🎤 [YTMusicArtistsScraper] Fetching extended artist data: $artistId',
      );

      final response = await _makeRequest(
        endpoint: 'browse',
        body: {'context': _context, 'browseId': artistId},
      );

      if (response == null) return null;

      // Extract artist metadata
      final artistData = _extractArtistMetadata(response, artistId);

      // Extract all songs with pagination
      final allSongs = await _extractAllSongs(
        response,
        artistData['name'] as String,
        artistId,
      );

      // Extract all albums with pagination
      final allAlbums = await _extractAllAlbums(response, artistId);

      // Extract all singles with pagination
      final allSingles = await _extractAllSingles(response, artistId);

      print(
        '✅ [YTMusicArtistsScraper] Loaded artist "${artistData['name']}" with ${allSongs.length} songs, ${allAlbums.length} albums, ${allSingles.length} singles',
      );

      return ArtistDetailsExtended(
        artist: Artist(
          id: artistId,
          name: artistData['name'] as String,
          profileImage: artistData['profileImage'] as String?,
          subscribers: artistData['subscribers'] as String,
        ),
        allSongs: allSongs,
        albums: allAlbums,
        singles: allSingles,
      );
    } catch (e) {
      print('❌ [YTMusicArtistsScraper] Error: $e');
      return null;
    }
  }

  /// Extract all songs from artist with pagination
  Future<List<Song>> _extractAllSongs(
    Map<String, dynamic> initialData,
    String artistName,
    String artistId,
  ) async {
    final songs = <Song>[];
    String? continuationToken;

    try {
      // Get initial songs
      final contents =
          initialData['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          var shelf = section['musicShelfRenderer'];
          shelf ??= section['musicCarouselShelfRenderer'];

          if (shelf == null) continue;

          // Check if this is a songs section
          final shelfTitle = _extractText(shelf['title']);
          final isSongs = shelfTitle?.toLowerCase().contains('song') ?? false;

          if (!isSongs) continue;

          final items = shelf['contents'] as List?;
          if (items != null) {
            for (final item in items) {
              final song = _parseSongMetadata(item, artistName);
              if (song != null) songs.add(song);
            }
          }

          // Get continuation token for pagination
          continuationToken =
              shelf['continuations']?[0]?['nextContinuationData']?['continuation']
                  as String?;
          break;
        }
      }

      // Continue fetching with pagination
      while (continuationToken != null && songs.length < 200) {
        print('🔄 Fetching more songs... (${songs.length} so far)');

        final continueResponse = await _makeRequest(
          endpoint: 'browse',
          body: {'context': _context, 'continuation': continuationToken},
        );

        if (continueResponse == null) break;

        final continuationContents =
            continueResponse['continuationContents']?['musicShelfContinuation'];

        if (continuationContents == null) break;

        final items = continuationContents['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final song = _parseSongMetadata(item, artistName);
            if (song != null) songs.add(song);
          }
        }

        // Get next continuation token
        continuationToken =
            continuationContents['continuations']?[0]?['nextContinuationData']?['continuation']
                as String?;

        // Break if no more items
        if (items == null || items.isEmpty) break;
      }

      print('✅ Total songs fetched: ${songs.length}');
    } catch (e) {
      print('⚠️ Error extracting all songs: $e');
    }

    return songs;
  }

  /// Extract all albums from artist with pagination
  Future<List<Album>> _extractAllAlbums(
    Map<String, dynamic> initialData,
    String artistId,
  ) async {
    final albums = <Album>[];
    String? continuationToken;

    try {
      // Get initial albums
      final contents =
          initialData['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicCarouselShelfRenderer'];
          if (shelf == null) continue;

          // Check if this is an albums section
          final shelfTitle = _extractText(shelf['title']);
          final isAlbums = shelfTitle?.toLowerCase().contains('album') ?? false;

          if (!isAlbums) continue;

          final items = shelf['contents'] as List?;
          if (items != null) {
            for (final item in items) {
              final album = _parseAlbumMetadata(item);
              if (album != null) albums.add(album);
            }
          }

          // Get continuation token
          continuationToken =
              shelf['continuations']?[0]?['nextContinuationData']?['continuation']
                  as String?;
          break;
        }
      }

      // Continue fetching with pagination
      while (continuationToken != null && albums.length < 200) {
        print('🔄 Fetching more albums... (${albums.length} so far)');

        final continueResponse = await _makeRequest(
          endpoint: 'browse',
          body: {'context': _context, 'continuation': continuationToken},
        );

        if (continueResponse == null) break;

        final continuationContents =
            continueResponse['continuationContents']?['musicCarouselShelfContinuation'];

        if (continuationContents == null) break;

        final items = continuationContents['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final album = _parseAlbumMetadata(item);
            if (album != null) albums.add(album);
          }
        }

        // Get next continuation token
        continuationToken =
            continuationContents['continuations']?[0]?['nextContinuationData']?['continuation']
                as String?;

        if (items == null || items.isEmpty) break;
      }

      print('✅ Total albums fetched: ${albums.length}');
    } catch (e) {
      print('⚠️ Error extracting all albums: $e');
    }

    return albums;
  }

  /// Extract all singles from artist with pagination
  Future<List<Album>> _extractAllSingles(
    Map<String, dynamic> initialData,
    String artistId,
  ) async {
    final singles = <Album>[];
    String? continuationToken;

    try {
      // Get initial singles
      final contents =
          initialData['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List?;

      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicCarouselShelfRenderer'];
          if (shelf == null) continue;

          // Check if this is a singles section
          final shelfTitle = _extractText(shelf['title']);
          final isSingles =
              shelfTitle?.toLowerCase().contains('single') ?? false;

          if (!isSingles) continue;

          final items = shelf['contents'] as List?;
          if (items != null) {
            for (final item in items) {
              final single = _parseAlbumMetadata(
                item,
              ); // Singles use same format
              if (single != null) singles.add(single);
            }
          }

          // Get continuation token
          continuationToken =
              shelf['continuations']?[0]?['nextContinuationData']?['continuation']
                  as String?;
          break;
        }
      }

      // Continue fetching with pagination
      while (continuationToken != null && singles.length < 200) {
        print('🔄 Fetching more singles... (${singles.length} so far)');

        final continueResponse = await _makeRequest(
          endpoint: 'browse',
          body: {'context': _context, 'continuation': continuationToken},
        );

        if (continueResponse == null) break;

        final continuationContents =
            continueResponse['continuationContents']?['musicCarouselShelfContinuation'];

        if (continuationContents == null) break;

        final items = continuationContents['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            final single = _parseAlbumMetadata(item);
            if (single != null) singles.add(single);
          }
        }

        // Get next continuation token
        continuationToken =
            continuationContents['continuations']?[0]?['nextContinuationData']?['continuation']
                as String?;

        if (items == null || items.isEmpty) break;
      }

      print('✅ Total singles fetched: ${singles.length}');
    } catch (e) {
      print('⚠️ Error extracting all singles: $e');
    }

    return singles;
  }

  /// Clear all caches (call on app restart)
  void clearCaches() {
    _artistDetailsCache.clear();
    _genreArtistsCache.clear();
    _trendingArtistsCache = null;
    _cacheManager.clearAll();
    print('🧹 Cleared all artist caches');
  }

  /// Dispose resources
  void dispose() {
    // Clean up if needed
  }
}

/// Artist details with top songs and albums
class ArtistDetails {
  final Artist artist;
  final List<Song> topSongs;
  final List<Album> albums;

  ArtistDetails({
    required this.artist,
    required this.topSongs,
    this.albums = const [],
  });
  // In ArtistDetails class (add to ytmusic_artists_scraper.dart)
  Map<String, dynamic> toJson() => {
    'artist': artist.toJson(),
    'topSongs': topSongs.map((song) => song.toJson()).toList(),
    'albums': albums.map((album) => album.toJson()).toList(),
  };

  factory ArtistDetails.fromJson(Map<String, dynamic> json) => ArtistDetails(
    artist: Artist.fromJson(json['artist']),
    topSongs: (json['topSongs'] as List)
        .map((item) => Song.fromJson(item))
        .toList(),
    albums: (json['albums'] as List)
        .map((item) => Album.fromJson(item))
        .toList(),
  );
}

/// Extended artist details with all songs, albums, and singles
class ArtistDetailsExtended {
  final Artist artist;
  final List<Song> allSongs;
  final List<Album> albums;
  final List<Album> singles;

  ArtistDetailsExtended({
    required this.artist,
    required this.allSongs,
    this.albums = const [],
    this.singles = const [],
  });

  /// Get top songs (first 10)
  List<Song> get topSongs => allSongs.take(10).toList();

  /// Get all content count
  int get totalContent => allSongs.length + albums.length + singles.length;
}
