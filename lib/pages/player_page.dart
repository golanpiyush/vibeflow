import 'dart:async';
import 'dart:ui';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/database/song_sharingService.dart';
import 'package:vibeflow/main.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/audio_equalizer_page.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/pages/user_taste_screen.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/audio_ui_sync.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';
import 'package:vibeflow/utils/album_color_generator.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/widgets/lyrics_widget.dart';
import 'package:vibeflow/widgets/radio_sheet.dart';
import 'package:vibeflow/widgets/playlist_bottomSheet.dart';
import 'package:vibeflow/widgets/shareSong.dart';

// ======================================================================================================================

// Legacy Screen

// ======================================================================================================================

class PlayerScreen extends ConsumerStatefulWidget {
  final QuickPick song;
  final String? heroTag;

  const PlayerScreen({Key? key, required this.song, this.heroTag})
    : super(key: key);

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  final _audioService = AudioServices.instance;
  late AnimationController _albumArtController;
  late AnimationController _albumRotationController;
  String? _currentArtworkUrl;

  AlbumPalette? _albumPalette;
  Timer? _sleepTimer;
  Duration? _sleepTimerDuration;
  DateTime? _sleepTimerEndTime;
  late AnimationController _lyricsController;
  late AnimationController _pauseOverlayController;
  bool _showLyrics = false;
  Offset _swipeStart = Offset.zero;

  // Error states
  bool _hasAudioError = false;
  String? _errorMessage;
  String? _detailedError;
  late AnimationController _errorOverlayController;

  bool _isSaved = false;
  bool _isDownloading = false;

