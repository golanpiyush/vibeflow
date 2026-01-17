// lib/pages/home_page.dart
// ignore_for_file: unused_local_variable

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miniplayer/miniplayer.dart';
import 'package:vibeflow/api_base/yt_music_search_suggestor.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/api_base/ytmusic_search_helper.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/pages/access_code_management_screen.dart';
import 'package:vibeflow/pages/album_view.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/artist_view.dart';
import 'package:vibeflow/pages/authOnboard/Screens/social_feed_page.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/pages/subpages/songs/albums.dart';
import 'package:vibeflow/pages/subpages/songs/albums_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/artists.dart';
import 'package:vibeflow/pages/subpages/songs/artists_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/last_played_service.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/widgets/recent_listening_speed_dial.dart';
import 'package:vibeflow/widgets/search_suggestions_widget.dart';
import 'package:vibeflow/widgets/shimmer_loadings.dart';
import 'package:vibeflow/api_base/ytmusic_artists_scraper.dart';
import 'package:vibeflow/api_base/scrapper.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/player_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _scrollController = ScrollController();
  final YouTubeMusicScraper _scraper = YouTubeMusicScraper();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final ValueNotifier<QuickPick?> _lastPlayedNotifier;

  Timer? _debounceTimer;
  final Duration _debounceDuration = const Duration(milliseconds: 500);

  late final YTMusicAlbumsScraper _albumsScraper;
  late final YTMusicArtistsScraper _artistsScraper;
  late final YTMusicSearchHelper _searchHelper;

  List<QuickPick> quickPicks = [];
  bool isLoadingQuickPicks = false;
  bool isSearchMode = false;

  List<Album> relatedAlbums = [];
  bool isLoadingAlbums = false;

  List<Artist> similarArtists = []; // Replace the dummy data
  bool isLoadingArtists = false;

  List<Song> searchResults = [];
  bool isSearching = false;

  final _audioService = AudioServices.instance;
  final MiniplayerController _miniplayerController = MiniplayerController();
  QuickPick? _lastPlayedSong;

  static const double _miniplayerMinHeight = 70.0;
  static const double _miniplayerMaxHeight = 370.0;

  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _albumsScraper = YTMusicAlbumsScraper();
    _artistsScraper = YTMusicArtistsScraper(); // Initialize
    _searchHelper = YTMusicSearchHelper();
    _lastPlayedNotifier = ValueNotifier<QuickPick?>(null);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      print('✅ YoutubeExplode initialized');

      // Load content in parallel
      await Future.wait([
        _loadQuickPicks(),
        _loadAlbums(),
        _loadArtists(),
        _fetchRandomArtists(),
        _loadLastPlayedSong(),
      ]);
    } catch (e) {
      print('❌ Error initializing app: $e');
    }
  }

  Future<void> _loadQuickPicks() async {
    setState(() => isLoadingQuickPicks = true);

    try {
      final songs = await _scraper.getQuickPicks(limit: 40);

      setState(() {
        quickPicks = songs.map((song) => QuickPick.fromSong(song)).toList();
        isLoadingQuickPicks = false;
      });
    } catch (e) {
      print('Error loading quick picks: $e');
      setState(() => isLoadingQuickPicks = false);
    }
  }

  Future<void> _loadAlbums() async {
    setState(() => isLoadingAlbums = true);

    try {
      final albums = await _albumsScraper.getMixedRandomAlbums(limit: 25);

      print('✅ Found ${albums.length} albums');

      setState(() {
        relatedAlbums = albums;
        isLoadingAlbums = false;
      });
    } catch (e, stack) {
      print('❌ Error loading albums: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      setState(() => isLoadingAlbums = false);
    }
  }

  Future<void> _loadArtists() async {
    setState(() => isLoadingArtists = true);

    try {
      final artists = await _artistsScraper.getTrendingArtists(limit: 10);

      print('✅ Found ${artists.length} artists');

      setState(() {
        similarArtists = artists;
        isLoadingArtists = false;
      });
    } catch (e, stack) {
      print('❌ Error loading artists: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      setState(() => isLoadingArtists = false);
    }
  }

  Future<void> _loadLastPlayedSong() async {
    final lastPlayed = await LastPlayedService.getLastPlayed();
    if (mounted) {
      _lastPlayedNotifier.value = lastPlayed;
    }
  }

  // Method to fetch random artists with images
  Future<void> _fetchRandomArtists() async {
    setState(() {
      isLoadingArtists = true;
    });

    try {
      final scraper = YTMusicArtistsScraper();

      // Fetch more artists to ensure we get 25+ with images
      final artists = await scraper.getRandomArtists(count: 50);

      // Filter to only artists with profile images
      final artistsWithImages = artists
          .where(
            (artist) =>
                artist.profileImage != null && artist.profileImage!.isNotEmpty,
          )
          .toList();

      // Take at least 25, or all if less
      setState(() {
        similarArtists = artistsWithImages.take(30).toList();
        isLoadingArtists = false;
      });

      print('✅ Loaded ${similarArtists.length} artists with images');
    } catch (e) {
      print('❌ Error fetching random artists: $e');
      setState(() {
        isLoadingArtists = false;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    // Cancel previous timer if it exists
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    // Show loading immediately
    setState(() => isSearching = true);

    // Start new debounce timer
    _debounceTimer = Timer(_debounceDuration, () async {
      try {
        final results = await _searchHelper.searchSongs(query, limit: 50);

        if (mounted) {
          setState(() {
            searchResults = results;
            isSearching = false;
          });

          // Save to history after successful search
          final suggestionsHelper = YTMusicSuggestionsHelper();
          await suggestionsHelper.saveToHistory(query);
          suggestionsHelper.dispose();
        }
      } catch (e) {
        print('Error searching: $e');
        if (mounted) {
          setState(() => isSearching = false);
        }
      }
    });
  }

  Future<void> _performSearchImmediately(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    setState(() => isSearching = true);

    try {
      final results = await _searchHelper.searchSongs(query, limit: 50);

      if (mounted) {
        setState(() {
          searchResults = results;
          isSearching = false;
        });

        // Save to history
        final suggestionsHelper = YTMusicSuggestionsHelper();
        await suggestionsHelper.saveToHistory(query);
        suggestionsHelper.dispose();
      }
    } catch (e) {
      print('Error searching: $e');
      if (mounted) {
        setState(() => isSearching = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _currentQuery = query; // Update current query for suggestions widget
    });
    _performSearch(query); // This handles debounced actual search
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Row(
              children: [
                _buildSidebar(context),
                Expanded(
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.xxxl),
                      _buildTopBar(ref),
                      Expanded(
                        child: isSearchMode
                            ? _buildSearchView()
                            : SingleChildScrollView(
                                controller: _scrollController,
                                padding: EdgeInsets.only(
                                  left: AppSpacing.lg,
                                  right: AppSpacing.lg,
                                  top: AppSpacing.lg,
                                  bottom: _lastPlayedSong != null
                                      ? 180
                                      : 120, // Increased from 90/20 to 180/120
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildQuickPicks(),
                                    const SizedBox(height: AppSpacing.xxxl),
                                    _buildAlbums(),
                                    const SizedBox(height: AppSpacing.xxxl),
                                    _buildSimilarArtists(),
                                    const SizedBox(
                                      height: 20,
                                    ), // Additional spacing after artists
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Miniplayer overlay
          ValueListenableBuilder<QuickPick?>(
            valueListenable: _lastPlayedNotifier,
            builder: (context, lastPlayed, _) {
              return StreamBuilder<MediaItem?>(
                stream: _audioService.mediaItemStream,
                builder: (context, snapshot) {
                  final currentMedia = snapshot.data;
                  final shouldShow = currentMedia != null || lastPlayed != null;
                  if (!shouldShow) return const SizedBox.shrink();

                  final displaySong = currentMedia != null
                      ? QuickPick(
                          videoId: currentMedia.id,
                          title: currentMedia.title,
                          artists: currentMedia.artist ?? '',
                          thumbnail: currentMedia.artUri?.toString() ?? '',
                          duration: currentMedia.duration != null
                              ? _formatDuration(
                                  currentMedia.duration!.inSeconds,
                                )
                              : null,
                        )
                      : lastPlayed!;

                  return Miniplayer(
                    controller: _miniplayerController,
                    minHeight: _miniplayerMinHeight,
                    maxHeight: _miniplayerMinHeight,
                    builder: (height, percentage) =>
                        _buildMiniPlayer(displaySong, currentMedia),
                  );
                },
              );
            },
          ),
        ],
      ),
      // FLOATING ACTION BUTTONS - Stack for multiple FABs
      floatingActionButton: Stack(
        children: [
          // Recent Listening Speed Dial - Center position
          // Positioned(
          //   bottom: 40,
          //   left:
          //       MediaQuery.of(context).size.width / 2 -
          //       28, // Center it (28 = half of FAB width)
          //   child: const RecentListeningSpeedDial(),
          // ),

          // Search FAB - Right position
          Positioned(
            bottom: 40,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'search_fab',
              onPressed: () {
                setState(() {
                  isSearchMode = !isSearchMode;
                  if (isSearchMode) {
                    _searchFocusNode.requestFocus();
                  } else {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                    searchResults = [];
                  }
                });
              },
              backgroundColor: iconActiveColor,
              child: Icon(
                isSearchMode ? Icons.close : Icons.search,
                color: backgroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Updated _buildSearchView method
  // Update the _buildSearchView method to use theme colors
  Widget _buildSearchView() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final accentColor = ref.watch(themeAccentColorProvider);
    final showSuggestions = searchResults.isEmpty && !isSearching;

    return Column(
      children: [
        if (showSuggestions)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: SearchSuggestionsWidget(
                key: ValueKey(_currentQuery),
                query: _currentQuery,
                onSuggestionTap: (suggestion) {
                  _searchController.text = suggestion;
                  setState(() {
                    _currentQuery = suggestion;
                  });
                  _debounceTimer?.cancel();
                  _performSearchImmediately(suggestion);
                  FocusScope.of(context).unfocus();
                },
                onClearHistory: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Search history cleared'),
                      duration: const Duration(seconds: 2),
                      backgroundColor: accentColor,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                },
              ),
            ),
          )
        else
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 0.02),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                );
              },
              child: isSearching
                  ? ShimmerLoading(
                      key: const ValueKey('loading'),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 80, height: 24, borderRadius: 4),
                            const SizedBox(height: AppSpacing.md),
                            ...List.generate(8, (index) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                height: 70,
                                child: Row(
                                  children: [
                                    SkeletonBox(
                                      width: 54,
                                      height: 54,
                                      borderRadius: 6,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SkeletonBox(
                                            width: double.infinity,
                                            height: 16,
                                            borderRadius: 4,
                                          ),
                                          const SizedBox(height: 6),
                                          SkeletonBox(
                                            width: 150,
                                            height: 12,
                                            borderRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SkeletonBox(
                                      width: 35,
                                      height: 11,
                                      borderRadius: 4,
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    )
                  : searchResults.isNotEmpty
                  ? SingleChildScrollView(
                      key: ValueKey('results-${searchResults.length}'),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 10 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              'Results',
                              style: AppTypography.sectionHeader.copyWith(
                                color: textPrimaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ...searchResults.asMap().entries.map((entry) {
                            final index = entry.key;
                            final song = entry.value;
                            final durationInSeconds = song.duration != null
                                ? _parseDurationToSeconds(song.duration!)
                                : null;

                            return TweenAnimationBuilder<double>(
                              duration: Duration(
                                milliseconds: 350 + (index * 40),
                              ),
                              curve: Curves.easeOutCubic,
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 15 * (1 - value)),
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildSearchResultItem(
                                videoId: song.videoId,
                                title: song.title,
                                subtitle: song.artists.join(', '),
                                thumbnail: song.thumbnail,
                                duration: durationInSeconds,
                                formattedDuration: song.duration,
                                onTap: () async {
                                  final helper = YTMusicSuggestionsHelper();
                                  await helper.saveToHistory(
                                    _searchController.text,
                                  );
                                  helper.dispose();

                                  final quickPick = QuickPick(
                                    videoId: song.videoId,
                                    title: song.title,
                                    artists: song.artists.join(', '),
                                    thumbnail: song.thumbnail,
                                    duration: song.duration,
                                  );

                                  await LastPlayedService.saveLastPlayed(
                                    quickPick,
                                  );
                                  setState(() {
                                    _lastPlayedSong = quickPick;
                                  });

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          PlayerScreen(song: quickPick),
                                    ),
                                  );
                                },
                                ref: ref,
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    )
                  : Center(
                      key: const ValueKey('empty'),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.music_off,
                              size: 64,
                              color: textSecondaryColor.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No results found',
                              style: AppTypography.subtitle.copyWith(
                                color: textSecondaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try a different search term',
                              style: AppTypography.caption.copyWith(
                                color: textSecondaryColor.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  // Updated _buildSearchResultItem signature (same as before):
  Widget _buildSearchResultItem({
    required String videoId,
    required String title,
    required String subtitle,
    required String thumbnail,
    int? duration,
    String? formattedDuration,
    required VoidCallback onTap,
    required WidgetRef ref,
  }) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(
      thumbnailRadiusProvider,
    ); // Get the radius

    final displayDuration =
        formattedDuration ??
        (duration != null ? _formatDuration(duration) : '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(bottom: 8),
        height: 70,
        child: Row(
          children: [
            Hero(
              tag: 'thumbnail-search-$videoId',
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: cardBackgroundColor,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(54 * thumbnailRadius),
                  child: thumbnail.isNotEmpty
                      ? Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildThumbnailFallback(),
                        )
                      : _buildThumbnailFallback(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.songTitle.copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: textSecondaryColor,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (displayDuration.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  displayDuration,
                  style: AppTypography.caption.copyWith(
                    color: textSecondaryColor,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to parse duration string to seconds (if not already in your file)
  int? _parseDurationToSeconds(String duration) {
    try {
      final parts = duration.split(':').map(int.parse).toList();

      if (parts.length == 2) {
        // MM:SS
        return parts[0] * 60 + parts[1];
      } else if (parts.length == 3) {
        // HH:MM:SS
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      }

      return null;
    } catch (e) {
      print('Error parsing duration: $e');
      return null;
    }
  }

  Widget _buildThumbnailFallback() {
    // This method is called from places where ref isn't available
    // You need to either pass ref or use a different approach
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.grey, size: 20),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final sidebarLabelColor = ref.watch(themeTextPrimaryColorProvider);
    final sidebarLabelActiveColor = ref.watch(themeIconActiveColorProvider);

    // Create theme-aware text styles
    final sidebarLabelStyle = AppTypography.sidebarLabel.copyWith(
      color: sidebarLabelColor,
    );
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive.copyWith(
      color: sidebarLabelActiveColor,
    );

    // Watch if user has access code
    final hasAccessCodeAsync = ref.watch(hasAccessCodeProvider);

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              icon: Icons.edit_square,
              label: '',
              isActive: true,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelActiveStyle,
              onTap: () {
                Navigator.of(context).pushFade(const AppearancePage());
              },
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              label: 'Quick picks',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Songs',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              onTap: () {
                Navigator.of(context).pushMaterialVertical(
                  const SavedSongsScreen(),
                  slideUp: true,
                  enableParallax: true,
                );
              },
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Playlists',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              onTap: () {
                Navigator.of(context).pushMaterialVertical(
                  const IntegratedPlaylistsScreen(),
                  slideUp: true,
                  enableParallax: true,
                );
              },
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Artists',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              onTap: () {
                Navigator.of(
                  context,
                ).pushMaterialVertical(const ArtistsGridPage(), slideUp: true);
              },
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Albums',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              onTap: () {
                Navigator.of(
                  context,
                ).pushMaterialVertical(const AlbumsGridPage(), slideUp: true);
              },
            ),

            // Social Item - Only show if user has access code
            hasAccessCodeAsync.when(
              data: (hasAccessCode) {
                if (!hasAccessCode) return const SizedBox.shrink();

                return Column(
                  children: [
                    const SizedBox(height: 24),
                    _buildSidebarItem(
                      label: 'Social',
                      iconActiveColor: iconActiveColor,
                      iconInactiveColor: iconInactiveColor,
                      labelStyle: sidebarLabelStyle,
                      onTap: () {
                        Navigator.of(context).pushMaterialVertical(
                          const SocialScreen(),
                          slideUp: true,
                          enableParallax: true,
                        );
                      },
                    ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    IconData? icon,
    required String label,
    bool isActive = false,
    required Color iconActiveColor,
    required Color iconInactiveColor,
    required TextStyle labelStyle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 28,
                color: isActive ? iconActiveColor : iconInactiveColor,
              ),
              const SizedBox(height: 16),
            ],
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: labelStyle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final backgroundColor = ref.watch(themeBackgroundColorProvider);

    final pageTitleStyle = AppTypography.pageTitle.copyWith(
      color: textPrimaryColor,
    );
    final hintStyle = AppTypography.pageTitle.copyWith(
      color: textSecondaryColor.withOpacity(0.5),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: backgroundColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side - Back button in search mode, Access Code icon in normal mode
          if (isSearchMode)
            IconButton(
              onPressed: () {
                setState(() {
                  isSearchMode = false;
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                  searchResults = [];
                });
              },
              icon: Icon(Icons.arrow_back, color: iconActiveColor, size: 28),
            )
          else
            Consumer(
              builder: (context, ref, child) {
                final hasAccessCodeAsync = ref.watch(hasAccessCodeProvider);

                return hasAccessCodeAsync.when(
                  data: (hasAccessCode) {
                    return GestureDetector(
                      onTap: hasAccessCode
                          ? () {
                              Navigator.of(
                                context,
                              ).pushFade(const AccessCodeManagementScreen());
                            }
                          : () {
                              // If no access code, show info or redirect to enter code
                              _showNoAccessCodeDialog(context);
                            },
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: hasAccessCode
                                  ? Colors.deepPurple.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              hasAccessCode ? Icons.security : Icons.lock_open,
                              color: hasAccessCode
                                  ? Colors.deepPurple
                                  : iconActiveColor,
                              size: 24,
                            ),
                          ),
                          // Badge for access code status
                          if (hasAccessCode)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                  loading: () => Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (error, stackTrace) => GestureDetector(
                    onTap: () {
                      // Show error message
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Error checking access code status',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                  ),
                );
              },
            ),

          // Middle content - takes available space
          Expanded(
            child: isSearchMode
                ? TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textAlign: TextAlign.right,
                    style: pageTitleStyle,
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, albums...',
                      hintStyle: hintStyle,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      _onSearchChanged(value);
                    },
                    onSubmitted: (value) {
                      _debounceTimer?.cancel();
                      _performSearchImmediately(value);
                      FocusScope.of(context).unfocus();
                    },
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: Text('Quick picks', style: pageTitleStyle),
                  ),
          ),
        ],
      ),
    );
  }

  void _showNoAccessCodeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Access Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You don\'t have an access code yet.'),
            const SizedBox(height: 8),
            Text(
              'Access code is required to manage access settings.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      const AccessCodeScreen(showSkipButton: false),
                ),
              );
            },
            child: const Text('Enter Code'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPicks() {
    if (isLoadingQuickPicks) {
      return ShimmerLoading(
        child: SizedBox(
          height: 280,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.95),
            itemCount: 2,
            itemBuilder: (context, pageIndex) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Column(
                  children: List.generate(
                    4,
                    (i) => Container(
                      height: 70,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          SkeletonBox(width: 54, height: 54, borderRadius: 12),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title line 1
                                SkeletonBox(
                                  width: double.infinity,
                                  height: 16,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 4),
                                // Title line 2 (shorter - not all titles are 2 lines)
                                SkeletonBox(
                                  width: 180,
                                  height: 16,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
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

    if (quickPicks.isEmpty) {
      final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
      return Center(
        child: Text(
          'No songs available',
          style: AppTypography.subtitle.copyWith(color: textPrimaryColor),
        ),
      );
    }
    return SizedBox(
      height: 280,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.95),
        itemCount: (quickPicks.length / 4).ceil(),
        itemBuilder: (context, pageIndex) {
          final start = pageIndex * 4;
          final end = (start + 4).clamp(0, quickPicks.length);
          final pageSongs = quickPicks.sublist(start, end);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Column(
              children: [
                for (var i = 0; i < pageSongs.length; i++)
                  SizedBox(
                    height: 70,
                    child: _buildQuickPickListItem(pageSongs[i]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickPickListItem(QuickPick quickPick) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final thumbnailRadius = ref.watch(
      thumbnailRadiusProvider,
    ); // Get the radius

    return GestureDetector(
      onTap: () async {
        await LastPlayedService.saveLastPlayed(quickPick);
        setState(() {
          _lastPlayedSong = quickPick;
        });
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, animation, __) => PlayerScreen(
              song: quickPick,
              heroTag: 'thumbnail-${quickPick.videoId}',
            ),
            transitionDuration: const Duration(milliseconds: 600),
            reverseTransitionDuration: const Duration(milliseconds: 500),
            transitionsBuilder: (_, animation, __, child) {
              final fade = CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
              );
              final slide =
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );
              return SlideTransition(
                position: slide,
                child: FadeTransition(opacity: fade, child: child),
              );
            },
          ),
        );
      },
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Hero(
              tag: 'thumbnail-${quickPick.videoId}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(54 * thumbnailRadius),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: quickPick.thumbnail.isNotEmpty
                      ? Image.network(
                          quickPick.thumbnail,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return ShimmerLoading(
                              child: SkeletonBox(
                                width: 54,
                                height: 54,
                                borderRadius: 12,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: cardBackgroundColor,
                            child: Center(
                              child: Icon(
                                Icons.music_note,
                                color: iconInactiveColor,
                                size: 20,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          color: cardBackgroundColor,
                          child: Center(
                            child: Icon(
                              Icons.music_note,
                              color: iconInactiveColor,
                              size: 20,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quickPick.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.songTitle.copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quickPick.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: textSecondaryColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Updated _buildQuickPicks method with skeleton

  // Updated _buildAlbums method with skeleton
  Widget _buildAlbums() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Albums',
                style: AppTypography.sectionHeader.copyWith(
                  color: textPrimaryColor,
                ),
              ),
              if (isLoadingAlbums)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconActiveColor,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (isLoadingAlbums)
          ShimmerLoading(
            child: SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                itemCount: 5,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 120,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 120,
                            height: 120,
                            borderRadius: AppSpacing.radiusMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SkeletonBox(width: 120, height: 14, borderRadius: 4),
                          const SizedBox(height: 6),
                          SkeletonBox(width: 80, height: 12, borderRadius: 4),
                          const SizedBox(height: 4),
                          SkeletonBox(width: 40, height: 10, borderRadius: 4),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          )
        else if (relatedAlbums.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'No albums found',
                style: AppTypography.subtitle.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16),
              itemCount: relatedAlbums.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 120,
                    height: 220,
                    child: _buildAlbumCard(relatedAlbums[index]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // Replace the _buildAlbumCard method with this updated version:

  Widget _buildAlbumCard(Album album) {
    const double size = 120;
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(
      thumbnailRadiusProvider,
    ); // Get the radius

    return GestureDetector(
      onTap: () {
        // Navigate immediately without showing loading dialog
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AlbumPage(album: album)),
        );
      },
      child: Container(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(54 * thumbnailRadius),
              child: Container(
                width: size,
                height: size,
                color: cardBackgroundColor,
                child: album.coverArt != null && album.coverArt!.isNotEmpty
                    ? Image.network(
                        album.coverArt!,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return ShimmerLoading(
                            child: SkeletonBox(
                              width: size,
                              height: size,
                              borderRadius: AppSpacing.radiusMedium,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Icon(
                            Icons.album,
                            color: iconInactiveColor,
                            size: 40,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.album,
                          color: iconInactiveColor,
                          size: 40,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              album.title,
              style: AppTypography.subtitle.copyWith(
                fontWeight: FontWeight.w600,
                color: textPrimaryColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Text(
              album.artist,
              style: AppTypography.caption.copyWith(color: textSecondaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (album.year > 0) ...[
              const SizedBox(height: AppSpacing.xs / 2),
              Text(
                album.year.toString(),
                style: AppTypography.captionSmall.copyWith(
                  color: textSecondaryColor.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Updated _buildSimilarArtists method with skeleton
  Widget _buildSimilarArtists() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    // Filter artists to only show those with profile images
    final artistsWithImages = similarArtists
        .where(
          (artist) =>
              artist.profileImage != null && artist.profileImage!.isNotEmpty,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Similar artists',
                style: AppTypography.sectionHeader.copyWith(
                  color: textPrimaryColor,
                ),
              ),
              Row(
                children: [
                  // if (artistsWithImages.isNotEmpty)
                  //   Text(
                  //     '${artistsWithImages.length} artists',
                  //     style: AppTypography.caption.copyWith(
                  //       color: AppColors.textSecondary,
                  //     ),
                  //   ),
                  const SizedBox(width: 8),
                  if (isLoadingArtists)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconActiveColor,
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.refresh, color: iconActiveColor),
                      onPressed: _fetchRandomArtists,
                      tooltip: 'Load more artists',
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (isLoadingArtists)
          ShimmerLoading(
            child: SizedBox(
              height: AppSpacing.artistCardSize + 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                itemCount: 10,
                itemBuilder: (context, index) {
                  return Container(
                    width: AppSpacing.artistCardSize,
                    margin: const EdgeInsets.only(right: AppSpacing.lg),
                    child: Column(
                      children: [
                        SkeletonBox(
                          width: AppSpacing.artistImageSize,
                          height: AppSpacing.artistImageSize,
                          borderRadius: AppSpacing.artistImageSize / 2,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SkeletonBox(width: 80, height: 14, borderRadius: 4),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 60, height: 10, borderRadius: 4),
                      ],
                    ),
                  );
                },
              ),
            ),
          )
        else if (artistsWithImages.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Text(
                    'No artists found',
                    style: AppTypography.subtitle.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _fetchRandomArtists,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Load Artists'),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: AppSpacing.artistCardSize + 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16),
              itemCount: artistsWithImages.length,
              itemBuilder: (context, index) {
                return _buildArtistCard(artistsWithImages[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildArtistCard(Artist artist) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistPage(artist: artist, artistName: ''),
          ),
        );
      },
      child: Container(
        width: AppSpacing.artistCardSize,
        margin: const EdgeInsets.only(right: AppSpacing.lg),
        child: Column(
          children: [
            ClipOval(
              child: Container(
                width: AppSpacing.artistImageSize,
                height: AppSpacing.artistImageSize,
                color: cardBackgroundColor,
                child: artist.profileImage != null
                    ? Image.network(
                        artist.profileImage!,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return ShimmerLoading(
                            child: SkeletonBox(
                              width: AppSpacing.artistImageSize,
                              height: AppSpacing.artistImageSize,
                              borderRadius: AppSpacing.artistImageSize / 2,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.person,
                              color: iconInactiveColor,
                              size: 48,
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Icon(
                          Icons.person,
                          color: iconInactiveColor,
                          size: 48,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              artist.name,
              style: AppTypography.subtitle.copyWith(color: textPrimaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Text(
              artist.subscribers,
              style: AppTypography.captionSmall.copyWith(
                color: textSecondaryColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(QuickPick song, MediaItem? currentMedia) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(
      thumbnailRadiusProvider,
    ); // Get the radius

    return GestureDetector(
      onTap: () {
        // Navigate to full PlayerScreen instead of expanding miniplayer
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PlayerScreen(
                  song: song,
                  heroTag: 'miniplayer-thumbnail-${song.videoId}',
                ),
            transitionDuration: const Duration(milliseconds: 400),
            reverseTransitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  // Slide up animation
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

                  return SlideTransition(
                    position: slideAnimation,
                    child: child,
                  );
                },
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardBackgroundColor, // Use card background color
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: StreamBuilder<PlaybackState>(
          stream: _audioService.playbackStateStream,
          builder: (context, playbackSnapshot) {
            final playbackState = playbackSnapshot.data;
            final isPlaying = playbackState?.playing ?? false;

            return Row(
              children: [
                // Album Art with thumbnail radius
                Hero(
                  tag: 'miniplayer-thumbnail-${song.videoId}',
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(
                        70 * thumbnailRadius,
                      ), // Apply radius
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        70 * thumbnailRadius,
                      ), // Match container
                      child: currentMedia?.artUri != null
                          ? Image.network(
                              currentMedia!.artUri.toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildMiniThumbnailFallback(
                                    ref,
                                    thumbnailRadius,
                                  ),
                            )
                          : song.thumbnail.isNotEmpty
                          ? Image.network(
                              song.thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildMiniThumbnailFallback(
                                    ref,
                                    thumbnailRadius,
                                  ),
                            )
                          : _buildMiniThumbnailFallback(ref, thumbnailRadius),
                    ),
                  ),
                ),

                // Song Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentMedia?.title ?? song.title,
                          style: AppTypography.songTitle.copyWith(
                            color: textPrimaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentMedia?.artist ?? song.artists,
                          style: AppTypography.caption.copyWith(
                            color: textSecondaryColor,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // Play/Pause Button
                Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: iconActiveColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: iconActiveColor,
                      size: 24,
                    ),
                    onPressed: () {
                      _audioService.playPause();
                    },
                  ),
                ),

                // Next Button
                Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: iconActiveColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.skip_next,
                      color: iconActiveColor,
                      size: 24,
                    ),
                    onPressed: () {
                      _audioService.skipToNext();
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMiniThumbnailFallback(WidgetRef ref, double thumbnailRadius) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);

    return Container(
      color: backgroundColor,
      child: Center(
        child: Icon(Icons.music_note, color: iconInactiveColor, size: 28),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchHelper.dispose();
    super.dispose();
  }
}

/// Extension to safely parse duration strings
extension DurationStringExtension on String? {
  int? get inSeconds {
    if (this == null || this!.isEmpty) return null;

    try {
      final parts = this!.split(':').map(int.parse).toList();

      if (parts.length == 2) {
        // MM:SS format
        return parts[0] * 60 + parts[1];
      } else if (parts.length == 3) {
        // HH:MM:SS format
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
