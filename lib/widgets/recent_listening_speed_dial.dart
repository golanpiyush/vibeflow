// lib/widgets/recent_listening_speed_dial.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/last_played_service.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/widgets/shimmer_loadings.dart';

// Cache entry model
class CachedSong {
  final QuickPick song;
  final String audioUrl;
  final DateTime cachedAt;

  CachedSong({
    required this.song,
    required this.audioUrl,
    required this.cachedAt,
  });

  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(cachedAt) > maxAge;
  }
}

// Audio URL Cache Manager
class AudioUrlCache {
  static final AudioUrlCache _instance = AudioUrlCache._internal();
  factory AudioUrlCache() => _instance;
  AudioUrlCache._internal();

  final Map<String, CachedSong> _cache = {};

  // Add or update cache entry
  void cache(QuickPick song, String audioUrl) {
    _cache[song.videoId] = CachedSong(
      song: song,
      audioUrl: audioUrl,
      cachedAt: DateTime.now(),
    );
    print('✅ Cached URL for: ${song.title} (${_cache.length} total)');
  }

  // Get cached URL if not expired
  String? getCachedUrl(
    String videoId, {
    Duration maxAge = const Duration(hours: 6),
  }) {
    final entry = _cache[videoId];
    if (entry != null && !entry.isExpired(maxAge)) {
      return entry.audioUrl;
    }
    return null;
  }

  // Get all recent songs with valid cache (younger than maxAge)
  List<QuickPick> getRecentSongs({
    Duration maxAge = const Duration(hours: 6),
    int limit = 9,
  }) {
    final now = DateTime.now();
    final recentSongs =
        _cache.values
            .where((entry) => now.difference(entry.cachedAt) <= maxAge)
            .toList()
          ..sort(
            (a, b) => b.cachedAt.compareTo(a.cachedAt),
          ); // Most recent first

    return recentSongs.take(limit).map((entry) => entry.song).toList();
  }

  // Remove expired entries
  void cleanExpired({Duration maxAge = const Duration(hours: 6)}) {
    _cache.removeWhere((key, value) => value.isExpired(maxAge));
    print('🧹 Cleaned cache, ${_cache.length} entries remain');
  }

  // Get cache statistics
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    final under1h = _cache.values
        .where((e) => now.difference(e.cachedAt).inHours < 1)
        .length;
    final under3h = _cache.values
        .where((e) => now.difference(e.cachedAt).inHours < 3)
        .length;
    final under6h = _cache.values
        .where((e) => now.difference(e.cachedAt).inHours < 6)
        .length;

    return {
      'total': _cache.length,
      'under_1h': under1h,
      'under_3h': under3h,
      'under_6h': under6h,
    };
  }

  // Clear all cache
  void clearAll() {
    _cache.clear();
    print('🗑️ All cache cleared');
  }
}

class RecentListeningSpeedDial extends ConsumerStatefulWidget {
  const RecentListeningSpeedDial({Key? key}) : super(key: key);

  @override
  ConsumerState<RecentListeningSpeedDial> createState() =>
      _RecentListeningSpeedDialState();
}

