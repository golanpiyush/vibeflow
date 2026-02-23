// newytradio.dart
//
// YouTube Music Radio using the Innertube /next endpoint.
//
// Hits the same endpoint ViMusic uses for "Up Next" / Radio:
//   POST /youtubei/v1/next  with playlistId = "RDAMVM{videoId}"
//
// This returns a curated mix from YouTube's recommendation engine —
// variety of artists, not just the same artist repeated.
//
// Usage:
//   final radio = NewYTRadio();
//   final songs = await radio.getRadio('dQw4w9WgXcW');
//   final more  = await radio.getMore(); // continuation

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vibeflow/models/quick_picks_model.dart';

class NewYTRadio {
  static const _nextEndpoint =
      'https://music.youtube.com/youtubei/v1/next'
      '?prettyPrint=false'
      '&key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  final http.Client _http;
  final Duration _timeout;

  String? _continuationToken;
  final Set<String> _seenVideoIds = {};
  final Map<String, List<QuickPick>> _cache = {};
  static const _maxCacheSize = 15;

  NewYTRadio({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client(),
       _timeout = timeout;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch a radio queue seeded by [videoId].
  /// Returns up to [limit] songs (default 25).
  /// Call [getMore] to load the next page via continuation.
  Future<List<QuickPick>> getRadio(
    String videoId, {
    int limit = 25,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _cache[videoId];
      if (cached != null) {
        print('⚡ [NewYTRadio] Cache hit for $videoId');
        return cached;
      }
    }

    print('📻 [NewYTRadio] Fetching radio for $videoId');
    _continuationToken = null;

    final songs = await _fetchNextPage(videoId: videoId, limit: limit);
    if (songs.isNotEmpty) {
      _cacheResults(videoId, songs);
      _seenVideoIds.addAll(songs.map((s) => s.videoId));
    }
    return songs;
  }

  /// Load more songs using the continuation token from the last [getRadio] call.
  Future<List<QuickPick>> getMore({int limit = 25}) async {
    if (_continuationToken == null) {
      print('⚠️ [NewYTRadio] No continuation token — call getRadio first');
      return [];
    }
    print('📻 [NewYTRadio] Loading more songs (continuation)');
    return _fetchContinuation(limit: limit);
  }

  /// Get radio and filter out the seed video from results.
  Future<List<QuickPick>> getUpNext(String videoId, {int limit = 30}) async {
    // Snapshot seen IDs BEFORE fetching so we don't filter the fresh results
    final seenBefore = Set<String>.from(_seenVideoIds);

    final songs = await getRadio(videoId, limit: limit + 1);

    return songs
        .where((s) => s.videoId != videoId && !seenBefore.contains(s.videoId))
        .take(limit)
        .toList();
  }

  void clearSeenHistory() => _seenVideoIds.clear();

  void clearCache() {
    _cache.clear();
    _seenVideoIds.clear();
  }

  void dispose() {
    _cache.clear();
    _http.close();
  }

  // ── Initial page fetch ─────────────────────────────────────────────────────

  Future<List<QuickPick>> _fetchNextPage({
    required String videoId,
    required int limit,
  }) async {
    // OAE%3D is the param that reliably triggers queue population.
    // Try it first, then fall back to the standard radio param.
    final paramVariants = ['OAE%3D', 'OAHyAQIIAQ%3D%3D'];

    for (final params in paramVariants) {
      final body = <String, dynamic>{
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'params': params,
        'context': _buildContext(),
        'enablePersistentPlaylistPanel': true,
        'isAudioOnly': true,
        'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
      };

      final response = await _http
          .post(
            Uri.parse(_nextEndpoint),
            headers: _buildHeaders(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        print('❌ [NewYTRadio] /next returned ${response.statusCode}');
        continue;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      // If hack=true, the queue needs hydration via a separate request.
      if (_hasHackFlag(json)) {
        print('🔄 [NewYTRadio] hack=true — fetching queue via hydration');
        return _fetchQueueHydration(
          videoId: videoId,
          queueContextParams: json['queueContextParams'] as String?,
          limit: limit,
        );
      }

      final songs = _parseNextResponse(json, limit);
      if (songs.isNotEmpty) return songs;
    }

    return [];
  }

  // ── Hydration fetch (hack=true fallback) ───────────────────────────────────

  /// Called when the initial response has hack=true.
  /// Tries OAE%3D first (proven to work), then falls back to no-playlistId.
  Future<List<QuickPick>> _fetchQueueHydration({
    required String videoId,
    required String? queueContextParams,
    required int limit,
  }) async {
    // OAE%3D is the param confirmed to resolve hack=true.
    // Try all playlist variants with it before anything else.
    final playlistVariants = ['RDAMVM$videoId', 'RDEM$videoId', 'RD$videoId'];

    for (final pl in playlistVariants) {
      final body = <String, dynamic>{
        'videoId': videoId,
        'playlistId': pl,
        'params': 'OAE%3D',
        'context': _buildContext(),
        'enablePersistentPlaylistPanel': true,
        'isAudioOnly': true,
        'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
        'autoplay': true,
      };
      if (queueContextParams != null && queueContextParams.isNotEmpty) {
        body['queueContextParams'] = queueContextParams;
      }

      final response = await _http
          .post(
            Uri.parse(_nextEndpoint),
            headers: _buildHeaders(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) continue;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final songs = _parseNextResponse(json, limit);
      if (songs.isNotEmpty) {
        print(
          '✅ [NewYTRadio] Hydration success: playlistId=$pl → ${songs.length} songs',
        );
        return songs;
      }
    }

    // ── Final fallback: no playlistId ──────────────────────────────────────
    // Omitting playlistId forces YouTube to return Up Next inline with
    // musicQueueRenderer.content populated, even when hack=true is set.
    print('🔄 [NewYTRadio] Trying no-playlistId fallback');
    final fallbackBody = <String, dynamic>{
      'videoId': videoId,
      'context': _buildContext(),
      'enablePersistentPlaylistPanel': true,
      'isAudioOnly': true,
    };
    if (queueContextParams != null && queueContextParams.isNotEmpty) {
      fallbackBody['queueContextParams'] = queueContextParams;
    }

    final fallbackResponse = await _http
        .post(
          Uri.parse(_nextEndpoint),
          headers: _buildHeaders(),
          body: jsonEncode(fallbackBody),
        )
        .timeout(_timeout);

    if (fallbackResponse.statusCode == 200) {
      final json = jsonDecode(fallbackResponse.body) as Map<String, dynamic>;
      final songs = _parseNextResponse(json, limit);
      if (songs.isNotEmpty) {
        print('✅ [NewYTRadio] No-playlistId fallback: ${songs.length} songs');
        return songs;
      }
    }

    print('❌ [NewYTRadio] All hydration attempts failed for $videoId');
    return [];
  }

  // ── Continuation fetch ─────────────────────────────────────────────────────

  Future<List<QuickPick>> _fetchContinuation({required int limit}) async {
    final body = {
      'context': _buildContext(),
      'continuation': _continuationToken,
    };

    final response = await _http
        .post(
          Uri.parse(_nextEndpoint),
          headers: _buildHeaders(),
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      print('❌ [NewYTRadio] Continuation returned ${response.statusCode}');
      return [];
    }

    return _parseContinuationResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
      limit,
    );
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  List<QuickPick> _parseNextResponse(Map<String, dynamic> json, int limit) {
    final songs = <QuickPick>[];
    try {
      final playlistPanel = _findPlaylistPanel(json);
      if (playlistPanel == null) {
        print('⚠️ [NewYTRadio] Could not locate playlistPanelRenderer');
        return songs;
      }

      _continuationToken = _extractContinuation(playlistPanel);

      final items = playlistPanel['contents'] as List? ?? [];
      print('[NewYTRadio] Found ${items.length} items in radio queue');

      for (final item in items) {
        final song = _parsePlaylistPanelItem(item);
        if (song != null) {
          songs.add(song);
          if (songs.length >= limit) break;
        }
      }
      print('✅ [NewYTRadio] Parsed ${songs.length} songs');
    } catch (e, stack) {
      print('❌ [NewYTRadio] Parse error: $e');
      print(stack.toString().split('\n').take(4).join('\n'));
    }
    return songs;
  }

  List<QuickPick> _parseContinuationResponse(
    Map<String, dynamic> json,
    int limit,
  ) {
    final songs = <QuickPick>[];
    try {
      final continuation =
          json['continuationContents']?['playlistPanelContinuation']
              as Map<String, dynamic>?;
      if (continuation == null) {
        print('⚠️ [NewYTRadio] No playlistPanelContinuation');
        return songs;
      }

      _continuationToken = _extractContinuation(continuation);

      for (final item in (continuation['contents'] as List? ?? [])) {
        final song = _parsePlaylistPanelItem(item);
        if (song != null) {
          songs.add(song);
          if (songs.length >= limit) break;
        }
      }
      print('✅ [NewYTRadio] Continuation: ${songs.length} more songs');
    } catch (e) {
      print('❌ [NewYTRadio] Continuation parse error: $e');
    }
    return songs;
  }

  // ── Panel finder ───────────────────────────────────────────────────────────

  /// Tries every known structural path YouTube Music uses for the queue panel.
  Map<String, dynamic>? _findPlaylistPanel(Map<String, dynamic> json) {
    // ── Path A: singleColumnMusicWatchNextResultsRenderer (ANDROID_MUSIC) ──
    try {
      final watchNext =
          json['contents']?['singleColumnMusicWatchNextResultsRenderer'];
      final tabs =
          watchNext?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']
              as List?;

      if (tabs != null && tabs.isNotEmpty) {
        final tabContent = tabs[0]?['tabRenderer']?['content'];
        final queueRenderer =
            tabContent?['musicQueueRenderer'] as Map<String, dynamic>?;

        if (queueRenderer != null) {
          // Always check content even when hack=true —
          // hack is a lazy-load signal; content may still be populated.
          final content = queueRenderer['content'] as Map<String, dynamic>?;
          if (content != null) {
            // A1: direct playlistPanelRenderer
            final panel =
                content['playlistPanelRenderer'] as Map<String, dynamic>?;
            if (panel != null) {
              print('[NewYTRadio] ✅ Path A1 matched');
              return panel;
            }

            // A2: contents array wrapper
            final inner = content['contents'] as List?;
            if (inner != null) {
              for (final c in inner) {
                final p = c['playlistPanelRenderer'] as Map<String, dynamic>?;
                if (p != null) {
                  print('[NewYTRadio] ✅ Path A2 matched');
                  return p;
                }
              }
            }

            // A4: any direct child map containing playlistPanelRenderer
            for (final val in content.values) {
              if (val is Map<String, dynamic>) {
                final p = val['playlistPanelRenderer'] as Map<String, dynamic>?;
                if (p != null) {
                  print('[NewYTRadio] ✅ Path A4 matched');
                  return p;
                }
              }
            }
          }

          // A3: flat tabContent.playlistPanelRenderer
          final flat =
              tabContent?['playlistPanelRenderer'] as Map<String, dynamic>?;
          if (flat != null) {
            print('[NewYTRadio] ✅ Path A3 matched');
            return flat;
          }
        }
      }
    } catch (e) {
      print('⚠️ [NewYTRadio] Path A exception: $e');
    }

    // ── Path B: twoColumnWatchNextResults (web-style) ──────────────────────
    try {
      final results =
          json['contents']?['twoColumnWatchNextResults']?['secondaryResults']?['secondaryResults']?['results']
              as List?;
      if (results != null) {
        for (final item in results) {
          final panel = item['playlistPanelRenderer'] as Map<String, dynamic>?;
          if (panel != null) {
            print('[NewYTRadio] ✅ Path B matched');
            return panel;
          }
        }
      }
    } catch (_) {}

    // ── Path C: top-level playlistPanelRenderer ─────────────────────────────
    try {
      final direct = json['playlistPanelRenderer'] as Map<String, dynamic>?;
      if (direct != null) {
        print('[NewYTRadio] ✅ Path C matched');
        return direct;
      }
    } catch (_) {}

    return null;
  }

  // ── Item parser ────────────────────────────────────────────────────────────

  QuickPick? _parsePlaylistPanelItem(dynamic item) {
    try {
      final renderer =
          item['playlistPanelVideoRenderer'] as Map<String, dynamic>?;
      if (renderer == null) return null;

      final videoId =
          renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;
      if (videoId == null) return null;

      final title =
          renderer['title']?['runs']?[0]?['text'] as String? ?? 'Unknown';

      final artistRuns =
          renderer['longBylineText']?['runs'] as List? ??
          renderer['shortBylineText']?['runs'] as List? ??
          [];
      final artist = artistRuns.isNotEmpty
          ? (artistRuns[0]['text'] as String? ?? 'Unknown Artist')
          : 'Unknown Artist';

      final duration = renderer['lengthText']?['runs']?[0]?['text'] as String?;

      final thumbnails = renderer['thumbnail']?['thumbnails'] as List? ?? [];
      final thumbnail = thumbnails.isNotEmpty
          ? (thumbnails.reduce(
                      (a, b) =>
                          ((a['width'] as int? ?? 0) >=
                              (b['width'] as int? ?? 0)
                          ? a
                          : b),
                    )['url']
                    as String? ??
                '')
          : '';
      // final thumbnail = _resolveBestThumbnail(thumbnails, videoId);

      return QuickPick(
        videoId: videoId,
        title: title,
        artists: artist,
        thumbnail: thumbnail,
        duration: duration,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  /// Picks the highest-quality thumbnail URL from the thumbnails list.
  ///
  /// Strategy (in order):
  ///   1. Strip YouTube's size params and request maxresdefault (1280×720)
  ///   2. Take the largest thumbnail from the list by declared width
  ///   3. Strip size params and request hqdefault (480×360)  ← fallback
  ///   4. Raw URL from the list as last resort
  String _resolveBestThumbnail(List thumbnails, String videoId) {
    // Always try maxresdefault first — highest quality YT thumbnail
    final maxRes = 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';

    // Pull the base ytimg URL from whatever thumbnail YT gave us,
    // strip their forced size params (=w226-h226... or ?sqp=...) so
    // we can substitute our own quality suffix.
    String? baseYtimgUrl;
    if (thumbnails.isNotEmpty) {
      final raw = thumbnails.last['url'] as String? ?? '';
      if (raw.contains('i.ytimg.com')) {
        // Strip everything after the filename
        baseYtimgUrl = raw.split('=w').first.split('?').first;
      }
    }

    // Ordered quality ladder — we return the first URL that loads;
    // the caller can use these in an Image widget with errorBuilder
    // chaining, or resolve eagerly with _probeUrl().
    //
    // For lazy/widget-based fallback, return an ordered list and let
    // the UI cycle through them. Here we return the best candidate
    // directly and attach fallbacks as a param on QuickPick if needed.
    //
    // Current approach: return maxres as primary; widget should fall
    // back through sddefault → hqdefault → raw list URL on error.
    return maxRes;

    // NOTE: If you want eager resolution (async probe), swap the return
    // above for: return await _probeUrl(videoId, baseYtimgUrl, thumbnails);
  }

  /// Ordered quality ladder for use in Image widget errorBuilder.
  /// Pass this list to your image widget so it cycles on network error.
  static List<String> thumbnailFallbacks(String videoId, {String? rawUrl}) {
    final base = rawUrl != null
        ? rawUrl.split('=w').first.split('?').first
        : 'https://i.ytimg.com/vi/$videoId';

    return [
      'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg', // 1280×720
      'https://i.ytimg.com/vi/$videoId/sddefault.jpg', //  640×480
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg', //  480×360
      'https://i.ytimg.com/vi/$videoId/mqdefault.jpg', //  320×180
      if (rawUrl != null && rawUrl.isNotEmpty)
        rawUrl, //  original as last resort
    ];
  }

  /// Returns true when musicQueueRenderer.hack == true (lazy queue signal).
  bool _hasHackFlag(Map<String, dynamic> json) {
    try {
      final watchNext =
          json['contents']?['singleColumnMusicWatchNextResultsRenderer'];
      final tabs =
          watchNext?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']
              as List?;
      if (tabs == null || tabs.isEmpty) return false;
      final tabContent = tabs[0]?['tabRenderer']?['content'];
      return tabContent?['musicQueueRenderer']?['hack'] == true;
    } catch (_) {
      return false;
    }
  }

  String? _extractContinuation(Map<String, dynamic> renderer) {
    try {
      final continuations = renderer['continuations'] as List?;
      if (continuations == null || continuations.isEmpty) return null;
      return continuations[0]?['nextRadioContinuationData']?['continuation']
              as String? ??
          continuations[0]?['nextContinuationData']?['continuation'] as String?;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _buildContext() => {
    'client': {
      'clientName': 'ANDROID_MUSIC',
      'clientVersion': '6.42.52',
      'androidSdkVersion': 33,
      'hl': 'en',
      'gl': 'US',
      'osName': 'Android',
      'osVersion': '13',
      'platform': 'MOBILE',
    },
  };

  Map<String, String> _buildHeaders() => {
    'Content-Type': 'application/json',
    'User-Agent':
        'com.google.android.apps.youtube.music/6.42.52 (Linux; U; Android 13; en_US) gzip',
    'Accept': 'application/json',
    'Accept-Encoding': 'identity',
    'X-YouTube-Client-Name': '21',
    'X-YouTube-Client-Version': '6.42.52',
    'Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
  };

  void _cacheResults(String videoId, List<QuickPick> songs) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[videoId] = songs;
  }
}
