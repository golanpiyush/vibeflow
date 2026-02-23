// lib/widgets/global_miniplayer.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/main.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/providers/immersive_mode_provider.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/last_played_service.dart';
import 'package:vibeflow/utils/album_color_generator.dart';

const double kMiniplayerHeight = 70.0;

class GlobalMiniplayer extends ConsumerStatefulWidget {
  const GlobalMiniplayer({Key? key}) : super(key: key);

  @override
  ConsumerState<GlobalMiniplayer> createState() => _GlobalMiniplayerState();
}

class _GlobalMiniplayerState extends ConsumerState<GlobalMiniplayer> {
  final _audioService = AudioServices.instance;

  AlbumPalette? _cachedPalette;
  String? _cachedArtworkUrl;
  bool _isExtractingColors = false;
  QuickPick? _lastPlayed;

  // ✅ FIX: Track navigation state to prevent duplicate pushes
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _loadLastPlayed();
  }

  Future<void> _loadLastPlayed() async {
    final last = await LastPlayedService.getLastPlayed();
    if (!mounted) return;
    setState(() => _lastPlayed = last);
  }

  Future<void> _extractColorsIfNeeded(String url) async {
    if (url.isEmpty || url == _cachedArtworkUrl || _isExtractingColors) return;
    _isExtractingColors = true;
    _cachedArtworkUrl = url;
    try {
      final palette = await AlbumColorGenerator.fromAnySource(url);
      if (mounted) setState(() => _cachedPalette = palette);
    } catch (_) {
      // Fall back to defaults
    } finally {
      _isExtractingColors = false;
    }
  }

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ✅ FIX: Centralized navigation method with full duplicate-push protection
  Future<void> _openPlayer(QuickPick song) async {
    // Guard 1: Already navigating from this miniplayer instance
    if (_isNavigating) {
      print('⚠️ [Miniplayer] Already navigating, ignoring tap');
      return;
    }

    // Guard 2: Player page is already open (isMiniplayerVisible is false
    // because new_player_page sets it false in initState and true in dispose)
    if (!isMiniplayerVisible.value) {
      print(
        '⚠️ [Miniplayer] Player already open (miniplayer hidden), ignoring tap',
      );
      return;
    }

    // Guard 3: Check the actual navigator stack
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    // If we can pop AND the miniplayer is somehow visible, something is off —
    // trust isMiniplayerVisible as the canonical signal and bail.
    if (!isMiniplayerVisible.value) return;

    _isNavigating = true;
    try {
      await NewPlayerPage.openWithNavigator(
        nav,
        song,
        heroTag: 'global-mini-${song.videoId}',
      );
    } finally {
      if (mounted) {
        _isNavigating = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImmersive = ref.watch(immersiveModeProvider);
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.padding.bottom;
    final hasVisibleNavBar = bottomInset > 24;

    return StreamBuilder<MediaItem?>(
      stream: _audioService.mediaItemStream,
      builder: (context, snapshot) {
        final currentMedia = snapshot.data;
        if (currentMedia == null && _lastPlayed == null) {
          return const SizedBox.shrink();
        }

        final song = currentMedia != null
            ? QuickPick(
                videoId: currentMedia.id,
                title: currentMedia.title,
                artists: currentMedia.artist ?? '',
                thumbnail: currentMedia.artUri?.toString() ?? '',
                duration: currentMedia.duration != null
                    ? _fmt(currentMedia.duration!.inSeconds)
                    : null,
              )
            : _lastPlayed!;

        if (song.thumbnail.isNotEmpty) {
          _extractColorsIfNeeded(song.thumbnail);
        }

        final dominant = _cachedPalette?.dominant ?? const Color(0xFF1A1A1A);
        final muted = _cachedPalette?.muted ?? const Color(0xFF2A2A2A);
        final vibrant = _cachedPalette?.vibrant ?? dominant;

        final double bottomPosition = isImmersive
            ? 0
            : (hasVisibleNavBar ? bottomInset : bottomInset);

        return Positioned(
          left: 0,
          right: 0,
          bottom: bottomPosition,
          child: _buildContent(
            song,
            currentMedia,
            dominant,
            muted,
            vibrant,
            isImmersive,
            hasVisibleNavBar,
            bottomInset,
          ),
        );
      },
    );
  }

  Widget _buildContent(
    QuickPick song,
    MediaItem? currentMedia,
    Color dominant,
    Color muted,
    Color vibrant,
    bool isImmersive,
    bool hasVisibleNavBar,
    double bottomInset,
  ) {
    return StreamBuilder<PlaybackState>(
      stream: _audioService.playbackStateStream,
      builder: (context, playbackSnap) {
        final isPlaying = playbackSnap.data?.playing ?? false;
        final processingState =
            playbackSnap.data?.processingState ?? AudioProcessingState.idle;
        final isLoading = processingState == AudioProcessingState.loading;

        return StreamBuilder<Duration>(
          stream: _audioService.positionStream,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            final duration = currentMedia?.duration ?? Duration.zero;
            final progress = duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  )
                : 0.0;

            final extraBottom = isImmersive && hasVisibleNavBar
                ? bottomInset
                : 0.0;
            final totalHeight = kMiniplayerHeight + extraBottom;

            return Material(
              color: Colors.transparent,
              child: GestureDetector(
                // ✅ FIX: Use _openPlayer which has full duplicate-push protection
                onTap: () => _openPlayer(song),
                child: Container(
                  height: totalHeight,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        dominant.withOpacity(0.97),
                        muted.withOpacity(0.92),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // ── Vibrant played-portion fill ───────────────────
                      if (progress > 0)
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    vibrant.withOpacity(0.50),
                                    vibrant.withOpacity(0.25),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // // ── Glowing progress line at top ──────────────────
                      // if (progress > 0)
                      //   Positioned(
                      //     top: 0,
                      //     left: 0,
                      //     right: 0,
                      //     child: LayoutBuilder(
                      //       builder: (context, constraints) => Container(
                      //         height: 2.5,
                      //         width: constraints.maxWidth * progress,
                      //         decoration: BoxDecoration(
                      //           color: vibrant,
                      //           borderRadius: const BorderRadius.only(
                      //             topRight: Radius.circular(2),
                      //             bottomRight: Radius.circular(2),
                      //           ),
                      //           boxShadow: [
                      //             BoxShadow(
                      //               color: vibrant.withOpacity(0.85),
                      //               blurRadius: 8,
                      //               spreadRadius: 1,
                      //             ),
                      //           ],
                      //         ),
                      //       ),
                      //     ),
                      //   ),

                      // ── Main row ──────────────────────────────────────
                      SizedBox(
                        height: kMiniplayerHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              // Thumbnail
                              Hero(
                                tag: 'global-mini-${song.videoId}',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 54,
                                    height: 54,
                                    child: song.thumbnail.isNotEmpty
                                        ? Image.network(
                                            song.thumbnail,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _fallback(),
                                          )
                                        : _fallback(),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              // Title + Artist
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentMedia?.title ?? song.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.none,
                                        decorationColor: Colors.transparent,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      currentMedia?.artist ?? song.artists,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                        decoration: TextDecoration.none,
                                        decorationColor: Colors.transparent,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),

                              // Play / Pause
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: isLoading
                                    ? const Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          isPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        onPressed: () async {
                                          if (isPlaying) {
                                            await _audioService.pause();
                                          } else if (processingState ==
                                                  AudioProcessingState.idle ||
                                              processingState ==
                                                  AudioProcessingState.error) {
                                            await _audioService.playSong(song);
                                          } else {
                                            await _audioService.play();
                                          }
                                        },
                                      ),
                              ),

                              // Skip next
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.skip_next,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: () => _audioService.skipToNext(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _fallback() => Container(
    color: Colors.grey.shade900,
    child: const Icon(Icons.music_note, color: Colors.grey, size: 24),
  );

  @override
  void dispose() {
    _lastPlayed = null;
    super.dispose();
  }
}
