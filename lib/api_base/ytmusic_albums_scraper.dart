// lib/api_base/ytmusic_albums_scraper.dart
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:vibeflow/api_base/albumartistqp_cache.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/song_model.dart';

/// Scraper for YouTube Music albums using the internal API.
///
/// Strategy for getting popular albums (no hardcoding):
///   1. Browse YTMusic's official chart pages (FEmusic_charts, etc.)
///      → These are curated by YTM based on global play counts.
///   2. Browse YTMusic's "New Releases" page — only chart-relevant releases
///      appear here.
///   3. Supplement with generic chart-term searches ("top albums 2024", etc.)
///      → YTMusic's own ranking puts popular albums first.
///
/// The key insight: albums that appear on chart browse pages or rank highly
/// in generic searches on YTMusic already have 500k–50M+ plays. We never
/// search by artist name, so we never get unknown artists.
class YTMusicAlbumsScraper {
  static const String _baseUrl = 'https://music.youtube.com';
  static const String _apiUrl = '$_baseUrl/youtubei/v1';

  final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30',
    'X-Goog-Visitor-Id': 'CgtEeEtvaEd2cXlQZyiDy5e2BjIKCgJVUxIEGgAgUA%3D%3D',
    'Origin': _baseUrl,
    'Referer': '$_baseUrl/',
  };

  final Map<String, dynamic> _context = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20231204.01.00',
      'hl': 'en',
      'gl': 'US',
    },
  };

  // Official YTMusic browse pages that surface trending/chart content.
  // These IDs are YTMusic's own internal page identifiers — not artist IDs.
  static const List<String> _trendingBrowseIds = [
    'FEmusic_charts', // Global chart (most reliable for popularity)
    'FEmusic_new_releases_albums_us', // New releases — chart-topping only
    'FEmusic_home', // Home feed — personalised trending
  ];

  // Generic chart-term searches — broad enough that YTMusic's own
  // ranking surfaces only popular albums. No artist names.
  static const List<String> _chartSearchTerms = [
    'top albums 2024',
    'best albums 2023',
    'trending albums',
    'top hip hop albums',
    'top pop albums',
    'top r&b albums',
    'top rap albums',
    'chart albums',
    'platinum albums 2024',
    'most streamed albums',
  ];

  // Search param that filters YTMusic search results to albums only.
  static const String _albumFilterParam = 'EgWKAQIYAWoKEAoQAxAEEAkQBQ%3D%3D';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch popular albums from YTMusic chart/trending pages.
  /// No artist list, no hardcoded IDs. YTMusic decides what's popular.
  Future<List<Album>> getMixedRandomAlbums({
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await AlbumArtistQPCache.loadAlbums();
      if (cached != null && cached.isNotEmpty) {
        print('⚡ [YTMusicScraper] Using cached albums (${cached.length})');
        return cached.take(limit).toList();
      }
    }

    print('🎵 [YTMusicScraper] Fetching popular albums from YTMusic charts...');

    final albums = <Album>[];
    final seenIds = <String>{};

    // Step 1: Browse official trending/chart pages.
    for (final browseId in _trendingBrowseIds) {
      if (albums.length >= limit) break;
      try {
        final found = await _fetchAlbumsFromBrowsePage(browseId);
        _mergeUnique(found, albums, seenIds);
        print(
          '  📈 "$browseId" → ${found.length} found, '
          '${albums.length} total so far',
        );
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        print('  ⚠️ Browse "$browseId" error: $e');
      }
    }

    // Step 2: Supplement with generic chart-term searches if needed.
    if (albums.length < limit) {
      final shuffledTerms = List<String>.from(_chartSearchTerms)
        ..shuffle(Random());
      for (final term in shuffledTerms) {
        if (albums.length >= limit) break;
        try {
          final found = await searchAlbums(term, limit: 20);
          _mergeUnique(found, albums, seenIds);
          print(
            '  🔍 "$term" → ${found.length} found, '
            '${albums.length} total so far',
          );
          await Future.delayed(const Duration(milliseconds: 250));
        } catch (e) {
          print('  ⚠️ Search "$term" error: $e');
        }
      }
    }

    albums.shuffle(Random());
    final result = albums.take(limit).toList();

    if (result.isNotEmpty) {
      await AlbumArtistQPCache.saveAlbums(result);
    }

    print('✅ [YTMusicScraper] Returning ${result.length} popular albums');
    return result.isNotEmpty ? result : _minimalFallback();
  }

  /// Fetches 20 Vevo albums dynamically by searching for Vevo artists and channels
  Future<List<Album>> getVevoAlbums({int limit = 20}) async {
    try {
      print('🎵 [YTMusicScraper] Fetching Vevo albums...');

      final albums = <Album>[];
      final seenIds = <String>{};

      // List of popular Vevo artists to search for
      final vevoArtists = [
        'Taylor Swift Vevo',
        'Ed Sheeran Vevo',
        'Ariana Grande Vevo',
        'Justin Bieber Vevo',
        'Katy Perry Vevo',
        'Rihanna Vevo',
        'Bruno Mars Vevo',
        'Billie Eilish Vevo',
        'Shawn Mendes Vevo',
        'Dua Lipa Vevo',
        'The Weeknd Vevo',
        'Selena Gomez Vevo',
        'Lady Gaga Vevo',
        'Beyoncé Vevo',
        'Drake Vevo',
        'Eminem Vevo',
        'Coldplay Vevo',
        'Maroon 5 Vevo',
        'Imagine Dragons Vevo',
        'Adele Vevo',
        'Sam Smith Vevo',
        'Post Malone Vevo',
        'Cardi B Vevo',
        'Camila Cabello Vevo',
        'Halsey Vevo',
        'Lizzo Vevo',
        'Harry Styles Vevo',
        'Lil Nas X Vevo',
        'Doja Cat Vevo',
        'Olivia Rodrigo Vevo',
      ];
      final vevoArtistsExtra = [
        'Shakira Vevo',
        'Jennifer Lopez Vevo',
        'Enrique Iglesias Vevo',
        'Pitbull Vevo',
        'Daddy Yankee Vevo',
        'Maluma Vevo',
        'J Balvin Vevo',
        'Karol G Vevo',
        'Bad Bunny Vevo',
        'Rosalía Vevo',
        'Anitta Vevo',
        'Nicky Jam Vevo',
        'Ozuna Vevo',
        'Luis Fonsi Vevo',
        'Becky G Vevo',
        'Prince Royce Vevo',
        'Romeo Santos Vevo',
        'Marc Anthony Vevo',
        'Wisin Vevo',
        'Yandel Vevo',

        'Sia Vevo',
        'Ellie Goulding Vevo',
        'Zara Larsson Vevo',
        'Tove Lo Vevo',
        'Ava Max Vevo',
        'Bebe Rexha Vevo',
        'Rita Ora Vevo',
        'Jessie J Vevo',
        'Anne-Marie Vevo',
        'Mabel Vevo',
        'Clean Bandit Vevo',
        'Calvin Harris Vevo',
        'David Guetta Vevo',
        'Martin Garrix Vevo',
        'Zedd Vevo',
        'Marshmello Vevo',
        'Kygo Vevo',
        'Avicii Vevo',
        'Swedish House Mafia Vevo',
        'Alan Walker Vevo',

        'OneRepublic Vevo',
        'The Chainsmokers Vevo',
        'Fall Out Boy Vevo',
        'Panic! At The Disco Vevo',
        'Paramore Vevo',
        'Green Day Vevo',
        'Linkin Park Vevo',
        'Twenty One Pilots Vevo',
        'Arctic Monkeys Vevo',
        'The 1975 Vevo',
        'Muse Vevo',
        'Kings of Leon Vevo',
        'The Killers Vevo',
        'Red Hot Chili Peppers Vevo',
        'Foo Fighters Vevo',
        'U2 Vevo',
        'Bastille Vevo',
        'Snow Patrol Vevo',
        'Keane Vevo',

        'Nick Jonas Vevo',
        'Joe Jonas Vevo',
        'Jonas Brothers Vevo',
        'Demi Lovato Vevo',
        'Miley Cyrus Vevo',
        'Troye Sivan Vevo',
        'Conan Gray Vevo',
        'Tate McRae Vevo',
        'Sabrina Carpenter Vevo',
        'Madison Beer Vevo',
        'Alessia Cara Vevo',
        'Julia Michaels Vevo',
        'Lauv Vevo',
        'Jeremy Zucker Vevo',
        'Alec Benjamin Vevo',
        'Khalid Vevo',
        'Frank Ocean Vevo',
        'Miguel Vevo',
        'The Kid LAROI Vevo',
        'Charlie Puth Vevo',

        'Jason Derulo Vevo',
        'Ne-Yo Vevo',
        'Usher Vevo',
        'Chris Brown Vevo',
        'T-Pain Vevo',
        'Akon Vevo',
        'Flo Rida Vevo',
        'Sean Paul Vevo',
        'Shaggy Vevo',
        'Taio Cruz Vevo',
        'Iyaz Vevo',
        'Example Vevo',
        'Tinie Tempah Vevo',
        'Stormzy Vevo',
        'Skepta Vevo',
        'AJ Tracey Vevo',
        'Central Cee Vevo',
        'Aitch Vevo',
        'Headie One Vevo',
        'Dave Vevo',

        'Future Vevo',
        'Young Thug Vevo',
        'Gunna Vevo',
        'Lil Baby Vevo',
        'DaBaby Vevo',
        'Travis Scott Vevo',
        'Playboi Carti Vevo',
        'Juice WRLD Vevo',
        'XXXTENTACION Vevo',
        'Lil Uzi Vert Vevo',
        '21 Savage Vevo',
        'Metro Boomin Vevo',
        'Jack Harlow Vevo',
        'Megan Thee Stallion Vevo',
        'Saweetie Vevo',
        'Iggy Azalea Vevo',
        'Nicki Minaj Vevo',
        'Latto Vevo',
        'GloRilla Vevo',
        'Ice Spice Vevo',

        'G-Eazy Vevo',
        'Logic Vevo',
        'Joyner Lucas Vevo',
        'NF Vevo',
        'Russ Vevo',
        'Big Sean Vevo',
        'Wiz Khalifa Vevo',
        'Tyga Vevo',
        'YG Vevo',
        'Schoolboy Q Vevo',
        'Kendrick Lamar Vevo',
        'J. Cole Vevo',
        'Mac Miller Vevo',
        "",
        "",
        'Pusha T Vevo',
        'Rick Ross Vevo',
        'Meek Mill Vevo',
        'Lil Wayne Vevo',
        'Birdman Vevo',

        'Bon Jovi Vevo',
        'Bryan Adams Vevo',
        'Celine Dion Vevo',
        'Whitney Houston Vevo',
        'Mariah Carey Vevo',
        'Christina Aguilera Vevo',
        'Backstreet Boys Vevo',
        'NSYNC Vevo',
        'Spice Girls Vevo',
        'Westlife Vevo',
        'Boyzone Vevo',
        'Take That Vevo',
        'Blue Vevo',
        'Sugababes Vevo',
        'Girls Aloud Vevo',
        'Little Mix Vevo',
        'Fifth Harmony Vevo',
        "Destiny's Child Vevo",
        'TLC Vevo',
        'En Vogue Vevo',

        'Metallica Vevo',
        'Iron Maiden Vevo',
        'Black Sabbath Vevo',
        'Slipknot Vevo',
        'Korn Vevo',
        'System Of A Down Vevo',
        'Disturbed Vevo',
        'Avenged Sevenfold Vevo',
        'Bring Me The Horizon Vevo',
        'Bullet For My Valentine Vevo',
        'Lamb of God Vevo',
        'Megadeth Vevo',
        'Pantera Vevo',
        'Dream Theater Vevo',
        'Ghost Vevo',
        'Nightwish Vevo',
        'Epica Vevo',
        'Within Temptation Vevo',
        'Evanescence Vevo',

        'ABBA Vevo',
        'Queen Vevo',
        'The Beatles Vevo',
        'The Rolling Stones Vevo',
        'Pink Floyd Vevo',
        'Led Zeppelin Vevo',
        'Eagles Vevo',
        'Fleetwood Mac Vevo',
        'The Beach Boys Vevo',
        'Earth, Wind & Fire Vevo',
        'Chicago Vevo',
        'Journey Vevo',
        'Toto Vevo',
        'Scorpions Vevo',
        'Europe Vevo',
        'Roxette Vevo',
        'a-ha Vevo',
        'Depeche Mode Vevo',
        'Pet Shop Boys Vevo',
        'Duran Duran Vevo',
      ];

      // Hindi / Indian VEVO search patterns
      final hindiVevoArtists = [
        // Many Indian VEVO channels use both styles
        'Arijit Singh Vevo',
        'ArijitSinghVEVO',
        'Shreya Ghoshal Vevo',
        'ShreyaGhoshalVEVO',
        'Neha Kakkar Vevo',
        'NehaKakkarVEVO',
        'Badshah Vevo',
        'BadshahVEVO',
        'Yo Yo Honey Singh Vevo',
        'HoneySinghVEVO',
        'Jubin Nautiyal Vevo',
        'JubinNautiyalVEVO',
        'Darshan Raval Vevo',
        'DarshanRavalVEVO',
        'Atif Aslam Vevo',
        'AtifAslamVEVO',
        'Vishal Mishra Vevo',
        'VishalMishraVEVO',
        'Pritam Vevo',
        'PritamVEVO',
        'A R Rahman Vevo',
        'ARRahmanVEVO',

        // Label-driven VEVO-like searches (helps a lot)
        'T-Series official albums',
        'Sony Music India Vevo',
        'Zee Music Company official',
        'Saregama official albums',
      ];

      // Merge all
      final allVevoArtists = [
        ...vevoArtists,
        ...vevoArtistsExtra,
        ...hindiVevoArtists,
      ];

      // Shuffle for variety
      final shuffledArtists = List<String>.from(allVevoArtists)
        ..shuffle(Random());

      // Queries that yield Vevo/official albums
      final vevoQueries = [
        'Vevo official albums',
        'Vevo popular albums',
        'Vevo certified',
        'Vevo top albums',
        'Vevo presents',
        'Vevo exclusive',
        'Bollywood official soundtrack',
        'Hindi movie album',
      ];

      // Search by artists
      for (final artist in shuffledArtists) {
        if (albums.length >= limit) break;

        try {
          final results = await searchAlbums(artist, limit: 5);

          for (final album in results) {
            if (!seenIds.contains(album.id) &&
                (album.artist.toLowerCase().contains('vevo') ||
                    album.artist.toLowerCase().contains('t-series') ||
                    album.artist.toLowerCase().contains('sony') ||
                    album.artist.toLowerCase().contains('zee') ||
                    album.artist.toLowerCase().contains('saregama') ||
                    album.title.toLowerCase().contains('soundtrack') ||
                    album.artist.contains(artist.replaceAll(' Vevo', '')))) {
              seenIds.add(album.id);
              albums.add(album);

              if (albums.length >= limit) break;
            }
          }

          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          print('⚠️ Error searching "$artist": $e');
        }
      }

      // Fallback queries
      if (albums.length < limit) {
        final shuffledQueries = List<String>.from(vevoQueries)
          ..shuffle(Random());

        for (final query in shuffledQueries) {
          if (albums.length >= limit) break;

          try {
            final results = await searchAlbums(query, limit: 10);

            for (final album in results) {
              if (!seenIds.contains(album.id) &&
                  (album.artist.toLowerCase().contains('vevo') ||
                      album.artist.toLowerCase().contains('t-series') ||
                      album.artist.toLowerCase().contains('sony') ||
                      album.artist.toLowerCase().contains('zee') ||
                      album.artist.toLowerCase().contains('saregama') ||
                      album.title.toLowerCase().contains('soundtrack'))) {
                seenIds.add(album.id);
                albums.add(album);

                if (albums.length >= limit) break;
              }
            }

            await Future.delayed(const Duration(milliseconds: 300));
          } catch (e) {
            print('⚠️ Error searching "$query": $e');
          }
        }
      }

      albums.shuffle(Random());

      print('✅ Returning ${albums.take(limit).length} Vevo/Hindi albums');
      return albums.take(limit).toList();
    } catch (e) {
      print('❌ Error fetching Vevo albums: $e');
      return [];
    }
  }

  Future<List<Album>> getTasteBasedAlbums({
    required List<String> topArtists,
    int limit = 20,
  }) async {
    final albums = <Album>[];
    final seenIds = <String>{};

    // If user has no taste data → fallback
    if (topArtists.isEmpty) {
      return getVevoAlbums(limit: limit);
    }

    for (final artist in topArtists) {
      if (albums.length >= limit) break;

      try {
        final results = await searchAlbums(artist, limit: 6);

        for (final album in results) {
          if (!seenIds.contains(album.id)) {
            seenIds.add(album.id);
            albums.add(album);

            if (albums.length >= limit) break;
          }
        }

        await Future.delayed(const Duration(milliseconds: 120));
      } catch (_) {}
    }

    // Fallback if still low
    if (albums.length < limit) {
      final fallback = await getVevoAlbums(limit: limit - albums.length);
      albums.addAll(fallback);
    }

    return albums.take(limit).toList();
  }

  /// Stream version that yields Vevo + Hindi albums
  Stream<Album> getVevoAlbumsStream({int limit = 20}) async* {
    final seenIds = <String>{};
    int yielded = 0;

    final vevoArtists = [
      'Taylor Swift Vevo',
      'Ed Sheeran Vevo',
      'Ariana Grande Vevo',
      'The Weeknd Vevo',
      'Dua Lipa Vevo',

      // Hindi
      'Arijit Singh Vevo',
      'Shreya Ghoshal Vevo',
      'Neha Kakkar Vevo',
      'T-Series official albums',
      'Bollywood official soundtrack',
    ];

    final shuffledArtists = List<String>.from(vevoArtists)..shuffle(Random());

    for (final artist in shuffledArtists) {
      if (yielded >= limit) break;

      try {
        final results = await searchAlbums(artist, limit: 5);

        for (final album in results) {
          if (!seenIds.contains(album.id) &&
              (album.artist.toLowerCase().contains('vevo') ||
                  album.artist.toLowerCase().contains('t-series') ||
                  album.artist.toLowerCase().contains('sony') ||
                  album.artist.toLowerCase().contains('zee') ||
                  album.artist.toLowerCase().contains('saregama') ||
                  album.title.toLowerCase().contains('soundtrack'))) {
            seenIds.add(album.id);
            yield album;
            yielded++;

            if (yielded >= limit) break;
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print('⚠️ Stream error "$artist": $e');
      }
    }
  }

  /// Helper method to check if an album is Vevo-related
  bool _isVevoAlbum(Album album) {
    final vevoKeywords = ['vevo', 'VEVO', 'Vevo', 'official', 'VEVO official'];

    return vevoKeywords.any(
      (keyword) =>
          album.artist.contains(keyword) || album.title.contains(keyword),
    );
  }

  /// Stream version — yields albums immediately as discovered from charts.
  Stream<Album> getMixedRandomAlbumsStream({int limit = 50}) async* {
    final seenIds = <String>{};
    int yielded = 0;

    for (final browseId in _trendingBrowseIds) {
      if (yielded >= limit) break;
      try {
        final found = await _fetchAlbumsFromBrowsePage(browseId);
        for (final album in found) {
          if (!seenIds.contains(album.id)) {
            seenIds.add(album.id);
            yield album;
            yielded++;
            if (yielded >= limit) return;
          }
        }
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        print('  ⚠️ Stream browse "$browseId" error: $e');
      }
    }

    if (yielded < limit) {
      final shuffledTerms = List<String>.from(_chartSearchTerms)
        ..shuffle(Random());
      for (final term in shuffledTerms) {
        if (yielded >= limit) break;
        try {
          final found = await searchAlbums(term, limit: 20);
          for (final album in found) {
            if (!seenIds.contains(album.id)) {
              seenIds.add(album.id);
              yield album;
              yielded++;
              if (yielded >= limit) return;
            }
          }
          await Future.delayed(const Duration(milliseconds: 250));
        } catch (e) {
          print('  ⚠️ Stream search "$term" error: $e');
        }
      }
    }
  }

  /// Get full album details including song list.
  Future<Album?> getAlbumDetails(String albumId) async {
    try {
      print('📀 [YTMusicScraper] Loading album: $albumId');
      final data = await _makeRequest(
        endpoint: 'browse',
        body: {'context': _context, 'browseId': albumId},
      );
      if (data == null) return null;

      final meta = _extractAlbumMetadata(data, albumId);
      final songs = _extractSongsMetadata(data);

      // If artist is still unknown, try to extract from songs
      String artistName = meta['artist'] as String;
      if (artistName == 'Unknown Artist' && songs.isNotEmpty) {
        // Get artist from first song
        artistName = songs.first.artists.isNotEmpty
            ? songs.first.artists.first
            : 'Unknown Artist';
      }

      print(
        '✅ [YTMusicScraper] "${meta['title']}" by "$artistName" — ${songs.length} songs',
      );
      return Album(
        id: albumId,
        title: meta['title'] as String,
        artist: artistName,
        coverArt: meta['coverArt'] as String?,
        year: meta['year'] as int? ?? 0,
        songs: songs,
      );
    } catch (e) {
      print('❌ [YTMusicScraper] getAlbumDetails error: $e');
      return null;
    }
  }

  /// Search albums by query string.
  Future<List<Album>> searchAlbums(String query, {int limit = 20}) async {
    try {
      final data = await _makeRequest(
        endpoint: 'search',
        body: {
          'context': _context,
          'query': query,
          'params': _albumFilterParam,
        },
      );
      if (data == null) return [];
      return _parseSearchResults(data, limit);
    } catch (e) {
      print('❌ [YTMusicScraper] searchAlbums error: $e');
      return [];
    }
  }

  // ── Browse Page Parsing ────────────────────────────────────────────────────

  Future<List<Album>> _fetchAlbumsFromBrowsePage(String browseId) async {
    final data = await _makeRequest(
      endpoint: 'browse',
      body: {'context': _context, 'browseId': browseId},
    );
    if (data == null) return [];

    final albums = <Album>[];
    _walkContentTree(data, albums);
    return albums;
  }

  /// Recursively walk all known YTMusic content structures and
  /// collect album entries wherever they appear.
  void _walkContentTree(Map<String, dynamic> data, List<Album> out) {
    final contentRoots = _findAllContentLists(data);
    for (final sections in contentRoots) {
      _extractFromSections(sections, out);
    }
  }

  /// Find all section-list content arrays in the response,
  /// regardless of which renderer structure wraps them.
  List<List<dynamic>> _findAllContentLists(Map<String, dynamic> data) {
    final results = <List<dynamic>>[];

    // singleColumnBrowseResultsRenderer → used by FEmusic_charts, FEmusic_home
    final tabs1 =
        data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
            as List?;
    if (tabs1 != null) {
      for (final tab in tabs1) {
        final sections =
            tab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (sections != null) results.add(sections);
      }
    }

    // twoColumnBrowseResultsRenderer → used by some browse pages
    final primary =
        data['contents']?['twoColumnBrowseResultsRenderer']?['primaryContents']?['sectionListRenderer']?['contents']
            as List?;
    if (primary != null) results.add(primary);

    final secondary =
        data['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents']
            as List?;
    if (secondary != null) results.add(secondary);

    // tabbedSearchResultsRenderer → used by search
    final tabs2 =
        data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
    if (tabs2 != null) {
      for (final tab in tabs2) {
        final sections =
            tab['tabRenderer']?['content']?['sectionListRenderer']?['contents']
                as List?;
        if (sections != null) results.add(sections);
      }
    }

    return results;
  }

  void _extractFromSections(List<dynamic> sections, List<Album> out) {
    for (final section in sections) {
      // Carousel shelf (home/charts — main format for trending albums)
      _extractFromShelf(
        section['musicCarouselShelfRenderer']?['contents'],
        out,
        isCarousel: true,
      );

      // Immersive carousel (sometimes used for chart highlights)
      _extractFromShelf(
        section['musicImmersiveCarouselShelfRenderer']?['contents'],
        out,
        isCarousel: true,
      );

      // Regular shelf (search results, new releases)
      _extractFromShelf(
        section['musicShelfRenderer']?['contents'],
        out,
        isCarousel: false,
      );
    }
  }

  void _extractFromShelf(
    dynamic items,
    List<Album> out, {
    required bool isCarousel,
  }) {
    if (items is! List) return;
    for (final item in items) {
      final album = isCarousel
          ? _parseCarouselItem(item as Map<String, dynamic>)
          : _parseShelfItem(item as Map<String, dynamic>);
      if (album != null) out.add(album);
    }
  }

  // ── Item Parsers ───────────────────────────────────────────────────────────

  /// Parse a musicTwoRowItemRenderer (carousel item).
  Album? _parseCarouselItem(Map<String, dynamic> item) {
    try {
      final r = item['musicTwoRowItemRenderer'];
      if (r == null) return null;

      final browseId =
          r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
      // Real album pages always start with MPREb_
      if (browseId == null || !browseId.startsWith('MPREb_')) return null;

      final title = _extractText(r['title']) ?? 'Unknown Album';
      final subtitleText = _extractText(r['subtitle']) ?? '';
      // Subtitle format: "Artist • Year" or just "Artist"
      final artist = subtitleText.contains('•')
          ? subtitleText.split('•').first.trim()
          : subtitleText.trim();

      final coverArt = _extractBestThumbnail(
        r['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail'],
      );

      return Album(
        id: browseId,
        title: title,
        artist: artist.isNotEmpty ? artist : 'Unknown Artist',
        coverArt: coverArt,
        year: _extractYear(r['subtitle']) ?? 0,
        songs: [],
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse a musicResponsiveListItemRenderer (search/shelf item).
  Album? _parseShelfItem(Map<String, dynamic> item) {
    try {
      final r = item['musicResponsiveListItemRenderer'];
      if (r == null) return null;

      final browseId =
          r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
      if (browseId == null || !browseId.startsWith('MPREb_')) return null;

      final cols = r['flexColumns'] as List?;
      if (cols == null || cols.isEmpty) return null;

      final title = _extractFlexColumnText(cols[0]) ?? 'Unknown Album';
      final artist = cols.length > 1
          ? _extractFlexColumnText(cols[1]) ?? 'Unknown Artist'
          : 'Unknown Artist';

      final coverArt = _extractBestThumbnail(r['thumbnail']);

      return Album(
        id: browseId,
        title: title,
        artist: artist,
        coverArt: coverArt,
        year: 0,
        songs: [],
      );
    } catch (_) {
      return null;
    }
  }

  List<Album> _parseSearchResults(Map<String, dynamic> data, int limit) {
    final albums = <Album>[];
    final contentLists = _findAllContentLists(data);
    for (final sections in contentLists) {
      _extractFromSections(sections, albums);
      if (albums.length >= limit) break;
    }
    return albums.take(limit).toList();
  }

  // ── Album Details ──────────────────────────────────────────────────────────

  Map<String, dynamic> _extractAlbumMetadata(
    Map<String, dynamic> data,
    String albumId,
  ) {
    String title = 'Unknown Album';
    String artist = 'Unknown Artist';
    String? coverArt;
    int? year;

    try {
      dynamic header = data['header']?['musicDetailHeaderRenderer'];
      header ??= data['header']?['musicEditablePlaylistDetailHeaderRenderer'];

      if (header != null) {
        // Extract title
        title = _extractText(header['title']) ?? title;

        // Extract artist - this is the key fix
        // The subtitle usually contains artist info in various formats
        final subtitle = header['subtitle'];
        if (subtitle != null) {
          final subtitleText = _extractText(subtitle) ?? '';

          // Try different subtitle formats to extract artist
          if (subtitleText.contains('•')) {
            // Format: "Artist • Year • Album"
            artist = subtitleText.split('•').first.trim();
          } else if (subtitleText.contains('·')) {
            // Alternative separator
            artist = subtitleText.split('·').first.trim();
          } else {
            // Check if there's a separate artist field
            final runs = subtitle['runs'] as List?;
            if (runs != null && runs.isNotEmpty) {
              // Sometimes artist is in a navigation endpoint
              for (final run in runs) {
                final navEndpoint =
                    run['navigationEndpoint']?['browseEndpoint'];
                if (navEndpoint != null) {
                  final pageType =
                      navEndpoint['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];
                  if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
                    artist = run['text'] as String? ?? artist;
                    break;
                  }
                }
              }

              // If still not found, just take the first part
              if (artist == 'Unknown Artist' && runs.isNotEmpty) {
                artist = runs.first['text'] as String? ?? artist;
              }
            }
          }

          // Extract year from subtitle
          year = _extractYear(subtitle);
        }

        // Try to get artist from subtitle2 if available
        if (artist == 'Unknown Artist') {
          final subtitle2 = header['subtitle2'];
          if (subtitle2 != null) {
            final subtitle2Text = _extractText(subtitle2) ?? '';
            if (subtitle2Text.isNotEmpty &&
                !subtitle2Text.contains(RegExp(r'\d{4}'))) {
              artist = subtitle2Text;
            }
          }
        }

        // Extract cover art
        coverArt = _extractBestThumbnail(header['thumbnail']);
      }

      // If still no artist, try to get from the first song in the track list
      if (artist == 'Unknown Artist') {
        try {
          final songs = _extractSongsMetadata(data);
          if (songs.isNotEmpty && songs.first.artists.isNotEmpty) {
            artist = songs.first.artists.first;
          }
        } catch (_) {}
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

  List<Song> _extractSongsMetadata(Map<String, dynamic> data) {
    final songs = <Song>[];
    try {
      final contentLists = _findAllContentLists(data);
      for (final sections in contentLists) {
        for (final section in sections) {
          var shelf = section['musicShelfRenderer'];
          shelf ??= section['musicPlaylistShelfRenderer'];
          if (shelf == null) continue;
          final items = shelf['contents'] as List?;
          if (items == null) continue;
          for (final item in items) {
            final song = _parseSongItem(item as Map<String, dynamic>);
            if (song != null) songs.add(song);
          }
          if (songs.isNotEmpty) return songs;
        }
      }
    } catch (e) {
      print('⚠️ Error extracting songs: $e');
    }
    return songs;
  }

  Song? _parseSongItem(Map<String, dynamic> item) {
    try {
      final r = item['musicResponsiveListItemRenderer'];
      if (r == null) return null;

      final videoId = r['playlistItemData']?['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) return null;

      final cols = r['flexColumns'] as List?;
      if (cols == null || cols.isEmpty) return null;

      final title = _extractFlexColumnText(cols[0]) ?? 'Unknown';

      final artists = <String>[];
      if (cols.length > 1) {
        final runs =
            cols[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                as List?;
        for (final run in runs ?? []) {
          final t = run['text'] as String?;
          // Filter out separators and non-artist text
          if (t != null &&
              t.trim().isNotEmpty &&
              t.trim() != '•' &&
              t.trim() != '·' &&
              !t.contains(RegExp(r'\d{4}'))) {
            // Filter out years
            artists.add(t);
          }
        }
      }

      // If no artists found in flex columns, try thumbnail overlay or other fields
      if (artists.isEmpty) {
        // Try to get artist from the subtitle
        final subtitle = r['subtitle'];
        if (subtitle != null) {
          final subtitleText =
              _extractText({
                'runs': [
                  {'text': subtitle},
                ],
              }) ??
              '';
          if (subtitleText.isNotEmpty &&
              !subtitleText.contains(RegExp(r'\d{4}'))) {
            artists.add(subtitleText);
          }
        }
      }

      if (artists.isEmpty) artists.add('Unknown Artist');

      return Song(
        videoId: videoId,
        title: title,
        artists: artists,
        thumbnail: _extractBestThumbnail(r['thumbnail']) ?? '',
        duration: cols.length > 2 ? _extractFlexColumnText(cols.last) : null,
        audioUrl: null,
      );
    } catch (e) {
      print('⚠️ Error parsing song: $e');
      return null;
    }
  }

  // Add to YTMusicAlbumsScraper class
  Future<List<Album>> getAlbumVersions(
    String title,
    String artist, {
    int limit = 20,
  }) async {
    try {
      print(
        '🔍 [YTMusicScraper] Looking for versions of "$title" by "$artist"',
      );

      // Search with album + artist
      final searchQuery = '$title $artist';
      final searchResults = await searchAlbums(searchQuery, limit: limit * 2);

      // Also try searching without artist for deluxe/remastered versions
      final titleOnlyResults = await searchAlbums(title, limit: limit);

      // Combine and remove duplicates
      final allResults = [...searchResults, ...titleOnlyResults];
      final uniqueAlbums = <String, Album>{};

      for (final album in allResults) {
        if (!uniqueAlbums.containsKey(album.id)) {
          uniqueAlbums[album.id] = album;
        }
      }

      final versions = uniqueAlbums.values.toList();
      print(
        '✅ [YTMusicScraper] Found ${versions.length} versions for "$title"',
      );

      return versions.take(limit).toList();
    } catch (e) {
      print('❌ [YTMusicScraper] Error getting album versions: $e');
      return [];
    }
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  void _mergeUnique(List<Album> source, List<Album> dest, Set<String> seen) {
    for (final a in source) {
      if (!seen.contains(a.id)) {
        seen.add(a.id);
        dest.add(a);
      }
    }
  }

  Future<Map<String, dynamic>?> _makeRequest({
    required String endpoint,
    required Map<String, dynamic> body,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiUrl/$endpoint'),
        headers: _headers,
        body: jsonEncode(body),
      );
      if (res.statusCode != 200) {
        print('❌ [YTMusicScraper] HTTP ${res.statusCode} /$endpoint');
        return null;
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      print('❌ [YTMusicScraper] Request error: $e');
      return null;
    }
  }

  String? _extractText(dynamic obj) {
    try {
      if (obj == null) return null;
      final runs = obj['runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        return runs.map((r) => r['text'] as String? ?? '').join('');
      }
      return obj['simpleText'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _extractFlexColumnText(dynamic col) {
    try {
      final runs =
          col?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
              as List?;
      return runs?.map((r) => r['text'] as String? ?? '').join('');
    } catch (_) {
      return null;
    }
  }

  String? _extractBestThumbnail(dynamic obj) {
    try {
      if (obj == null) return null;
      List? thumbs =
          obj['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List?;
      thumbs ??=
          obj['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
      thumbs ??= obj['thumbnails'] as List?;
      if (thumbs != null && thumbs.isNotEmpty) {
        var url = (thumbs.last as Map)['url'] as String?;
        if (url != null && url.contains('=w')) {
          url = '${url.split('=w')[0]}=w500-h500';
        }
        return url;
      }
    } catch (_) {}
    return null;
  }

  int? _extractYear(dynamic obj) {
    try {
      final text = _extractText(obj);
      final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(text ?? '');
      return match != null ? int.tryParse(match.group(0)!) : null;
    } catch (_) {
      return null;
    }
  }

  /// Emergency fallback — only triggered if ALL network calls fail.
  /// Uses YTMusic's own global chart playlist IDs (not artist-specific).
  List<Album> _minimalFallback() {
    return [
      Album(
        id: 'MPREb_4pL8gzVGOTL',
        title: 'Top Songs - Global',
        artist: 'YouTube Music Charts',
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
    ];
  }

  void dispose() {}
}
