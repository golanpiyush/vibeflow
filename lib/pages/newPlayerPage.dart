// PATCHED FILE — new_player_page.dart
//
// PROBLEM: Stale `_onSongChanged` calls were overwriting `_lastKnownMediaItem`
// with old song data, then calling `setState()` which caused the UI to briefly
// (or permanently) show the previous song's title/artist/art.
//
// Root causes:
//   1. `_isSongChanging` guard scheduled `Future.delayed` retries that captured
//      the old MediaItem in their closures.
//   2. `_lastKnownMediaItem` was written inside `_onSongChanged` (after async
//      gaps), so stale calls could overwrite fresh data.
//   3. The StreamBuilder fell back to `_lastKnownMediaItem` when
//      `mediaSnapshot.data` was momentarily null during transitions.
//

// FIX:
//   • Add `AudioUISync` as the single source of truth for display metadata.
//   • `_lastKnownMediaItem` is now seeded from AudioUISync (never written
//     inside async callbacks).
//   • Stream listener only tracks ID changes for side-effect dispatch
//     (`_onSongChanged`). It never retries with stale closures.
//   • `_onSongChanged` no longer has the `_isSongChanging` retry loop.
//     Side effects (palette, like-check) are guarded with a simple
//     `_pendingSideEffectId` check instead.
//   • Build method reads from `AudioUISync.instance.currentMedia` first —
//     guaranteed to always have the latest song from the handler stream.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/main.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/managers/download_state_provider.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/audio_equalizer_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/pages/thoughtsScreen.dart';
import 'package:vibeflow/pages/user_taste_screen.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/audio_ui_sync.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';
import 'package:vibeflow/utils/album_color_generator.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/widgets/lyrics_widget.dart';
import 'package:vibeflow/widgets/playlist_bottomSheet.dart';
import 'package:vibeflow/widgets/radio_sheet.dart';
import 'package:vibeflow/widgets/shareSong.dart';

enum ViewMode { album, lyrics }

ViewMode _viewMode = ViewMode.album;

final currentLyricsProvider = StateProvider<List<Map<String, dynamic>>>(
  (ref) => [],
);
final currentLyricsLoadingProvider = StateProvider<bool>((ref) => false);
final sliderStyleProvider = StateProvider<SliderStyle>(
  (ref) => SliderStyle.straight,
);

enum SliderStyle { straight, squiggly }

class NewPlayerPage extends ConsumerStatefulWidget {
  final QuickPick song;
  final String? heroTag;

  const NewPlayerPage({Key? key, required this.song, this.heroTag})
    : super(key: key);

  @override
  ConsumerState<NewPlayerPage> createState() => _NewPlayerPageState();
  static bool _isNavigating = false;
  static bool _isOpen = false;

  // ───────── Open with Navigator ─────────
  static Future<void> openWithNavigator(
    NavigatorState navigator,
    QuickPick song, {
    String? heroTag,
  }) async {
    if (_isOpen) {
      print('⚠️ [NewPlayerPage] Already open, ignoring duplicate navigation');
      return;
    }
    _isOpen = true;
    isMiniplayerVisible.value = false;

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    bool useBetaPlayer = false;

    if (userId != null) {
      try {
        final profile = await supabase
            .from('profiles')
            .select('is_beta_tester')
            .eq('id', userId)
            .single();
        useBetaPlayer = profile?['is_beta_tester'] ?? false;
      } catch (e) {
        print('Error checking beta status: $e');
        useBetaPlayer = false;
      }
    }

    try {
      await navigator.push(
        PageTransitions.playerScale(
          page: useBetaPlayer
              ? NewPlayerPage(song: song, heroTag: heroTag)
              : PlayerScreen(song: song, heroTag: heroTag),
        ),
      );
    } finally {
      isMiniplayerVisible.value = true;
      _isOpen = false;
    }
  }

  static Future<void> open(
    BuildContext context,
    QuickPick song, {
    String? heroTag,
  }) async {
    if (_isOpen) {
      print('⚠️ [NewPlayerPage] Already open, ignoring duplicate navigation');
      return;
    }
    _isOpen = true;
    isMiniplayerVisible.value = false;

    final navigator = Navigator.of(context);
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    bool useBetaPlayer = false;

    if (userId != null) {
      try {
        final profile = await supabase
            .from('profiles')
            .select('is_beta_tester')
            .eq('id', userId)
            .single();
        useBetaPlayer = profile?['is_beta_tester'] ?? false;
      } catch (e) {
        print('Error checking beta status: $e');
        useBetaPlayer = false;
      }
    }

    try {
      await navigator.push(
        PageTransitions.playerScale(
          page: useBetaPlayer
              ? NewPlayerPage(song: song, heroTag: heroTag)
              : PlayerScreen(song: song, heroTag: heroTag),
        ),
      );
    } finally {
      isMiniplayerVisible.value = true;
      _isOpen = false;
    }
  }
}