  MediaItem? _currentDisplayMedia;
  String? _currentVideoId;
  String? _pendingSideEffectId;
  bool _isSideEffectRunning = false;
  String? _lastArtworkUrl; // rename from _currentArtworkUrl for palette guard
  bool _isCheckingLiked = false;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    isMiniplayerVisible.value = false;
    _currentDisplayMedia =
        AudioUISync.instance.currentMedia ?? getAudioHandler()?.mediaItem.value;
    _currentVideoId = _currentDisplayMedia?.id;
    AudioUISync.instance.addListener(_onAudioSyncChanged);
    _albumArtController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _albumRotationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _lyricsController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _pauseOverlayController = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    );

    //  Error overlay animation controller
    _errorOverlayController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _currentArtworkUrl = widget.song.thumbnail;
    _playInitialSong();
    _loadAlbumColors();
    _checkIfSongIsSaved();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _albumArtController.forward();
      }
    });
  }

  Future<void> _playInitialSong() async {
    try {
      final handler = getAudioHandler();
      if (handler == null) return;
      final currentMedia = handler.mediaItem.value;
      final hasAudioSource = handler.audioSource != null;
      final isPlaying = handler.isPlaying;

      if (currentMedia?.id == widget.song.videoId && hasAudioSource) {
        print(
          '✅ [PlayerScreen] Song already loaded: ${_currentDisplayMedia?.title}',
        );
        if (!isPlaying) await _audioService.play();
        return;
      }
      print(
        '🎵 [PlayerScreen] Playing new song: ${_currentDisplayMedia?.title}',
      );
      await _audioService.playSong(widget.song);
    } catch (e, stackTrace) {
      print('❌ [PlayerScreen] Playback error: $e');
      await HapticFeedbackService().vibrateCriticalError();
      setState(() {
        _hasAudioError = true;
        _errorMessage = 'Playback Error';
        _detailedError =
            'Error: $e\n\nStack:\n${stackTrace.toString().split('\n').take(5).join('\n')}';
      });
      _errorOverlayController.forward();
    }
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

  void _dispatchSideEffects(MediaItem item) {
    _pendingSideEffectId = item.id;
    _currentArtworkUrl =
        item.artUri?.toString() ??
        _currentArtworkUrl ??
        widget.song.thumbnail; // ADD
    final artUrl = item.artUri?.toString() ?? '';
    if (artUrl.isNotEmpty && artUrl != _lastArtworkUrl) {
      _lastArtworkUrl = artUrl;
      _loadAlbumColorsFromUrl(artUrl);
    }
    _checkIfSongIsSaved(item.id);
  }

  Future<void> _loadAlbumColorsFromUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final palette = await AlbumColorGenerator.fromAnySource(url);
      if (mounted) setState(() => _albumPalette = palette);
    } catch (e) {
      print('Error loading album colors: $e');
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _loadAlbumColors({String? artUrl}) async {
    final url = artUrl ?? _currentArtworkUrl ?? widget.song.thumbnail;
    if (url.isEmpty) return;

    // Capture the videoId now — discard result if song changed during await
    final expectedId = _currentVideoId;

    try {
      final palette = await AlbumColorGenerator.fromAnySource(url);
      if (mounted && _currentVideoId == expectedId) {
        setState(() => _albumPalette = palette);
      }
    } catch (e) {
      print('Error loading album colors: $e');
    }
  }

  Future<void> _checkIfSongIsSaved([String? videoId]) async {
    final id = videoId ?? _currentVideoId ?? widget.song.videoId;

    _pendingSideEffectId = id;
    if (_isSideEffectRunning) return;
    _isSideEffectRunning = true;

    try {
      final downloadService = DownloadService.instance;
      final savedSongs = await downloadService.getDownloadedSongs();

      if (!mounted || id != _pendingSideEffectId) return;

      setState(() {
        _isLiked = savedSongs.any((s) => s.videoId == id); // ← uses correct id
        _isCheckingLiked = false;
      });
    } catch (e) {
      if (mounted && id == _pendingSideEffectId) {
        setState(() => _isCheckingLiked = false);
      }
    } finally {
      _isSideEffectRunning = false;
      if (_pendingSideEffectId != null && _pendingSideEffectId != id) {
        final next = _pendingSideEffectId!;
        _pendingSideEffectId = null;
        _checkIfSongIsSaved(next);
      }
    }
  }

  Future<String?> _getAudioUrl() async {
    try {
      final handler = AudioServices.handler;
      final currentMedia = await handler.mediaItem.first;

      final targetId = _currentDisplayMedia?.id ?? widget.song.videoId;
      final core = VibeFlowCore();

      if (currentMedia?.id == targetId) {
        final url = await core.getAudioUrlWithRetry(targetId);
        return url;
      }

      return null;
    } catch (e) {
      debugPrint('Error getting audio URL: $e');
      return null;
    }
  }

  Future<void> _handleSaveToggle() async {
    if (_isDownloading) return;

    if (_isSaved) {
      // Remove from saved songs
      final videoId = _currentDisplayMedia?.id ?? widget.song.videoId;
      final success = await DownloadService.instance.deleteDownload(videoId);
      if (success && mounted) {
        setState(() {
          _isSaved = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed from Saved Songs'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Download song
      setState(() {
        _isDownloading = true;
        _isSaved = true;
      });

      try {
        final audioUrl = await _getAudioUrl();

        if (audioUrl == null) {
          throw Exception('Failed to get audio URL');
        }

        final result = await DownloadService.instance.downloadSong(
          videoId: widget.song.videoId,
          audioUrl: audioUrl,
          title: widget.song.title,
          artist: widget.song.artists,
          thumbnailUrl: widget.song.thumbnail,
          onProgress: (progress) {
            debugPrint(
              'Download progress: ${(progress * 100).toStringAsFixed(1)}%',
            );
          },
        );

        if (mounted) {
          setState(() {
            _isDownloading = false;
          });

          if (result.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${widget.song.title} saved successfully'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          } else {
            setState(() {
              _isSaved = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Download failed: ${result.message}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isSaved = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save song: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Widget _buildAlbumArtWithBlur(
    double albumArtSize,
    double albumArtPadding,
    MediaItem? currentMedia,
    bool isPlaying,
  ) {
    final themeData = Theme.of(context);
    final blurContainerSize = 340.0;
    final actualAlbumSize = 340.0;
    final artworkUrl =
        currentMedia?.artUri?.toString() ?? widget.song.thumbnail;
    final radiusMultiplier = ref.watch(thumbnailRadiusProvider);

    return GestureDetector(
      onTap: () {
        if (!_hasAudioError) {
          _audioService.playPause();
        }
      },
      onVerticalDragStart: (details) {
        _swipeStart = details.globalPosition;
      },
      onVerticalDragEnd: (details) {
        final delta = details.globalPosition.dy - _swipeStart.dy;

        if (delta > 100) {
          Navigator.pop(context);
        } else if (delta < -100 && !_hasAudioError) {
          setState(() {
            _showLyrics = !_showLyrics;
            if (_showLyrics) {
              _lyricsController.forward();
            } else {
              _lyricsController.reverse();
            }
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_hasAudioError) return;

        if (details.primaryVelocity! > 0) {
          _audioService.skipToPrevious();
        } else if (details.primaryVelocity! < 0) {
          _audioService.skipToNext();
        }
      },
      child: Hero(
        tag: widget.heroTag ?? 'thumbnail-${widget.song.videoId}',
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _albumArtController,
            _albumRotationController,
          ]),
          builder: (context, child) {
            final scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
              CurvedAnimation(
                parent: _albumArtController,
                curve: Curves.elasticOut,
              ),
            );

            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: _albumArtController,
                curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
              ),
            );

            final rotationValue = isPlaying
                ? _albumRotationController.value
                : 0.0;

            return Transform.scale(
              scale: scaleAnimation.value,
              child: Opacity(
                opacity: fadeAnimation.value,
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Animated Blur Background
                      Transform.rotate(
                        angle: rotationValue * 2 * 3.14159,
                        child: Container(
                          width: blurContainerSize,
                          height: blurContainerSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              blurContainerSize * radiusMultiplier,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (_albumPalette?.dominant ?? Colors.purple)
                                        .withOpacity(0.6),
                                blurRadius: 60,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              blurContainerSize * radiusMultiplier,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (artworkUrl.isNotEmpty)
                                  buildAlbumArtImage(
                                    artworkUrl: artworkUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _buildColorGradient(),
                                  )
                                else
                                  _buildColorGradient(),
                                BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 30,
                                    sigmaY: 30,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          (_albumPalette?.vibrant ??
                                                  Colors.purple)
                                              .withOpacity(0.4),
                                          (_albumPalette?.dominant ??
                                                  Colors.blue)
                                              .withOpacity(0.5),
                                          (_albumPalette?.muted ?? Colors.grey)
                                              .withOpacity(0.4),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Main Album Art
                      Container(
                        width: actualAlbumSize,
                        height: actualAlbumSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            blurContainerSize * radiusMultiplier,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: themeData.shadowColor.withOpacity(0.4),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            blurContainerSize * radiusMultiplier,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Album artwork
                              artworkUrl.isNotEmpty
                                  ? buildAlbumArtImage(
                                      artworkUrl: artworkUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildPlaceholder(),
                                    )
                                  : _buildPlaceholder(),

                              // Dimming overlay when error occurs
                              if (_hasAudioError)
                                Container(
                                  color: themeData.shadowColor.withOpacity(0.6),
                                ),

                              // Pause Overlay (when not playing and no error)
                              if (!isPlaying && !_hasAudioError)
                                FadeTransition(
                                  opacity: _pauseOverlayController,
                                  child: Container(
                                    color: themeData.shadowColor.withOpacity(
                                      0.4,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Error Overlay (shown when audio fails)
                      if (_hasAudioError) _buildErrorOverlay(actualAlbumSize),

                      // Lyrics Overlay (only when no error)
                      if (!_hasAudioError)
                        _buildLyricsOverlay(
                          actualAlbumSize,
                          currentMedia?.title ??
                              _currentDisplayMedia?.title ??
                              widget.song.title,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLyricsOverlay(double size, String songTitle) {
    final themeData = Theme.of(context);
    final radiusMultiplier = ref.watch(thumbnailRadiusProvider);
    final actualAlbumSize = 340.0;

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _lyricsController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: FadeTransition(
        opacity: _lyricsController,
        child: Container(
          width: actualAlbumSize,
          height: actualAlbumSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              actualAlbumSize * radiusMultiplier,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                (_albumPalette?.vibrant ?? themeData.colorScheme.primary)
                    .withOpacity(0.98),
                (_albumPalette?.dominant ?? themeData.colorScheme.secondary)
                    .withOpacity(0.98),
                (_albumPalette?.muted ?? themeData.disabledColor).withOpacity(
                  0.98,
                ),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: Icon(
                    Icons.close,
                    color: themeData.colorScheme.onPrimary,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _showLyrics = false;
                      _lyricsController.reverse();
                    });
                  },
                ),
              ),
              Center(
                child: SizedBox(
                  width: actualAlbumSize - 40,
                  height: actualAlbumSize - 60,
                  child: CenteredLyricsWidget(
                    title: _currentDisplayMedia?.title ?? widget.song.title,
                    artist: _currentDisplayMedia?.artist ?? widget.song.artists,
                    videoId: _currentDisplayMedia?.id ?? widget.song.videoId,
                    duration: widget.song.duration != null
                        ? int.tryParse(widget.song.duration!) ?? -1
                        : -1,
                    accentColor:
                        _albumPalette?.vibrant ??
                        themeData.colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(double size) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final radiusMultiplier = ref.watch(thumbnailRadiusProvider);

    return AnimatedBuilder(
      animation: _errorOverlayController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _errorOverlayController,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * radiusMultiplier),
              color: colorScheme.surface.withOpacity(0.85),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Error Icon
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),

                  // Error Message
                  Text(
                    _errorMessage ?? 'Playback Error',
                    style: themeData.textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Simple description
                  Text(
                    'Unable to load audio source',
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // More Info Button
                      OutlinedButton.icon(
                        onPressed: () {
                          _showDetailedErrorDialog();
                        },
                        icon: Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: colorScheme.onSurface,
                        ),
                        label: Text(
                          'More Info',
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: colorScheme.onSurface.withOpacity(0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Retry Button
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _hasAudioError = false;
                            _errorMessage = null;
                            _detailedError = null;
                          });
                          _errorOverlayController.reverse();
                          _playInitialSong();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorGradient() {
    final themeData = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _albumPalette?.vibrant ?? themeData.colorScheme.primary,
            _albumPalette?.dominant ?? themeData.colorScheme.secondary,
            _albumPalette?.muted ?? themeData.disabledColor,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;

    // Use colorScheme for all colors
    final backgroundColor = colorScheme.surface;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.7);
    final textMuted = colorScheme.onSurface.withOpacity(0.5);
    final iconActiveColor = colorScheme.primary;
    final iconInactiveColor = colorScheme.onSurface.withOpacity(0.3);
    final errorColor = colorScheme.error;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: _audioService.mediaItemStream,
          builder: (context, mediaSnapshot) {
            final currentMedia = mediaSnapshot.data;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleAlbumArtChange(currentMedia?.artUri?.toString());
            });

            return StreamBuilder<PlaybackState>(
              stream: _audioService.playbackStateStream,
              builder: (context, playbackSnapshot) {
                final isPlaying = playbackSnapshot.data?.playing ?? false;

                if (!isPlaying) {
                  _pauseOverlayController.forward();
                } else {
                  _pauseOverlayController.reverse();
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final screenWidth = constraints.maxWidth;

                    return Column(
                      children: [
                        // ───────────────── TOP BAR ─────────────────
                        SizedBox(
                          height: 56,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 32,
                                    color: textPrimary,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 28,
                                    color: textPrimary,
                                  ),
                                  onPressed: _showMoreOptions,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Spacer(),

                        // ─────────────── ALBUM ART ───────────────
                        _buildAlbumArtWithBlur(
                          300,
                          (screenWidth - 230) / 2,
                          currentMedia,
                          isPlaying,
                        ),

                        const Spacer(),

                        // ───────────── SONG INFO ─────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              AutoSizeText(
                                _currentDisplayMedia?.title ??
                                    widget.song.title,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cabin(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.6,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              AutoSizeText(
                                _currentDisplayMedia?.artist ??
                                    widget.song.artists,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.dancingScript(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ───────────── PROGRESS BAR ─────────────
                        StreamBuilder<Duration>(
                          stream: _audioService.positionStream,
                          builder: (context, posSnap) {
                            return StreamBuilder<Duration?>(
                              stream: _audioService.durationStream,
                              builder: (context, durSnap) {
                                final position = posSnap.data ?? Duration.zero;
                                final duration = durSnap.data ?? Duration.zero;

                                final progress = duration.inMilliseconds > 0
                                    ? position.inMilliseconds /
                                          duration.inMilliseconds
                                    : 0.0;

                                return Column(
                                  children: [
                                    SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 4,
                                        activeTrackColor: iconActiveColor,
                                        inactiveTrackColor: iconInactiveColor,
                                        thumbColor: iconActiveColor,
                                      ),
                                      child: Slider(
                                        value: progress.clamp(0.0, 1.0),
                                        onChanged: (value) {
                                          _audioService.seek(
                                            Duration(
                                              milliseconds:
                                                  (duration.inMilliseconds *
                                                          value)
                                                      .round(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatDuration(position),
                                            style: GoogleFonts.pacifico(
                                              fontSize: 14,
                                              color: textMuted,
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(duration),
                                            style: GoogleFonts.pacifico(
                                              fontSize: 14,
                                              color: textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 20),

                        // ─────────── UPPER CONTROLS (PREV / PLAY / NEXT) ───────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.skip_previous_rounded,
                                size: 38,
                                color: iconActiveColor,
                              ),
                              onPressed: _audioService.skipToPrevious,
                            ),
                            const SizedBox(width: 20),
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: iconActiveColor,
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 20,
                                    color: iconActiveColor.withOpacity(0.3),
                                  ),
                                ],
                              ),
                              child: StreamBuilder<PlaybackState>(
                                stream: _audioService.playbackStateStream,
                                builder: (context, snap) {
                                  final state = snap.data;
                                  final isLoading =
                                      state?.processingState ==
                                          AudioProcessingState.loading ||
                                      state?.processingState ==
                                          AudioProcessingState.buffering;

                                  return IconButton(
                                    icon: isLoading
                                        ? SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: backgroundColor,
                                            ),
                                          )
                                        : Icon(
                                            isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            size: 40,
                                            color: backgroundColor,
                                          ),
                                    onPressed: isLoading
                                        ? null
                                        : _audioService.playPause,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: Icon(
                                Icons.skip_next_rounded,
                                size: 38,
                                color: iconActiveColor,
                              ),
                              onPressed: _audioService.skipToNext,
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ─────────── LOWER CONTROLS (LOOP · HEART · RADIO) ───────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // LOOP
                            StreamBuilder<LoopMode>(
                              stream: _audioService.loopModeStream,
                              builder: (context, snap) {
                                final mode = snap.data ?? LoopMode.off;
                                return IconButton(
                                  icon: Icon(
                                    mode == LoopMode.one
                                        ? Icons.repeat_one_rounded
                                        : Icons.repeat_rounded,
                                    color: mode == LoopMode.off
                                        ? iconInactiveColor
                                        : iconActiveColor,
                                  ),
                                  onPressed: () {
                                    _audioService.setLoopMode(
                                      mode == LoopMode.off
                                          ? LoopMode.all
                                          : mode == LoopMode.all
                                          ? LoopMode.one
                                          : LoopMode.off,
                                    );
                                  },
                                );
                              },
                            ),

                            // HEART
                            IconButton(
                              icon: Icon(
                                widget.song.isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: widget.song.isFavorite
                                    ? errorColor
                                    : iconInactiveColor,
                              ),
                              onPressed: () {
                                setState(() {
                                  widget.song.isFavorite =
                                      !widget.song.isFavorite;
                                });
                                _handleSaveToggle();
                              },
                            ),

                            // RADIO
                            IconButton(
                              icon: Icon(
                                Icons.radio_rounded,
                                color: iconActiveColor,
                              ),
                              onPressed: _showRadioBottomSheet,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showMoreOptions() {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
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
                  color: colorScheme.onSurface.withOpacity(0.3),
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
                    color: colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _sleepTimer != null && _sleepTimer!.isActive
                        ? Icons.bedtime
                        : Icons.bedtime_outlined,
                    color: _sleepTimer != null && _sleepTimer!.isActive
                        ? Colors.blue.shade300
                        : colorScheme.onSurface,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Sleep Timer',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  _sleepTimer != null && _sleepTimer!.isActive
                      ? 'Active: ${_getRemainingTime()}'
                      : 'Pause music after a set time',
                  style: GoogleFonts.inter(
                    color: _sleepTimer != null && _sleepTimer!.isActive
                        ? Colors.blue.shade300
                        : colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: colorScheme.onSurface.withOpacity(0.4),
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showSleepTimerDialog();
                },
              ),

              Divider(
                color: colorScheme.onSurface.withOpacity(0.1),
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
                    color: colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.equalizer_rounded,
                    color: colorScheme.onSurface,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Equalizer',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Adjust audio settings',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: colorScheme.onSurface.withOpacity(0.4),
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openEqualizer();
                },
              ),

              Divider(
                color: colorScheme.onSurface.withOpacity(0.1),
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
                    color: colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.emoji_emotions_outlined,
                    color: colorScheme.onSurface,
                    size: 22,
                  ),
                ),
                title: Text(
                  'User Taste',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Personalize your music preferences',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: colorScheme.onSurface.withOpacity(0.4),
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
                color: colorScheme.onSurface.withOpacity(0.1),
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
                    color: colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.playlist_add_rounded,
                    color: colorScheme.onSurface,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Add to Playlist',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Save to your collection',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: colorScheme.onSurface.withOpacity(0.4),
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAddToPlaylistSheet();
                },
              ),

              // Share Option
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.share_rounded,
                    color: colorScheme.onSurface,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Share',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Share this song',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: colorScheme.onSurface.withOpacity(0.4),
                  size: 16,
                ),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final sharingService = ref.read(songSharingServiceProvider);
                    await sharingService.shareSongPublic();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to share song: ${e.toString()}',
                            style: GoogleFonts.inter(),
                          ),
                          backgroundColor: colorScheme.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _openEqualizer() {
    Navigator.push(
      context,
      PageTransitions.fade(page: const AudioEqualizerPage()),
    );
  }

  Future<void> _showRadioBottomSheet() async {
    final themeData = Theme.of(context);

    if (!mounted) return;

    // ✅ Ensure handler has radio loaded before opening sheet
    final handler = getAudioHandler();
    if (handler != null) {
      final customState =
          handler.customState.value as Map<String, dynamic>? ?? {};
      final radioQueue = customState['radio_queue'] as List<dynamic>? ?? [];

      if (radioQueue.isEmpty) {
        // Get current song and trigger radio load
        final currentMedia = handler.mediaItem.value;
        if (currentMedia != null) {
          final currentSong = QuickPick(
            videoId: currentMedia.id,
            title: currentMedia.title,
            artists: currentMedia.artist ?? 'Unknown Artist',
            thumbnail: currentMedia.artUri?.toString() ?? '',
            duration: currentMedia.duration?.inSeconds.toString(),
          );

          // ✅ Trigger load using public method
          handler.loadRadioImmediately(currentSong);
        }
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => EnhancedRadioSheet(
        currentVideoId: _currentDisplayMedia?.id ?? widget.song.videoId,
        currentTitle: _currentDisplayMedia?.title ?? widget.song.title,
        currentArtist: _currentDisplayMedia?.artist ?? widget.song.artists,
        audioService: _audioService,
      ),
    );
  }

  // ✅ NEW: Get remaining time for display
  String _getRemainingTime() {
    if (_sleepTimerEndTime == null) return '';

    final remaining = _sleepTimerEndTime!.difference(DateTime.now());

    if (remaining.isNegative) return '0 min';

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours hr ${minutes} min';
    } else {
      return '$minutes min';
    }
  }

  // ✅ NEW: Start sleep timer
  void _startSleepTimer(Duration duration, String label) {
    // Cancel existing timer if any
    _sleepTimer?.cancel();

    setState(() {
      _sleepTimerDuration = duration;
      _sleepTimerEndTime = DateTime.now().add(duration);
    });

    _sleepTimer = Timer(duration, () {
      if (mounted) {
        // Pause the music
        _audioService.pause();

        // Show notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.bedtime, color: Colors.blue.shade300, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Sleep timer ended - Music paused',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue.shade900,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );

        setState(() {
          _sleepTimer = null;
          _sleepTimerDuration = null;
          _sleepTimerEndTime = null;
        });
      }
    });

    // Show confirmation
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

  // ✅ NEW: Cancel sleep timer
  void _cancelSleepTimer() {
    _sleepTimer?.cancel();

    if (mounted) {
      setState(() {
        _sleepTimer = null;
        _sleepTimerDuration = null;
        _sleepTimerEndTime = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cancel_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              const Expanded(
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

  // ✅ NEW: Show sleep timer dialog
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

    // Get theme colors
    final themeData = Theme.of(context);
    final cardBg = themeData.colorScheme.surface;
    final textPrimary = themeData.colorScheme.onSurface;
    final textSecondary = textPrimary.withOpacity(0.7);

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

              // Active timer info (if running)
              if (_sleepTimer != null && _sleepTimer!.isActive)
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
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.3),
                        width: 1,
                      ),
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
                            'Timer active: Music will pause in ${_getRemainingTime()}',
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

              // Scrollable duration options
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: (_sleepTimer != null && _sleepTimer!.isActive)
                        ? 0
                        : 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: durations.map((item) {
                      final duration = item['duration'] as Duration;
                      final label = item['label'] as String;
                      final isActive =
                          _sleepTimerDuration == duration &&
                          _sleepTimer != null &&
                          _sleepTimer!.isActive;

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

              // Cancel timer button (if active)
              if (_sleepTimer != null && _sleepTimer!.isActive)
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

  Widget _buildPlaceholder() {
    return Image.asset(
      'assets/imgs/funny_dawg.jpg',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        // Ultimate fallback if even the local asset fails
        return Container(
          color: Theme.of(context).cardColor,
          child: Center(
            child: Icon(
              Icons.broken_image_rounded,
              size: 80,
              color: Theme.of(context).disabledColor,
            ),
          ),
        );
      },
    );
  }

  void _showDetailedErrorDialog() {
    final themeData = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: themeData.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.bug_report_rounded,
                    color: themeData.colorScheme.error,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Error Details',
                      style: themeData.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: themeData.iconTheme.color),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scrollable Error Content
              Flexible(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: themeData.scaffoldBackgroundColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: themeData.dividerColor),
                    ),
                    child: SelectableText(
                      _detailedError ?? 'No error details available',
                      style: themeData.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Copy to Clipboard Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _detailedError ?? ''),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error details copied to clipboard',
                          style: TextStyle(
                            color: themeData.colorScheme.onPrimary,
                          ),
                        ),
                        backgroundColor: themeData.cardColor,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: themeData.colorScheme.onPrimary,
                  ),
                  label: Text(
                    'Copy Error Details',
                    style: TextStyle(color: themeData.colorScheme.onPrimary),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeData.disabledColor.withOpacity(0.1),
                    foregroundColor: themeData.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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

  void _showAddToPlaylistSheet() {
    final themeData = Theme.of(context);
    final currentMedia = _audioService.currentMediaItem;

    if (currentMedia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No song currently playing',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: themeData.colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dbSong = DbSong(
      videoId: currentMedia.id,
      title: currentMedia.title,
      artists: [currentMedia.artist ?? 'Unknown Artist'],
      thumbnail: currentMedia.artUri?.toString() ?? '',
      duration: currentMedia.duration?.inSeconds.toString() ?? '0',
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddToPlaylistSheet(song: dbSong),
    ).then((_) => PlaylistCoverCache.invalidateAll());
  }

  void _handleAlbumArtChange(String? newArtUrl) {
    if (newArtUrl != _currentArtworkUrl) {
      setState(() {
        _albumArtController.reset();
        _currentArtworkUrl = newArtUrl;
      });
      _albumArtController.forward();

      if (newArtUrl != null && newArtUrl.isNotEmpty) {
        _loadAlbumColors();
      }
    }
  }

  Future<void> _createNotificationChannel() async {
    final themeData = Theme.of(context);
    final iconActiveColor =
        themeData.iconTheme.color ?? themeData.colorScheme.primary;

    await AwesomeNotifications().initialize(null, [
      NotificationChannel(
        channelKey: 'download_channel',
        channelName: 'Downloads',
        channelDescription: 'Download progress notifications',
        defaultColor: iconActiveColor,
        ledColor: Colors.white,
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: false,
        enableVibration: false,
      ),
    ]);
  }

  Future<void> _showDownloadNotification({
    required String title,
    required String body,
    required int progress,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: widget.song.videoId.hashCode,
        channelKey: 'download_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.ProgressBar,
        progress: progress.toDouble(),
        locked: true,
        category: NotificationCategory.Progress,
      ),
    );
  }

  void _updateDownloadNotification({
    required String title,
    required String body,
    required int progress,
  }) {
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: widget.song.videoId.hashCode,
        channelKey: 'download_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.ProgressBar,
        progress: progress.toDouble(),
        locked: progress < 100,
        category: NotificationCategory.Progress,
      ),
    );
  }

  Future<void> _showNotification({
    required String title,
    required String body,
    required NotificationLayout notificationLayout,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'download_channel',
        title: title,
        body: body,
        notificationLayout: notificationLayout,
        autoDismissible: true,
      ),
    );
  }

  @override
  void dispose() {
    isMiniplayerVisible.value = true; // ✅ VERIFY THIS EXISTS
    AudioUISync.instance.removeListener(_onAudioSyncChanged);
    _albumArtController.dispose();
    _albumRotationController.dispose();
    _lyricsController.dispose();
    _pauseOverlayController.dispose();
    _errorOverlayController.dispose();
    super.dispose();
  }
}