class _RecentListeningSpeedDialState
    extends ConsumerState<RecentListeningSpeedDial>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  List<QuickPick>? _recentSongs;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  final _audioCache = AudioUrlCache();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.75).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _loadRecentSongs();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _loadRecentSongs() {
    setState(() => _isLoading = true);

    try {
      // Clean expired entries first
      _audioCache.cleanExpired();

      // Get recent songs from cache (last 6 hours)
      final recentSongs = _audioCache.getRecentSongs(
        maxAge: const Duration(hours: 6),
        limit: 9,
      );

      final stats = _audioCache.getStats();
      print(
        '📊 Cache Stats: ${stats['total']} total, ${stats['under_6h']} under 6h',
      );
      print('✅ Found ${recentSongs.length} recent songs with cached URLs');

      setState(() {
        _recentSongs = recentSongs;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading recent songs: $e');
      setState(() {
        _recentSongs = [];
        _isLoading = false;
      });
    }
  }

  void _toggleSpeedDial() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animationController.forward();
        _loadRecentSongs(); // Refresh on open
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final backgroundColor = ref.watch(themeBackgroundColorProvider);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Overlay
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleSpeedDial,
              child: Container(color: Colors.black.withOpacity(0.5)),
            ),
          ),

        // Speed dial button options
        if (_isOpen)
          Positioned(
            bottom: 80,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              tween: Tween(begin: 0.0, end: 1.0),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: FloatingActionButton.extended(
                heroTag: 'recent_listening_option',
                backgroundColor: iconActiveColor.withOpacity(0.95),
                onPressed: () {
                  _toggleSpeedDial();
                  _showRecentListeningDialog();
                },
                icon: Icon(Icons.history, color: backgroundColor),
                label: Text(
                  'Recent Listening',
                  style: TextStyle(
                    color: backgroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

        // Main FAB
        FloatingActionButton(
          heroTag: 'recent_listening_main',
          backgroundColor: iconActiveColor,
          onPressed: _toggleSpeedDial,
          child: AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationAnimation.value * 3.14159 * 2,
                child: Icon(
                  _isOpen ? Icons.close : Icons.music_note,
                  color: backgroundColor,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRecentListeningDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => _RecentListeningDialog(
        recentSongs: _recentSongs,
        isLoading: _isLoading,
        onRefresh: _loadRecentSongs,
      ),
    );
  }
}

class _RecentListeningDialog extends ConsumerWidget {
  final List<QuickPick>? recentSongs;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _RecentListeningDialog({
    required this.recentSongs,
    required this.isLoading,
    required this.onRefresh,
  });

  Future<void> _playSong(BuildContext context, QuickPick song) async {
    try {
      // Save last played
      await LastPlayedService.saveLastPlayed(song);

      // Navigate to player
      if (context.mounted) {
        Navigator.of(context).pop(); // Close dialog first
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                PlayerScreen(song: song, heroTag: 'recent-${song.videoId}'),
          ),
        );
      }
    } catch (e) {
      print('❌ Error playing song: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        tween: Tween(begin: 0.0, end: 1.0),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(
            scale: 0.8 + (0.2 * value),
            child: Opacity(opacity: value, child: child),
          );
        },
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Listening',
                        style: AppTypography.sectionHeader.copyWith(
                          color: textPrimaryColor,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last 6 hours • Cached URLs',
                        style: AppTypography.caption.copyWith(
                          color: textSecondaryColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.refresh, color: iconActiveColor),
                        onPressed: onRefresh,
                        tooltip: 'Refresh',
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: iconActiveColor),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Content
              Expanded(
                child: isLoading
                    ? _buildLoadingGrid(ref)
                    : (recentSongs == null || recentSongs!.isEmpty)
                    ? _buildEmptyState(ref)
                    : _buildSongsGrid(
                        recentSongs!,
                        ref,
                        cardBackgroundColor,
                        textPrimaryColor,
                        textSecondaryColor,
                        thumbnailRadius,
                        context,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingGrid(WidgetRef ref) {
    return ShimmerLoading(
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: 9,
        itemBuilder: (context, index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(
                width: double.infinity,
                height: 100,
                borderRadius: 12,
              ),
              const SizedBox(height: 8),
              SkeletonBox(width: double.infinity, height: 14, borderRadius: 4),
              const SizedBox(height: 4),
              SkeletonBox(width: 60, height: 12, borderRadius: 4),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lottie Animation
          SizedBox(
            width: 200,
            height: 200,
            child: Lottie.network(
              'https://assets5.lottiefiles.com/packages/lf20_khzniaya.json',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.headphones_outlined,
                  size: 100,
                  color: textSecondaryColor.withOpacity(0.5),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Start Listening',
            style: AppTypography.sectionHeader.copyWith(
              color: textPrimaryColor,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Play some songs and they\'ll\nappear here for quick access',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: textSecondaryColor.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongsGrid(
    List<QuickPick> songs,
    WidgetRef ref,
    Color cardBackgroundColor,
    Color textPrimaryColor,
    Color textSecondaryColor,
    double thumbnailRadius,
    BuildContext context,
  ) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return _buildSongCard(
          song,
          cardBackgroundColor,
          textPrimaryColor,
          textSecondaryColor,
          thumbnailRadius,
          index,
          context,
        );
      },
    );
  }

  Widget _buildSongCard(
    QuickPick song,
    Color cardBackgroundColor,
    Color textPrimaryColor,
    Color textSecondaryColor,
    double thumbnailRadius,
    int index,
    BuildContext context,
  ) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTap: () => _playSong(context, song),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Art
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cardBackgroundColor,
                  borderRadius: BorderRadius.circular(12 * thumbnailRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12 * thumbnailRadius),
                  child: song.thumbnail.isNotEmpty
                      ? Stack(
                          children: [
                            Image.network(
                              song.thumbnail,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    Icons.music_note,
                                    color: textSecondaryColor.withOpacity(0.5),
                                    size: 32,
                                  ),
                                );
                              },
                            ),
                            // Play overlay
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.3),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Icon(
                            Icons.music_note,
                            color: textSecondaryColor.withOpacity(0.5),
                            size: 32,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              song.title,
              style: AppTypography.subtitle.copyWith(
                color: textPrimaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // Artists
            Text(
              song.artists,
              style: AppTypography.caption.copyWith(
                color: textSecondaryColor,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
