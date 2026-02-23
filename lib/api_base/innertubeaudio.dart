// innertubeaudio.dart
//
// Drop-in InnerTube audio resolution — with visitor_data + working clients.
//
// KEY FIXES (Feb 2026):
//   1. Fetch visitor_data from /config endpoint before player calls
//   2. Added ANDROID client back with params:"CgIQBg" integrity bypass
//   3. Added ANDROID_VR as additional fallback
//   4. ANDROID_MUSIC version downgraded to 5.26.1 (matches zerodytrash verified)
//   5. Correct client versions from zerodytrash/YouTube-Internal-Clients
//   6. User-selectable AudioSourcePreference (InnerTube vs YTMusicAPI)
//      VibeFlow will auto-override if the preferred source fails.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Audio source preference
// ─────────────────────────────────────────────────────────────────────────────

/// The user's preferred audio resolution backend.
///
/// VibeFlow will always try the preferred source first, but may silently
/// fall back to the other if the preferred one fails. This override is
/// transparent — the user's preference is restored for the next track.
enum AudioSourcePreference {
  /// Use InnerTube Android clients directly (ANDROID_MUSIC → ANDROID_VR → …).
  /// Lower latency, no intermediate server. Default.
  innerTube,

  /// Use the YouTube Music API / web-style scraping path as the primary.
  /// Slightly higher success rate on restricted regions, slower.
  ytMusicApi,
}

// ─────────────────────────────────────────────────────────────────────────────
// Result model
// ─────────────────────────────────────────────────────────────────────────────

class InnerTubeAudioResult {
  final String videoId;
  final String url;
  final int itag;
  final String mimeType;
  final String codec;
  final int bitrate;
  final int? contentLength;
  final double? loudnessDb;
  final String clientUsed;
  final String userAgent;
  final DateTime expiresAt;

  /// Which backend actually resolved this URL. May differ from the user's
  /// [AudioSourcePreference] if VibeFlow triggered an auto-override.
  final AudioSourcePreference resolvedVia;

  /// True if VibeFlow ignored the user's preference and used the other backend.
  final bool wasOverridden;

