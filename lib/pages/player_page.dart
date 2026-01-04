import 'dart:ui';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/audio_equalizer_page.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';
import 'package:vibeflow/utils/album_color_generator.dart';
import 'package:vibeflow/utils/audio_governerScreen.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/widgets/lyrics_widget.dart';
import 'package:vibeflow/widgets/radio_sheet.dart';
import 'package:vibeflow/widgets/playlist_bottomSheet.dart';

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

  @override
  void initState() {
    super.initState();

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
      final core = VibeFlowCore();
      await core.initialize();

      // Get audio URL with error handling
      final audioUrl = await core.getAudioUrlWithRetry(
        widget.song.videoId,
        maxRetries: 3,
      );

      if (audioUrl == null || audioUrl.isEmpty) {
        // 📳 VIBRATE: na-na pattern for audio error
        await HapticFeedbackService().vibrateCriticalError();
        // Show error overlay
        setState(() {
          _hasAudioError = true;
          _errorMessage = 'Unable to load audio';
          _detailedError =
              'Failed to retrieve audio stream for "${widget.song.title}".\n\n'
              'Possible causes:\n'
              '• Video ID: ${widget.song.videoId}\n'
              '• The audio source may be unavailable\n'
              '• Now Broken Engine\n'
              '• YouTube API changes';
        });
        _errorOverlayController.forward();
        return;
      }

      // Play song normally
      await _audioService.playSong(widget.song);
    } catch (e, stackTrace) {
      // 📳 VIBRATE: Triple pattern for critical error
      await HapticFeedbackService().vibrateCriticalError();
      // Detailed error for debugging
      setState(() {
        _hasAudioError = true;
        _errorMessage = 'Playback Error';
        _detailedError =
            'An error occurred while trying to play "${widget.song.title}".\n\n'
            'Error Details:\n'
            '${e.toString()}\n\n'
            'Video ID: ${widget.song.videoId}\n\n'
            'Stack Trace:\n'
            '${stackTrace.toString().split('\n').take(5).join('\n')}';
      });
      _errorOverlayController.forward();
      print('❌ [PlayerScreen] Playback error: $e');
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _loadAlbumColors() async {
    if (widget.song.thumbnail.isEmpty) return;

    try {
      final palette = await AlbumColorGenerator.fromAnySource(
        widget.song.thumbnail,
      );
      if (mounted) {
        setState(() {
          _albumPalette = palette;
        });
      }
    } catch (e) {
      print('Error loading album colors: $e');
    }
  }

  Future<void> _checkIfSongIsSaved() async {
    final downloadedSongs = await DownloadService.instance.getDownloadedSongs();
    final isSaved = downloadedSongs.any(
      (s) => s.videoId == widget.song.videoId,
    );

    if (mounted) {
      setState(() {
        _isSaved = isSaved;
      });
    }
  }

  Future<String?> _getAudioUrl() async {
    try {
      final handler = AudioServices.handler;
      final currentMedia = await handler.mediaItem.first;

      if (currentMedia?.id == widget.song.videoId) {
        final core = VibeFlowCore();
        await core.initialize();
        final url = await core.getAudioUrlWithRetry(widget.song.videoId);
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
      final success = await DownloadService.instance.deleteDownload(
        widget.song.videoId,
      );

      if (success && mounted) {
        setState(() {
          _isSaved = false;
        });

        _showNotification(
          title: 'Removed from Saved Songs',
          body: widget.song.title,
          notificationLayout: NotificationLayout.Default,
        );
      }
    } else {
      setState(() {
        _isDownloading = true;
        _isSaved = true;
      });

      await _createNotificationChannel();

      await _showDownloadNotification(
        title: 'Downloading',
        body: widget.song.title,
        progress: 0,
      );

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
            _updateDownloadNotification(
              title: 'Downloading',
              body: widget.song.title,
              progress: progress.toInt(),
            );
          },
        );

        if (mounted) {
          setState(() {
            _isDownloading = false;
          });

          if (result.success) {
            _showNotification(
              title: 'Download Complete',
              body: '${widget.song.title} saved successfully',
              notificationLayout: NotificationLayout.Default,
            );
          } else {
            setState(() {
              _isSaved = false;
            });

            _showNotification(
              title: 'Download Failed',
              body: result.message,
              notificationLayout: NotificationLayout.Default,
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isSaved = false;
          });

          _showNotification(
            title: 'Download Failed',
            body: 'Failed to save song: $e',
            notificationLayout: NotificationLayout.Default,
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
                              color: Colors.black.withOpacity(0.4),
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
                                Container(color: Colors.black.withOpacity(0.6)),

                              // Pause Overlay (when not playing and no error)
                              if (!isPlaying && !_hasAudioError)
                                FadeTransition(
                                  opacity: _pauseOverlayController,
                                  child: Container(
                                    color: Colors.black.withOpacity(0.4),
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
                          currentMedia?.title ?? widget.song.title,
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
                (_albumPalette?.vibrant ?? Colors.purple).withOpacity(0.98),
                (_albumPalette?.dominant ?? Colors.blue).withOpacity(0.98),
                (_albumPalette?.muted ?? Colors.grey).withOpacity(0.98),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
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
                    title: widget.song.title,
                    artist: widget.song.artists,
                    videoId: widget.song.videoId,
                    duration: widget.song.duration != null
                        ? int.tryParse(widget.song.duration!) ?? -1
                        : -1,
                    accentColor: _albumPalette?.vibrant ?? Colors.white,
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
              color: Colors.black.withOpacity(0.85),
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
                    color: const Color(0xFFFF4458),
                  ),
                  const SizedBox(height: 16),

                  // Error Message
                  Text(
                    _errorMessage ?? 'Playback Error',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Simple description
                  Text(
                    'Unable to load audio source',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
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
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'More Info',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.3),
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
                          backgroundColor: const Color(0xFFFF4458),
                          foregroundColor: Colors.white,
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _albumPalette?.vibrant ?? const Color(0xFF6B4CE8),
            _albumPalette?.dominant ?? const Color(0xFF2D1B69),
            _albumPalette?.muted ?? const Color(0xFF1A1A2E),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get theme-aware background color
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);

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
                    final screenHeight = constraints.maxHeight;
                    final screenWidth = constraints.maxWidth;

                    final topBarHeight = 56.0;
                    final bottomControlsHeight = 80.0;
                    final songInfoHeight = 100.0;
                    final progressBarHeight = 70.0; // Reduced from 80
                    final playerControlsHeight = 90.0; // Reduced from 100

                    // Calculate available space for album art
                    final totalFixedHeight =
                        topBarHeight +
                        songInfoHeight +
                        progressBarHeight +
                        playerControlsHeight +
                        bottomControlsHeight;
                    final availableSpace = screenHeight - totalFixedHeight;
                    final albumArtSize = (availableSpace * 0.8).clamp(
                      280.0,
                      340.0,
                    );
                    final albumArtPadding = (screenWidth - albumArtSize) / 2;

                    return Column(
                      children: [
                        // Minimalist Top Bar
                        SizedBox(
                          height: topBarHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: ref.watch(
                                      themeTextPrimaryColorProvider,
                                    ),
                                    size: 32,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    color: ref.watch(
                                      themeTextPrimaryColorProvider,
                                    ),
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      PageTransitions.fade(
                                        page: const AudioEqualizerPage(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Flexible spacer instead of fixed
                        Flexible(
                          flex: 1,
                          child: SizedBox(height: availableSpace * 0.1),
                        ),

                        // Album Art - wrapped in Flexible
                        Flexible(
                          flex: 5,
                          child: _buildAlbumArtWithBlur(
                            albumArtSize,
                            (screenWidth - albumArtSize) / 2,
                            currentMedia,
                            isPlaying,
                          ),
                        ),

                        // Flexible spacer
                        Flexible(
                          flex: 1,
                          child: SizedBox(height: availableSpace * 0.1),
                        ),

                        // Song Info
                        Container(
                          height: songInfoHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                currentMedia?.title ?? widget.song.title,
                                style: GoogleFonts.cabin(
                                  color: ref.watch(
                                    themeTextPrimaryColorProvider,
                                  ),
                                  fontSize: (screenWidth * 0.055).clamp(
                                    20.0,
                                    26.0,
                                  ),
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.6,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),

                              const SizedBox(height: 8),
                              Text(
                                currentMedia?.artist ?? widget.song.artists,
                                style: GoogleFonts.dancingScript(
                                  color: ref.watch(
                                    themeTextSecondaryColorProvider,
                                  ),
                                  fontSize: (screenWidth * 0.04).clamp(
                                    14.0,
                                    18.0,
                                  ),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Progress Bar
                        StreamBuilder<Duration>(
                          stream: _audioService.positionStream,
                          builder: (context, positionSnapshot) {
                            return StreamBuilder<Duration?>(
                              stream: _audioService.durationStream,
                              builder: (context, durationSnapshot) {
                                final position =
                                    positionSnapshot.data ?? Duration.zero;
                                final duration =
                                    durationSnapshot.data ?? Duration.zero;

                                final progress = duration.inMilliseconds > 0
                                    ? position.inMilliseconds /
                                          duration.inMilliseconds
                                    : 0.0;

                                return SizedBox(
                                  height:
                                      progressBarHeight + 10, // slightly taller
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0, // 🔥 wider bar
                                        ),
                                        child: SliderTheme(
                                          data: SliderThemeData(
                                            trackHeight: 4, // 🔥 thicker track
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                  enabledThumbRadius:
                                                      7, // 🔥 bigger thumb
                                                ),
                                            overlayShape:
                                                const RoundSliderOverlayShape(
                                                  overlayRadius: 16,
                                                ),
                                            activeTrackColor: ref.watch(
                                              themeIconActiveColorProvider,
                                            ),
                                            inactiveTrackColor: ref
                                                .watch(
                                                  themeTextSecondaryColorProvider,
                                                )
                                                .withOpacity(0.25),
                                            thumbColor: ref.watch(
                                              themeIconActiveColorProvider,
                                            ),
                                            overlayColor: ref
                                                .watch(
                                                  themeIconActiveColorProvider,
                                                )
                                                .withOpacity(0.25),
                                          ),
                                          child: Slider(
                                            value: progress.clamp(0.0, 1.0),
                                            onChanged: (value) {
                                              final newPosition = Duration(
                                                milliseconds:
                                                    (duration.inMilliseconds *
                                                            value)
                                                        .round(),
                                              );
                                              _audioService.seek(newPosition);
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal:
                                              20.0, // match slider width
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatDuration(position),
                                              style: GoogleFonts.pacifico(
                                                color: ref.watch(
                                                  themeTextSecondaryColorProvider,
                                                ),
                                                fontSize: 14,
                                                fontWeight: FontWeight
                                                    .w400, // Pacifico looks best lighter
                                                letterSpacing: 0.6,
                                              ),
                                            ),

                                            Text(
                                              _formatDuration(duration),
                                              style: GoogleFonts.pacifico(
                                                color: ref.watch(
                                                  themeTextSecondaryColorProvider,
                                                ),
                                                fontSize: 14,
                                                fontWeight: FontWeight
                                                    .w400, // Pacifico looks best lighter
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),

                        // Premium Player Controls
                        SizedBox(
                          height: playerControlsHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Heart Icon
                                IconButton(
                                  icon: Icon(
                                    widget.song.isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: widget.song.isFavorite
                                        ? Colors
                                              .red // Keep red for favorite state
                                        : ref.watch(
                                            themeTextSecondaryColorProvider,
                                          ),
                                    size: 26,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      widget.song.isFavorite =
                                          !widget.song.isFavorite;
                                    });
                                    _handleSaveToggle();
                                  },
                                ),

                                // Previous
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_previous_rounded,
                                    color: ref.watch(
                                      themeTextPrimaryColorProvider,
                                    ),
                                    size: 36,
                                  ),
                                  onPressed: () {
                                    _audioService.skipToPrevious();
                                  },
                                ),

                                // Play/Pause
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: ref.watch(
                                      themeIconActiveColorProvider,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: ref
                                            .watch(themeIconActiveColorProvider)
                                            .withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      playbackSnapshot.data?.processingState ==
                                              AudioProcessingState.loading
                                          ? Icons.hourglass_empty_rounded
                                          : isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color:
                                          backgroundColor, // Use background color for contrast
                                      size: 36,
                                    ),
                                    onPressed: () {
                                      _audioService.playPause();
                                    },
                                  ),
                                ),

                                // Next
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: ref.watch(
                                      themeTextPrimaryColorProvider,
                                    ),
                                    size: 36,
                                  ),
                                  onPressed: () {
                                    _audioService.skipToNext();
                                  },
                                ),

                                // Repeat
                                IconButton(
                                  icon: Icon(
                                    Icons.repeat_rounded,
                                    color: ref.watch(
                                      themeTextSecondaryColorProvider,
                                    ),
                                    size: 26,
                                  ),
                                  onPressed: () {},
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Bottom Controls
                        SizedBox(
                          height: bottomControlsHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.queue_music_rounded,
                                    color: ref.watch(
                                      themeTextSecondaryColorProvider,
                                    ),
                                    size: 26,
                                  ),
                                  onPressed: () => _showAddToPlaylistSheet(),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.radio_rounded,
                                    color: ref.watch(
                                      themeTextSecondaryColorProvider,
                                    ),
                                    size: 26,
                                  ),
                                  onPressed: _showRadioBottomSheet,
                                ),
                              ],
                            ),
                          ),
                        ),
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

  Future<void> _showRadioBottomSheet() async {
    if (!mounted) return;

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
  }

  Widget _buildPlaceholder() {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);

    return Container(
      color: cardBackgroundColor,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 80,
          color: iconInactiveColor,
        ),
      ),
    );
  }

  void _showDetailedErrorDialog() {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: cardBackgroundColor,
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
                    color: Colors.red, // Keep red for error icon
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Error Details',
                      style: TextStyle(
                        color: textPrimaryColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textPrimaryColor),
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
                      color: backgroundColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: textSecondaryColor.withOpacity(0.1),
                      ),
                    ),
                    child: SelectableText(
                      _detailedError ?? 'No error details available',
                      style: TextStyle(
                        color: textPrimaryColor.withOpacity(0.9),
                        fontSize: 13,
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
                          style: TextStyle(color: textPrimaryColor),
                        ),
                        backgroundColor: cardBackgroundColor,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: textPrimaryColor,
                  ),
                  label: Text(
                    'Copy Error Details',
                    style: TextStyle(color: textPrimaryColor),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: textSecondaryColor.withOpacity(0.1),
                    foregroundColor: textPrimaryColor,
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
    // Convert QuickPick to DbSong
    final dbSong = SongConverter.quickPickToDb(widget.song);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddToPlaylistSheet(song: dbSong),
    );
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
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

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
    _albumArtController.dispose();
    _albumRotationController.dispose();
    _lyricsController.dispose();
    _pauseOverlayController.dispose();
    _errorOverlayController.dispose();
    super.dispose();
  }
}
