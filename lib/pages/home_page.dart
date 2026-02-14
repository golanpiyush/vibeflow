// lib/pages/home_page.dart
// ignore_for_file: unused_local_variable

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miniplayer/miniplayer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/cache_manager.dart';
import 'package:vibeflow/api_base/community_playlistScaper.dart';
import 'package:vibeflow/api_base/yt_music_search_suggestor.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/api_base/ytmusic_search_helper.dart';
import 'package:vibeflow/constants/ai_models_config.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/installer_services/update_manager_service.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/pages/access_code_management_screen.dart';
import 'package:vibeflow/pages/album_view.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/artist_view.dart';
import 'package:vibeflow/pages/authOnboard/Screens/social_feed_page.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/pages/subpages/songs/albums.dart';
import 'package:vibeflow/pages/subpages/songs/albums_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/artists.dart';
import 'package:vibeflow/pages/subpages/songs/artists_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/dailyPLaylist.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/services/last_played_service.dart';
import 'package:vibeflow/services/sync_services/musicIntelligence.dart';
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
import 'package:vibeflow/widgets/update_dialog.dart';

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
  bool _isCommunityPlaylistsSelected = false;

  final _audioService = AudioServices.instance;
  final MiniplayerController _miniplayerController = MiniplayerController();
  QuickPick? _lastPlayedSong;
  EligibilityStatus? _eligibilityStatus;
  static const double _miniplayerMinHeight = 70.0;
  DailyPlaylist? _featuredPlaylist;
  bool _isLoadingFeaturedPlaylist = false;
  bool _hasAccessCode = false;
  String _currentQuery = '';
  List<CommunityPlaylist> communityPlaylists = [];
  bool isLoadingCommunityPlaylists = false;

  @override
  void initState() {
    super.initState();
    _albumsScraper = YTMusicAlbumsScraper();
    _artistsScraper = YTMusicArtistsScraper(); // Initialize
    _searchHelper = YTMusicSearchHelper();
    _lastPlayedNotifier = ValueNotifier<QuickPick?>(null);
    _initializeApp();

    // 🔄 Check for updates after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      _checkAccessCodeAndLoadPlaylist();
    });
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

  // Replace these methods in your _HomePageState class:

  Future<void> _loadQuickPicks() async {
    if (!mounted) return; // ✅ Check before setState
    setState(() => isLoadingQuickPicks = true);

    try {
      final songs = await _scraper.getQuickPicks(limit: 40);

      if (!mounted) return; // ✅ Check after async operation
      setState(() {
        quickPicks = songs.map((song) => QuickPick.fromSong(song)).toList();
        isLoadingQuickPicks = false;
      });
    } catch (e) {
      print('Error loading quick picks: $e');
      if (!mounted) return; // ✅ Check before setState in catch
      setState(() => isLoadingQuickPicks = false);
    }
  }

  Future<void> _checkAccessCodeAndLoadPlaylist() async {
    try {
      // Use the existing hasAccessCodeProvider instead of direct query
      final hasAccessCodeAsync = ref.read(hasAccessCodeProvider);

      hasAccessCodeAsync.when(
        data: (hasCode) async {
          if (!mounted) return;

          setState(() {
            _hasAccessCode = hasCode;
          });

          if (hasCode) {
            // ✅ ENSURE ORCHESTRATOR IS INITIALIZED BEFORE LOADING PLAYLIST
            try {
              await MusicIntelligenceOrchestrator.init();
              print('✅ AI Orchestrator initialized from home_page');
            } catch (e) {
              print('❌ Failed to init orchestrator: $e');
              return; // Don't proceed if init fails
            }

            await _loadFeaturedPlaylist();
          }
        },
        loading: () {
          print('⏳ Loading access code status...');
        },
        error: (error, stack) {
          print('❌ Error checking access code: $error');
        },
      );
    } catch (e) {
      print('❌ Error checking access code: $e');
    }
  }

  Future<void> _loadAlbums() async {
    if (!mounted) return; // ✅ Check before setState
    setState(() => isLoadingAlbums = true);

    try {
      final albums = await _albumsScraper.getMixedRandomAlbums(limit: 25);

      print('✅ Found ${albums.length} albums');

      if (!mounted) return; // ✅ Check after async operation
      setState(() {
        relatedAlbums = albums;
        isLoadingAlbums = false;
      });
    } catch (e, stack) {
      print('❌ Error loading albums: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      if (!mounted) return; // ✅ Check before setState in catch
      setState(() => isLoadingAlbums = false);
    }
  }

  Future<void> _loadArtists() async {
    if (!mounted) return; // ✅ Check before setState
    setState(() => isLoadingArtists = true);

    try {
      final artists = await _artistsScraper.getTrendingArtists(limit: 10);

      print('✅ Found ${artists.length} artists');

      if (!mounted) return; // ✅ Check after async operation
      setState(() {
        similarArtists = artists;
        isLoadingArtists = false;
      });
    } catch (e, stack) {
      print('❌ Error loading artists: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      if (!mounted) return; // ✅ Check before setState in catch
      setState(() => isLoadingArtists = false);
    }
  }

  Future<void> _fetchRandomArtists() async {
    if (!mounted) return; // ✅ Check before setState
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
      if (!mounted) return; // ✅ Check after async operation
      setState(() {
        similarArtists = artistsWithImages.take(30).toList();
        isLoadingArtists = false;
      });

      print('✅ Loaded ${similarArtists.length} artists with images');
    } catch (e) {
      print('❌ Error fetching random artists: $e');
      if (!mounted) return; // ✅ Check before setState in catch
      setState(() {
        isLoadingArtists = false;
      });
    }
  }

  Future<void> _loadCommunityPlaylists() async {
    if (!mounted) return;

    setState(() => isLoadingCommunityPlaylists = true);

    try {
      // TRY 1: Get featured playlists from home feed
      print('🎵 [Playlist] Trying home feed...');
      var playlists = await _scraper.getCommunityPlaylists(limit: 20);

      // TRY 2: If home feed returns empty, search for popular playlists
      if (playlists.isEmpty) {
        print('🔍 [Playlist] Home feed empty, trying search...');

        // Search for various popular playlist topics
        final searchQueries = [
          'top hits',
          'chill vibes',
          'workout',
          'party mix',
          'study music',
          'rock classics',
        ];

        for (final query in searchQueries) {
          final searchResults = await _scraper.searchPlaylists(query, limit: 5);
          playlists.addAll(searchResults);

          if (playlists.length >= 20) break;
        }
      }

      if (!mounted) return;

      setState(() {
        communityPlaylists = playlists;
        isLoadingCommunityPlaylists = false;
      });

      print('✅ Loaded ${communityPlaylists.length} community playlists');
    } catch (e) {
      print('❌ Error loading community playlists: $e');
      if (!mounted) return;
      setState(() => isLoadingCommunityPlaylists = false);
    }
  }

  Future<void> _performSearch(String query) async {
    // Cancel previous timer if it exists
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      if (!mounted) return; // ✅ Check before setState
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    // Show loading immediately
    if (!mounted) return; // ✅ Check before setState
    setState(() => isSearching = true);

    // Start new debounce timer
    _debounceTimer = Timer(_debounceDuration, () async {
      try {
        final results = await _searchHelper.searchSongs(query, limit: 50);

        if (mounted) {
          // ✅ Check before setState
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
          // ✅ Check before setState in catch
          setState(() => isSearching = false);
        }
      }
    });
  }

  Future<void> _performSearchImmediately(String query) async {
    if (query.trim().isEmpty) {
      if (!mounted) return; // ✅ Check before setState
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    if (!mounted) return; // ✅ Check before setState
    setState(() => isSearching = true);

    try {
      final results = await _searchHelper.searchSongs(query, limit: 50);

      if (mounted) {
        // ✅ Check after async operation
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
        // ✅ Check before setState in catch
        setState(() => isSearching = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    if (!mounted) return; // ✅ Check before setState
    setState(() {
      _currentQuery = query; // Update current query for suggestions widget
    });
    _performSearch(query); // This handles debounced actual search
  }

  Future<void> _loadLastPlayedSong() async {
    final lastPlayed = await LastPlayedService.getLastPlayed();
    if (!mounted) return; // ✅ Check after async operation
    _lastPlayedNotifier.value = lastPlayed;
  }

  Future<void> _checkForUpdates() async {
    try {
      final updateResult = await UpdateManagerService.checkForUpdate();

      if (!mounted) return;

      if (updateResult.status == UpdateStatus.available &&
          updateResult.updateInfo != null) {
        final current = updateResult.updateInfo!.currentVersion;
        final latest = updateResult.updateInfo!.latestVersion;

        // 🔒 Show ONLY if latest > current
        if (_isVersionLower(current, latest)) {
          UpdateDialog.show(context, updateResult.updateInfo!);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Update check failed: $e');
      // Silent failure by design
    }
  }

  Future<void> _loadFeaturedPlaylist() async {
    if (!mounted) return;

    setState(() => _isLoadingFeaturedPlaylist = true);

    try {
      // ✅ ENSURE ORCHESTRATOR IS INITIALIZED
      if (!MusicIntelligenceOrchestrator.isInitialized) {
        print('🔧 Orchestrator not initialized, initializing now...');
        await MusicIntelligenceOrchestrator.init();
      }

      // Check eligibility first
      final eligibility = await DailyPlaylistService.instance
          .checkEligibility();

      if (!mounted) return;

      setState(() {
        _eligibilityStatus = eligibility; // Store eligibility status
      });

      if (!eligibility.isEligible) {
        print('📊 Not eligible for AI playlist yet');
        print(
          '   Songs: ${eligibility.uniqueSongs}/${GatingRules.minUniqueSongs}',
        ); // ✅ USE CONSTANT
        print(
          '   Days: ${eligibility.listeningDays}/${GatingRules.minListeningDays}',
        ); // ✅ USE CONSTANT
        if (!mounted) return;
        setState(() => _isLoadingFeaturedPlaylist = false);
        return;
      }

      // Generate playlist
      final playlist = await DailyPlaylistService.instance.generatePlaylist();

      if (!mounted) return;

      setState(() {
        _featuredPlaylist = playlist;
        _isLoadingFeaturedPlaylist = false;
      });

      if (playlist != null) {
        print('✅ Featured playlist loaded: ${playlist.songs.length} songs');
      }
    } catch (e) {
      print('❌ Error loading featured playlist: $e');
      if (!mounted) return;
      setState(() => _isLoadingFeaturedPlaylist = false);
    }
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
                                    ), // ADD THIS SECTION HERE ⬇️
                                    if (_hasAccessCode) ...[
                                      const SizedBox(height: AppSpacing.xxxl),
                                      _buildFeaturedPlaylist(),
                                    ],

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

  Widget _buildSearchView() {
    return Column(
      children: [
        // Community Playlist Ticker - Fixed height
        Container(
          height: 40, // FIXED HEIGHT to prevent overflow
          child: _buildCommunityPlaylistTicker(),
        ),

        // Main content area - Must be Expanded
        Expanded(child: _buildSearchContent()),
      ],
    );
  }

  Widget _buildSearchContent() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final accentColor = ref.watch(themeAccentColorProvider);

    final showSuggestions =
        (isSearching && _currentQuery.trim().isEmpty) ||
        (searchResults.isEmpty && !isSearching);

    // CHANGE: Show community playlists grid when selected
    if (_isCommunityPlaylistsSelected) {
      return _buildCommunityPlaylistsGrid();
    } else if (showSuggestions) {
      return AnimatedSwitcher(
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
      );
    } else {
      return AnimatedSwitcher(
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
                child: _buildSearchLoadingShimmer(),
              )
            : searchResults.isNotEmpty
            ? _buildSearchResults()
            : _buildEmptySearchState(),
      );
    }
  }

  Widget _buildSearchLoadingShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 80, height: 24, borderRadius: 4),
          const SizedBox(height: AppSpacing.md),
          ...List.generate(8, (index) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              height: 70,
              child: Row(
                children: [
                  SkeletonBox(width: 54, height: 54, borderRadius: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: double.infinity,
                          height: 16,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 150, height: 12, borderRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 35, height: 11, borderRadius: 4),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return SingleChildScrollView(
      key: ValueKey('results-${searchResults.length}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder(
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
              style: AppTypography.sectionHeader(
                context,
              ).copyWith(color: textPrimaryColor),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...searchResults.asMap().entries.map((entry) {
            final index = entry.key;
            final song = entry.value;
            final durationInSeconds = song.duration != null
                ? _parseDurationToSeconds(song.duration!)
                : null;

            return TweenAnimationBuilder(
              duration: Duration(milliseconds: 350 + (index * 40)),
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
              // Around line 580, in _buildSearchResults:
              child: _buildSearchResultItem(
                videoId: song.videoId,
                title: song.title,
                subtitle: song.artists.join(', '),
                thumbnail: song.thumbnail,
                duration: durationInSeconds,
                formattedDuration: song.duration,
                onTap: () async {
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

                  await LastPlayedService.saveLastPlayed(quickPick);
                  if (mounted) {
                    setState(() => _lastPlayedSong = quickPick);

                    // 🔥 Play with search source type
                    final handler = getAudioHandler();
                    if (handler != null) {
                      await handler.playSong(
                        quickPick,
                        sourceType: RadioSourceType.search, // ✅ SPECIFY SOURCE
                      );
                    }

                    _openPlayer(
                      quickPick,
                      heroTag: 'thumbnail-search-${quickPick.videoId}',
                    );
                  }
                },
                ref: ref,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildEmptySearchState() {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return Center(
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
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textSecondaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityPlaylistTicker() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () async {
            setState(() {
              _isCommunityPlaylistsSelected = !_isCommunityPlaylistsSelected;
            });

            // Load playlists when selected
            if (_isCommunityPlaylistsSelected && communityPlaylists.isEmpty) {
              await _loadCommunityPlaylists();
            }
          },
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isCommunityPlaylistsSelected
                    ? Colors.green
                    : textSecondaryColor.withOpacity(0.3),
                width: 1,
              ),
              color: _isCommunityPlaylistsSelected
                  ? Colors.green.withOpacity(0.1)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 14,
                  color: _isCommunityPlaylistsSelected
                      ? Colors.green
                      : textSecondaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'Community',
                  style: TextStyle(
                    color: _isCommunityPlaylistsSelected
                        ? Colors.green
                        : textPrimaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Replace _buildCommunityPlaylistShimmer with actual playlist grid
  Widget _buildCommunityPlaylistsGrid() {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    if (isLoadingCommunityPlaylists) {
      // Show shimmer while loading
      return ShimmerLoading(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 150, height: 24, borderRadius: 4),
              const SizedBox(height: 12),
              SkeletonBox(width: 200, height: 16, borderRadius: 4),
              const SizedBox(height: AppSpacing.xxxl),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12, // SPACE BETWEEN COLUMNS
                  mainAxisSpacing: 12, // SPACE BETWEEN ROWS
                  childAspectRatio: 0.75, // HEIGHT/WIDTH ratio - taller cards
                ),
                itemCount: communityPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = communityPlaylists[index];
                  return _buildCommunityPlaylistCard(playlist);
                },
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                    'Community Playlists',
                    style: AppTypography.sectionHeader(context).copyWith(
                      color: textPrimaryColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${communityPlaylists.length} playlists',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: iconActiveColor),
                onPressed: _loadCommunityPlaylists,
                tooltip: 'Refresh playlists',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxxl),

          // Grid of playlists
          if (communityPlaylists.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.playlist_play,
                      size: 64,
                      color: textSecondaryColor.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No community playlists found',
                      style: AppTypography.subtitle(
                        context,
                      ).copyWith(color: textPrimaryColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try refreshing or check back later',
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: communityPlaylists.length,
              itemBuilder: (context, index) {
                final playlist = communityPlaylists[index];
                return _buildCommunityPlaylistCard(playlist);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCommunityPlaylistCard(CommunityPlaylist playlist) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return GestureDetector(
      onTap: () => _openPlaylistDetails(playlist),
      child: Container(
        decoration: BoxDecoration(
          color: cardBackgroundColor.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8), // PADDING INSIDE CARD
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail - ASPECT RATIO prevents overflow
            Expanded(
              flex: 7, // 70% of card height
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  color: Colors.grey[900],
                  child:
                      playlist.thumbnail != null &&
                          playlist.thumbnail!.isNotEmpty
                      ? Image.network(
                          playlist.thumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
                              Icons.playlist_play,
                              color: iconInactiveColor.withOpacity(0.5),
                              size: 28,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.playlist_play,
                            color: iconInactiveColor.withOpacity(0.5),
                            size: 28,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 8), // SPACE BETWEEN IMAGE AND TEXT
            // Text area - FLEXIBLE with constraints
            Expanded(
              flex: 3, // 30% of card height
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    playlist.title,
                    style: TextStyle(
                      color: textPrimaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const Spacer(), // PUSH METADATA TO BOTTOM
                  // Song count + Creator
                  Text(
                    '${playlist.songCount} songs • ${playlist.creator}',
                    style: TextStyle(
                      color: textSecondaryColor.withOpacity(0.7),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Open playlist details
  Future<void> _openPlaylistDetails(CommunityPlaylist playlist) async {
    // Show loading dialog with streaming support
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StreamBuilder<List<Song>>(
        stream: _streamPlaylistLoading(playlist.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AlertDialog(
              title: const Text('Error'),
              content: Text('Failed to load playlist: ${snapshot.error}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          }

          final loadedSongs = snapshot.data ?? [];
          final isComplete = snapshot.connectionState == ConnectionState.done;

          return AlertDialog(
            title: Text('Loading ${playlist.title}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  isComplete
                      ? 'Loaded ${loadedSongs.length} songs'
                      : 'Loading... ${loadedSongs.length} songs',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      // Load with streaming
      final songs = <Song>[];

      await for (final song in _scraper.streamPlaylistSongs(playlist.id)) {
        songs.add(song);
        // Cache each song as it arrives
        if (songs.length % 10 == 0) {
          await CacheManager.instance.cachePlaylistSongs(playlist.id, songs);
        }
      }

      // Final cache
      await CacheManager.instance.cachePlaylistSongs(playlist.id, songs);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (songs.isNotEmpty) {
        final fullPlaylist = CommunityPlaylist(
          id: playlist.id,
          title: playlist.title,
          creator: playlist.creator,
          thumbnail: playlist.thumbnail,
          songCount: songs.length,
          songs: songs,
        );

        _showCommunityPlaylistBottomSheet(fullPlaylist);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No songs found in playlist'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ Error loading playlist details: $e');
      if (!mounted) return;

      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load playlist'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ADD THIS NEW METHOD
  Stream<List<Song>> _streamPlaylistLoading(String playlistId) async* {
    final songs = <Song>[];

    await for (final song in _scraper.streamPlaylistSongs(playlistId)) {
      songs.add(song);
      yield List<Song>.from(songs); // Yield copy to trigger rebuild
    }
  }

  // Show playlist bottom sheet
  void _showCommunityPlaylistBottomSheet(CommunityPlaylist playlist) {
    final backgroundColor = ref.read(themeBackgroundColorProvider);
    final textPrimaryColor = ref.read(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.read(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.read(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.read(themeIconActiveColorProvider);
    final thumbnailRadius = ref.read(thumbnailRadiusProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // HEADER with Playlist Info
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      iconActiveColor.withOpacity(0.2),
                      cardBackgroundColor,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // Drag handle
                      Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 16),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textSecondaryColor.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Playlist Cover + Info
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Large playlist cover
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey[900],
                                child:
                                    playlist.thumbnail != null &&
                                        playlist.thumbnail!.isNotEmpty
                                    ? Image.network(
                                        playlist.thumbnail!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Icon(
                                            Icons.playlist_play,
                                            color: textSecondaryColor,
                                            size: 48,
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(
                                          Icons.playlist_play,
                                          color: textSecondaryColor,
                                          size: 48,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(width: 16),

                            // Playlist details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Playlist title
                                  Text(
                                    playlist.title,
                                    style: TextStyle(
                                      color: textPrimaryColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  const SizedBox(height: 8),

                                  // Creator
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 14,
                                        color: textSecondaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          playlist.creator,
                                          style: TextStyle(
                                            color: textSecondaryColor,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 4),

                                  // Song count
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.music_note,
                                        size: 14,
                                        color: textSecondaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${playlist.songs?.length ?? playlist.songCount} songs',
                                        style: TextStyle(
                                          color: textSecondaryColor,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  // Play all button
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      if (playlist.songs != null &&
                                          playlist.songs!.isNotEmpty) {
                                        // Convert all songs to QuickPicks
                                        final allSongs = playlist.songs!
                                            .map(
                                              (song) => QuickPick(
                                                videoId: song.videoId,
                                                title: song.title,
                                                artists: song.artists.join(
                                                  ', ',
                                                ),
                                                thumbnail: song.thumbnail,
                                                duration: song.duration,
                                              ),
                                            )
                                            .toList();

                                        // Save first song as last played
                                        await LastPlayedService.saveLastPlayed(
                                          allSongs.first,
                                        );

                                        if (mounted) {
                                          setState(
                                            () => _lastPlayedSong =
                                                allSongs.first,
                                          );
                                          Navigator.pop(context);

                                          // 🔥 UPDATED: Pass playlist ID for continuation
                                          final handler = getAudioHandler();
                                          if (handler != null) {
                                            await handler.playPlaylistQueue(
                                              allSongs,
                                              startIndex: 0,
                                              playlistId:
                                                  playlist.id, // ✅ ADD THIS
                                            );
                                          }
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.play_arrow,
                                      size: 18,
                                    ),
                                    label: const Text('Play All'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: iconActiveColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Close button
                            IconButton(
                              icon: Icon(Icons.close, color: textPrimaryColor),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // SONGS LIST with album art
              Expanded(
                child: playlist.songs == null || playlist.songs!.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.music_note,
                                size: 64,
                                color: textSecondaryColor.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No songs available',
                                style: TextStyle(
                                  color: textPrimaryColor,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: playlist.songs!.length,
                        itemBuilder: (context, index) {
                          final song = playlist.songs![index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: cardBackgroundColor.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),

                              // Song number badge
                              leading: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Stack(
                                  children: [
                                    // Album art
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: song.thumbnail.isNotEmpty
                                          ? Image.network(
                                              song.thumbnail,
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                    color: Colors.grey[800],
                                                    child: Icon(
                                                      Icons.music_note,
                                                      color: textSecondaryColor,
                                                      size: 24,
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: Colors.grey[800],
                                              child: Icon(
                                                Icons.music_note,
                                                color: textSecondaryColor,
                                                size: 24,
                                              ),
                                            ),
                                    ),

                                    // Track number overlay
                                    Positioned(
                                      bottom: 2,
                                      right: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Song info
                              title: Text(
                                song.title,
                                style: TextStyle(
                                  color: textPrimaryColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                song.artists.join(', '),
                                style: TextStyle(
                                  color: textSecondaryColor,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),

                              // Play button
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.play_circle_filled,
                                  color: iconActiveColor,
                                  size: 32,
                                ),
                                onPressed: () async {
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

                                  if (mounted) {
                                    setState(() => _lastPlayedSong = quickPick);
                                    Navigator.pop(context);

                                    // 🔥 FIX: Play with playlist context - handler will detect it
                                    final handler = getAudioHandler();
                                    if (handler != null) {
                                      // Store playlist songs in handler's cache
                                      if (playlist.songs != null &&
                                          playlist.songs!.isNotEmpty) {
                                        await handler.setPlaylistContext(
                                          playlistId: playlist.id,
                                          songs: playlist.songs!,
                                        );
                                      }

                                      await handler.playSong(
                                        quickPick,
                                        sourceType:
                                            RadioSourceType.communityPlaylist,
                                      );
                                    }
                                  }
                                },
                              ),

                              onTap: () async {
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

                                if (mounted) {
                                  setState(() => _lastPlayedSong = quickPick);
                                  Navigator.pop(context);

                                  // 🔥 FIX: Play with playlist context
                                  final handler = getAudioHandler();
                                  if (handler != null) {
                                    // Store playlist songs in handler's cache
                                    if (playlist.songs != null &&
                                        playlist.songs!.isNotEmpty) {
                                      await handler.setPlaylistContext(
                                        playlistId: playlist.id,
                                        songs: playlist.songs!,
                                      );
                                    }

                                    await handler.playSong(
                                      quickPick,
                                      sourceType:
                                          RadioSourceType.communityPlaylist,
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Updated _buildSearchView method
  // Update the _buildSearchView method to use theme colors
  // Widget _buildSearchView() {
  //   final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
  //   final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
  //   final accentColor = ref.watch(themeAccentColorProvider);
  //   final showSuggestions = searchResults.isEmpty && !isSearching;

  //   return Column(
  //     children: [
  //       if (showSuggestions)
  //         Expanded(
  //           child: AnimatedSwitcher(
  //             duration: const Duration(milliseconds: 300),
  //             switchInCurve: Curves.easeOutCubic,
  //             switchOutCurve: Curves.easeInCubic,
  //             child: SearchSuggestionsWidget(
  //               key: ValueKey(_currentQuery),
  //               query: _currentQuery,
  //               onSuggestionTap: (suggestion) {
  //                 _searchController.text = suggestion;
  //                 setState(() {
  //                   _currentQuery = suggestion;
  //                 });
  //                 _debounceTimer?.cancel();
  //                 _performSearchImmediately(suggestion);
  //                 FocusScope.of(context).unfocus();
  //               },
  //               onClearHistory: () {
  //                 ScaffoldMessenger.of(context).showSnackBar(
  //                   SnackBar(
  //                     content: const Text('Search history cleared'),
  //                     duration: const Duration(seconds: 2),
  //                     backgroundColor: accentColor,
  //                     behavior: SnackBarBehavior.floating,
  //                     shape: RoundedRectangleBorder(
  //                       borderRadius: BorderRadius.circular(8),
  //                     ),
  //                     margin: const EdgeInsets.all(16),
  //                   ),
  //                 );
  //               },
  //             ),
  //           ),
  //         )
  //       else
  //         Expanded(
  //           child: AnimatedSwitcher(
  //             duration: const Duration(milliseconds: 400),
  //             switchInCurve: Curves.easeOutCubic,
  //             switchOutCurve: Curves.easeInCubic,
  //             transitionBuilder: (child, animation) {
  //               return FadeTransition(
  //                 opacity: animation,
  //                 child: SlideTransition(
  //                   position:
  //                       Tween<Offset>(
  //                         begin: const Offset(0, 0.02),
  //                         end: Offset.zero,
  //                       ).animate(
  //                         CurvedAnimation(
  //                           parent: animation,
  //                           curve: Curves.easeOutCubic,
  //                         ),
  //                       ),
  //                   child: child,
  //                 ),
  //               );
  //             },
  //             child: isSearching
  //                 ? ShimmerLoading(
  //                     key: const ValueKey('loading'),
  //                     child: SingleChildScrollView(
  //                       padding: const EdgeInsets.all(AppSpacing.lg),
  //                       child: Column(
  //                         crossAxisAlignment: CrossAxisAlignment.start,
  //                         children: [
  //                           SkeletonBox(width: 80, height: 24, borderRadius: 4),
  //                           const SizedBox(height: AppSpacing.md),
  //                           ...List.generate(8, (index) {
  //                             return Container(
  //                               padding: const EdgeInsets.symmetric(
  //                                 horizontal: 16,
  //                                 vertical: 8,
  //                               ),
  //                               margin: const EdgeInsets.only(bottom: 8),
  //                               height: 70,
  //                               child: Row(
  //                                 children: [
  //                                   SkeletonBox(
  //                                     width: 54,
  //                                     height: 54,
  //                                     borderRadius: 6,
  //                                   ),
  //                                   const SizedBox(width: 12),
  //                                   Expanded(
  //                                     child: Column(
  //                                       mainAxisAlignment:
  //                                           MainAxisAlignment.center,
  //                                       crossAxisAlignment:
  //                                           CrossAxisAlignment.start,
  //                                       children: [
  //                                         SkeletonBox(
  //                                           width: double.infinity,
  //                                           height: 16,
  //                                           borderRadius: 4,
  //                                         ),
  //                                         const SizedBox(height: 6),
  //                                         SkeletonBox(
  //                                           width: 150,
  //                                           height: 12,
  //                                           borderRadius: 4,
  //                                         ),
  //                                       ],
  //                                     ),
  //                                   ),
  //                                   const SizedBox(width: 8),
  //                                   SkeletonBox(
  //                                     width: 35,
  //                                     height: 11,
  //                                     borderRadius: 4,
  //                                   ),
  //                                 ],
  //                               ),
  //                             );
  //                           }),
  //                         ],
  //                       ),
  //                     ),
  //                   )
  //                 : searchResults.isNotEmpty
  //                 ? SingleChildScrollView(
  //                     key: ValueKey('results-${searchResults.length}'),
  //                     padding: const EdgeInsets.all(AppSpacing.lg),
  //                     child: Column(
  //                       crossAxisAlignment: CrossAxisAlignment.start,
  //                       children: [
  //                         TweenAnimationBuilder<double>(
  //                           duration: const Duration(milliseconds: 350),
  //                           curve: Curves.easeOutCubic,
  //                           tween: Tween(begin: 0.0, end: 1.0),
  //                           builder: (context, value, child) {
  //                             return Opacity(
  //                               opacity: value,
  //                               child: Transform.translate(
  //                                 offset: Offset(0, 10 * (1 - value)),
  //                                 child: child,
  //                               ),
  //                             );
  //                           },
  //                           child: Text(
  //                             'Results',
  //                             style: AppTypography.sectionHeader.copyWith(
  //                               color: textPrimaryColor,
  //                             ),
  //                           ),
  //                         ),
  //                         const SizedBox(height: AppSpacing.md),
  //                         ...searchResults.asMap().entries.map((entry) {
  //                           final index = entry.key;
  //                           final song = entry.value;
  //                           final durationInSeconds = song.duration != null
  //                               ? _parseDurationToSeconds(song.duration!)
  //                               : null;

  //                           return TweenAnimationBuilder<double>(
  //                             duration: Duration(
  //                               milliseconds: 350 + (index * 40),
  //                             ),
  //                             curve: Curves.easeOutCubic,
  //                             tween: Tween(begin: 0.0, end: 1.0),
  //                             builder: (context, value, child) {
  //                               return Opacity(
  //                                 opacity: value,
  //                                 child: Transform.translate(
  //                                   offset: Offset(0, 15 * (1 - value)),
  //                                   child: child,
  //                                 ),
  //                               );
  //                             },
  //                             child: _buildSearchResultItem(
  //                               videoId: song.videoId,
  //                               title: song.title,
  //                               subtitle: song.artists.join(', '),
  //                               thumbnail: song.thumbnail,
  //                               duration: durationInSeconds,
  //                               formattedDuration: song.duration,
  //                               onTap: () async {
  //                                 final helper = YTMusicSuggestionsHelper();
  //                                 await helper.saveToHistory(
  //                                   _searchController.text,
  //                                 );
  //                                 helper.dispose();

  //                                 final quickPick = QuickPick(
  //                                   videoId: song.videoId,
  //                                   title: song.title,
  //                                   artists: song.artists.join(', '),
  //                                   thumbnail: song.thumbnail,
  //                                   duration: song.duration,
  //                                 );

  //                                 await LastPlayedService.saveLastPlayed(
  //                                   quickPick,
  //                                 );
  //                                 setState(() {
  //                                   _lastPlayedSong = quickPick;
  //                                 });

  //                                 NewPlayerPage.open(context, quickPick);
  //                               },
  //                               ref: ref,
  //                             ),
  //                           );
  //                         }).toList(),
  //                       ],
  //                     ),
  //                   )
  //                 : Center(
  //                     key: const ValueKey('empty'),
  //                     child: Padding(
  //                       padding: const EdgeInsets.all(32.0),
  //                       child: Column(
  //                         mainAxisAlignment: MainAxisAlignment.center,
  //                         children: [
  //                           Icon(
  //                             Icons.music_off,
  //                             size: 64,
  //                             color: textSecondaryColor.withOpacity(0.5),
  //                           ),
  //                           const SizedBox(height: 16),
  //                           Text(
  //                             'No results found',
  //                             style: AppTypography.subtitle.copyWith(
  //                               color: textSecondaryColor,
  //                             ),
  //                           ),
  //                           const SizedBox(height: 8),
  //                           Text(
  //                             'Try a different search term',
  //                             style: AppTypography.caption.copyWith(
  //                               color: textSecondaryColor.withOpacity(0.7),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                     ),
  //                   ),
  //           ),
  //         ),
  //     ],
  //   );
  // }

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
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

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
                    style: AppTypography.songTitle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor, fontSize: 12),
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
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: textSecondaryColor, fontSize: 11),
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
    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: sidebarLabelActiveColor);

    // Watch if user has access code
    final hasAccessCodeAsync = ref.watch(hasAccessCodeProvider);
    (context);

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

    final pageTitleStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textPrimaryColor);
    final hintStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textSecondaryColor.withOpacity(0.5));

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
                    cursorColor: iconActiveColor,
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
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              // Stop audio player
              try {
                await AudioServices.instance.stop();
                print('🛑 Audio stopped before access code entry');
              } catch (e) {
                print('⚠️ Error stopping audio: $e');
              }

              await Future.delayed(const Duration(milliseconds: 100));

              if (context.mounted) {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => const AccessCodeScreen(
                      showSkipButton: false,
                      isFromDialog: true, // NEW FLAG
                    ),
                    fullscreenDialog: true,
                  ),
                );

                // Refresh if code was entered successfully
                if (result == true && context.mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Access code verified successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
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
          style: AppTypography.subtitle(
            context,
          ).copyWith(color: textPrimaryColor),
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
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return GestureDetector(
      onTap: () async {
        await LastPlayedService.saveLastPlayed(quickPick);
        if (mounted) {
          setState(() => _lastPlayedSong = quickPick);

          // 🔥 Play with quickPick source type
          final handler = getAudioHandler();
          if (handler != null) {
            await handler.playSong(
              quickPick,
              sourceType: RadioSourceType.quickPick, // ✅ SPECIFY SOURCE
            );
          }

          _openPlayer(quickPick, heroTag: 'thumbnail-${quickPick.videoId}');
        }
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
                    style: AppTypography.songTitle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quickPick.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor),
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
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: AppColors.textSecondary),
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
              style: AppTypography.subtitle(
                context,
              ).copyWith(fontWeight: FontWeight.w600, color: textPrimaryColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Text(
              album.artist,
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (album.year > 0) ...[
              const SizedBox(height: AppSpacing.xs / 2),
              Text(
                album.year.toString(),
                style: AppTypography.captionSmall(
                  context,
                ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
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
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor),
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
                    style: AppTypography.subtitle(
                      context,
                    ).copyWith(color: AppColors.textSecondary),
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

  Widget _buildFeaturedPlaylist() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: iconActiveColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Featured Playlist',
                    style: AppTypography.sectionHeader(
                      context,
                    ).copyWith(color: textPrimaryColor),
                  ),
                ],
              ),
              if (_isLoadingFeaturedPlaylist)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconActiveColor,
                  ),
                )
              else if (_featuredPlaylist != null)
                IconButton(
                  icon: Icon(Icons.refresh, color: iconActiveColor),
                  onPressed: _loadFeaturedPlaylist,
                  tooltip: 'Refresh playlist',
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Subtitle with date
        if (_featuredPlaylist != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              _featuredPlaylist!.formattedDate,
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor, fontSize: 12),
            ),
          ),

        const SizedBox(height: AppSpacing.md),

        // Loading state
        if (_isLoadingFeaturedPlaylist)
          ShimmerLoading(
            child: SizedBox(
              height: 320,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                itemCount: 5,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: 160,
                            height: 160,
                            borderRadius: AppSpacing.radiusMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SkeletonBox(width: 160, height: 14, borderRadius: 4),
                          const SizedBox(height: 6),
                          SkeletonBox(width: 120, height: 12, borderRadius: 4),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          )
        // Empty state - Not eligible
        else if (_featuredPlaylist == null && !_isLoadingFeaturedPlaylist)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    _eligibilityStatus != null &&
                            _eligibilityStatus!.uniqueSongs > 0
                        ? Icons.hourglass_empty
                        : Icons.lock_outline,
                    size: 48,
                    color: textSecondaryColor.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _eligibilityStatus != null &&
                            _eligibilityStatus!.uniqueSongs > 0
                        ? 'Keep listening to unlock!'
                        : 'Start listening to unlock',
                    style: AppTypography.subtitle(context).copyWith(
                      color: textPrimaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Progress indicators
                  if (_eligibilityStatus != null) ...[
                    // Songs progress
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Unique Songs',
                                style: AppTypography.caption(
                                  context,
                                ).copyWith(color: textSecondaryColor),
                              ),
                              Text(
                                '${_eligibilityStatus!.uniqueSongs} / ${GatingRules.minUniqueSongs}', // ✅ USE CONSTANT
                                style: AppTypography.caption(context).copyWith(
                                  color:
                                      _eligibilityStatus!.uniqueSongs >=
                                          GatingRules
                                              .minUniqueSongs // ✅ USE CONSTANT
                                      ? Colors.green
                                      : textPrimaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value:
                                (_eligibilityStatus!.uniqueSongs /
                                        GatingRules.minUniqueSongs)
                                    .clamp(0.0, 1.0), // ✅ USE CONSTANT
                            backgroundColor: textSecondaryColor.withOpacity(
                              0.2,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _eligibilityStatus!.uniqueSongs >=
                                      GatingRules
                                          .minUniqueSongs // ✅ USE CONSTANT
                                  ? Colors.green
                                  : iconActiveColor,
                            ),
                          ),
                          if (_eligibilityStatus!.songsRemaining > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${_eligibilityStatus!.songsRemaining} more songs needed',
                                style: AppTypography.captionSmall(context)
                                    .copyWith(
                                      color: textSecondaryColor.withOpacity(
                                        0.7,
                                      ),
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Days progress
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Listening Days',
                                style: AppTypography.caption(
                                  context,
                                ).copyWith(color: textSecondaryColor),
                              ),
                              Text(
                                '${_eligibilityStatus!.listeningDays} / ${GatingRules.minListeningDays}', // ✅ USE CONSTANT
                                style: AppTypography.caption(context).copyWith(
                                  color:
                                      _eligibilityStatus!.listeningDays >=
                                          GatingRules
                                              .minListeningDays // ✅ USE CONSTANT
                                      ? Colors.green
                                      : textPrimaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value:
                                (_eligibilityStatus!.listeningDays /
                                        GatingRules.minListeningDays)
                                    .clamp(0.0, 1.0), // ✅ USE CONSTANT
                            backgroundColor: textSecondaryColor.withOpacity(
                              0.2,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _eligibilityStatus!.listeningDays >=
                                      GatingRules
                                          .minListeningDays // ✅ USE CONSTANT
                                  ? Colors.green
                                  : iconActiveColor,
                            ),
                          ),
                          if (_eligibilityStatus!.daysRemaining > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${_eligibilityStatus!.daysRemaining} more days needed',
                                style: AppTypography.captionSmall(context)
                                    .copyWith(
                                      color: textSecondaryColor.withOpacity(
                                        0.7,
                                      ),
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else
                    Text(
                      'Listen to 35+ unique songs over 7 days',
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: textSecondaryColor),
                      textAlign: TextAlign.center,
                    ),

                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadFeaturedPlaylist,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text(
                      'Check Progress',
                      style: TextStyle(color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconActiveColor,
                    ),
                  ),
                ],
              ),
            ),
          )
        // Playlist loaded
        else if (_featuredPlaylist != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Horizontal scrolling song cards
              SizedBox(
                height: 220,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 16),
                  itemCount: _featuredPlaylist!.songs.take(10).length,
                  itemBuilder: (context, index) {
                    final song = _featuredPlaylist!.songs[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildFeaturedSongCard(song),
                    );
                  },
                ),
              ),

              // View all button
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: TextButton.icon(
                  onPressed: () {
                    _showFullPlaylist();
                  },
                  icon: Icon(Icons.playlist_play, color: iconActiveColor),
                  label: Text(
                    'View All ${_featuredPlaylist!.songs.length} Songs',
                    style: TextStyle(color: iconActiveColor),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // 6. ADD FEATURED SONG CARD WIDGET
  Widget _buildFeaturedSongCard(PlaylistSong song) {
    const double size = 140;
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return GestureDetector(
      onTap: () async {
        // Search for the song and play it
        await _searchAndPlayFeaturedSong(song);
      },
      child: Container(
        width: size,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Placeholder album art (since we don't have it from AI)
            ClipRRect(
              borderRadius: BorderRadius.circular(size * thumbnailRadius),
              child: Container(
                width: size - 24,
                height: size - 24,
                color: Colors.grey[800],
                child: const Center(
                  child: Icon(Icons.music_note, color: Colors.grey, size: 40),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              song.title,
              style: AppTypography.subtitle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: textPrimaryColor,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              song.artist,
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // 7. ADD METHOD TO SEARCH AND PLAY FEATURED SONG
  Future<void> _searchAndPlayFeaturedSong(PlaylistSong song) async {
    try {
      // Show loading indicator
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Searching for ${song.title}...'),
          duration: const Duration(seconds: 2),
        ),
      );

      // Search for the song
      final searchQuery = '${song.title} ${song.artist}';
      final results = await _searchHelper.searchSongs(searchQuery, limit: 1);

      if (results.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Song not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Play the first result
      final foundSong = results.first;
      final quickPick = QuickPick(
        videoId: foundSong.videoId,
        title: foundSong.title,
        artists: foundSong.artists.join(', '),
        thumbnail: foundSong.thumbnail,
        duration: foundSong.duration,
      );

      await LastPlayedService.saveLastPlayed(quickPick);

      if (!mounted) return;

      setState(() {
        _lastPlayedSong = quickPick;
      });

      _openPlayer(
        quickPick,
        heroTag: 'featured-thumbnail-${quickPick.videoId}',
      );
    } catch (e) {
      print('❌ Error playing featured song: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to play song'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 8. ADD METHOD TO SHOW FULL PLAYLIST
  void _showFullPlaylist() {
    if (_featuredPlaylist == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final backgroundColor = ref.read(themeBackgroundColorProvider);
        final textPrimaryColor = ref.read(themeTextPrimaryColorProvider);
        final textSecondaryColor = ref.read(themeTextSecondaryColorProvider);
        final cardBackgroundColor = ref.read(themeCardBackgroundColorProvider);

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBackgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textSecondaryColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: textPrimaryColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Featured Playlist',
                                style: AppTypography.pageTitle(
                                  context,
                                ).copyWith(color: textPrimaryColor),
                              ),
                              Text(
                                _featuredPlaylist!.formattedDate,
                                style: AppTypography.caption(
                                  context,
                                ).copyWith(color: textSecondaryColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: textPrimaryColor),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Song list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _featuredPlaylist!.songs.length,
                  itemBuilder: (context, index) {
                    final song = _featuredPlaylist!.songs[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cardBackgroundColor,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: textPrimaryColor),
                        ),
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(color: textPrimaryColor),
                      ),
                      subtitle: Text(
                        song.artist,
                        style: TextStyle(color: textSecondaryColor),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _searchAndPlayFeaturedSong(song);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Text(
              artist.subscribers,
              style: AppTypography.captionSmall(
                context,
              ).copyWith(color: textSecondaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Replace the _buildMiniPlayer method in your home_page.dart

  Widget _buildMiniPlayer(QuickPick song, MediaItem? currentMedia) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return GestureDetector(
      onTap: () {
        // OPTIMIZED: Direct navigation
        NewPlayerPage.open(
          context,
          song,
          heroTag: 'miniplayer-thumbnail-${song.videoId}',
        );
      },

      child: Container(
        decoration: BoxDecoration(
          color: cardBackgroundColor,
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
            // Extract both playing state and processing state
            final playbackState = playbackSnapshot.data;
            final isPlaying = playbackState?.playing ?? false;
            final processingState =
                playbackState?.processingState ?? AudioProcessingState.idle;

            return Row(
              children: [
                // Album Art
                Hero(
                  tag: 'miniplayer-thumbnail-${song.videoId}',
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(70 * thumbnailRadius),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(70 * thumbnailRadius),
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
                          style: AppTypography.songTitle(context).copyWith(
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
                          style: AppTypography.caption(
                            context,
                          ).copyWith(color: textSecondaryColor, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // Play/Pause Button - FIXED LOGIC
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
                      processingState == AudioProcessingState.loading
                          ? Icons.hourglass_empty
                          : isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: iconActiveColor,
                      size: 24,
                    ),
                    onPressed: () async {
                      if (isPlaying) {
                        // If playing, just pause
                        await _audioService.pause();
                      } else {
                        // If paused/stopped, check if we need to reload
                        if (processingState == AudioProcessingState.idle ||
                            processingState == AudioProcessingState.error) {
                          // Audio source lost - need to reload with playSong
                          print(
                            '🎵 [Miniplayer] Audio source lost, reloading song...',
                          );
                          await _audioService.playSong(song);
                        } else {
                          // Audio source still loaded - just resume
                          print('▶️ [Miniplayer] Resuming playback...');
                          await _audioService.play();
                        }
                      }
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

  Future<void> _openPlayer(QuickPick song, {String? heroTag}) async {
    await NewPlayerPage.open(context, song, heroTag: heroTag);
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

bool _isVersionLower(String current, String latest) {
  List<int> parse(String v) =>
      v.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  final c = parse(current);
  final l = parse(latest);

  final maxLen = c.length > l.length ? c.length : l.length;

  for (int i = 0; i < maxLen; i++) {
    final cv = i < c.length ? c[i] : 0;
    final lv = i < l.length ? l[i] : 0;

    if (cv < lv) return true;
    if (cv > lv) return false;
  }

  return false; // equal versions
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
