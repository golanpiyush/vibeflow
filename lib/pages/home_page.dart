// lib/pages/home_page.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:miniplayer/miniplayer.dart';
import 'package:vibeflow/api_base/yt_music_search_suggestor.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/api_base/ytmusic_search_helper.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/pages/album_page.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/artist_page.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/last_played_service.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/widgets/search_suggestions_widget.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:vibeflow/api_base/ytmusic_artists_scraper.dart';
import 'package:vibeflow/api_base/scrapper.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scrollController = ScrollController();
  final YouTubeMusicScraper _scraper = YouTubeMusicScraper();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final ValueNotifier<QuickPick?> _lastPlayedNotifier;

  // Only use YoutubeExplode - remove YTMusic
  late final YoutubeExplode _yt;

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
    _yt = YoutubeExplode();
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
      final albums = await _albumsScraper.getTrendingAlbums(limit: 20);

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
    return Scaffold(
      backgroundColor: AppColors.background,
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
                      _buildTopBar(),
                      Expanded(
                        child: isSearchMode
                            ? _buildSearchView()
                            : SingleChildScrollView(
                                controller: _scrollController,
                                padding: EdgeInsets.only(
                                  left: AppSpacing.lg,
                                  right: AppSpacing.lg,
                                  top: AppSpacing.lg,
                                  bottom: _lastPlayedSong != null ? 90 : 20,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildQuickPicks(),
                                    const SizedBox(height: AppSpacing.xxxl),
                                    _buildAlbums(),
                                    const SizedBox(height: AppSpacing.xxxl),
                                    _buildSimilarArtists(),
                                    const SizedBox(height: 100),
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
      floatingActionButton: _lastPlayedSong != null
          ? null // Hide FAB when miniplayer is showing
          : FloatingActionButton(
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
              backgroundColor: AppColors.iconActive,
              child: Icon(
                isSearchMode ? Icons.close : Icons.search,
                color: AppColors.background,
              ),
            ),
    );
  }

  // Updated _buildSearchView method
  Widget _buildSearchView() {
    // Show suggestions when:
    // 1. Search field has text BUT no search results yet (typing)
    // 2. OR search field is empty (show history)
    final showSuggestions = searchResults.isEmpty && !isSearching;

    return Column(
      children: [
        // Search suggestions (when not searching and no results)
        if (showSuggestions)
          Expanded(
            child: SearchSuggestionsWidget(
              key: ValueKey(_currentQuery), // Force rebuild on query change
              query: _currentQuery,
              onSuggestionTap: (suggestion) {
                // Update search field
                _searchController.text = suggestion;
                setState(() {
                  _currentQuery = suggestion;
                });

                // Perform immediate search
                _debounceTimer?.cancel();
                _performSearchImmediately(suggestion);

                // Unfocus keyboard
                FocusScope.of(context).unfocus();
              },
              onClearHistory: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Search history cleared'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: AppColors.accent,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
            ),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Loading state
                  if (isSearching)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.textPrimary,
                      ),
                    ),

                  // Search results
                  if (!isSearching && searchResults.isNotEmpty) ...[
                    Text('Results', style: AppTypography.sectionHeader),
                    const SizedBox(height: AppSpacing.md),
                    ...searchResults.map((song) {
                      final durationInSeconds = song.duration != null
                          ? _parseDurationToSeconds(song.duration!)
                          : null;

                      return _buildSearchResultItem(
                        videoId: song.videoId,
                        title: song.title,
                        subtitle: song.artists.join(', '),
                        thumbnail: song.thumbnail,
                        duration: durationInSeconds,
                        formattedDuration: song.duration,
                        onTap: () async {
                          // Save search to history when user taps a result
                          final helper = YTMusicSuggestionsHelper();
                          await helper.saveToHistory(_searchController.text);
                          helper.dispose();

                          final quickPick = QuickPick(
                            videoId: song.videoId,
                            title: song.title,
                            artists: song.artists.join(', '),
                            thumbnail: song.thumbnail,
                            duration: song.duration,
                          );

                          // ✅ Save as last played and update state
                          await LastPlayedService.saveLastPlayed(quickPick);
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
                      );
                    }).toList(),
                  ],

                  // Empty state
                  if (!isSearching &&
                      searchResults.isEmpty &&
                      _searchController.text.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.music_off,
                              size: 64,
                              color: AppColors.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No results found',
                              style: AppTypography.subtitle.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try a different search term',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary.withOpacity(0.7),
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
  }) {
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
            // Wrap with Hero for smooth transition
            Hero(
              tag: 'thumbnail-search-$videoId',
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: AppColors.cardBackground,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
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
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
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
                    color: AppColors.textSecondary,
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
    return Container(
      color: AppColors.cardBackground,
      child: const Center(
        child: Icon(Icons.music_note, color: AppColors.iconInactive, size: 20),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final double availableHeight = MediaQuery.of(context).size.height;

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
              onTap: () {
                Navigator.of(context).pushFade(const AppearancePage());
              },
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(label: 'Quick picks'),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Songs',
              onTap: () {
                Navigator.of(context).pushFade(const SavedSongsScreen());
              },
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(label: 'Playlists'),
            const SizedBox(height: 24),
            _buildSidebarItem(label: 'Artists'),
            const SizedBox(height: 24),
            _buildSidebarItem(label: 'Albums'),
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
                color: isActive ? AppColors.iconActive : AppColors.iconInactive,
              ),
              const SizedBox(height: 16),
            ],
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style:
                    (isActive
                            ? AppTypography.sidebarLabelActive
                            : AppTypography.sidebarLabel)
                        .copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isSearchMode)
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textAlign: TextAlign.right,
                style: AppTypography.pageTitle,
                decoration: InputDecoration(
                  hintText: 'Enter a name',
                  hintStyle: AppTypography.pageTitle.copyWith(
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (value) {
                  _onSearchChanged(value);
                },
                onSubmitted: (value) {
                  // Cancel debounce and search immediately
                  _debounceTimer?.cancel();
                  _performSearchImmediately(value);
                  FocusScope.of(context).unfocus();
                },
              ),
            )
          else
            Text('Quick picks', style: AppTypography.pageTitle),
        ],
      ),
    );
  }

  Widget _buildQuickPicks() {
    if (isLoadingQuickPicks) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.textPrimary),
      );
    }

    if (quickPicks.isEmpty) {
      return Center(
        child: Text('No songs available', style: AppTypography.subtitle),
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
    return GestureDetector(
      onTap: () async {
        // Save as last played
        await LastPlayedService.saveLastPlayed(quickPick);
        setState(() {
          _lastPlayedSong = quickPick;
        });

        // Navigate with animation
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PlayerScreen(
                  song: quickPick,
                  heroTag: 'thumbnail-${quickPick.videoId}',
                ),
            transitionDuration: const Duration(milliseconds: 600),
            reverseTransitionDuration: const Duration(milliseconds: 500),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final fadeAnimation = CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
                  );

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
                    child: FadeTransition(opacity: fadeAnimation, child: child),
                  );
                },
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 70,
        child: Row(
          children: [
            Hero(
              tag: 'thumbnail-${quickPick.videoId}',
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: quickPick.thumbnail.isNotEmpty
                      ? Image.network(
                          quickPick.thumbnail,
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
                    quickPick.title,
                    style: AppTypography.songTitle.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quickPick.artists,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (quickPick.duration != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  quickPick.duration.toString(),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbums() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16), // Add padding here
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Albums', style: AppTypography.sectionHeader),
              if (isLoadingAlbums)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.iconActive,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (relatedAlbums.isEmpty && !isLoadingAlbums)
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

  Widget _buildAlbumCard(Album album) {
    const double size = 120;

    return GestureDetector(
      onTap: () async {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: AppColors.iconActive),
          ),
        );

        try {
          // Fetch album with songs
          final fullAlbum = await _albumsScraper.getAlbumDetails(album.id);

          if (mounted) Navigator.pop(context);

          if (fullAlbum != null) {
            // Navigate to album page
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AlbumPage(album: fullAlbum),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not load album'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) Navigator.pop(context);
          print('Error loading album: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error loading album'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      child: Container(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              child: Container(
                width: size,
                height: size,
                color: AppColors.cardBackground,
                child: album.coverArt != null && album.coverArt!.isNotEmpty
                    ? Image.network(
                        album.coverArt!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                              child: Icon(
                                Icons.album,
                                color: AppColors.iconInactive,
                                size: 40,
                              ),
                            ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.album,
                          color: AppColors.iconInactive,
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
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Text(
              album.artist,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (album.year > 0) ...[
              const SizedBox(height: AppSpacing.xs / 2),
              Text(
                album.year.toString(),
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSimilarArtists() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16), // Add padding here
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Similar artists', style: AppTypography.sectionHeader),
              if (isLoadingArtists)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.iconActive,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (similarArtists.isEmpty && !isLoadingArtists)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'No artists found',
                style: AppTypography.subtitle.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: AppSpacing.artistCardSize + 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16),
              itemCount: similarArtists.length,
              itemBuilder: (context, index) {
                return _buildArtistCard(similarArtists[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildArtistCard(Artist artist) {
    return GestureDetector(
      onTap: () {
        // Navigate directly to artist page
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ArtistPage(artist: artist)),
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
                color: AppColors.cardBackground,
                child: artist.profileImage != null
                    ? Image.network(
                        artist.profileImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.person,
                              color: AppColors.iconInactive,
                              size: 48,
                            ),
                          );
                        },
                      )
                    : const Center(
                        child: Icon(
                          Icons.person,
                          color: AppColors.iconInactive,
                          size: 48,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              artist.name,
              style: AppTypography.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Text(
              artist.subscribers,
              style: AppTypography.captionSmall,
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
          color: const Color(0xFF1A1A1A),
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
                // Album Art
                Hero(
                  tag: 'miniplayer-thumbnail-${song.videoId}',
                  child: Container(
                    width: 70,
                    height: 70,
                    child: ClipRRect(
                      child: currentMedia?.artUri != null
                          ? Image.network(
                              currentMedia!.artUri.toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildMiniThumbnailFallback(),
                            )
                          : song.thumbnail.isNotEmpty
                          ? Image.network(
                              song.thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildMiniThumbnailFallback(),
                            )
                          : _buildMiniThumbnailFallback(),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentMedia?.artist ?? song.artists,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
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
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
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
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.skip_next,
                      color: Colors.white,
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

  Widget _buildExpandedPlayer(QuickPick song, MediaItem? currentMedia) {
    return SizedBox(
      height: _miniplayerMaxHeight,
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF1A1A1A), Colors.black],
          ),
        ),
        child: PlayerScreen(
          song: song,
          heroTag: 'miniplayer-thumbnail-${song.videoId}',
        ),
      ),
    );
  }

  Widget _buildMiniThumbnailFallback() {
    return Container(
      color: AppColors.cardBackground,
      child: const Center(
        child: Icon(Icons.music_note, color: AppColors.iconInactive, size: 28),
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
    _yt.close();
    _searchHelper.dispose();
    super.dispose();
  }
}

/// Extension to get high quality thumbnails from ThumbnailSet
extension ThumbnailSetExtension on List<Thumbnail> {
  String get highResUrl {
    if (isEmpty) return '';

    // Sort by resolution (width * height) and get the highest
    final sorted = [...this];
    sorted.sort((a, b) {
      final aRes = (a.width ?? 0) * (a.height ?? 0);
      final bRes = (b.width ?? 0) * (b.height ?? 0);
      return bRes.compareTo(aRes);
    });

    return sorted.first.url.toString();
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
