import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/thoughtsScreen.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/utils/album_color_generator.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/utils/material_transitions.dart';

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
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => useBetaPlayer
              ? NewPlayerPage(song: song, heroTag: heroTag)
              : PlayerScreen(song: song, heroTag: heroTag),
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final slideAnimation =
                Tween<Offset>(
                  begin: const Offset(0.0, 1.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );

            return SlideTransition(position: slideAnimation, child: child);
          },
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

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _rotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    // ✅ Load palette using initial song artwork
    _loadAlbumPalette(widget.song.thumbnail);

    _playInitialSong();

    // ✅ Listen to playback state changes for rotation control
    _audioService.playbackStateStream.listen((state) {
      if (mounted) {
        _updateRotation(state.playing);
      }
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _scaleController.forward();
      }
    });
  }

  Future<void> _playInitialSong() async {
    try {
      await _audioService.playSong(widget.song);
    } catch (e) {
      print('❌ [NewPlayerPage] Playback error: $e');
    }
  }

  Future<void> _loadAlbumPalette(String artworkUrl) async {
    if (artworkUrl.isEmpty || artworkUrl == _lastArtworkUrl) return;

    _lastArtworkUrl = artworkUrl;

    try {
      final palette = await AlbumColorGenerator.fromAnySource(artworkUrl);
      if (mounted) {
        setState(() => _albumPalette = palette);
      }
    } catch (_) {
      // fail silently – UI should never break
    }
  } // Add this method to handle play/pause state changes

  void _updateRotation(bool isPlaying) {
    if (isPlaying) {
      // Start continuous rotation
      _rotationController.repeat();
    } else {
      // Smoothly return to 0 position
      final currentValue = _rotationController.value;
      _rotationController.stop();

      // Animate to nearest 0 position (complete the current rotation)
      _rotationController
          .animateTo(
            1.0,
            duration: Duration(
              milliseconds: (800 * (1.0 - currentValue)).round(),
            ),
            curve: Curves.easeOut,
          )
          .then((_) {
            _rotationController.value = 0.0; // Reset to start
          });
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

                  return StreamBuilder<Duration>(
                    stream: _audioService.positionStream,
                    builder: (context, positionSnapshot) {
                      return StreamBuilder<Duration?>(
                        stream: _audioService.durationStream,
                        builder: (context, durationSnapshot) {
                          final position =
                              positionSnapshot.data ?? Duration.zero;
                          final duration =
                              durationSnapshot.data ?? Duration.zero;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top Bar
                                _buildTopBar(),

                                const SizedBox(height: 24),

                                // Song Title
                                _buildSongTitle(currentMedia),

                                const SizedBox(height: 32),

                                // Circular Album Art
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

                                // Playback Controls
                                _buildPlaybackControls(
                                  isPlaying,
                                  playbackSnapshot,
                                ),

                                const SizedBox(height: 30),

                                // // Next Songs Section
                                _buildNextSongsSection(),
                                const SizedBox(height: 20),
                              ],
                            ),
                          );
                        },
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentMedia?.title ?? widget.song.title,
                style: GoogleFonts.inter(
                  fontSize: 38,
                  fontWeight: FontWeight.w300, // Very thin, like in image
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                currentMedia?.artist ?? widget.song.artists,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500, // Light weight
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
        IconButton(
          icon: Icon(
            _isLiked ? Icons.favorite : Icons.favorite_border,
            color: _isLiked ? Colors.red : Colors.white,
            size: 26,
          ),
          onPressed: () {
            setState(() {
              _isLiked = !_isLiked;
            });
          },
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
    final artworkUrl =
        currentMedia?.artUri?.toString() ?? widget.song.thumbnail;

    final palette = _albumPalette;

    return AnimatedBuilder(
      animation: Listenable.merge([_scaleController, _rotationController]),
      builder: (context, child) {
        final scaleValue = Tween<double>(begin: 0.8, end: 1.0)
            .animate(
              CurvedAnimation(
                parent: _scaleController,
                curve: Curves.easeOutCubic,
              ),
            )
            .value;

        final rotationValue = _rotationController.value;

        return Transform.scale(
          scale: scaleValue,
          child: GestureDetector(
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
                // 🌈 PALETTE GLOW (PERFECT CIRCLE)
                if (palette != null)
                  Transform.rotate(
                    angle: rotationValue * 2 * pi,
                    child: Container(
                      width: 420,
                      height: 420,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: palette.vibrant.withOpacity(0.55),
                            blurRadius: 50,
                            spreadRadius: 12,
                          ),
                          BoxShadow(
                            color: palette.dominant.withOpacity(0.35),
                            blurRadius: 23,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),

                // 🖤 FALLBACK DARK RING (while palette loads)
                if (palette == null)
                  Transform.rotate(
                    angle: rotationValue * 2 * pi,
                    child: Container(
                      width: 390,
                      height: 390,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2F2F2F), Color(0xFF1A1A1A)],
                        ),
                      ),
                    ),
                  ),

                // 💿 ALBUM FRAME (with rotation when playing)
                Transform.rotate(
                  angle: rotationValue * 2 * pi,
                  child: Container(
                    width: 350,
                    height: 350,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3D3D3D), Color(0xFF1F1F1F)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.75),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (artworkUrl.isNotEmpty)
                            buildAlbumArtImage(
                              artworkUrl: artworkUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPlaceholder(),
                            )
                          else
                            _buildPlaceholder(),

                          // 🎚 Subtle vignette
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.25),
                                ],
                              ),
                            ),
                          ),

                          // 🔘 PAUSE OVERLAY (60% dim when paused)
                          AnimatedOpacity(
                            opacity: isPlaying ? 0.0 : 0.6,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: Container(color: Colors.black),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ⏱ TIME BADGE
                Positioned(
                  bottom: -12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                            width: 0.5,
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
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  Widget _buildPlaybackControls(
    bool isPlaying,
    AsyncSnapshot<PlaybackState> playbackSnapshot,
  ) {
    return Column(
      children: [
        // Main playback controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous
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

            // Play/Pause
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
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  playbackSnapshot.data?.processingState ==
                          AudioProcessingState.loading
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

            // Next
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

        // Shuffle and Repeat controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle button

            // Shuffle button
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
                      setState(() {}); // Force rebuild to show updated state
                    }
                  },
                  padding: EdgeInsets.zero,
                );
              },
            ),

            const SizedBox(width: 60),

            // Repeat/Loop button
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
      ],
    );
  }

  Widget _buildNextSongsSection() {
    final handler = getAudioHandler();

    if (handler == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<MediaItem>>(
      stream: handler.queue,
      builder: (context, queueSnapshot) {
        final queue = queueSnapshot.data ?? [];

        return StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (context, mediaSnapshot) {
            final currentMedia = mediaSnapshot.data;

            // Filter to get only upcoming songs
            final upcomingSongs = queue.where((item) {
              if (currentMedia == null) return true;
              final currentIndex = queue.indexOf(currentMedia);
              final itemIndex = queue.indexOf(item);
              return itemIndex > currentIndex;
            }).toList();

            // If no upcoming songs, show placeholder
            if (upcomingSongs.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 1, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 18),
                  Text(
                    'Next Songs',
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          color: Colors.white.withOpacity(0.4),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Auto-playing similar songs',
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // Show first upcoming song
            final nextSong = upcomingSongs.first;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 1, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 18),
                Text(
                  'Next Songs',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: nextSong.artUri != null
                            ? Image.network(
                                nextSong.artUri.toString(),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _buildNextSongPlaceholder(),
                              )
                            : _buildNextSongPlaceholder(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nextSong.title,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Auto-playing next',
                              style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (nextSong.duration != null)
                        Text(
                          _formatDuration(nextSong.duration),
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
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
    );
  }

  // ==================== HELPER METHOD FOR NEXT SONG PLACEHOLDER ====================
  Widget _buildNextSongPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white70,
        size: 24,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _rotationController.dispose();
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
