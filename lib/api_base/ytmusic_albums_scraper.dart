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
  // Future<List<Album>> getTrendingAlbums({int limit = 20}) async {
  //   try {
  //     print('🔍 [YTMusicScraper] Fetching trending albums...');

  //     final response = await _makeRequest(
  //       endpoint: 'browse',
  //       body: {'context': _context, 'browseId': 'FEmusic_home'},
  //     );

  //     if (response == null) {
  //       return _getFallbackAlbums();
  //     }

  //     final albums = _parseAlbumsFromBrowse(response, limit);

  //     if (albums.isEmpty) {
  //       print('⚠️ No albums found, using fallback');
  //       return _getFallbackAlbums();
  //     }

  //     print('✅ [YTMusicScraper] Found ${albums.length} albums');
  //     return albums;
  //   } catch (e) {
  //     print('❌ [YTMusicScraper] Error: $e');
  //     return _getFallbackAlbums();
  //   }
  // }

  /// Get random albums by artist
  Future<List<Album>> getRandomAlbumsByArtist(
    String artist, {
    int limit = 50,
  }) async {
    try {
      print('👤 [YTMusicScraper] Fetching random albums by $artist...');

      // Search for the artist's albums
      final albums = await searchAlbums('$artist album', limit: 30);

      if (albums.isEmpty) return [];

      // Filter to only include albums by this artist
      final artistAlbums = albums.where((album) {
        return album.artist.toLowerCase().contains(artist.toLowerCase());
      }).toList();

      // Shuffle for randomness
      artistAlbums.shuffle();

      final result = artistAlbums.take(limit).toList();

      print(
        '✅ [YTMusicScraper] Found ${result.length} random albums by $artist',
      );
      return result;
    } catch (e) {
      print('❌ [YTMusicScraper] Error getting random artist albums: $e');
      return [];
    }
  }

  Future<List<Album>> getRandomAlbumsByPopularArtists({int limit = 50}) async {
    try {
      print('👤 [YTMusicScraper] Fetching albums by popular artists...');

      // Large array of popular artists from 2010-2025
      final popularArtists = [
        'Eminem',
        'Maroon 5',
        'Taylor Swift',
        'Drake',
        'Ed Sheeran',
        'The Weeknd',
        'Bruno Mars',
        'Ariana Grande',
        'Post Malone',
        'Justin Bieber',
        'Billie Eilish',
        'Dua Lipa',
        'Harry Styles',
        'Kanye West',
        'Kendrick Lamar',
        'Travis Scott',
        'Bad Bunny',
        'J Balvin',
        'Rihanna',
        'Beyoncé',
        'Lady Gaga',
        'Coldplay',
        'Imagine Dragons',
        'One Direction',
        'Twenty One Pilots',
        'Halsey',
        'Shawn Mendes',
        'Selena Gomez',
        'Miley Cyrus',
        'Katy Perry',
        'Nicki Minaj',
        'Cardi B',
        'Megan Thee Stallion',
        'Doja Cat',
        'Lil Nas X',
        'Olivia Rodrigo',
        'The Kid LAROI',
        'SZA',
        'Lizzo',
        'Sam Smith',
        'Adele',
        'Pink Floyd',
        'Metallica',
        'Linkin Park',
        'Green Day',
        'Foo Fighters',
        'Red Hot Chili Peppers',
        'Arctic Monkeys',
        'Tame Impala',
        'Lana Del Rey',
        'Frank Ocean',
        'Tyler, The Creator',
        'Mac Miller',
        'Juice WRLD',
        'XXXTENTACION',
        'Pop Smoke',
        'Future',
        'Lil Baby',
        'DaBaby',
        'Roddy Ricch',
        'Jack Harlow',
        'Lil Uzi Vert',
        'Playboi Carti',
        'Young Thug',
        'Gunna',
        'Chris Brown',
        'Usher',
        'John Legend',
        'Alicia Keys',
        'Mariah Carey',
        'Whitney Houston',
        'Michael Jackson',
        'Prince',
        'Queen',
        'The Beatles',
        'Elvis Presley',
        'Bob Dylan',
        'David Bowie',
        'Madonna',
      ];

      // Shuffle artists for randomness
      popularArtists.shuffle();

      final allAlbums = <Album>{};

      // Try multiple artists until we get enough albums
      for (final artist in popularArtists.take(10)) {
        // Try first 10 random artists
        if (allAlbums.length >= limit) break;

        print('🔍 Searching albums for: $artist');
        final albums = await searchAlbums('$artist album', limit: 30);

        // Filter to only include albums by this artist
        final artistAlbums = albums.where((album) {
          return album.artist.toLowerCase().contains(artist.toLowerCase());
        }).toList();

        // Shuffle this artist's albums
        artistAlbums.shuffle();

        // Add unique albums
        for (final album in artistAlbums) {
          if (!allAlbums.any((a) => a.id == album.id)) {
            allAlbums.add(album);
          }
          if (allAlbums.length >= limit) break;
        }

        // Small delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Convert to list and shuffle all together
      final albumList = allAlbums.toList();
      albumList.shuffle();

      final result = albumList.take(limit).toList();

      print(
        '✅ [YTMusicScraper] Found ${result.length} albums by popular artists',
      );
      return result;
    } catch (e) {
      print('❌ [YTMusicScraper] Error getting albums by popular artists: $e');
      return _getFallbackAlbums();
    }
  }

  /// Get only official studio albums from various artists (no remixes, compilations, live albums, etc.)
  Future<List<Album>> getOfficialAlbumsFromArtists({int limit = 50}) async {
    try {
      print('🎵 [YTMusicScraper] Fetching official albums only...');

      final popularArtists = [
        'Eminem',
        'Maroon 5',
        'Taylor Swift',
        'Drake',
        'Ed Sheeran',
        'The Weeknd',
        'Bruno Mars',
        'Ariana Grande',
        'Post Malone',
        'Justin Bieber',
        'Billie Eilish',
        'Dua Lipa',
        'Harry Styles',
        'Kanye West',
        'Kendrick Lamar',
        'Travis Scott',
        'Bad Bunny',
        'J Balvin',
        'Rihanna',
        'Beyoncé',
        'Lady Gaga',
        'Coldplay',
        'Imagine Dragons',
        'One Direction',
        'Twenty One Pilots',
        'Halsey',
        'Shawn Mendes',
        'Selena Gomez',
        'Miley Cyrus',
        'Katy Perry',
        'Nicki Minaj',
        'Cardi B',
        'Megan Thee Stallion',
        'Doja Cat',
        'Lil Nas X',
        'Olivia Rodrigo',
        'The Kid LAROI',
        'SZA',
        'Lizzo',
        'Sam Smith',
        'Adele',
        'Pink Floyd',
        'Metallica',
        'Linkin Park',
        'Green Day',
        'Foo Fighters',
        'Red Hot Chili Peppers',
        'Arctic Monkeys',
        'Tame Impala',
        'Lana Del Rey',
        'Frank Ocean',
        'Tyler, The Creator',
        'Mac Miller',
        'Juice WRLD',
        'XXXTENTACION',
        'Pop Smoke',
        'Future',
        'Lil Baby',
        'DaBaby',
        'Roddy Ricch',
        'Jack Harlow',
        'Lil Uzi Vert',
        'Playboi Carti',
        'Young Thug',
        'Gunna',
        'Chris Brown',
        'Usher',
        'John Legend',
        'Alicia Keys',
        'Mariah Carey',
        'Whitney Houston',
        'Michael Jackson',
        'Prince',
        'Queen',
        'The Beatles',
        'Elvis Presley',
        'Bob Dylan',
        'David Bowie',
        'Madonna',
      ];

      // Shuffle for randomness
      popularArtists.shuffle();

      final allAlbums = <Album>{};

      // Try artists until we get enough albums
      for (final artist in popularArtists.take(20)) {
        if (allAlbums.length >= limit) break;

        print('🔍 Searching official albums for: $artist');
        final albums = await searchAlbums('$artist album', limit: 30);

        if (albums.isEmpty) {
          print('⚠️ No results for $artist');
          continue;
        }

        // Extract key words from artist name
        final artistWords = artist
            .toLowerCase()
            .split(' ')
            .where((w) => w.length > 2)
            .toList();

        // Filter for official albums only
        final officialAlbums = albums.where((album) {
          final albumArtistLower = album.artist.toLowerCase();
          final albumTitleLower = album.title.toLowerCase();
          final artistLower = artist.toLowerCase();

          // Must match the artist
          bool artistMatch = false;
          if (albumArtistLower.contains(artistLower)) {
            artistMatch = true;
          } else {
            for (final word in artistWords) {
              if (albumArtistLower.contains(word)) {
                artistMatch = true;
                break;
              }
            }
          }

          if (!artistMatch) return false;

          // Exclude non-official albums (remix, live, deluxe, remaster, etc.)
          final excludeKeywords = [
            'remix',
            'remixes',
            'mix',
            'mixtape',
            'live',
            'concert',
            'acoustic',
            'unplugged',
            'sessions',
            'karaoke',
            'instrumental',
            'covers',
            'tribute',
            'greatest hits',
            'best of',
            'collection',
            'anthology',
            'essentials',
            'playlist',
            'radio',
            'singles',
            'ep',
            'demo',
            'bootleg',
            'unreleased',
            'b-sides',
            'rarities',
            'outtakes',
            'bonus',
            'anniversary',
            'edition',
            'version',
            'vol.',
            'volume',
            'part',
            'chapter',
            'tape',
            'soundtrack',
            'various artists',
            'compilation',
            'deluxe',
            'expanded',
            'remaster',
            'remastered',
          ];

          // Check if title contains any exclude keywords
          for (final keyword in excludeKeywords) {
            if (albumTitleLower.contains(keyword)) {
              return false;
            }
          }

          // Exclude if title has parentheses or brackets (often indicates special editions)
          if (albumTitleLower.contains('(') ||
              albumTitleLower.contains('[') ||
              albumTitleLower.contains(')') ||
              albumTitleLower.contains(']')) {
            return false;
          }

          return true;
        }).toList();

        print(
          '📊 Found ${officialAlbums.length} official albums for $artist from ${albums.length} results',
        );

        if (officialAlbums.isEmpty) {
          print('⚠️ No official albums found for $artist');
          continue;
        }

        // Shuffle albums
        officialAlbums.shuffle();

        // Add unique albums (max 3 per artist for variety)
        int addedCount = 0;
        for (final album in officialAlbums.take(3)) {
          if (!allAlbums.any((a) => a.id == album.id)) {
            allAlbums.add(album);
            addedCount++;
            print('  ✓ Added: "${album.title}" by ${album.artist}');
          }
          if (allAlbums.length >= limit) break;
        }

        print(
          '✅ Added $addedCount official albums for $artist (total: ${allAlbums.length})',
        );

        // Small delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Convert to list and shuffle
      final albumList = allAlbums.toList();
      albumList.shuffle();

      final result = albumList.take(limit).toList();

      print(
        '✅ [YTMusicScraper] Found ${result.length} official albums from ${allAlbums.length} unique albums',
      );
      return result.isNotEmpty ? result : _getFallbackAlbums();
    } catch (e) {
      print('❌ [YTMusicScraper] Error getting official albums: $e');
      return _getFallbackAlbums();
    }
  }

  /// Get mixed albums from multiple random artists
  Future<List<Album>> getMixedRandomAlbums({int limit = 50}) async {
    try {
      print('🎭 [YTMusicScraper] Fetching mixed albums from random artists...');

      // Diverse array of popular artists from different genres
      final artistsByGenre = {
        'Hip-Hop/Rap': [
          'Eminem',
          'Drake',
          'Kendrick Lamar',
          'Travis Scott',
          'Post Malone',
          'Kanye West',
          'J. Cole',
          'Lil Wayne',
          'Nicki Minaj',
          'Cardi B',
          'Megan Thee Stallion',
          'Future',
          'Lil Baby',
          'DaBaby',
          'Roddy Ricch',
          'Jack Harlow',
          'Lil Uzi Vert',
          'Playboi Carti',
          'Young Thug',
          'Juice WRLD',
          'XXXTENTACION',
          'Pop Smoke',
          'Mac Miller',
        ],
        'Pop': [
          'Taylor Swift',
          'Ariana Grande',
          'Ed Sheeran',
          'Justin Bieber',
          'Billie Eilish',
          'Dua Lipa',
          'Harry Styles',
          'Bruno Mars',
          'Maroon 5',
          'The Weeknd',
          'One Direction',
          'Halsey',
          'Shawn Mendes',
          'Selena Gomez',
          'Miley Cyrus',
          'Katy Perry',
          'Lady Gaga',
          'Rihanna',
          'Beyoncé',
          'Adele',
          'Sam Smith',
          'Olivia Rodrigo',
          'The Kid LAROI',
          'Doja Cat',
          'Lil Nas X',
        ],
        'Rock/Alternative': [
          'Coldplay',
          'Imagine Dragons',
          'Twenty One Pilots',
          'Linkin Park',
          'Green Day',
          'Foo Fighters',
          'Red Hot Chili Peppers',
          'Arctic Monkeys',
          'Tame Impala',
          'Lana Del Rey',
          'Frank Ocean',
          'Tyler, The Creator',
        ],
        'R&B/Soul': [
          'The Weeknd',
          'Frank Ocean',
          'SZA',
          'H.E.R.',
          'Daniel Caesar',
          'Summer Walker',
          'Jhené Aiko',
          'Giveon',
          'Lucky Daye',
          'Chris Brown',
          'Usher',
          'John Legend',
          'Alicia Keys',
        ],
        'Latin': [
          'Bad Bunny',
          'J Balvin',
          'Karol G',
          'Maluma',
          'Ozuna',
          'Anuel AA',
          'Daddy Yankee',
          'Shakira',
        ],
      };

      final allAlbums = <Album>{};
      final allArtists = <String>[];

      // Collect artists from all genres
      for (final genreArtists in artistsByGenre.values) {
        allArtists.addAll(genreArtists);
      }

      // Shuffle all artists
      allArtists.shuffle();

      // Try artists until we get enough albums
      int artistIndex = 0;
      while (allAlbums.length < limit && artistIndex < allArtists.length) {
        final artist = allArtists[artistIndex];
        artistIndex++;

        try {
          final albums = await searchAlbums('$artist album', limit: 20);

          // Filter to this artist
          final artistAlbums = albums.where((album) {
            final albumArtist = album.artist.toLowerCase();
            return albumArtist.contains(artist.toLowerCase()) ||
                album.title.toLowerCase().contains(artist.toLowerCase());
          }).toList();

          artistAlbums.shuffle();

          // Add unique albums
          for (final album in artistAlbums.take(5)) {
            // Take max 5 per artist
            if (!allAlbums.any((a) => a.id == album.id)) {
              allAlbums.add(album);
            }
            if (allAlbums.length >= limit) break;
          }

          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          print('⚠️ Error with artist $artist: $e');
        }
      }

      // Convert to list and final shuffle
      final albumList = allAlbums.toList();
      albumList.shuffle();

      final result = albumList.take(limit).toList();

      print(
        '✅ [YTMusicScraper] Found ${result.length} mixed albums from ${artistIndex} artists',
      );
      return result;
    } catch (e) {
      print('❌ [YTMusicScraper] Error getting mixed albums: $e');
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

  /// Get other versions of an album (remasters, deluxe, live versions, etc.)
  Future<List<Album>> getAlbumVersions(
    String albumTitle,
    String artist, {
    int limit = 20,
  }) async {
    try {
      print(
        '🔍 [YTMusicScraper] Searching album versions: "$albumTitle by $artist"',
      );

      // Search for the album with artist to get related versions
      final searchQuery = '$albumTitle $artist';

      final response = await _makeRequest(
        endpoint: 'search',
        body: {
          'context': _context,
          'query': searchQuery,
          'params': 'EgWKAQIYAWoKEAoQAxAEEAkQBQ%3D%3D', // Filter for albums
        },
      );

      if (response == null) return [];

      final albums = _parseAlbumsFromSearch(
        response,
        limit * 2,
      ); // Get more to filter

      // Filter to only show versions that match the album name
      final versions = albums
          .where((album) {
            final titleLower = album.title.toLowerCase();
            final searchTitleLower = albumTitle.toLowerCase();

            // Check if title contains the original album name
            return titleLower.contains(searchTitleLower) ||
                searchTitleLower.contains(
                  titleLower.split('(')[0].trim().toLowerCase(),
                );
          })
          .take(limit)
          .toList();

      print('✅ [YTMusicScraper] Found ${versions.length} album versions');
      return versions;
    } catch (e) {
      print('❌ [YTMusicScraper] Version search error: $e');
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