class _NewPlayerPageState extends ConsumerState<NewPlayerPage>
    with TickerProviderStateMixin {
  final _audioService = AudioServices.instance;
  late AnimationController _scaleController;
  late AnimationController _rotationController;
  AlbumPalette? _albumPalette;
  String? _lastArtworkUrl;
  bool _isLiked = false;
  bool _isCheckingLiked = true;
  bool _isSavingLike = false;
  bool _isRefetchingUrl = false;
  double _lastRotationValue = 0.0;
  bool _isReturningToNormal = false;

  // ── AudioUISync state ────────────────────────────────────────────────────
  // Single source of truth: always reflects the latest song from the handler.
  // Never written inside async callbacks — no stale-closure risk.
  String? _currentVideoId;
  MediaItem? _currentDisplayMedia;

  // Guards palette+like side effects so stale async results are discarded.
  String? _pendingSideEffectId;
  bool _isSideEffectRunning = false;

  @override
  void initState() {
    super.initState();

    // ── Seed display state synchronously before first frame ─────────────
    _currentDisplayMedia =
        AudioUISync.instance.currentMedia ?? getAudioHandler()?.mediaItem.value;
    _currentVideoId = _currentDisplayMedia?.id;

    AudioUISync.instance.addListener(_onAudioSyncChanged);
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _rotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );

    _rotationController.addListener(() {
      if (!_isReturningToNormal && mounted) {
        _lastRotationValue = _rotationController.value;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scaleController.forward();
        _loadAlbumPalette(_currentDisplayMedia?.artUri?.toString() ?? '');
        _preloadArtwork();
      }
    });

    _playInitialSong();
    _checkIfLiked();
    _listenForPlaybackErrors();

    // ── Rotation listener (playback state only — no song-change logic) ───
    _audioService.playbackStateStream.listen((state) {
      if (mounted) _updateRotation(state.playing);
    });
  }

  @override
  void dispose() {
    AudioUISync.instance.removeListener(_onAudioSyncChanged);
    _scaleController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  void _onAudioSyncChanged() {
    final item = AudioUISync.instance.currentMedia;
    if (item == null || !mounted) return;

    _currentDisplayMedia = item;

    if (item.id != _currentVideoId) {
      _currentVideoId = item.id;
      _dispatchSideEffects(item);
    }

    setState(() {});
  }

  void _dispatchSideEffects(MediaItem mediaItem) {
    _pendingSideEffectId = mediaItem.id;

    final artworkUrl = mediaItem.artUri?.toString() ?? '';
    if (artworkUrl.isNotEmpty && artworkUrl != _lastArtworkUrl) {
      _lastArtworkUrl = artworkUrl; // ← this IS the artwork cache field here
      _loadAlbumPalette(artworkUrl);
    }

    setState(() => _isCheckingLiked = true);
    _checkIfSongIsSaved(mediaItem.id);
  }

  // ── Kept for direct calls (e.g. initial load, manual like toggle) ────────
  Future<void> _checkIfLiked() async {
    if (!mounted) return;

    try {
      final currentMedia = _audioService.currentMediaItem;
      if (currentMedia == null) {
        if (mounted)
          setState(() {
            _isLiked = false;
            _isCheckingLiked = false;
          });
        return;
      }
      await _refreshLikeStatus(currentMedia.id);
    } catch (e) {
      print('Error checking if song is liked: $e');
      if (mounted) setState(() => _isCheckingLiked = false);
    }
  }

  Future<void> _checkIfSongIsSaved(String videoId) async {
    _pendingSideEffectId = videoId; // always update FIRST
    if (_isSideEffectRunning) return;
    _isSideEffectRunning = true;

    try {
      final downloadService = DownloadService.instance;
      final savedSongs = await downloadService.getDownloadedSongs();

      if (!mounted ||
          (_pendingSideEffectId != null && videoId != _pendingSideEffectId))
        return;

      setState(() {
        _isLiked = savedSongs.any((s) => s.videoId == videoId);
        _isCheckingLiked = false;
      });
    } catch (e) {
      if (mounted && videoId == _pendingSideEffectId) {
        setState(() => _isCheckingLiked = false);
      }
    } finally {
      _isSideEffectRunning = false;
      // If a newer song arrived while we were running, process it now
      if (_pendingSideEffectId != null && _pendingSideEffectId != videoId) {
        final next = _pendingSideEffectId!;
        _pendingSideEffectId = null;
        _checkIfSongIsSaved(next);
      }
    }
  }

  // ── Like-check with stale-result guard ───────────────────────────────────
  Future<void> _refreshLikeStatus(String videoId) async {
    // If a side effect is already running, just update the pending id and bail.
    // The running task will check _pendingSideEffectId on completion.
    if (_isSideEffectRunning) {
      _pendingSideEffectId = videoId;
      return;
    }

    _isSideEffectRunning = true;

    try {
      final downloadService = DownloadService.instance;
      final savedSongs = await downloadService.getDownloadedSongs();

      // Discard if the user has moved to a different song while we were awaiting
      if (!mounted || videoId != _pendingSideEffectId) {
        print(
          '🚫 [_refreshLikeStatus] Discarding stale result for $videoId '
          '(current: $_pendingSideEffectId)',
        );
        return;
      }

      final isLiked = savedSongs.any((song) => song.videoId == videoId);

      setState(() {
        _isLiked = isLiked;
        _isCheckingLiked = false;
      });
    } catch (e) {
      print('Error checking if song is liked: $e');
      if (mounted && videoId == _pendingSideEffectId) {
        setState(() => _isCheckingLiked = false);
      }
    } finally {
      _isSideEffectRunning = false;
    }
  }

  // ✅ ADD: Helper to preload artwork from URL
  void _preloadArtworkFromUrl(String url) {
    if (url.isEmpty || !mounted) return;

    precacheImage(
      NetworkImage(url),
      context,
      onError: (exception, stackTrace) {
        print('⚠️ Artwork preload failed: $exception');
      },
    );
  }

  Future<bool> _ensureStoragePermission() async {
    Permission permission;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ - Use audio permission
        permission = Permission.audio;
      } else if (androidInfo.version.sdkInt >= 30) {
        // Android 11-12 - Use manageExternalStorage
        permission = Permission.manageExternalStorage;
      } else {
        // Android 10 and below
        permission = Permission.storage;
      }
    } else {
      return true; // iOS / others
    }

    // Check if already granted
    if (await permission.isGranted) return true;

    // For Android 11+, check if we need MANAGE_EXTERNAL_STORAGE
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30 && androidInfo.version.sdkInt < 33) {
        // Try manageExternalStorage first
        if (await Permission.manageExternalStorage.isGranted) {
          return true;
        }
      }
    }

    // Show permission dialog
    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // Get theme colors
        final cardBg = Theme.of(context).colorScheme.surface;
        final textColor = Theme.of(context).colorScheme.onSurface;

        return AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Storage permission required',
            style: GoogleFonts.inter(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'VibeFlow needs access to save songs '
            'so you can listen offline anytime.',
            style: GoogleFonts.inter(color: textColor.withOpacity(0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Not now',
                style: GoogleFonts.inter(color: textColor.withOpacity(0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Allow',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );

    if (shouldRequest != true) return false;

    // Request permission
    var result = await permission.request();

    // If initial request denied on Android 11+, try opening settings
    if (!result.isGranted && Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 30 && androidInfo.version.sdkInt < 33) {
        // For Android 11-12, try manageExternalStorage via settings
        final settingsOpened = await openAppSettings();

        if (settingsOpened) {
          // Wait a bit for user to grant permission
          await Future.delayed(const Duration(seconds: 1));
          result = await permission.status;
        }
      } else if (androidInfo.version.sdkInt >= 33) {
        // For Android 13+, audio permission should work
        result = await Permission.audio.status;
      }
    }

    return result.isGranted;
  }

  void _listenForPlaybackErrors() {
    final handler = getAudioHandler();
    if (handler == null) return;

    handler.customState.listen((customState) {
      if (!mounted) return;

      final hasError = customState['playback_error'] as bool? ?? false;
      final errorMessage = customState['error_message'] as String?;
      final isSourceError = customState['is_source_error'] as bool? ?? false;
      final isAutoRetrying = customState['auto_retrying'] as bool? ?? false;
      final recoverySuccess = customState['recovery_success'] as bool? ?? false;

      if (recoverySuccess) {
        _showRecoverySuccessSnackbar();
        return;
      }

      if (hasError && errorMessage != null) {
        print('🔴 [NewPlayerPage] Playback error detected: $errorMessage');

        if (isAutoRetrying) {
          _showAutoRetrySnackbar(errorMessage);
        } else if (isSourceError) {
          _showErrorSnackbarWithRetry(errorMessage);
        } else {
          _showErrorSnackbar(errorMessage);
        }

        // Clear error state after showing
        handler.clearPlaybackError();
      }
    });
  }

  // ADD this NEW method:
  void _showAutoRetrySnackbar(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Auto-recovering...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Trying alternative sources',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ADD this NEW method:
  void _showRecoverySuccessSnackbar() {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Playback recovered',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // UPDATE _showErrorSnackbar():
  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // UPDATE _showErrorSnackbarWithRetry():
  void _showErrorSnackbarWithRetry(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Playback Issue',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'RETRY',
          textColor: Colors.white,
          onPressed: _hardRefetchAndRetry,
        ),
      ),
    );
  }

  Future<void> _hardRefetchAndRetry() async {
    if (_isRefetchingUrl) {
      print('⏳ Already refetching URL, please wait...');
      return;
    }

    setState(() => _isRefetchingUrl = true);

    try {
      print('🔄 [Hard Refetch] Starting manual URL refresh...');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Refreshing audio source...'),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 30),
        ),
      );

      final handler = getAudioHandler();
      if (handler == null) throw Exception('Audio handler not available');

      final currentMedia = handler.mediaItem.value;
      if (currentMedia == null) throw Exception('No song currently playing');

      // Hard refetch the URL
      final success = await handler.hardRefetchCurrentUrl();

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                const Text('Playback resumed successfully'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        throw Exception('Failed to refresh URL');
      }
    } catch (e) {
      print('❌ [Hard Refetch] Failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to recover: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefetchingUrl = false);
      }
    }
  }

  Future<void> _playInitialSong() async {
    try {
      final handler = getAudioHandler();
      if (handler == null) return;

      final currentMedia = handler.mediaItem.value;
      final hasAudioSource = handler.audioSource != null;
      final isPlaying = handler.isPlaying;
      final isCrossfading = handler.isCrossfading; // ✅ check this too

      // ✅ Never interrupt an active crossfade
      if (isCrossfading) {
        print('🎵 [PlayerPage] Crossfade active — skipping playSong');
        return;
      }

      // ✅ Never interrupt anything actively playing
      if (currentMedia != null && hasAudioSource && isPlaying) {
        print('🎵 [PlayerPage] Audio already playing — skipping playSong');
        return;
      }

      // ✅ Same song loaded but paused — just resume
      if (currentMedia?.id == widget.song.videoId && hasAudioSource) {
        print('✅ [PlayerPage] Song already loaded: ${currentMedia?.title}');
        await _audioService.play();
        return;
      }

      // Nothing loaded at all — safe to play
      print('🎵 [PlayerPage] Playing new song: ${widget.song.title}');
      await _audioService.playSong(widget.song);
    } catch (e, stackTrace) {
      print('❌ [PlayerPage] Playback error: $e');
      await HapticFeedbackService().vibrateCriticalError();
    }
  }

  Future<void> _loadAlbumPalette(String artworkUrl) async {
    if (!mounted) return; // ✅ ADD: Safety check

    if (artworkUrl.isEmpty || artworkUrl == _lastArtworkUrl) return;

    _lastArtworkUrl = artworkUrl;

    try {
      AlbumColorGenerator.fromAnySource(artworkUrl)
          .then((palette) {
            if (mounted) {
              setState(() => _albumPalette = palette);
            }
          })
          .catchError((e) {
            print('⚠️ Palette extraction failed: $e');
          });
    } catch (e) {
      print('⚠️ Palette load error: $e');
    }
  }

  void _updateRotation(bool isPlaying) {
    if (!mounted) return; // ✅ ADD: Safety check

    if (isPlaying) {
      // Resume rotation from where we left off
      if (_isReturningToNormal) {
        // If we were returning to normal, continue from current position
        _isReturningToNormal = false;
        if (mounted && _rotationController.isAnimating) {
          // ✅ ADD: Check if already animating
          _rotationController.forward(from: _rotationController.value);
        }
      } else if (!_rotationController.isAnimating) {
        // Start fresh rotation
        if (mounted) {
          // ✅ ADD: Safety check
          _rotationController.repeat();
        }
      }
    } else {
      // Paused - rotate back to normal (0° or 360°)
      _rotateToNearestNormal();
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Get theme colors
    final themeData = Theme.of(context);
    final bgColor = themeData.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bgColor,
              bgColor.withOpacity(0.95),
              bgColor.withOpacity(0.9),
            ],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<MediaItem?>(
            stream: _audioService.mediaItemStream,
            builder: (context, mediaSnapshot) {
              // ✅ FIX: Fall back to _currentDisplayMedia (always current),
              // not _lastKnownMediaItem (which stale closures could corrupt).
              final currentMedia = mediaSnapshot.data ?? _currentDisplayMedia;

              return StreamBuilder<PlaybackState>(
                stream: _audioService.playbackStateStream,
                builder: (context, playbackSnapshot) {
                  final isPlaying = playbackSnapshot.data?.playing ?? false;
                  final playbackState = playbackSnapshot.data;

                  return StreamBuilder<Duration>(
                    stream: _audioService.positionStream,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(),
                            const SizedBox(height: 24),
                            _buildSongTitle(currentMedia),
                            const SizedBox(height: 32),
                            Expanded(
                              child: Center(
                                child: _buildCircularAlbumArt(
                                  currentMedia,
                                  isPlaying,
                                  position,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            _buildPlaybackControls(isPlaying, playbackState),
                            const SizedBox(height: 30),
                            _buildRadioLyricsToggle(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final iconColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.keyboard_arrow_down, color: iconColor, size: 24),
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.more_vert, color: iconColor, size: 24),
          padding: EdgeInsets.zero,
          onPressed: _showMoreOptions,
        ),
      ],
    );
  }

  void _showMoreOptions() {
    final handler = getAudioHandler();
    final isTimerActive = handler?.sleepTimerActive ?? false;
    // Get theme colors from provider
    final themeData = Theme.of(context);
    final cardBg = themeData.colorScheme.surface;
    final textPrimary = themeData.colorScheme.onSurface;
    final textSecondary = themeData.colorScheme.onSurface.withOpacity(0.6);
    final dividerColor = themeData.colorScheme.onSurface.withOpacity(0.1);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: textSecondary.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Sleep Timer Option
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: textSecondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isTimerActive ? Icons.bedtime : Icons.bedtime_outlined,
                    color: isTimerActive ? Colors.blue.shade300 : textPrimary,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Sleep Timer',
                  style: GoogleFonts.inter(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  isTimerActive
                      ? 'Active: ${handler?.getSleepTimerRemaining() ?? ''}'
                      : 'Pause music after a set time',
                  style: GoogleFonts.inter(
                    color: isTimerActive ? Colors.blue.shade300 : textSecondary,
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: textSecondary,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showSleepTimerDialog();
                },
              ),

              Divider(
                color: dividerColor,
                height: 1,
                indent: 20,
                endIndent: 20,
              ),

              // EQ Option
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: textSecondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.equalizer_rounded,
                    color: textPrimary,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Equalizer',
                  style: GoogleFonts.inter(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Adjust audio settings',
                  style: GoogleFonts.inter(color: textSecondary, fontSize: 13),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: textSecondary,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openEqualizer();
                },
              ),

              Divider(
                color: dividerColor,
                height: 1,
                indent: 20,
                endIndent: 20,
              ),

              // Audio Governor Option
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: textSecondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.tune_rounded, color: textPrimary, size: 22),
                ),
                title: Text(
                  'Audio Governor',
                  style: GoogleFonts.inter(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Advanced audio controls',
                  style: GoogleFonts.inter(color: textSecondary, fontSize: 13),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: textSecondary,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openAudioGovernor();
                },
              ),

              Divider(
                color: dividerColor,
                height: 1,
                indent: 20,
                endIndent: 20,
              ),

              // ✅ ADD THIS: User Taste Option
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: textSecondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.emoji_emotions_outlined,
                    color: textPrimary,
                    size: 22,
                  ),
                ),
                title: Text(
                  'User Taste',
                  style: GoogleFonts.inter(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Personalize your music preferences',
                  style: GoogleFonts.inter(color: textSecondary, fontSize: 13),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: textSecondary,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserTasteScreen(),
                    ),
                  );
                },
              ),

              Divider(
                color: dividerColor,
                height: 1,
                indent: 20,
                endIndent: 20,
              ),

              // Add to Playlist Option
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: textSecondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.playlist_add_rounded,
                    color: textPrimary,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Add to Playlist',
                  style: GoogleFonts.inter(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Save to your collection',
                  style: GoogleFonts.inter(color: textSecondary, fontSize: 13),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: textSecondary,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _addToPlaylist();
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _openAudioGovernor() {
    Navigator.push(
      context,
      PageTransitions.fade(page: const AudioThoughtsScreen()),
    );
  }

  void _openEqualizer() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AudioEqualizerPage()),
    );
  }

  void _addToPlaylist() {
    final currentMedia = _audioService.currentMediaItem;

    if (currentMedia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No song currently playing',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // ✅ FIXED: Convert MediaItem to DbSong with correct parameters
    final dbSong = DbSong(
      videoId: currentMedia.id,
      title: currentMedia.title,
      artists: [currentMedia.artist ?? 'Unknown Artist'], // List<String>
      thumbnail: currentMedia.artUri?.toString() ?? '',
      duration: currentMedia.duration?.inSeconds.toString() ?? '0',
    );

    // Show the playlist bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddToPlaylistSheet(song: dbSong),
    ).then((_) => PlaylistCoverCache.invalidateAll());
  }

  Widget _buildSongTitle(MediaItem? currentMedia) {
    final textPrimary = Theme.of(context).colorScheme.onSurface;
    final textSecondary = textPrimary.withOpacity(0.7);

    if (currentMedia == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loading...',
                  style: GoogleFonts.inter(
                    fontSize: 38,
                    fontWeight: FontWeight.w300,
                    color: textPrimary.withOpacity(0.5),
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final displayTitle = currentMedia.title;
    final displayArtist = currentMedia.artist ?? 'Unknown artist';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayTitle,
                style: GoogleFonts.inter(
                  fontSize: 38,
                  fontWeight: FontWeight.w300,
                  color: textPrimary,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                displayArtist,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        SongShareButton(song: widget.song),
        const SizedBox(width: 12),

        // Download/Like button with provider
        Consumer(
          builder: (context, ref, child) {
            final downloadState = ref.watch(downloadStateProvider);
            final isDownloading = downloadState.containsKey(currentMedia.id);
            final downloadProgress =
                downloadState[currentMedia.id]?.progress ?? 0.0;

            if (_isCheckingLiked || isDownloading) {
              return SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isDownloading)
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            value: downloadProgress,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              textPrimary,
                            ),
                            backgroundColor: textSecondary.withOpacity(0.2),
                          ),
                        )
                      else
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              textPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: IconButton(
                key: ValueKey(_isLiked),
                icon: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? Colors.red : textPrimary,
                  size: 26,
                ),
                onPressed: _isSavingLike ? null : _toggleLike,
                padding: EdgeInsets.zero,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCircularAlbumArt(
    MediaItem? currentMedia,
    bool isPlaying,
    Duration position,
  ) {
    final artworkUrl = currentMedia?.artUri?.toString() ?? '';
    final palette = _albumPalette;

    return AnimatedBuilder(
      animation: _scaleController,
      builder: (context, child) {
        final scaleValue = Tween<double>(begin: 0.88, end: 1.0)
            .animate(
              CurvedAnimation(
                parent: _scaleController,
                curve: Curves.easeOutCubic,
              ),
            )
            .value;

        return Transform.scale(scale: scaleValue, child: child);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        child: _viewMode == ViewMode.lyrics
            ? _buildLyricsView(currentMedia)
            : _buildAlbumView(artworkUrl, palette, isPlaying, position),
      ),
    );
  }

  Widget _buildAlbumView(
    String artworkUrl,
    AlbumPalette? palette,
    bool isPlaying,
    Duration position,
  ) {
    // Get theme colors
    final themeData = Theme.of(context);
    final surfaceVariant = themeData.colorScheme.surfaceVariant;
    final onSurface = themeData.colorScheme.onSurface;

    return GestureDetector(
      onTap: () {
        if (isPlaying) {
          _audioService.pause();
        } else {
          _audioService.play();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Static glow (keep existing palette-based glow)
          if (palette != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: palette.vibrant.withOpacity(isPlaying ? 0.4 : 0.25),
                    blurRadius: isPlaying ? 40 : 30,
                    spreadRadius: isPlaying ? 8 : 5,
                  ),
                ],
              ),
            ),

          // Album frame with smooth transitions
          _buildAlbumFrame(artworkUrl, isPlaying),

          // Time badge with theme colors
          Positioned(
            bottom: -12,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: surfaceVariant.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: onSurface.withOpacity(0.2), width: 1),
              ),
              child: Text(
                _formatDuration(position),
                style: GoogleFonts.inter(
                  color: onSurface.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // REPLACE _buildAlbumFrame method with this version (smooth image loading)
  // ============================================================================

  Widget _buildAlbumFrame(String artworkUrl, bool isPlaying) {
    return Container(
      width: 350,
      height: 350,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D3D3D), Color(0xFF1F1F1F)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ✅ Smooth image transition with AnimatedSwitcher
              if (artworkUrl.isNotEmpty)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: widget.heroTag != null
                      ? Hero(
                          key: ValueKey(artworkUrl), // Key for AnimatedSwitcher
                          tag: widget.heroTag!,
                          child: Image.network(
                            artworkUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            cacheWidth: 350,
                            cacheHeight: 350,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;

                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildPlaceholder(),
                                  Center(
                                    child: CircularProgressIndicator(
                                      value:
                                          loadingProgress.expectedTotalBytes !=
                                              null
                                          ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                          : null,
                                      strokeWidth: 2,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white54,
                                          ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        )
                      : Image.network(
                          key: ValueKey(artworkUrl), // Key for AnimatedSwitcher
                          artworkUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          cacheWidth: 350,
                          cacheHeight: 350,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildPlaceholder(),
                                Center(
                                  child: CircularProgressIndicator(
                                    value:
                                        loadingProgress.expectedTotalBytes !=
                                            null
                                        ? loadingProgress
                                                  .cumulativeBytesLoaded /
                                              loadingProgress
                                                  .expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Colors.white54,
                                        ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                )
              else
                _buildPlaceholder(),

              // Subtle overlay with smooth transition
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.15),
                    ],
                  ),
                ),
              ),

              // Pause overlay with smooth fade
              AnimatedOpacity(
                opacity: isPlaying ? 0.0 : 0.5,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Container(color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Updated placeholder with transparent background
  Widget _buildPlaceholder() {
    return Image.asset(
      'assets/imgs/funny_dawg.jpg',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        // Ultimate fallback if even the local asset fails
        return Container(
          color: Colors.transparent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.3),
              ),
              child: const Icon(
                Icons.broken_image_rounded,
                size: 70,
                color: Colors.white38,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaybackControls(bool isPlaying, PlaybackState? playbackState) {
    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onPrimary = themeData.colorScheme.onPrimary;
    final surfaceVariant = themeData.colorScheme.surfaceVariant;
    final onSurface = themeData.colorScheme.onSurface;
    final textSecondary = onSurface.withOpacity(0.6);

    // Check if line-by-line lyrics is enabled
    final isLineByLineEnabled = ref.watch(lineByLineLyricsEnabledProvider);
    // Show compact lyrics in controls area whenever line-by-line is enabled
    final showLyricsHere = isLineByLineEnabled;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous button
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surfaceVariant.withOpacity(0.5),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.skip_previous_rounded,
                  color: onSurface,
                  size: 26,
                ),
                onPressed: () => _audioService.skipToPrevious(),
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 24),

            // Play/Pause button
            GestureDetector(
              onTap: () => _audioService.playPause(),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  playbackState?.processingState == AudioProcessingState.loading
                      ? Icons.hourglass_empty_rounded
                      : isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: onPrimary,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Next button
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surfaceVariant.withOpacity(0.5),
              ),
              child: IconButton(
                icon: Icon(Icons.skip_next_rounded, color: onSurface, size: 26),
                onPressed: () => _audioService.skipToNext(),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Shuffle and Repeat buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<PlaybackState>(
              stream: _audioService.playbackStateStream,
              builder: (context, snapshot) {
                final handler = getAudioHandler();
                final isShuffleEnabled = handler?.isShuffleEnabled ?? false;

                return IconButton(
                  icon: Icon(
                    Icons.shuffle_rounded,
                    color: isShuffleEnabled ? primaryColor : textSecondary,
                    size: 22,
                  ),
                  onPressed: () async {
                    if (handler != null) {
                      await handler.toggleShuffleMode();
                      setState(() {});
                    }
                  },
                  padding: EdgeInsets.zero,
                );
              },
            ),
            const SizedBox(width: 60),
            StreamBuilder<LoopMode>(
              stream: _audioService.loopModeStream,
              builder: (context, snapshot) {
                final loopMode = snapshot.data ?? LoopMode.off;
                return IconButton(
                  icon: Icon(
                    loopMode == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    color: loopMode != LoopMode.off
                        ? primaryColor
                        : textSecondary,
                    size: 22,
                  ),
                  onPressed: () {
                    switch (loopMode) {
                      case LoopMode.off:
                        _audioService.setLoopMode(LoopMode.all);
                        break;
                      case LoopMode.all:
                        _audioService.setLoopMode(LoopMode.one);
                        break;
                      case LoopMode.one:
                        _audioService.setLoopMode(LoopMode.off);
                        break;
                    }
                  },
                  padding: EdgeInsets.zero,
                );
              },
            ),
          ],
        ),

        // ✨ FIXED: Line-by-line lyrics area with proper visibility
        if (showLyricsHere) ...[
          const SizedBox(height: 5),
          Container(
            height: 50, // Increased height for better visibility
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromARGB(0, 255, 255, 255),
              borderRadius: BorderRadius.circular(12),
            ),
            child: StreamBuilder<MediaItem?>(
              stream: _audioService.mediaItemStream,
              builder: (context, snapshot) {
                final currentMedia = snapshot.data;

                if (currentMedia == null) {
                  return Center(
                    child: Text(
                      'No song playing',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  );
                }

                return CompactLineByLineLyrics(
                  title: currentMedia.title,
                  artist: currentMedia.artist ?? 'Unknown Artist',
                  videoId: currentMedia.id,
                  duration: currentMedia.duration?.inSeconds ?? 0,
                  accentColor: _albumPalette?.vibrant ?? primaryColor,
                );
              },
            ),
          ),
          // const SizedBox(height: 16),
        ],

        // Progress slider
        _buildOptimizedSlider(),
      ],
    );
  }

  Widget _buildOptimizedSlider() {
    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;
    final textSecondary = onSurface.withOpacity(0.6);

    return StreamBuilder<Duration>(
      stream: _audioService.positionStream,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration?>(
          stream: _audioService.durationStream,
          builder: (context, durationSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final duration = durationSnapshot.data ?? Duration.zero;
            final validDuration = duration.inMilliseconds > 0
                ? duration
                : Duration.zero;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                children: [
                  // Time labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: GoogleFonts.inter(
                            color: textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          _formatDuration(validDuration),
                          style: GoogleFonts.inter(
                            color: textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Slider
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: primaryColor,
                      inactiveTrackColor: textSecondary.withOpacity(0.2),
                      thumbColor: primaryColor,
                      overlayColor: primaryColor.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: validDuration.inMilliseconds > 0
                          ? position.inMilliseconds.toDouble().clamp(
                              0.0,
                              validDuration.inMilliseconds.toDouble(),
                            )
                          : 0.0,
                      min: 0.0,
                      max: validDuration.inMilliseconds.toDouble(),
                      onChanged: (value) {
                        _audioService.seek(
                          Duration(milliseconds: value.toInt()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color primaryColor,
    required Color onSurface,
    required Color surfaceVariant,
  }) {
    final selectedBg = primaryColor.withOpacity(0.15);
    final unselectedBg = surfaceVariant.withOpacity(0.3);
    final selectedBorder = primaryColor.withOpacity(0.3);
    final unselectedBorder = onSurface.withOpacity(0.08);
    final selectedColor = primaryColor;
    final unselectedColor = onSurface.withOpacity(0.5);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? selectedBorder : unselectedBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? selectedColor : unselectedColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected ? selectedColor : unselectedColor,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UPDATED PARTS ONLY

  Widget _buildRadioLyricsToggle() {
    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;
    final surfaceVariant = themeData.colorScheme.surfaceVariant;
    final dividerColor = onSurface.withOpacity(0.1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: dividerColor),
        const SizedBox(height: 18),
        Row(
          children: [
            // Radio button
            Expanded(
              child: _buildToggleButton(
                icon: Icons.radio_rounded,
                label: 'Radio',
                isSelected: _viewMode == ViewMode.album,
                onTap: () {
                  setState(() => _viewMode = ViewMode.album);

                  // Ensure handler has radio loaded
                  final handler = getAudioHandler();
                  if (handler != null) {
                    final customState =
                        handler.customState.value as Map<String, dynamic>? ??
                        {};
                    final radioQueue =
                        customState['radio_queue'] as List<dynamic>? ?? [];

                    if (radioQueue.isEmpty) {
                      final currentMedia = handler.mediaItem.value;
                      if (currentMedia != null) {
                        final currentSong = QuickPick(
                          videoId: currentMedia.id,
                          title: currentMedia.title,
                          artists: currentMedia.artist ?? 'Unknown Artist',
                          thumbnail: currentMedia.artUri?.toString() ?? '',
                          duration: currentMedia.duration?.inSeconds.toString(),
                        );

                        handler.loadRadioImmediately(currentSong);
                      }
                    }
                  }

                  // Open sheet
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => EnhancedRadioSheet(
                      currentVideoId: widget.song.videoId,
                      currentTitle: _currentDisplayMedia?.title ?? 'Loading...',
                      currentArtist: _currentDisplayMedia?.artist ?? '',
                      audioService: _audioService,
                    ),
                  );
                },
                primaryColor: primaryColor,
                onSurface: onSurface,
                surfaceVariant: surfaceVariant,
              ),
            ),
            const SizedBox(width: 12),

            // Lyrics button
            Expanded(
              child: _buildToggleButton(
                icon: Icons.lyrics_rounded,
                label: 'Lyrics',
                isSelected: _viewMode == ViewMode.lyrics,
                onTap: () {
                  setState(() {
                    if (_viewMode == ViewMode.lyrics) {
                      _viewMode = ViewMode.album;
                    } else {
                      _viewMode = ViewMode.lyrics;
                    }
                  });
                },
                primaryColor: primaryColor,
                onSurface: onSurface,
                surfaceVariant: surfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ✅ UPDATE: Toggle like for current song, not widget.song
  Future<void> _toggleLike() async {
    if (_isSavingLike) return;

    final currentMedia = _audioService.currentMediaItem;
    if (currentMedia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No song currently playing')),
      );
      return;
    }

    setState(() => _isSavingLike = true);

    try {
      final downloadService = DownloadService.instance;

      if (_isLiked) {
        // Remove from downloads
        final success = await downloadService.deleteDownload(currentMedia.id);

        if (success && mounted) {
          setState(() => _isLiked = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('Removed from saved songs'),
                ],
              ),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Add to downloads with progress tracking
        final hasPermission = await _ensureStoragePermission();
        if (!hasPermission) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission denied')),
          );
          return;
        }

        // ✅ Start tracking download in provider
        ref.read(downloadStateProvider.notifier).startDownload(currentMedia.id);

        final core = VibeFlowCore();

        final currentSong = QuickPick(
          videoId: currentMedia.id,
          title: currentMedia.title,
          artists: currentMedia.artist ?? 'Unknown Artist',
          thumbnail: currentMedia.artUri?.toString() ?? '',
          duration: currentMedia.duration?.inSeconds.toString(),
        );

        final audioUrl = await core.getAudioUrl(
          currentSong.videoId,
          song: currentSong,
        );

        if (audioUrl == null || audioUrl.isEmpty) {
          ref
              .read(downloadStateProvider.notifier)
              .failDownload(currentMedia.id);
          throw Exception('Failed to get audio URL');
        }

        // ✅ Download with progress callback
        final result = await downloadService.downloadSong(
          videoId: currentSong.videoId,
          audioUrl: audioUrl,
          title: currentSong.title,
          artist: currentSong.artists,
          thumbnailUrl: currentSong.thumbnail,
          onProgress: (progress) {
            // Update progress in provider
            ref
                .read(downloadStateProvider.notifier)
                .updateProgress(currentMedia.id, progress);
          },
        );

        // ✅ Complete download tracking
        ref
            .read(downloadStateProvider.notifier)
            .completeDownload(currentMedia.id);

        if (result.success && mounted) {
          setState(() => _isLiked = true);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('Added to saved songs'),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          throw Exception(result.message);
        }
      }
    } catch (e) {
      // ✅ Clean up download state on error
      final currentMedia = _audioService.currentMediaItem;
      if (currentMedia != null) {
        ref.read(downloadStateProvider.notifier).failDownload(currentMedia.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingLike = false);
    }
  }

  Widget _buildLyricsView(MediaItem? currentMedia) {
    if (currentMedia == null) {
      return const Center(
        child: Text('No song playing', style: TextStyle(color: Colors.white70)),
      );
    }

    return Container(
      width: 420,
      height: 420,
      decoration: const BoxDecoration(color: Colors.transparent),
      child: CenteredLyricsWidget(
        title: currentMedia.title,
        artist: currentMedia.artist ?? 'Unknown Artist',
        videoId: currentMedia.id,
        duration: currentMedia.duration?.inSeconds ?? 0,
        accentColor: _albumPalette?.vibrant ?? Colors.white,
        // ✅ NEW: Show shimmers while loading
        loadingBuilder: (context) => _buildLyricsLoadingShimmer(),
        // ✅ NEW: Enable auto-translation for CJK languages
        autoTranslate: true,
      ),
    );
  }

  Widget _buildLyricsLoadingShimmer() {
    // Get theme colors
    final themeData = Theme.of(context);
    final shimmerBase = themeData.colorScheme.onSurface.withOpacity(0.05);
    final shimmerHighlight = themeData.colorScheme.onSurface.withOpacity(0.15);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShimmerLine(
                width:
                    MediaQuery.of(context).size.width *
                    (0.6 + (index % 3) * 0.15),
                height: 20,
                delay: Duration(milliseconds: index * 100),
                baseColor: shimmerBase,
                highlightColor: shimmerHighlight,
              ),
              const SizedBox(height: 8),
              _ShimmerLine(
                width:
                    MediaQuery.of(context).size.width *
                    (0.5 + (index % 2) * 0.2),
                height: 16,
                delay: Duration(milliseconds: index * 100 + 50),
                baseColor: shimmerBase,
                highlightColor: shimmerHighlight,
              ),
            ],
          ),
        );
      },
    );
  }

  void _preloadArtwork() {
    final wad = _currentDisplayMedia?.artUri?.toString() ?? '';
    if (wad.isEmpty || !mounted) return;

    precacheImage(
      NetworkImage(wad),
      context,
      onError: (exception, stackTrace) {
        // Silent fail - don't show errors for preloading
        print('⚠️ Artwork preload failed: $exception');
      },
    );
  }

  /// Rotates the album art back to normal position (0° or 360°)
  void _rotateToNearestNormal() {
    if (_isReturningToNormal || !mounted) return; // ✅ ADD: Check mounted

    _isReturningToNormal = true;

    // Stop the repeating animation
    if (_rotationController.isAnimating) {
      // ✅ ADD: Check before stopping
      _rotationController.stop();
    }

    // Get current rotation value (0.0 to 1.0 where 1.0 = 360°)
    final currentValue = _rotationController.value;

    // Determine shortest path to normal (0.0 or 1.0)
    final targetValue = currentValue < 0.5 ? 0.0 : 1.0;
    final distance = (targetValue - currentValue).abs();

    // Calculate duration based on distance
    final duration = Duration(
      milliseconds: (distance * 800).clamp(200, 800).toInt(),
    );

    // Create a new animation controller for the return animation
    final returnController = AnimationController(
      duration: duration,
      vsync: this,
    );

    // Animate from current position to target
    final animation = Tween<double>(begin: currentValue, end: targetValue)
        .animate(
          CurvedAnimation(parent: returnController, curve: Curves.easeOutCubic),
        );

    animation.addListener(() {
      if (mounted) {
        // ✅ ADD: Safety check
        _rotationController.value = animation.value;
      }
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Reset to 0.0 if we went to 1.0
        if (targetValue == 1.0 && mounted) {
          // ✅ ADD: Check mounted
          _rotationController.value = 0.0;
        }
        _lastRotationValue = 0.0;
        _isReturningToNormal = false;
        returnController.dispose();
      }
    });

    if (mounted) {
      // ✅ ADD: Safety check before starting animation
      returnController.forward();
    }
  }

  void _showSleepTimerDialog() {
    final durations = [
      {'label': '15 minutes', 'duration': const Duration(minutes: 15)},
      {'label': '30 minutes', 'duration': const Duration(minutes: 30)},
      {'label': '45 minutes', 'duration': const Duration(minutes: 45)},
      {'label': '1 hour', 'duration': const Duration(hours: 1)},
      {'label': '2 hours', 'duration': const Duration(hours: 2)},
      {'label': '3 hours', 'duration': const Duration(hours: 3)},
      {'label': '5 hours', 'duration': const Duration(hours: 5)},
    ];

    final themeData = Theme.of(context);
    final cardBg = themeData.colorScheme.surface;
    final textPrimary = themeData.colorScheme.onSurface;
    final textSecondary = textPrimary.withOpacity(0.7);

    final handler = getAudioHandler();
    final isTimerActive = handler?.sleepTimerActive ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: textSecondary.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.bedtime_rounded,
                      color: Colors.blue.shade300,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sleep Timer',
                      style: GoogleFonts.inter(
                        color: textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Active timer banner
              if (isTimerActive)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          color: Colors.blue.shade300,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Music will pause in ${handler?.getSleepTimerRemaining() ?? ''}',
                            style: GoogleFonts.inter(
                              color: Colors.blue.shade300,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // Duration list
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: isTimerActive ? 0 : 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: durations.map((item) {
                      final duration = item['duration'] as Duration;
                      final label = item['label'] as String;
                      final isActive =
                          (handler?.currentSleepTimerDuration == duration) &&
                          isTimerActive;

                      return Column(
                        children: [
                          ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.blue.withOpacity(0.2)
                                    : textSecondary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.access_time_rounded,
                                color: isActive
                                    ? Colors.blue.shade300
                                    : textSecondary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              label,
                              style: GoogleFonts.inter(
                                color: isActive
                                    ? Colors.blue.shade300
                                    : textPrimary,
                                fontSize: 16,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            trailing: isActive
                                ? Icon(
                                    Icons.check_circle,
                                    color: Colors.blue.shade300,
                                    size: 20,
                                  )
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              _startSleepTimer(duration, label);
                            },
                          ),
                          if (item != durations.last)
                            Divider(
                              color: textSecondary.withOpacity(0.1),
                              height: 1,
                              indent: 20,
                              endIndent: 20,
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Cancel button
              if (isTimerActive)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _cancelSleepTimer();
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 20),
                      label: Text(
                        'Cancel Timer',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _startSleepTimer(Duration duration, String label) {
    getAudioHandler()?.startSleepTimer(duration);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.bedtime, color: Colors.blue.shade300, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sleep timer set for $label',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade900,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'CANCEL',
          textColor: Colors.white,
          onPressed: _cancelSleepTimer,
        ),
      ),
    );
  }

  void _cancelSleepTimer() {
    getAudioHandler()?.cancelSleepTimer();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.cancel_outlined, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sleep timer cancelled',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.grey.shade800,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class GlowingAlbumRing extends StatefulWidget {
  final String artworkPath; // network OR file
  final double size;

  const GlowingAlbumRing({
    super.key,
    required this.artworkPath,
    this.size = 290,
  });

  @override
  State<GlowingAlbumRing> createState() => _GlowingAlbumRingState();
}

class _GlowingAlbumRingState extends State<GlowingAlbumRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  AlbumPalette? palette;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _loadPalette();
  }

  Future<void> _loadPalette() async {
    final extracted = await AlbumColorGenerator.fromAnySource(
      widget.artworkPath,
    );

    if (mounted) {
      setState(() => palette = extracted);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (palette == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.1415926,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.size / 2),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette!.vibrant, palette!.dominant, palette!.muted],
              ),
              boxShadow: [
                // MAIN GLOW
                BoxShadow(
                  color: palette!.vibrant.withOpacity(0.45),
                  blurRadius: 70,
                  spreadRadius: 12,
                ),
                // INNER DEPTH
                BoxShadow(
                  color: palette!.dominant.withOpacity(0.35),
                  blurRadius: 35,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerLine extends StatefulWidget {
  final double width;
  final double height;
  final Duration delay;
  final Color baseColor;
  final Color highlightColor;

  const _ShimmerLine({
    required this.width,
    required this.height,
    this.delay = Duration.zero,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<_ShimmerLine> createState() => _ShimmerLineState();
}

class _ShimmerLineState extends State<_ShimmerLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Start animation after delay
    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                max(0.0, _animation.value - 0.3),
                max(0.0, _animation.value),
                min(1.0, _animation.value + 0.3),
              ],
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
            ),
          ),
        );
      },
    );
  }
}
