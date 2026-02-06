import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/thoughtsScreen.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/utils/album_color_generator.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/widgets/lyrics_widget.dart';
import 'package:vibeflow/widgets/radio_sheet.dart';

enum ViewMode { album, lyrics }

ViewMode _viewMode = ViewMode.album;

class NewPlayerPage extends ConsumerStatefulWidget {
  final QuickPick song;
  final String? heroTag;

  const NewPlayerPage({Key? key, required this.song, this.heroTag})
    : super(key: key);

  @override
  ConsumerState<NewPlayerPage> createState() => _NewPlayerPageState();

  /// Static method to navigate with beta check and slide-up animation
  static Future<void> open(
    BuildContext context,
    QuickPick song, {
    String? heroTag,
  }) async {
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
      }
    }

    if (context.mounted) {
      // Use PageTransitions.instant for zero-lag navigation
      await Navigator.push(
        context,
        PageTransitions.playerScale(
          page: useBetaPlayer
              ? NewPlayerPage(song: song, heroTag: heroTag)
              : PlayerScreen(song: song, heroTag: heroTag),
        ),
      );
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
  String? _currentVideoId;
  String? _lastProcessedVideoId;
  String? _lastProcessedTitle;

  @override
  void initState() {
    super.initState();

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
        _loadAlbumPalette(widget.song.thumbnail);
        _preloadArtwork();
      }
    });

    _playInitialSong();
    _checkIfLiked();
    _listenForPlaybackErrors();

    _audioService.playbackStateStream.listen((state) {
      if (mounted) {
        _updateRotation(state.playing);
      }
    });

    // ✅ CRITICAL FIX: Debounce mediaItemStream to prevent duplicate triggers
    Timer? _debounceTimer;
    String? _lastProcessedVideoId;
    String? _lastProcessedTitle;

    _audioService.mediaItemStream.listen((mediaItem) {
      if (!mounted) return;

      if (mediaItem != null) {
        final newVideoId = mediaItem.id;
        final newTitle = mediaItem.title;

        // ✅ FIX: Cancel pending debounce if same song
        if (_debounceTimer?.isActive ?? false) {
          if (newVideoId == _lastProcessedVideoId &&
              newTitle == _lastProcessedTitle) {
            print('⏭️ [MediaStream] Ignoring duplicate emission');
            return;
          }
          _debounceTimer?.cancel();
        }

        print('🎵 [MediaStream] Received update:');
        print('   VideoId: $newVideoId (current: $_currentVideoId)');
        print('   Title: $newTitle');
        print('   Last processed: $_lastProcessedVideoId');

        // ✅ FIX: Check if this is truly a new song
        final isDifferentSong =
            newVideoId != _currentVideoId ||
            newVideoId != _lastProcessedVideoId;

        if (isDifferentSong || _currentVideoId == null) {
          print('🔄 [MediaStream] New song detected, updating UI');

          // ✅ FIX: Debounce to prevent multiple rapid calls
          _debounceTimer = Timer(const Duration(milliseconds: 150), () {
            if (!mounted) return;

            _currentVideoId = newVideoId;
            _lastProcessedVideoId = newVideoId;
            _lastProcessedTitle = newTitle;

            _onSongChanged(mediaItem);
          });
        } else {
          print(
            '✓ [MediaStream] Same song as current/last processed, no update',
          );
        }
      }
    });
  }

  // ✅ ADD: Cleanup debounce timer
  Timer? _mediaItemDebounceTimer;

  // ✅ ADD: Handle song changes
  Future<void> _onSongChanged(MediaItem mediaItem) async {
    if (!mounted) return;

    print('🔄 [_onSongChanged] Updating UI for: ${mediaItem.title}');
    print('   VideoId: ${mediaItem.id}');
    print('   Artist: ${mediaItem.artist}');
    print('   Artwork: ${mediaItem.artUri}');

    // ✅ FIX 1: Update like status FIRST (critical for saved songs)
    setState(() {
      _isCheckingLiked = true;
    });

    await _checkIfLiked();

    // ✅ FIX 2: Update album art and palette
    final artworkUrl = mediaItem.artUri?.toString() ?? '';
    if (artworkUrl.isNotEmpty) {
      print(
        '🎨 [_onSongChanged] Loading new artwork: ${artworkUrl.substring(0, 50)}...',
      );
      _lastArtworkUrl = null; // Force reload even if URL is similar
      await _loadAlbumPalette(artworkUrl);
      _preloadArtworkFromUrl(artworkUrl);
    }

    // ✅ FIX 3: Force UI rebuild with delay to ensure state propagation
    if (mounted) {
      setState(() {
        // Force rebuild
      });

      // Additional rebuild after short delay to catch any async updates
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() {
          // Second rebuild to ensure everything is in sync
        });
      }
    }
    _logCurrentState();
    print('✅ [_onSongChanged] UI update complete');
  }

  Future<void> _forceRefreshMetadata() async {
    if (!mounted) return;

    final currentMedia = _audioService.currentMediaItem;
    if (currentMedia != null) {
      print('🔄 [ForceRefresh] Manually refreshing metadata');
      await _onSongChanged(currentMedia);
    }
  }

  Future<void> _checkIfLiked() async {
    if (!mounted) return; // ✅ ADD: Safety check

    try {
      final currentMedia = _audioService.currentMediaItem;
      if (currentMedia == null) {
        if (mounted) {
          setState(() {
            _isLiked = false;
            _isCheckingLiked = false;
          });
        }
        return;
      }

      final downloadService = DownloadService.instance;
      final savedSongs = await downloadService.getDownloadedSongs();

      final isLiked = savedSongs.any((song) => song.videoId == currentMedia.id);

      if (mounted) {
        setState(() {
          _isLiked = isLiked;
          _isCheckingLiked = false;
        });
      }
    } catch (e) {
      print('Error checking if song is liked: $e');
      if (mounted) {
        setState(() => _isCheckingLiked = false);
      }
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
        // Android 13+
        permission = Permission.audio; // READ_MEDIA_AUDIO
      } else {
        // Android 12 and below
        permission = Permission.storage;
      }
    } else {
      return true; // iOS / others
    }

    if (await permission.isGranted) return true;

    // Explain first
    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text(
          'Storage permission required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'VibeFlow needs access to save songs '
          'so you can listen offline anytime.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Not now',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (shouldRequest != true) return false;

    final result = await permission.request();
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
      print('🎵 [NewPlayerPage] Checking if song needs to be played');

      final currentMedia = await _audioService.mediaItemStream.first;

      // Only play if it's a different song
      if (currentMedia == null || currentMedia.id != widget.song.videoId) {
        print('🎵 [NewPlayerPage] Playing new song: ${widget.song.title}');
        await _audioService.playSong(widget.song);
      } else {
        print('✅ [NewPlayerPage] Song already playing: ${widget.song.title}');
      }
    } catch (e) {
      print('❌ [NewPlayerPage] Playback error: $e');
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A0A), Colors.black, Colors.black],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<MediaItem?>(
            stream: _audioService.mediaItemStream,
            builder: (context, mediaSnapshot) {
              final currentMedia = mediaSnapshot.data;

              return StreamBuilder<PlaybackState>(
                stream: _audioService.playbackStateStream,
                builder: (context, playbackSnapshot) {
                  final isPlaying = playbackSnapshot.data?.playing ?? false;
                  final playbackState = playbackSnapshot.data;

                  // OPTIMIZED: Single position/duration listener
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

  void _logCurrentState() {
    print('📊 [Player State]');
    print('   Current VideoId: $_currentVideoId');
    print('   Widget song: ${widget.song.title}');
    print('   Is liked: $_isLiked');
    print('   Last artwork URL: $_lastArtworkUrl');
    print('   Has palette: ${_albumPalette != null}');
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 30,
          ),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white70, size: 24),
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pushMaterialVertical(
              const AudioThoughtsScreen(),
              slideUp: true, // recommended for hierarchical navigation
            );
          },
        ),
      ],
    );
  }

  Widget _buildSongTitle(MediaItem? currentMedia) {
    // ✅ CRITICAL: Show nothing if no current media
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
                    color: Colors.white.withOpacity(0.5),
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

    // ✅ ALWAYS use currentMedia
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
                  color: Colors.white,
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
                  color: Colors.white.withOpacity(0.7),
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _isCheckingLiked
            ? const SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              )
            : IconButton(
                icon: _isSavingLike
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.red : Colors.white,
                        size: 26,
                      ),
                onPressed: _isSavingLike ? null : _toggleLike,
                padding: EdgeInsets.zero,
              ),
      ],
    );
  }

  Widget _buildCircularAlbumArt(
    MediaItem? currentMedia,
    bool isPlaying,
    Duration position,
  ) {
    // ✅ CRITICAL FIX: ALWAYS use currentMedia for artwork
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
      child: _viewMode == ViewMode.lyrics
          ? _buildLyricsView(currentMedia)
          : _buildAlbumView(artworkUrl, palette, isPlaying, position),
    );
  }

  Widget _buildAlbumView(
    String artworkUrl,
    AlbumPalette? palette,
    bool isPlaying,
    Duration position,
  ) {
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
          // ✅ FIXED: Static glow (doesn't rotate)
          if (palette != null)
            Container(
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

          // ✅ FIXED: No rotation - static album frame
          _buildAlbumFrame(artworkUrl, isPlaying),

          // TIME BADGE (doesn't rotate)
          Positioned(
            bottom: -12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Text(
                _formatDuration(position),
                style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.9),
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
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (artworkUrl.isNotEmpty)
              widget.heroTag != null
                  ? Hero(
                      tag: widget.heroTag!,
                      child: Image.network(
                        artworkUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 350,
                        cacheHeight: 350,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      ),
                    )
                  : Image.network(
                      artworkUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 350,
                      cacheHeight: 350,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
            else
              _buildPlaceholder(),

            // Subtle overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.15)],
                ),
              ),
            ),

            // Pause overlay
            AnimatedOpacity(
              opacity: isPlaying ? 0.0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: Container(color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  // Updated placeholder with transparent background
  Widget _buildPlaceholder() {
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
            Icons.music_note_rounded,
            size: 70,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackControls(bool isPlaying, PlaybackState? playbackState) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: () => _audioService.skipToPrevious(),
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 24),
            GestureDetector(
              onTap: () => _audioService.playPause(),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.15),
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
                  color: Colors.black,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: () => _audioService.skipToNext(),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Shuffle and Repeat
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
                    color: isShuffleEnabled ? Colors.white : Colors.white60,
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
                        ? Colors.white
                        : Colors.white60,
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
        const SizedBox(height: 28),

        // OPTIMIZED: Progress slider with single stream
        _buildOptimizedSlider(),
      ],
    );
  }

  Widget _buildOptimizedSlider() {
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          _formatDuration(validDuration),
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white.withOpacity(0.2),
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withOpacity(0.2),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.15)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withOpacity(0.5),
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

  // 1. Update the _buildRadioLyricsToggle method:
  Widget _buildRadioLyricsToggle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: Colors.white.withOpacity(0.1)),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _buildToggleButton(
                icon: Icons.radio_rounded,
                label: 'Radio',
                isSelected: _viewMode == ViewMode.album,
                onTap: () {
                  // Always switch to album view first
                  setState(() => _viewMode = ViewMode.album);

                  // Show the enhanced radio sheet
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => EnhancedRadioSheet(
                      currentVideoId: widget.song.videoId,
                      currentTitle: widget.song.title,
                      currentArtist: widget.song.artists,
                      audioService: _audioService,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
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

    // Get current playing song
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
        final success = await downloadService.deleteDownload(currentMedia.id);

        if (success && mounted) {
          setState(() => _isLiked = false);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Removed from saved songs'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        final hasPermission = await _ensureStoragePermission();
        if (!hasPermission) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission denied')),
          );
          return;
        }

        final core = VibeFlowCore();

        // ✅ Create QuickPick from current media
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
          throw Exception('Failed to get audio URL');
        }

        final result = await downloadService.downloadSong(
          videoId: currentSong.videoId,
          audioUrl: audioUrl,
          title: currentSong.title,
          artist: currentSong.artists,
          thumbnailUrl: currentSong.thumbnail,
        );

        if (result.success && mounted) {
          setState(() => _isLiked = true);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Added to saved songs'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(result.message);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingLike = false);
    }
  }

  // ✅ UPDATE: Lyrics view should use current song
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
      ),
    );
  }

  // ==================== HELPER METHOD FOR NEXT SONG PLACEHOLDER ====================
  Widget _buildQueueItemPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white38,
        size: 20,
      ),
    );
  }

  void _preloadArtwork() {
    if (widget.song.thumbnail.isEmpty || !mounted) return;

    precacheImage(
      NetworkImage(widget.song.thumbnail),
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

  @override
  void dispose() {
    _mediaItemDebounceTimer?.cancel();

    if (_rotationController.isAnimating) {
      _rotationController.stop();
    }
    if (_scaleController.isAnimating) {
      _scaleController.stop();
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      _scaleController.dispose();
      _rotationController.dispose();
    });

    super.dispose();
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
