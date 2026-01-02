import 'dart:ui';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/utils/album_color_generator.dart';
import 'package:vibeflow/utils/audio_governerScreen.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/widgets/radio_sheet.dart';

class PlayerScreen extends StatefulWidget {
  final QuickPick song;
  final String? heroTag;

  const PlayerScreen({Key? key, required this.song, this.heroTag})
    : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  final _audioService = AudioServices.instance;
  late AnimationController _albumArtController;
  late AnimationController _controlsController;
  String? _currentArtworkUrl;

  AlbumPalette? _albumPalette;

  late AnimationController _lyricsController;
  late AnimationController _pauseOverlayController;
  bool _showLyrics = false;
  Offset _swipeStart = Offset.zero;

  bool _isSaved = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();

    _albumArtController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _controlsController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // NEW: Lyrics animation controller
    _lyricsController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // NEW: Pause overlay controller
    _pauseOverlayController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _currentArtworkUrl = widget.song.thumbnail;
    _playInitialSong();
    _loadAlbumColors();
    _checkIfSongIsSaved();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _albumArtController.forward();
        _controlsController.forward();
      }
    });
  }

  Future<void> _playInitialSong() async {
    await _audioService.playSong(widget.song);
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
      // Use the new auto-detect method
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
      if (mounted) {}
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
      // Option 1: Get from BackgroundAudioHandler if available
      final handler = AudioServices.handler;

      // Check if currently playing this song
      final currentMedia = await handler.mediaItem.first;

      if (currentMedia?.id == widget.song.videoId) {
        // Get the URL from the audio player's current source
        // Note: BackgroundAudioHandler stores URL in _urlCache

        // For now, we need to fetch fresh URL
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
      // Delete the download
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
      // Start download
      setState(() {
        _isDownloading = true;
        _isSaved = true; // Optimistic update
      });

      // Create notification channel
      await _createNotificationChannel();

      // Show initial notification
      await _showDownloadNotification(
        title: 'Downloading',
        body: widget.song.title,
        progress: 0, // ✅ FIX 1: Changed from int to double
      );

      try {
        // ✅ FIX 2: Get the audio URL first before calling downloadSong
        final audioUrl = await _getAudioUrl();

        if (audioUrl == null) {
          throw Exception('Failed to get audio URL');
        }

        final result = await DownloadService.instance.downloadSong(
          videoId: widget.song.videoId,
          audioUrl: audioUrl, // ✅ Now passing String instead of Function
          title: widget.song.title,
          artist: widget.song.artists,
          thumbnailUrl: widget.song.thumbnail,
          onProgress: (progress) {
            _updateDownloadNotification(
              title: 'Downloading',
              body: widget.song.title,
              progress: progress.toInt(), // ✅ FIX 3: Convert to double
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
  ) {
    final blurContainerSize = 325.0;
    final actualAlbumSize = 325.0;
    final artworkUrl =
        currentMedia?.artUri?.toString() ?? widget.song.thumbnail;

    return GestureDetector(
      onTap: () {
        // Toggle play/pause
        _audioService.playPause();
      },
      onVerticalDragStart: (details) {
        _swipeStart = details.globalPosition;
      },
      onVerticalDragUpdate: (details) {
        // Track swipe direction
      },
      onVerticalDragEnd: (details) {
        final delta = details.globalPosition.dy - _swipeStart.dy;

        // Swipe down - go back
        if (delta > 100) {
          Navigator.pop(context);
        }
        // Swipe up - show lyrics
        else if (delta < -100) {
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
        // Swipe right - previous song
        if (details.primaryVelocity! > 0) {
          _audioService.skipToPrevious();
        }
        // Swipe left - next song
        else if (details.primaryVelocity! < 0) {
          _audioService.skipToNext();
        }
      },
      child: Hero(
        tag: widget.heroTag ?? 'thumbnail-${widget.song.videoId}',
        child: AnimatedBuilder(
          animation: _albumArtController,
          builder: (context, child) {
            final scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(
                parent: _albumArtController,
                curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
              ),
            );

            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: _albumArtController,
                curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
              ),
            );

            final rotationAnimation = Tween<double>(begin: -0.05, end: 0.0)
                .animate(
                  CurvedAnimation(
                    parent: _albumArtController,
                    curve: Curves.easeOut,
                  ),
                );

            return Transform.scale(
              scale: scaleAnimation.value,
              child: Transform.rotate(
                angle: rotationAnimation.value,
                child: Opacity(
                  opacity: fadeAnimation.value,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Layer 1: Gaussian Blur Background
                        Container(
                          width: blurContainerSize,
                          height: blurContainerSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: (_albumPalette?.dominant ?? Colors.black)
                                    .withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (artworkUrl.isNotEmpty)
                                  // CHANGED: Use buildAlbumArtImage instead of Image.network
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
                                    sigmaX: 20,
                                    sigmaY: 20,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          (_albumPalette?.vibrant ??
                                                  Colors.purple)
                                              .withOpacity(0.3),
                                          (_albumPalette?.dominant ??
                                                  Colors.blue)
                                              .withOpacity(0.4),
                                          (_albumPalette?.muted ?? Colors.grey)
                                              .withOpacity(0.3),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Layer 2: Album Art
                        Container(
                          width: actualAlbumSize,
                          height: actualAlbumSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Artwork
                                artworkUrl.isNotEmpty
                                    ? buildAlbumArtImage(
                                        artworkUrl: artworkUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                _buildPlaceholder(),
                                      )
                                    : _buildPlaceholder(),

                                // Pause Overlay (Layer 2.5)
                                StreamBuilder<PlaybackState>(
                                  stream: _audioService.playbackStateStream,
                                  builder: (context, snapshot) {
                                    final isPlaying =
                                        snapshot.data?.playing ?? false;

                                    if (!isPlaying) {
                                      _pauseOverlayController.forward();
                                    } else {
                                      _pauseOverlayController.reverse();
                                    }

                                    return FadeTransition(
                                      opacity: _pauseOverlayController,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Layer 3: Lyrics Overlay
                        _buildLyricsOverlay(
                          actualAlbumSize,
                          currentMedia?.title ?? widget.song.title,
                        ),
                      ],
                    ),
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
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                (_albumPalette?.vibrant ?? Colors.purple).withOpacity(0.95),
                (_albumPalette?.dominant ?? Colors.blue).withOpacity(0.95),
                (_albumPalette?.muted ?? Colors.grey).withOpacity(0.95),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Close button
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _showLyrics = false;
                      _lyricsController.reverse();
                    });
                  },
                ),
              ),
              // Lyrics content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      songTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _getDummyLyrics(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // NEW: Dummy lyrics generator
  String _getDummyLyrics() {
    return '''
Every song has a story to tell
With melodies that cast a spell
Through the rhythm and the rhyme
We transcend both space and time

When the music starts to play
All our worries fade away
In this moment we are free
Lost in perfect harmony

Let the bass drop, feel the beat
Move your body, feel the heat
In this song we come alive
In this moment we survive

Every note a memory
Every chord a symphony
Close your eyes and feel the sound
Let the music take you down

This is where we belong
In the magic of this song
Together we are strong
Forever in this song
''';
  }

  // Build color gradient fallback
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: _audioService.mediaItemStream,
          builder: (context, mediaSnapshot) {
            final currentMedia = mediaSnapshot.data;

            // Update album art when media changes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleAlbumArtChange(currentMedia?.artUri?.toString());
            });

            return LayoutBuilder(
              builder: (context, constraints) {
                // Calculate responsive sizes based on available space
                final screenHeight = constraints.maxHeight;
                final screenWidth = constraints.maxWidth;

                // Dynamic sizing with constraints
                final topBarHeight = 56.0;
                final bottomControlsHeight = 80.0;
                final songInfoHeight = 100.0;
                final progressBarHeight = 80.0;
                final playerControlsHeight = 100.0;

                // Calculate remaining space for album art
                final remainingHeight =
                    screenHeight -
                    topBarHeight -
                    bottomControlsHeight -
                    songInfoHeight -
                    progressBarHeight -
                    playerControlsHeight -
                    60; // Additional padding

                // Album art size (constrained between min and max)
                final albumArtSize = 310.0;
                final albumArtPadding = (screenWidth - albumArtSize) / 2;

                return Column(
                  children: [
                    // Top bar with fade animation
                    FadeTransition(
                      opacity: _controlsController,
                      child: SizedBox(
                        height: topBarHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.expand_more,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Flexible spacer (takes remaining space evenly)
                    const Spacer(flex: 1),

                    // Album Art with Hero and animations
                    _buildAlbumArtWithBlur(
                      albumArtSize,
                      albumArtPadding,
                      currentMedia,
                    ),

                    const Spacer(flex: 1),

                    // Song Info with slide animation
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0.0, 0.3),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _controlsController,
                              curve: const Interval(
                                0.2,
                                0.8,
                                curve: Curves.easeOut,
                              ),
                            ),
                          ),
                      child: FadeTransition(
                        opacity: _controlsController,
                        child: Container(
                          height: songInfoHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                currentMedia?.title ?? widget.song.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: (screenWidth * 0.05).clamp(
                                    18.0,
                                    24.0,
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                currentMedia?.artist ?? widget.song.artists,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: (screenWidth * 0.04).clamp(
                                    14.0,
                                    16.0,
                                  ),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Progress Bar with fade
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _controlsController,
                        curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
                      ),
                      child: StreamBuilder<Duration>(
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
                                height: progressBarHeight,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24.0,
                                      ),
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 3,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                              ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 14,
                                              ),
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
                                          activeColor: Colors.white,
                                          inactiveColor: Colors.white
                                              .withOpacity(0.3),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32.0,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatDuration(position),
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.7,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(duration),
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.7,
                                              ),
                                              fontSize: 12,
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
                    ),

                    // Player Controls with scale animation
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _controlsController,
                          curve: const Interval(
                            0.4,
                            1.0,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                      ),
                      child: FadeTransition(
                        opacity: _controlsController,
                        child: StreamBuilder<PlaybackState>(
                          stream: _audioService.playbackStateStream,
                          builder: (context, snapshot) {
                            final playbackState = snapshot.data;
                            final isPlaying = playbackState?.playing ?? false;
                            final processingState =
                                playbackState?.processingState;

                            return SizedBox(
                              height: playerControlsHeight,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        widget.song.isFavorite
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: widget.song.isFavorite
                                            ? AppColors.error
                                            : Colors.white,
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

                                    IconButton(
                                      icon: const Icon(
                                        Icons.skip_previous,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                      onPressed: () {
                                        _audioService.skipToPrevious();
                                      },
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 64,
                                      height: 64,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: Icon(
                                          processingState ==
                                                  AudioProcessingState.loading
                                              ? Icons.hourglass_empty
                                              : isPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: Colors.black,
                                          size: 32,
                                        ),
                                        onPressed: () {
                                          _audioService.playPause();
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.skip_next,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                      onPressed: () {
                                        _audioService.skipToNext();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.repeat,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                      onPressed: () {},
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Bottom controls with fade
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _controlsController,
                        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
                      ),
                      child: SizedBox(
                        height: bottomControlsHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.playlist_play,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () {
                                  Navigator.of(context).pushFade(
                                    AudioGovernanceDebugScreen(
                                      audioManager: null,
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.radio,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: _showRadioBottomSheet,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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
    return Container(
      color: AppColors.cardBackground,
      child: const Center(
        child: Icon(Icons.music_note, size: 80, color: AppColors.iconInactive),
      ),
    );
  }

  void _handleAlbumArtChange(String? newArtUrl) {
    if (newArtUrl != _currentArtworkUrl) {
      setState(() {
        _albumArtController.reset();
        _currentArtworkUrl = newArtUrl;
      });
      _albumArtController.forward();

      // Reload colors when artwork changes
      if (newArtUrl != null && newArtUrl.isNotEmpty) {
        _loadAlbumColors();
      }
    }
  }

  // Create notification channel
  Future<void> _createNotificationChannel() async {
    await AwesomeNotifications().initialize(null, [
      NotificationChannel(
        channelKey: 'download_channel',
        channelName: 'Downloads',
        channelDescription: 'Download progress notifications',
        defaultColor: AppColors.iconActive,
        ledColor: Colors.white,
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: false,
        enableVibration: false,
      ),
    ]);
  }

  // Show download notification with progress
  Future<void> _showDownloadNotification({
    required String title,
    required String body,
    required int progress, // ✅ Use int - AwesomeNotifications expects int
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: widget.song.videoId.hashCode,
        channelKey: 'download_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.ProgressBar,
        progress: progress.toDouble(), // ✅ Pass int directly
        locked: true,
        category: NotificationCategory.Progress,
      ),
    );
  }

  // Update download notification progress
  void _updateDownloadNotification({
    required String title,
    required String body,
    required int progress, // ✅ Use int - AwesomeNotifications expects int
  }) {
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: widget.song.videoId.hashCode,
        channelKey: 'download_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.ProgressBar,
        progress: progress.toDouble(), // ✅ Pass int directly
        locked: progress < 100,
        category: NotificationCategory.Progress,
      ),
    );
  }

  // Show simple notification
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
    _controlsController.dispose();
    _lyricsController.dispose(); // NEW
    _pauseOverlayController.dispose(); // NEW
    super.dispose();
  }
}

// class _RadioBottomSheet extends StatefulWidget {
//   final String currentVideoId;
//   final String currentTitle;
//   final String currentArtist;
//   final AudioServices audioService;

//   const _RadioBottomSheet({
//     required this.currentVideoId,
//     required this.currentTitle,
//     required this.currentArtist,
//     required this.audioService,
//   });

//   @override
//   State<_RadioBottomSheet> createState() => _RadioBottomSheetState();
// }

// class _RadioBottomSheetState extends State<_RadioBottomSheet> {
//   final RadioService _radioService = RadioService();
//   List<QuickPick> radioSongs = [];
//   bool isLoading = true;
//   String? errorMessage;

//   @override
//   void initState() {
//     super.initState();
//     _loadRadio();
//   }

//   Future<void> _loadRadio() async {
//     setState(() {
//       isLoading = true;
//       errorMessage = null;
//     });

//     try {
//       final songs = await _radioService.getRadioForSong(
//         videoId: widget.currentVideoId,
//         title: widget.currentTitle,
//         artist: widget.currentArtist,
//         limit: 25,
//       );

//       if (mounted) {
//         setState(() {
//           radioSongs = songs;
//           isLoading = false;
//         });
//       }
//     } catch (e) {
//       print('Error loading radio: $e');
//       if (mounted) {
//         setState(() {
//           errorMessage = 'Failed to load similar songs';
//           isLoading = false;
//         });
//       }
//     }
//   }

//   String _formatDuration(int? seconds) {
//     if (seconds == null) return '';
//     final minutes = seconds ~/ 60;
//     final secs = seconds % 60;
//     return '$minutes:${secs.toString().padLeft(2, '0')}';
//   }

//   Future<void> _addToQueue(QuickPick song) async {
//     try {
//       await widget.audioService.addToQueue(song);

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Added "${song.title}" to queue'),
//             duration: const Duration(seconds: 2),
//             backgroundColor: AppColors.iconActive,
//           ),
//         );
//       }
//     } catch (e) {
//       print('Error adding to queue: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Failed to add to queue'),
//             duration: Duration(seconds: 2),
//             backgroundColor: AppColors.error,
//           ),
//         );
//       }
//     }
//   }

//   Future<void> _playNow(QuickPick song) async {
//     try {
//       await widget.audioService.playSong(song);

//       if (mounted) {
//         Navigator.pop(context);
//       }
//     } catch (e) {
//       print('Error playing song: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _radioService.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: MediaQuery.of(context).size.height * 0.7,
//       decoration: const BoxDecoration(
//         color: Color(0xFF1A1A1A),
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       child: Column(
//         children: [
//           // Handle bar
//           Container(
//             margin: const EdgeInsets.only(top: 12),
//             width: 40,
//             height: 4,
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.3),
//               borderRadius: BorderRadius.circular(2),
//             ),
//           ),

//           // Header
//           Padding(
//             padding: const EdgeInsets.all(20),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 const Text(
//                   'Radio - Similar Songs',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 IconButton(
//                   icon: const Icon(Icons.close, color: Colors.white),
//                   onPressed: () => Navigator.pop(context),
//                 ),
//               ],
//             ),
//           ),

//           // Content
//           Expanded(
//             child: isLoading
//                 ? const Center(
//                     child: CircularProgressIndicator(
//                       color: AppColors.iconActive,
//                     ),
//                   )
//                 : errorMessage != null
//                 ? Center(
//                     child: Column(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         const Icon(
//                           Icons.error_outline,
//                           color: Colors.white54,
//                           size: 48,
//                         ),
//                         const SizedBox(height: 16),
//                         Text(
//                           errorMessage!,
//                           style: const TextStyle(
//                             color: Colors.white54,
//                             fontSize: 16,
//                           ),
//                         ),
//                         const SizedBox(height: 16),
//                         ElevatedButton(
//                           onPressed: _loadRadio,
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: AppColors.iconActive,
//                           ),
//                           child: const Text('Retry'),
//                         ),
//                       ],
//                     ),
//                   )
//                 : radioSongs.isEmpty
//                 ? const Center(
//                     child: Text(
//                       'No similar songs found',
//                       style: TextStyle(color: Colors.white54, fontSize: 16),
//                     ),
//                   )
//                 : ListView.builder(
//                     itemCount: radioSongs.length,
//                     padding: const EdgeInsets.only(bottom: 20),
//                     itemBuilder: (context, index) {
//                       final song = radioSongs[index];

//                       return ListTile(
//                         contentPadding: const EdgeInsets.symmetric(
//                           horizontal: 20,
//                           vertical: 8,
//                         ),
//                         leading: ClipRRect(
//                           borderRadius: BorderRadius.circular(8),
//                           child: Container(
//                             width: 56,
//                             height: 56,
//                             color: AppColors.cardBackground,
//                             child: song.thumbnail.isNotEmpty
//                                 ? Image.network(
//                                     song.thumbnail,
//                                     fit: BoxFit.cover,
//                                     errorBuilder: (context, error, stackTrace) {
//                                       return const Icon(
//                                         Icons.music_note,
//                                         color: AppColors.iconInactive,
//                                       );
//                                     },
//                                   )
//                                 : const Icon(
//                                     Icons.music_note,
//                                     color: AppColors.iconInactive,
//                                   ),
//                           ),
//                         ),
//                         title: Text(
//                           song.title,
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 15,
//                             fontWeight: FontWeight.w500,
//                           ),
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                         subtitle: Text(
//                           song.artists,
//                           style: TextStyle(
//                             color: Colors.white.withOpacity(0.6),
//                             fontSize: 13,
//                           ),
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                         trailing: Row(
//                           mainAxisSize: MainAxisSize.min,
//                           children: [
//                             if (song.duration != null)
//                               Text(
//                                 song.duration?.isNotEmpty == true
//                                     ? song.duration!
//                                     : '0:00',
//                                 style: TextStyle(
//                                   color: Colors.white.withOpacity(0.5),
//                                   fontSize: 12,
//                                 ),
//                               ),
//                             const SizedBox(width: 8),
//                             PopupMenuButton(
//                               icon: const Icon(
//                                 Icons.more_vert,
//                                 color: Colors.white,
//                               ),
//                               color: const Color(0xFF2A2A2A),
//                               itemBuilder: (context) => [
//                                 PopupMenuItem(
//                                   onTap: () => _playNow(song),
//                                   child: const Row(
//                                     children: [
//                                       Icon(
//                                         Icons.play_arrow,
//                                         color: Colors.white,
//                                       ),
//                                       SizedBox(width: 12),
//                                       Text(
//                                         'Play now',
//                                         style: TextStyle(color: Colors.white),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                                 PopupMenuItem(
//                                   onTap: () => _addToQueue(song),
//                                   child: const Row(
//                                     children: [
//                                       Icon(
//                                         Icons.queue_music,
//                                         color: Colors.white,
//                                       ),
//                                       SizedBox(width: 12),
//                                       Text(
//                                         'Add to queue',
//                                         style: TextStyle(color: Colors.white),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ],
//                         ),
//                         onTap: () => _playNow(song),
//                       );
//                     },
//                   ),
//           ),
//         ],
//       ),
//     );
//   }
// }
