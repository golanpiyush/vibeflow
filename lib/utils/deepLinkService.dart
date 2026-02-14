import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/main.dart' show rootNavigatorKey;

// Provider for deep link service
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService(ref);
});

class DeepLinkService {
  final Ref _ref;
  final AppLinks _appLinks = AppLinks();

  DeepLinkService(this._ref);

  /// Initialize deep link listener — call once from VibeFlowApp.initState
  void initDeepLinks(BuildContext context) {
    // Handle links when app is already running
    _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('🔗 [DeepLink] Stream received: $uri');
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('❌ [DeepLink] Stream error: $err');
      },
    );

    // Handle cold-start link (app was NOT running)
    _handleInitialLink();
  }

  /// Handle initial deep link when app is launched from a link
  Future<void> _handleInitialLink() async {
    try {
      // Small delay so the navigator is ready
      await Future.delayed(const Duration(milliseconds: 500));

      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        debugPrint('🔗 [DeepLink] Initial link: $uri');
        _handleDeepLink(uri);
      }
    } catch (e) {
      debugPrint('❌ [DeepLink] Failed to get initial link: $e');
    }
  }

  /// Parse and route the deep link
  void _handleDeepLink(Uri uri) {
    debugPrint('🔗 [DeepLink] Full URI: $uri');
    debugPrint('   Scheme: ${uri.scheme}');
    debugPrint('   Host: ${uri.host}');
    debugPrint('   Path: ${uri.path}');
    debugPrint('   Query: ${uri.queryParameters}');

    String? songId;

    // Handle vibeflow://song/VIDEO_ID
    if (uri.scheme == 'vibeflow' && uri.host == 'song') {
      songId = uri.path.replaceFirst('/', '');
    }
    // Handle https://vibeflow.app/song/VIDEO_ID
    else if (uri.scheme == 'https' && uri.host == 'golanpiyush.github.io') {
      if (uri.pathSegments.length >= 3 && uri.pathSegments[1] == 'song') {
        songId = uri.pathSegments[2];
      }
    }

    if (songId == null || songId.isEmpty) {
      debugPrint('⚠️ [DeepLink] Could not extract song ID');
      return;
    }

    final title = uri.queryParameters['title'];
    final artist = uri.queryParameters['artist'];
    final thumb = uri.queryParameters['thumb'];
    final duration = uri.queryParameters['duration'];

    debugPrint('🎵 [DeepLink] Parsed:');
    debugPrint('   songId: $songId');
    debugPrint('   title: $title');
    debugPrint('   artist: $artist');

    // If we have song data in params, navigate directly
    if (title != null && artist != null) {
      final song = QuickPick(
        videoId: songId,
        title: title,
        artists: artist,
        thumbnail: thumb ?? '',
        duration: duration,
      );
      _navigateToSong(song);
    } else {
      // No params — old style link, show error
      debugPrint('⚠️ [DeepLink] No song data in URL params');
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Text(
              'This is an old share link, ask them to reshare',
            ),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    }
  }

  /// Navigate directly to player — no Supabase, no loading dialog needed
  Future<void> _navigateToSong(QuickPick song) async {
    final navigatorContext = rootNavigatorKey.currentContext;

    if (navigatorContext == null) {
      debugPrint('❌ [DeepLink] Navigator not ready, retrying in 500ms...');
      await Future.delayed(const Duration(milliseconds: 500));
      return _navigateToSong(song);
    }

    try {
      debugPrint('🎵 [DeepLink] Navigating to: ${song.title}');

      if (navigatorContext.mounted) {
        await NewPlayerPage.open(
          navigatorContext,
          song,
          heroTag: 'deeplink_${song.videoId}',
        );
      }
    } catch (e) {
      debugPrint('❌ [DeepLink] Navigation failed: $e');

      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Could not open song: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Generate a shareable deep link with all song data embedded in the URL
  String generateSongLink(String videoId, QuickPick song) {
    final params = {
      'title': Uri.encodeComponent(song.title),
      'artist': Uri.encodeComponent(song.artists),
      'thumb': Uri.encodeComponent(song.thumbnail),
      if (song.duration != null)
        'duration': Uri.encodeComponent(song.duration!),
    };

    final queryString = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    return 'https://golanpiyush.github.io/vibeflow/song/$videoId?$queryString';
  }
}
