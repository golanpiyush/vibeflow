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
import 'package:vibeflow/services/audio_service.dart';
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
    isMiniplayerVisible.value = false;

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
      print('🎵 [PlayerScreen] Checking if song needs to be played');

      final currentMedia = await _audioService.mediaItemStream.first;

      // Only play if it's a different song
      if (currentMedia == null || currentMedia.id != widget.song.videoId) {
        print('🎵 [PlayerScreen] Playing new song: ${widget.song.title}');
        await _audioService.playSong(widget.song);
      } else {
        print('✅ [PlayerScreen] Song already playing: ${widget.song.title}');
      }
    } catch (e, stackTrace) {
      print('❌ [PlayerScreen] Playback error: $e');
      await HapticFeedbackService().vibrateCriticalError();

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
      // Remove from saved songs
      final success = await DownloadService.instance.deleteDownload(
        widget.song.videoId,
      );

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
                    title: widget.song.title,
                    artist: widget.song.artists,
                    videoId: widget.song.videoId,
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
              color: themeData.shadowColor.withOpacity(0.85),
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
                    color: themeData.colorScheme.error,
                  ),
                  const SizedBox(height: 16),

                  // Error Message
                  Text(
                    _errorMessage ?? 'Playback Error',
                    style: themeData.textTheme.titleLarge?.copyWith(
                      color: themeData.colorScheme.onPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Simple description
                  Text(
                    'Unable to load audio source',
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      color: themeData.colorScheme.onPrimary.withOpacity(0.7),
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
                          color: themeData.colorScheme.onPrimary,
                        ),
                        label: Text(
                          'More Info',
                          style: TextStyle(
                            color: themeData.colorScheme.onPrimary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: themeData.colorScheme.onPrimary.withOpacity(
                              0.3,
                            ),
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
                          backgroundColor: themeData.colorScheme.error,
                          foregroundColor: themeData.colorScheme.onPrimary,
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
    final backgroundColor = themeData.scaffoldBackgroundColor;
    final iconActiveColor =
        themeData.iconTheme.color ?? themeData.colorScheme.primary;
    final iconInactiveColor = themeData.disabledColor;

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
                                    color: themeData.textTheme.bodyLarge?.color,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),

                                // Option 2: Public sharing (no access code needed)
                                const SizedBox(width: 8),

                                IconButton(
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 28,
                                    color: themeData.textTheme.bodyLarge?.color,
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
                                currentMedia?.title ?? widget.song.title,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cabin(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.6,
                                  color: themeData.textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 6),
                              AutoSizeText(
                                currentMedia?.artist ?? widget.song.artists,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.dancingScript(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                  color: themeData.textTheme.bodyMedium?.color,
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
                                        inactiveTrackColor: iconInactiveColor
                                            .withOpacity(0.25),
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
                                              color: iconInactiveColor,
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(duration),
                                            style: GoogleFonts.pacifico(
                                              fontSize: 14,
                                              color: iconInactiveColor,
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
                              child: IconButton(
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 40,
                                  color: backgroundColor,
                                ),
                                onPressed: _audioService.playPause,
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
                                    ? themeData.colorScheme.error
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: themeData.cardColor,
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
                  color: themeData.disabledColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // EQ Option
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: themeData.disabledColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.equalizer_rounded,
                    color: themeData.iconTheme.color,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Equalizer',
                  style: GoogleFonts.inter(
                    color: themeData.textTheme.bodyLarge?.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Adjust audio settings',
                  style: GoogleFonts.inter(
                    color: themeData.textTheme.bodyMedium?.color?.withOpacity(
                      0.6,
                    ),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: themeData.disabledColor.withOpacity(0.4),
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openEqualizer();
                },
              ),

              Divider(
                color: themeData.dividerColor,
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
                    color: themeData.disabledColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.playlist_add_rounded,
                    color: themeData.iconTheme.color,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Add to Playlist',
                  style: GoogleFonts.inter(
                    color: themeData.textTheme.bodyLarge?.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Save to your collection',
                  style: GoogleFonts.inter(
                    color: themeData.textTheme.bodyMedium?.color?.withOpacity(
                      0.6,
                    ),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: themeData.disabledColor.withOpacity(0.4),
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
                    color: themeData.disabledColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.share_rounded,
                    color: themeData.iconTheme.color,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Share',
                  style: GoogleFonts.inter(
                    color: themeData.textTheme.bodyLarge?.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Share this song',
                  style: GoogleFonts.inter(
                    color: themeData.textTheme.bodyMedium?.color?.withOpacity(
                      0.6,
                    ),
                    fontSize: 13,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: themeData.disabledColor.withOpacity(0.4),
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
                          backgroundColor: themeData.colorScheme.error,
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
        currentVideoId: widget.song.videoId,
        currentTitle: widget.song.title,
        currentArtist: widget.song.artists,
        audioService: _audioService,
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

    // Convert current MediaItem to DbSong
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
    _albumArtController.dispose();
    _albumRotationController.dispose();
    _lyricsController.dispose();
    _pauseOverlayController.dispose();
    _errorOverlayController.dispose();
    super.dispose();
  }
}