  const InnerTubeAudioResult({
    required this.videoId,
    required this.url,
    required this.itag,
    required this.mimeType,
    required this.codec,
    required this.bitrate,
    this.contentLength,
    this.loudnessDb,
    required this.clientUsed,
    required this.userAgent,
    required this.expiresAt,
    required this.resolvedVia,
    this.wasOverridden = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override
  String toString() =>
      'InnerTubeAudioResult(videoId: $videoId, itag: $itag, '
      'codec: $codec, bitrate: ${bitrate ~/ 1000}kbps, '
      'client: $clientUsed, via: ${resolvedVia.name}'
      '${wasOverridden ? " [OVERRIDE]" : ""})';
}

// ─────────────────────────────────────────────────────────────────────────────
// Client definitions
// ─────────────────────────────────────────────────────────────────────────────

class _ITClient {
  final String name;
  final String clientName;
  final String clientVersion;
  final String apiKey;
  final int? androidSdkVersion;
  final String userAgent;
  final String? playerParams;

  const _ITClient({
    required this.name,
    required this.clientName,
    required this.clientVersion,
    required this.apiKey,
    this.androidSdkVersion,
    required this.userAgent,
    this.playerParams,
  });
}

const _kAndroidMusicApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
const _kAndroidApiKey = 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w';

/// InnerTube Android client ladder — tried in order.
const _kInnerTubeClients = [
  _ITClient(
    name: 'ANDROID_MUSIC',
    clientName: 'ANDROID_MUSIC',
    clientVersion: '5.26.1',
    apiKey: _kAndroidMusicApiKey,
    androidSdkVersion: 33,
    userAgent:
        'com.google.android.apps.youtube.music/5.26.1 (Linux; U; Android 13; en_US) gzip',
  ),
  _ITClient(
    name: 'ANDROID_VR',
    clientName: 'ANDROID_VR',
    clientVersion: '1.60.19',
    apiKey: _kAndroidApiKey,
    androidSdkVersion: 33,
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
  ),
  _ITClient(
    name: 'ANDROID',
    clientName: 'ANDROID',
    clientVersion: '17.36.4',
    apiKey: _kAndroidApiKey,
    androidSdkVersion: 30,
    userAgent: 'com.google.android.youtube/17.36.4 (Linux; U; Android 11) gzip',
    playerParams: 'CgIQBg',
  ),
  _ITClient(
    name: 'ANDROID_TESTSUITE',
    clientName: 'ANDROID_TESTSUITE',
    clientVersion: '1.9',
    apiKey: _kAndroidApiKey,
    androidSdkVersion: 33,
    userAgent:
        'com.google.android.youtube/1.9 (Linux; U; Android 13; en_US) gzip',
  ),
];

const _kPlayerEndpoint = 'https://music.youtube.com/youtubei/v1/player';
const _kConfigEndpoint = 'https://music.youtube.com/youtubei/v1/config';

// ─────────────────────────────────────────────────────────────────────────────
// YTMusicAPI shim
//
// Replace _resolveViaYtMusicApi() body with your real YTMusicAPI call.
// The contract: return a resolved InnerTubeAudioResult or null on failure.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// InnerTubeAudio
// ─────────────────────────────────────────────────────────────────────────────

class InnerTubeAudio {
  final http.Client _http;
  final Duration _timeout;

  /// The user's preferred backend. VibeFlow may override this at runtime.
  AudioSourcePreference preference;

  final Map<String, InnerTubeAudioResult> _cache = {};
  final Map<String, Future<InnerTubeAudioResult?>> _inFlight = {};

  String? _visitorData;
  Future<String?>? _visitorDataFetch;

  InnerTubeAudio({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
    this.preference = AudioSourcePreference.innerTube,
  }) : _http = httpClient ?? http.Client(),
       _timeout = timeout;

  void dispose() {
    _http.close();
    _cache.clear();
    _inFlight.clear();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<InnerTubeAudioResult?> fetchSingle(
    String videoId, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      _cache.remove(videoId);
      _inFlight.remove(videoId);
    }

    final cached = _cache[videoId];
    if (cached != null && !cached.isExpired) {
      _log('⚡ [$videoId] Cache hit (via ${cached.resolvedVia.name})');
      return Future.value(cached);
    }

    final existing = _inFlight[videoId];
    if (existing != null) {
      _log('🔗 [$videoId] Joining in-flight request');
      return existing;
    }

    final future = _resolve(videoId).whenComplete(() {
      _inFlight.remove(videoId);
    });

    _inFlight[videoId] = future;
    return future;
  }

  Future<Map<String, InnerTubeAudioResult>> fetchBatch(
    List<String> videoIds, {
    bool forceRefresh = false,
    int concurrency = 5,
  }) async {
    final ids = videoIds.take(30).toList();
    _log('🎵 Batch resolving ${ids.length} videos (concurrency: $concurrency)');

    final results = <String, InnerTubeAudioResult>{};
    final toFetch = <String>[];

    if (!forceRefresh) {
      for (final id in ids) {
        final cached = _cache[id];
        if (cached != null && !cached.isExpired) {
          results[id] = cached;
        } else {
          toFetch.add(id);
        }
      }
    } else {
      toFetch.addAll(ids);
    }

    if (toFetch.isEmpty) return results;

    await _ensureVisitorData();

    for (int i = 0; i < toFetch.length; i += concurrency) {
      final chunk = toFetch.skip(i).take(concurrency).toList();
      final chunkResults = await Future.wait(
        chunk.map((id) => fetchSingle(id, forceRefresh: forceRefresh)),
      );
      for (int j = 0; j < chunk.length; j++) {
        final result = chunkResults[j];
        if (result != null) results[chunk[j]] = result;
      }
      if (i + concurrency < toFetch.length) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    _log('✅ Batch complete: ${results.length}/${ids.length} succeeded');
    return results;
  }

  // ── Visitor data ───────────────────────────────────────────────────────────

  Future<String?> _ensureVisitorData() async {
    if (_visitorData != null) return _visitorData;
    _visitorDataFetch ??= _fetchVisitorData().then((v) {
      _visitorData = v;
      _visitorDataFetch = null;
      return v;
    });
    return _visitorDataFetch;
  }

  Future<String?> _fetchVisitorData() async {
    try {
      _log('🔑 Fetching visitor_data from config endpoint...');
      final response = await _http
          .post(
            Uri.parse(
              '$_kConfigEndpoint?key=$_kAndroidMusicApiKey&prettyPrint=false',
            ),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'com.google.android.apps.youtube.music/5.26.1 (Linux; U; Android 13; en_US) gzip',
              'X-YouTube-Client-Name': '21',
              'X-YouTube-Client-Version': '5.26.1',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'ANDROID_MUSIC',
                  'clientVersion': '5.26.1',
                  'androidSdkVersion': 33,
                  'osName': 'Android',
                  'osVersion': '13',
                  'hl': 'en',
                  'gl': 'US',
                },
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final visitorData =
            json['responseContext']?['visitorData'] as String? ??
            json['visitorData'] as String?;
        if (visitorData != null) {
          _log('✅ Got visitor_data: ${visitorData.substring(0, 10)}...');
          return visitorData;
        }
      }
    } catch (e) {
      _log('⚠️ visitor_data fetch failed: $e');
    }
    _log('⚠️ No visitor_data obtained — requests may get LOGIN_REQUIRED');
    return null;
  }

  // ── Core resolver — preference-aware with auto-override ───────────────────

  Future<InnerTubeAudioResult?> _resolve(String videoId) async {
    final visitorData = await _ensureVisitorData();

    // Determine attempt order based on user preference.
    // Primary is tried first; if it fully fails, we auto-override to secondary.
    final primary = preference;
    final secondary = preference == AudioSourcePreference.innerTube
        ? AudioSourcePreference.ytMusicApi
        : AudioSourcePreference.innerTube;

    _log(
      '🎯 [$videoId] Preferred: ${primary.name} | '
      'Fallback: ${secondary.name}',
    );

    // ── Primary attempt ──────────────────────────────────────────────────────
    final primaryResult = await _resolveWith(
      videoId,
      primary,
      visitorData: visitorData,
      wasOverridden: false,
    );

    if (primaryResult != null) {
      _cache[videoId] = primaryResult;
      return primaryResult;
    }

    // ── Auto-override to secondary ───────────────────────────────────────────
    _log(
      '⚡ [$videoId] Primary (${primary.name}) exhausted — '
      'VibeFlow auto-overriding to ${secondary.name}',
    );

    final secondaryResult = await _resolveWith(
      videoId,
      secondary,
      visitorData: visitorData,
      wasOverridden: true,
    );

    if (secondaryResult != null) {
      _cache[videoId] = secondaryResult;
      return secondaryResult;
    }

    _log('❌ [$videoId] All sources exhausted');
    return null;
  }

  Future<InnerTubeAudioResult?> _resolveWith(
    String videoId,
    AudioSourcePreference source, {
    String? visitorData,
    required bool wasOverridden,
  }) async {
    switch (source) {
      case AudioSourcePreference.innerTube:
        return _resolveViaInnerTube(
          videoId,
          visitorData: visitorData,
          wasOverridden: wasOverridden,
        );
      case AudioSourcePreference.ytMusicApi:
        return _resolveViaYtMusicApi(videoId, wasOverridden: wasOverridden);
    }
  }

  // ── InnerTube resolution (Android client ladder) ───────────────────────────

  Future<InnerTubeAudioResult?> _resolveViaInnerTube(
    String videoId, {
    String? visitorData,
    required bool wasOverridden,
  }) async {
    for (final client in _kInnerTubeClients) {
      try {
        _log('📱 [$videoId] Trying ${client.name}...');
        final result = await _callPlayerEndpoint(
          videoId,
          client,
          visitorData: client.name == 'ANDROID_MUSIC' ? null : visitorData,
          resolvedVia: AudioSourcePreference.innerTube,
          wasOverridden: wasOverridden,
        );
        if (result != null) {
          _log(
            '✅ [$videoId] ${client.name} succeeded — '
            '${result.codec} ${result.bitrate ~/ 1000}kbps'
            '${wasOverridden ? " [auto-override]" : ""}',
          );
          return result;
        }
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('400')) {
          _log('⚠️ [$videoId] ${client.name} HTTP 400 — skipping');
        } else {
          _log('⚠️ [$videoId] ${client.name} error: $e');
        }
        continue;
      }
    }
    return null;
  }

  // ── YTMusicAPI resolution shim ─────────────────────────────────────────────
  //
  // Replace the body here with your real YTMusicAPI integration.
  // This stub falls through immediately so the override ladder still works.

  Future<InnerTubeAudioResult?> _resolveViaYtMusicApi(
    String videoId, {
    required bool wasOverridden,
  }) async {
    _log('🌐 [$videoId] Trying YTMusicAPI path...');

    try {
      // ── TODO: replace with your real YTMusicAPI call ──────────────────────
      // Example shape of what you'd do:
      //
      //   final resp = await yourYtMusicApiClient.getStreamingUrl(videoId);
      //   if (resp == null) return null;
      //   return InnerTubeAudioResult(
      //     videoId:     videoId,
      //     url:         resp.url,
      //     itag:        resp.itag,
      //     mimeType:    resp.mimeType,
      //     codec:       _extractCodec(resp.mimeType),
      //     bitrate:     resp.bitrate,
      //     contentLength: resp.contentLength,
      //     loudnessDb:  resp.loudnessDb,
      //     clientUsed:  'YTMusicAPI',
      //     userAgent:   resp.userAgent ?? '',
      //     expiresAt:   _parseExpiry(resp.url),
      //     resolvedVia: AudioSourcePreference.ytMusicApi,
      //     wasOverridden: wasOverridden,
      //   );
      // ─────────────────────────────────────────────────────────────────────

      _log('⚠️ [$videoId] YTMusicAPI shim not implemented — skipping');
      return null;
    } catch (e) {
      _log('⚠️ [$videoId] YTMusicAPI error: $e');
      return null;
    }
  }

  // ── Player endpoint ────────────────────────────────────────────────────────

  Future<InnerTubeAudioResult?> _callPlayerEndpoint(
    String videoId,
    _ITClient client, {
    String? visitorData,
    required AudioSourcePreference resolvedVia,
    required bool wasOverridden,
  }) async {
    final response = await _http
        .post(
          Uri.parse('$_kPlayerEndpoint?key=${client.apiKey}&prettyPrint=false'),
          headers: _buildHeaders(client),
          body: jsonEncode(
            _buildPlayerBody(videoId, client, visitorData: visitorData),
          ),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    final status = json['playabilityStatus']?['status'] as String? ?? '';
    if (status != 'OK') {
      _log('⚠️ [$videoId] ${client.name} playabilityStatus: $status');
      if (status == 'LOGIN_REQUIRED') {
        _log('🔄 [$videoId] Invalidating visitor_data due to LOGIN_REQUIRED');
        _visitorData = null;
      }
      return null;
    }

    final formats = ((json['streamingData']?['adaptiveFormats']) as List? ?? [])
        .cast<Map<String, dynamic>>();

    final audioFormats = formats.where((f) {
      final mime = f['mimeType'] as String? ?? '';
      if (!mime.startsWith('audio/')) return false;
      final url = f['url'] as String?;
      if (url == null || url.isEmpty) return false;
      final hasCipher =
          f.containsKey('signatureCipher') || f.containsKey('cipher');
      return !hasCipher;
    }).toList();

    if (audioFormats.isEmpty) {
      _log('⚠️ [$videoId] ${client.name} no direct-URL audio formats');
      return null;
    }

    const preferredItags = [251, 250, 140];
    Map<String, dynamic>? best;
    for (final itag in preferredItags) {
      best = audioFormats.cast<Map<String, dynamic>?>().firstWhere(
        (f) => f!['itag'] == itag,
        orElse: () => null,
      );
      if (best != null) break;
    }
    best ??= audioFormats.reduce((a, b) {
      return ((a['bitrate'] as int?) ?? 0) >= ((b['bitrate'] as int?) ?? 0)
          ? a
          : b;
    });

    final url = best['url'] as String;
    if (!_isUsableUrl(url)) {
      _log('⚠️ [$videoId] ${client.name} URL failed sanity check');
      return null;
    }

    final contentLength =
        int.tryParse(best['contentLength'] as String? ?? '') ??
        (best['contentLength'] as int?);
    if (contentLength != null && contentLength <= 0) {
      _log('⚠️ [$videoId] contentLength=0, skipping');
      return null;
    }

    final mimeType = best['mimeType'] as String? ?? '';

    return InnerTubeAudioResult(
      videoId: videoId,
      url: url,
      itag: best['itag'] as int? ?? 0,
      mimeType: mimeType,
      codec: _extractCodec(mimeType),
      bitrate: best['bitrate'] as int? ?? 0,
      contentLength: contentLength,
      loudnessDb: (best['loudnessDb'] as num?)?.toDouble(),
      clientUsed: client.name,
      userAgent: client.userAgent,
      expiresAt: _parseExpiry(url),
      resolvedVia: resolvedVia,
      wasOverridden: wasOverridden,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _isUsableUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.contains('googlevideo.com') &&
          uri.queryParameters.containsKey('expire');
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _buildPlayerBody(
    String videoId,
    _ITClient client, {
    String? visitorData,
  }) {
    return {
      'videoId': videoId,
      if (client.playerParams != null) 'params': client.playerParams,
      'context': {
        'client': {
          'clientName': client.clientName,
          'clientVersion': client.clientVersion,
          if (client.androidSdkVersion != null) ...{
            'androidSdkVersion': client.androidSdkVersion,
            'osName': 'Android',
            'osVersion': client.androidSdkVersion! >= 33 ? '13' : '11',
            'platform': 'MOBILE',
          },
          'hl': 'en',
          'gl': 'US',
          'utcOffsetMinutes': 0,
          if (visitorData != null) 'visitorData': visitorData,
        },
      },
      'playbackContext': {
        'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    };
  }

  Map<String, String> _buildHeaders(_ITClient client) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': client.userAgent,
    'X-YouTube-Client-Name': _clientCode(client.clientName),
    'X-YouTube-Client-Version': client.clientVersion,
  };

  String _clientCode(String name) =>
      const {
        'ANDROID_MUSIC': '21',
        'ANDROID': '3',
        'ANDROID_TESTSUITE': '30',
        'ANDROID_VR': '28',
        'IOS': '5',
        'WEB_REMIX': '67',
      }[name] ??
      '3';

  String _extractCodec(String mimeType) =>
      RegExp(r'codecs="([^"]+)"').firstMatch(mimeType)?.group(1) ?? 'unknown';

  DateTime _parseExpiry(String url) {
    try {
      final expire = Uri.parse(url).queryParameters['expire'];
      if (expire != null) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(expire) * 1000);
      }
    } catch (_) {}
    return DateTime.now().add(const Duration(hours: 6));
  }

  void _log(String msg) => print('[InnerTubeAudio] $msg');
}
