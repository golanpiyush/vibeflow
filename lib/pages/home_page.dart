// lib/pages/home_page.dart
// ignore_for_file: unused_local_variable

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miniplayer/miniplayer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/cache_manager.dart';
import 'package:vibeflow/api_base/community_playlistScaper.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/api_base/yt_music_search_suggestor.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/api_base/ytmusic_search_helper.dart';
import 'package:vibeflow/constants/ai_models_config.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/installer_services/update_manager_service.dart';
import 'package:vibeflow/managers/vibeflow_engine_logger.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/pages/access_code_management_screen.dart';
import 'package:vibeflow/pages/album_view.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/artist_view.dart';
import 'package:vibeflow/pages/authOnboard/Screens/social_feed_page.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/pages/subpages/engine_status_screen.dart';
import 'package:vibeflow/pages/subpages/songs/albums_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/artists_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/dailyPLaylist.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/providers/miniplayer_provider.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/services/last_played_service.dart';
import 'package:vibeflow/services/sync_services/musicIntelligence.dart';
import 'package:vibeflow/utils/album_color_generator.dart';
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

class _HomePageState extends ConsumerState<HomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final ScrollController _scrollController = ScrollController();
  final YouTubeMusicScraper _scraper = YouTubeMusicScraper();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final _engineLogger = VibeFlowEngineLogger();
  final _vibeFlowCore = VibeFlowCore();

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
  MediaItem? _cachedMediaItem;
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

  static const List<String> _featuredPlaylistIds = [
    'PLeSOpHVuLnrj3GiP9cYPgbCsDBZviWJab',
    'PL7op4eJJ-4qhnDYjf3yKWDhvd307jbGK6',
    'PLJmgVeYWaLwCGsVp-ug3QTVabyIufjxKD',
    'PLF1dRqxCfd0fYFwNrbe1NSwsuTf7FWskp',
  ];
  List<CommunityPlaylist> _featuredPlaylists = [];
  bool _isLoadingFeaturedPlaylists = false;

  @override
  void initState() {
    super.initState();

    // // ✅ CRITICAL FIX: Use addPostFrameCallback correctly
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (mounted) {
    //     // Hide global miniplayer ONLY on HomePage
    //     ref.read(showGlobalMiniplayerProvider.notifier).state = false;
    //     print('🎵 [HomePage] Hiding global miniplayer (showing local)');
    //   }
    // });

    _albumsScraper = YTMusicAlbumsScraper();
    _artistsScraper = YTMusicArtistsScraper();
    _searchHelper = YTMusicSearchHelper();
    _lastPlayedNotifier = ValueNotifier<QuickPick?>(null);

    // Initialize VibeFlow Engine
    _initializeVibeFlowEngine();

    _initializeApp();

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
        _loadFeaturedPlaylists(), // ✅ ADD THIS LINE
        _loadAlbums(),
        _loadArtists(),
        _fetchRandomArtists(),
        _loadLastPlayedSong(),
      ]);
    } catch (e) {
      print('❌ Error initializing app: $e');
    }
  }

  Future<void> _initializeVibeFlowEngine() async {
    try {
      await _vibeFlowCore.initialize();
      print('✅ VibeFlow Engine initialized');
    } catch (e) {
      print('❌ VibeFlow Engine initialization failed: $e');
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

  Future<void> _loadFeaturedPlaylists() async {
    if (!mounted) return;
    setState(() => _isLoadingFeaturedPlaylists = true);

    try {
      final playlists = <CommunityPlaylist>[];

      // Load each playlist's metadata
      for (final playlistId in _featuredPlaylistIds) {
        try {
          final playlistData = await _scraper.getPlaylistMetadata(playlistId);
          if (playlistData != null) {
            playlists.add(playlistData);
          }
        } catch (e) {
          print('⚠️ Error loading playlist $playlistId: $e');
          // Continue loading other playlists even if one fails
        }
      }

      if (!mounted) return;
      setState(() {
        _featuredPlaylists = playlists;
        _isLoadingFeaturedPlaylists = false;
      });

      print('✅ Loaded ${_featuredPlaylists.length} featured playlists');
    } catch (e) {
      print('❌ Error loading featured playlists: $e');
      if (!mounted) return;
      setState(() => _isLoadingFeaturedPlaylists = false);
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

  // In home_page.dart, update _performSearch method:
  Future<void> _performSearch(String query) async {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => isSearching = true);

    _debounceTimer = Timer(_debounceDuration, () async {
      try {
        final results = await _searchHelper.searchSongs(query, limit: 10);

        if (mounted) {
          setState(() {
            searchResults = results;
            isSearching = false;
          });

          // ✅ CHECK IF HISTORY IS PAUSED BEFORE SAVING
          final prefs = await SharedPreferences.getInstance();
          final isHistoryPaused =
              prefs.getBool('search_history_paused') ?? false;

          if (!isHistoryPaused) {
            final suggestionsHelper = YTMusicSuggestionsHelper();
            await suggestionsHelper.saveToHistory(query);
            suggestionsHelper.dispose();
          }
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
    _debounceTimer?.cancel(); // Cancel previous timer

    // ✅ Update UI immediately (no delay)
    if (!mounted) return;
    setState(() {
      _currentQuery = query;
    });

    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    // ✅ Show loading state immediately
    setState(() => isSearching = true);

    // ✅ Delay the actual search
    _debounceTimer = Timer(_debounceDuration, () async {
      try {
        final results = await _searchHelper.searchSongs(query, limit: 50);

        if (mounted) {
          setState(() {
            searchResults = results;
            isSearching = false;
          });

          final prefs = await SharedPreferences.getInstance();
          final isHistoryPaused =
              prefs.getBool('search_history_paused') ?? false;

          if (!isHistoryPaused) {
            final suggestionsHelper = YTMusicSuggestionsHelper();
            await suggestionsHelper.saveToHistory(query);
            suggestionsHelper.dispose();
          }
        }
      } catch (e) {
        print('Error searching: $e');
        if (mounted) {
          setState(() => isSearching = false);
        }
      }
    });
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
    super.build(context);
    final themeData = Theme.of(context);
    final backgroundColor = themeData.scaffoldBackgroundColor;
    final iconActiveColor = themeData.colorScheme.primary;
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
                      const SizedBox(height: AppSpacing.fourxxxl),
                      _buildTopBar(ref),
                      const SizedBox(height: AppSpacing.xxl),
                      Expanded(
                        child: isSearchMode
                            ? _buildSearchView()
                            : SingleChildScrollView(
                                controller: _scrollController,
                                padding: EdgeInsets.only(
                                  top: AppSpacing.md,
                                  bottom: _lastPlayedSong != null ? 180 : 120,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildQuickPicks(),
                                    const SizedBox(height: 36),
                                    // _buildFeaturedPlaylists(), // ✅ ADD THIS LINE
                                    // const SizedBox(height: 36),
                                    _buildAlbums(),
                                    const SizedBox(height: 36),
                                    _buildSimilarArtists(),
                                    const SizedBox(height: 20),
                                    // if (_hasAccessCode) ...[
                                    //   const SizedBox(height: 36),
                                    //   _buildFeaturedPlaylist(),
                                    // ],
                                    const SizedBox(height: 20),
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
          // _buildOptimizedMiniplayer(),
        ],
      ),
      // FLOATING ACTION BUTTONS - Stack for multiple FABs
      // REPLACE the floatingActionButton section (around line 580-620):
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 95),
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
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail
            Expanded(
              flex: 7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  color: cardBackgroundColor,
                  child:
                      playlist.thumbnail != null &&
                          playlist.thumbnail!.isNotEmpty
                      ? Image.network(
                          playlist.thumbnail!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  iconInactiveColor.withOpacity(0.5),
                                ),
                              ),
                            );
                          },
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

            const SizedBox(height: 8),

            // Text area
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
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

                  const Spacer(),

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

  Widget _buildFeaturedPlaylists() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final cardSize = ResponsiveSpacing.albumCardSize(context);
    final listHeight = cardSize + 90.0; // Slightly taller for playlist info
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Playlists You Might Like',
                style: AppTypography.sectionHeader(context).copyWith(
                  color: textPrimaryColor,
                  fontSize: ResponsiveSpacing.sectionHeaderFontSize(context),
                ),
              ),
              if (_isLoadingFeaturedPlaylists)
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
        const SizedBox(height: 14),

        if (_isLoadingFeaturedPlaylists)
          ShimmerLoading(
            child: SizedBox(
              height: listHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                itemCount: 4,
                cacheExtent: 500,
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: cardSize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: cardSize,
                            height: cardSize,
                            borderRadius: cardSize * thumbnailRadius * 0.08,
                          ),
                          const SizedBox(height: 10),
                          SkeletonBox(
                            width: cardSize,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: cardSize * 0.7,
                            height: 12,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 5),
                          SkeletonBox(width: 60, height: 11, borderRadius: 4),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          )
        else if (_featuredPlaylists.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'No playlists found',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textPrimaryColor.withOpacity(0.6)),
              ),
            ),
          )
        else
          SizedBox(
            height: listHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16),
              cacheExtent: 500,
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
              itemCount: _featuredPlaylists.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: cardSize,
                    height: listHeight,
                    child: _buildFeaturedPlaylistCard(
                      _featuredPlaylists[index],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFeaturedPlaylistCard(CommunityPlaylist playlist) {
    final cardSize = ResponsiveSpacing.albumCardSize(context);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    final double borderRadius = cardSize * thumbnailRadius * 0.08;

    return GestureDetector(
      onTap: () => _openPlaylistDetails(playlist),
      child: SizedBox(
        width: cardSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playlist Cover
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: Container(
                    width: cardSize,
                    height: cardSize,
                    color: cardBackgroundColor,
                    child:
                        playlist.thumbnail != null &&
                            playlist.thumbnail!.isNotEmpty
                        ? Image.network(
                            playlist.thumbnail!,
                            fit: BoxFit.cover,
                            cacheWidth: 500,
                            cacheHeight: 500,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return ShimmerLoading(
                                child: SkeletonBox(
                                  width: cardSize,
                                  height: cardSize,
                                  borderRadius: borderRadius,
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
                                  child: Icon(
                                    Icons.playlist_play,
                                    color: iconInactiveColor,
                                    size: cardSize * 0.3,
                                  ),
                                ),
                          )
                        : Center(
                            child: Icon(
                              Icons.playlist_play,
                              color: iconInactiveColor,
                              size: cardSize * 0.3,
                            ),
                          ),
                  ),
                ),
                // Playlist indicator overlay
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.playlist_play,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${playlist.songCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Playlist Title
            Text(
              playlist.title,
              style: AppTypography.subtitle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: textPrimaryColor,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Creator Name
            Text(
              playlist.creator,
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),

            // Song count
            Text(
              '${playlist.songCount} songs',
              style: AppTypography.captionSmall(
                context,
              ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );
  }

  // Open playlist details
  Future<void> _openPlaylistDetails(CommunityPlaylist playlist) async {
    // Get theme colors
    final themeData = Theme.of(context);
    final surfaceColor = themeData.colorScheme.surface;
    final onSurface = themeData.colorScheme.onSurface;
    final primaryColor = themeData.colorScheme.primary;

    // Show loading dialog with streaming support
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StreamBuilder<List<Song>>(
        stream: _streamPlaylistLoading(playlist.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AlertDialog(
              backgroundColor: surfaceColor,
              title: Text('Error', style: TextStyle(color: onSurface)),
              content: Text(
                'Failed to load playlist: ${snapshot.error}',
                style: TextStyle(color: onSurface.withOpacity(0.8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close', style: TextStyle(color: primaryColor)),
                ),
              ],
            );
          }

          final loadedSongs = snapshot.data ?? [];
          final isComplete = snapshot.connectionState == ConnectionState.done;

          return AlertDialog(
            backgroundColor: surfaceColor,
            title: Text(
              'Loading ${playlist.title}',
              style: TextStyle(color: onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
                const SizedBox(height: 16),
                Text(
                  isComplete
                      ? 'Loaded ${loadedSongs.length} songs'
                      : 'Loading... ${loadedSongs.length} songs',
                  style: TextStyle(
                    fontSize: 14,
                    color: onSurface.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final songs = <Song>[];

      await for (final song in _scraper.streamPlaylistSongs(playlist.id)) {
        songs.add(song);
        if (songs.length % 10 == 0) {
          await CacheManager.instance.cachePlaylistSongs(playlist.id, songs);
        }
      }

      await CacheManager.instance.cachePlaylistSongs(playlist.id, songs);

      if (!mounted) return;
      Navigator.pop(context);

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
          SnackBar(
            content: const Text('No songs found in playlist'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      print('❌ Error loading playlist details: $e');
      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to load playlist'),
          backgroundColor: Theme.of(context).colorScheme.error,
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
                        cacheExtent: 500, // ✅ Pre-render off-screen items
                        addAutomaticKeepAlives: true, // ✅ Keep items alive
                        addRepaintBoundaries: true, // ✅ Isolate repaints
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
                          cacheWidth: 500, // ✅ Reduce memory usage
                          cacheHeight: 500,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
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

  // Replace _buildSidebar() and _buildSidebarItem() in home_page.dart

  Widget _buildSidebar(BuildContext context) {
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final sidebarLabelColor = ref.watch(themeTextPrimaryColorProvider);
    final sidebarLabelActiveColor = ref.watch(themeIconActiveColorProvider);

    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: sidebarLabelActiveColor);

    final hasAccessCodeAsync = ref.watch(hasAccessCodeProvider);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sidebar width
    final sidebarWidth = screenWidth < 360
        ? 52.0
        : screenWidth < 400
        ? 58.0
        : 64.0;

    // Spacing between items scales with screen height
    final itemSpacing = screenHeight < 680
        ? 18.0
        : screenHeight < 740
        ? 22.0
        : screenHeight < 820
        ? 26.0
        : 30.0;

    // Bottom clearance for miniplayer
    final bottomClearance =
        _miniplayerMinHeight + MediaQuery.of(context).padding.bottom + 16;

    return SizedBox(
      width: sidebarWidth,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                screenHeight -
                MediaQuery.of(context).padding.top -
                bottomClearance,
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: screenHeight * 0.042),
                // ← was 0.13, moves icon up
                // Right-aligned edit/appearance icon
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(
                      context,
                    ).pushDropFall(const AppearancePage()),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20, bottom: 20),
                      child: Icon(
                        Icons.settings,
                        size: screenHeight < 740 ? 22.0 : 27.0,
                        color: iconActiveColor,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: AppSpacing.xxxl),

                _buildSidebarItem(
                  label: 'Quick picks',
                  iconActiveColor: iconActiveColor,
                  iconInactiveColor: iconInactiveColor,
                  labelStyle: sidebarLabelStyle,
                  sidebarWidth: sidebarWidth,
                  screenHeight: screenHeight,
                ),

                SizedBox(height: itemSpacing),

                _buildSidebarItem(
                  label: 'Songs',
                  iconActiveColor: iconActiveColor,
                  iconInactiveColor: iconInactiveColor,
                  labelStyle: sidebarLabelStyle,
                  sidebarWidth: sidebarWidth,
                  screenHeight: screenHeight,
                  onTap: () => Navigator.of(context).pushMaterialVertical(
                    const SavedSongsScreen(),
                    slideUp: true,
                    enableParallax: true,
                  ),
                ),

                SizedBox(height: itemSpacing),

                _buildSidebarItem(
                  label: 'Playlists',
                  iconActiveColor: iconActiveColor,
                  iconInactiveColor: iconInactiveColor,
                  labelStyle: sidebarLabelStyle,
                  sidebarWidth: sidebarWidth,
                  screenHeight: screenHeight,
                  onTap: () => Navigator.of(context).pushMaterialVertical(
                    const IntegratedPlaylistsScreen(),
                    slideUp: true,
                    enableParallax: true,
                  ),
                ),

                SizedBox(height: itemSpacing),

                _buildSidebarItem(
                  label: 'Artists',
                  iconActiveColor: iconActiveColor,
                  iconInactiveColor: iconInactiveColor,
                  labelStyle: sidebarLabelStyle,
                  sidebarWidth: sidebarWidth,
                  screenHeight: screenHeight,
                  onTap: () => Navigator.of(context).pushMaterialVertical(
                    const ArtistsGridPage(),
                    slideUp: true,
                  ),
                ),

                SizedBox(height: itemSpacing),

                _buildSidebarItem(
                  label: 'Albums',
                  iconActiveColor: iconActiveColor,
                  iconInactiveColor: iconInactiveColor,
                  labelStyle: sidebarLabelStyle,
                  sidebarWidth: sidebarWidth,
                  screenHeight: screenHeight,
                  onTap: () => Navigator.of(
                    context,
                  ).pushMaterialVertical(const AlbumsGridPage(), slideUp: true),
                ),

                hasAccessCodeAsync.when(
                  data: (hasAccessCode) {
                    if (!hasAccessCode) return const SizedBox.shrink();
                    return Column(
                      children: [
                        SizedBox(height: itemSpacing),
                        _buildSidebarItem(
                          label: 'Social',
                          iconActiveColor: iconActiveColor,
                          iconInactiveColor: iconInactiveColor,
                          labelStyle: sidebarLabelStyle,
                          sidebarWidth: sidebarWidth,
                          screenHeight: screenHeight,
                          onTap: () =>
                              Navigator.of(context).pushMaterialVertical(
                                const SocialScreen(),
                                slideUp: true,
                                enableParallax: true,
                              ),
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                SizedBox(height: bottomClearance),
              ],
            ),
          ),
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
    required double sidebarWidth,
    required double screenHeight,
    VoidCallback? onTap,
  }) {
    // Font size scales with screen height
    final fontSize = screenHeight < 680
        ? 13.0
        : screenHeight < 740
        ? 14.0
        : screenHeight < 820
        ? 15.0
        : 16.0;

    // Icon size scales too
    final iconSize = screenHeight < 680
        ? 20.0
        : screenHeight < 740
        ? 22.0
        : 24.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: sidebarWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: iconSize,
                color: isActive ? iconActiveColor : iconInactiveColor,
              )
            else
              RotatedBox(
                quarterTurns: -1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: labelStyle.copyWith(
                    fontSize: fontSize,
                    letterSpacing: 0.4,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.visible,
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
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    final titleFontSize = ResponsiveSpacing.pageTitleFontSize(context);

    final pageTitleStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textPrimaryColor, fontSize: titleFontSize);
    final hintStyle = AppTypography.pageTitle(context).copyWith(
      color: textSecondaryColor.withOpacity(0.5),
      fontSize: titleFontSize * 0.65,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: backgroundColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
              icon: Icon(Icons.arrow_back, color: iconActiveColor, size: 26),
            )
          else
            Row(
              children: [
                // Engine status indicator
                ListenableBuilder(
                  listenable: _engineLogger,
                  builder: (context, _) {
                    final isEngineRunning = _engineLogger.isEngineInitialized;
                    final hasActiveOps =
                        _engineLogger.activeOperations.isNotEmpty;
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const EngineStatusScreen(),
                          ),
                        );
                      },
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isEngineRunning
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.settings_input_component,
                              color: isEngineRunning
                                  ? Colors.green
                                  : Colors.grey,
                              size: 22,
                            ),
                          ),
                          if (hasActiveOps)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isEngineRunning
                                    ? Colors.green
                                    : Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isEngineRunning ? Icons.check : Icons.close,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(width: 8),

                // Access code indicator
                Consumer(
                  builder: (context, ref, child) {
                    final hasAccessCodeAsync = ref.watch(hasAccessCodeProvider);
                    return hasAccessCodeAsync.when(
                      data: (hasAccessCode) {
                        return GestureDetector(
                          onTap: hasAccessCode
                              ? () => Navigator.of(
                                  context,
                                ).pushFade(const AccessCodeManagementScreen())
                              : () => _showNoAccessCodeDialog(context),
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
                                  hasAccessCode
                                      ? Icons.security
                                      : Icons.lock_open,
                                  color: hasAccessCode
                                      ? Colors.deepPurple
                                      : iconActiveColor,
                                  size: 22,
                                ),
                              ),
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
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, __) => GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
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
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 22,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

          Expanded(
            child: isSearchMode
                ? TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textAlign: TextAlign.right,
                    style: pageTitleStyle,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: hintStyle,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    cursorColor: iconActiveColor,
                    onChanged: _onSearchChanged,
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
    final themeData = Theme.of(context);
    final surfaceColor = themeData.colorScheme.surface;
    final onSurface = themeData.colorScheme.onSurface;
    final primaryColor = themeData.colorScheme.primary;
    final onPrimary = themeData.colorScheme.onPrimary;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text('No Access Code', style: TextStyle(color: onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You don\'t have an access code yet.',
              style: TextStyle(color: onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Access code is required to manage access settings.',
              style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: primaryColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

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
                      isFromDialog: true,
                    ),
                    fullscreenDialog: true,
                  ),
                );

                if (result == true && context.mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Access code verified successfully!'),
                      backgroundColor: primaryColor,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: onPrimary,
            ),
            child: const Text('Enter Code'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPicks() {
    // Get theme colors
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    final itemHeight = ResponsiveSpacing.listItemHeight(context);
    final totalHeight = itemHeight * 4 + 4;

    if (isLoadingQuickPicks) {
      return ShimmerLoading(
        child: SizedBox(
          height: totalHeight,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.95),
            itemCount: 2,
            itemBuilder: (context, pageIndex) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Column(
                  children: List.generate(4, (i) {
                    final artSize = ResponsiveSpacing.albumArtSize(context);
                    final vertPad = (itemHeight - artSize) / 2;
                    return Container(
                      height: itemHeight,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: vertPad,
                      ),
                      child: Row(
                        children: [
                          SkeletonBox(
                            width: artSize,
                            height: artSize,
                            borderRadius: 12,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(
                                  width: double.infinity,
                                  height: 15,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 6),
                                SkeletonBox(
                                  width: 160,
                                  height: 13,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),
      );
    }

    if (quickPicks.isEmpty) {
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
      height: totalHeight,
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
                    height: itemHeight,
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
    // ✅ ADD THESE LINES at the start:
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    final artSize = ResponsiveSpacing.albumArtSize(context);
    final itemHeight = ResponsiveSpacing.listItemHeight(context);
    final verticalPad = (itemHeight - artSize) / 2;

    return GestureDetector(
      onTap: () async {
        await LastPlayedService.saveLastPlayed(quickPick);
        if (mounted) {
          setState(() => _lastPlayedSong = quickPick);
          final handler = getAudioHandler();
          if (handler != null) {
            await handler.playSong(
              quickPick,
              sourceType: RadioSourceType.quickPick,
            );
          }
          _openPlayer(quickPick, heroTag: 'thumbnail-${quickPick.videoId}');
        }
      },
      child: Container(
        height: itemHeight,
        padding: EdgeInsets.only(
          left: 0,
          right: 12,
          top: verticalPad,
          bottom: verticalPad,
        ),
        child: Row(
          children: [
            // 🔥 FIXED: Removed SizedBox, let AspectRatio control the size
            Hero(
              tag: 'thumbnail-${quickPick.videoId}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(artSize * thumbnailRadius),
                child: SizedBox(
                  width: artSize,
                  height: artSize,
                  child: quickPick.thumbnail.isNotEmpty
                      ? Image.network(
                          quickPick.thumbnail,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return ShimmerLoading(
                              child: Container(
                                width: artSize,
                                height: artSize,
                                color: cardBackgroundColor,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            width: artSize,
                            height: artSize,
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
                          width: artSize,
                          height: artSize,
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
            const SizedBox(width: 10),
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
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quickPick.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subtitle(
                      context,
                    ).copyWith(color: textSecondaryColor, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbums() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final cardSize = ResponsiveSpacing.albumCardSize(context);
    final listHeight = cardSize + 72.0;
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Albums',
                style: AppTypography.sectionHeader(context).copyWith(
                  color: textPrimaryColor,
                  fontSize: ResponsiveSpacing.sectionHeaderFontSize(context),
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
        const SizedBox(height: 14),
        if (isLoadingAlbums)
          ShimmerLoading(
            child: SizedBox(
              height: listHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                itemCount: 5,
                cacheExtent: 500,
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: cardSize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: cardSize,
                            height: cardSize,
                            borderRadius: cardSize * thumbnailRadius * 0.08,
                          ),
                          const SizedBox(height: 10),
                          SkeletonBox(
                            width: cardSize,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: cardSize * 0.7,
                            height: 12,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 5),
                          SkeletonBox(width: 40, height: 11, borderRadius: 4),
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
                ).copyWith(color: textPrimaryColor.withOpacity(0.6)),
              ),
            ),
          )
        else
          SizedBox(
            height: listHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16),
              cacheExtent: 500,
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
              itemCount: relatedAlbums.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: cardSize,
                    height: listHeight,
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
    final cardSize = ResponsiveSpacing.albumCardSize(context);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    // ✅ ADD THESE LINES:
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    final double borderRadius = cardSize * thumbnailRadius * 0.08;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AlbumPage(album: album)),
        );
      },
      child: SizedBox(
        width: cardSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Container(
                width: cardSize,
                height: cardSize,
                color: cardBackgroundColor,
                child: album.coverArt != null && album.coverArt!.isNotEmpty
                    ? Image.network(
                        album.coverArt!,
                        fit: BoxFit.cover,
                        cacheWidth: 500,
                        cacheHeight: 500,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return ShimmerLoading(
                            child: SkeletonBox(
                              width: cardSize,
                              height: cardSize,
                              borderRadius: borderRadius,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Icon(
                            Icons.album,
                            color: iconInactiveColor,
                            size: cardSize * 0.3,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.album,
                          color: iconInactiveColor,
                          size: cardSize * 0.3,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            // ✅ UPDATE THIS TEXT:
            Text(
              album.title,
              style: AppTypography.subtitle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: textPrimaryColor, // ✅ ADDED
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // ✅ UPDATE THIS TEXT:
            Text(
              album.artist,
              style: AppTypography.caption(context).copyWith(
                color: textSecondaryColor, // ✅ ADDED
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (album.year > 0) ...[
              const SizedBox(height: 3),
              // ✅ UPDATE THIS TEXT:
              Text(
                album.year.toString(),
                style: AppTypography.captionSmall(context).copyWith(
                  color: textSecondaryColor.withOpacity(0.7), // ✅ ADDED
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSimilarArtists() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    final imageSize = ResponsiveSpacing.artistImageSize(context);
    final cardWidth = ResponsiveSpacing.artistCardWidth(context);
    final listHeight = imageSize + 56.0;

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
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Similar artists',
                style: AppTypography.sectionHeader(context).copyWith(
                  color: textPrimaryColor,
                  fontSize: ResponsiveSpacing.sectionHeaderFontSize(context),
                ),
              ),
              Row(
                children: [
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
        const SizedBox(height: 14),
        if (isLoadingArtists)
          ShimmerLoading(
            child: SizedBox(
              height: listHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16),
                itemCount: 8,
                cacheExtent: 500,
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  return Container(
                    width: cardWidth,
                    margin: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        SkeletonBox(
                          width: imageSize,
                          height: imageSize,
                          borderRadius: imageSize / 2,
                        ),
                        const SizedBox(height: 10),
                        SkeletonBox(width: 70, height: 13, borderRadius: 4),
                        const SizedBox(height: 5),
                        SkeletonBox(width: 50, height: 11, borderRadius: 4),
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
                    ).copyWith(color: textPrimaryColor.withOpacity(0.6)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _fetchRandomArtists,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Load Artists'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconActiveColor,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: listHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16),
              itemCount: artistsWithImages.length,
              cacheExtent: 500,
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
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
    // ✅ ADD THESE LINES:
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    final imageSize = ResponsiveSpacing.artistImageSize(context);
    final cardWidth = ResponsiveSpacing.artistCardWidth(context);

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
        width: cardWidth,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            ClipOval(
              child: Container(
                width: imageSize,
                height: imageSize,
                color: cardBackgroundColor,
                child: artist.profileImage != null
                    ? Image.network(
                        artist.profileImage!,
                        fit: BoxFit.cover,
                        cacheWidth: 500,
                        cacheHeight: 500,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return ShimmerLoading(
                            child: SkeletonBox(
                              width: imageSize,
                              height: imageSize,
                              borderRadius: imageSize / 2,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.person,
                              color: iconInactiveColor,
                              size: imageSize * 0.42,
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Icon(
                          Icons.person,
                          color: iconInactiveColor,
                          size: imageSize * 0.42,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            // ✅ UPDATE THIS TEXT:
            Text(
              artist.name,
              style: AppTypography.subtitle(context).copyWith(
                color: textPrimaryColor, // ✅ ADDED
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            // ✅ UPDATE THIS TEXT:
            Text(
              artist.subscribers,
              style: AppTypography.captionSmall(context).copyWith(
                color: textSecondaryColor, // ✅ ADDED
                fontSize: 11,
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
                cacheExtent: 500, // ✅ Pre-render off-screen items
                addAutomaticKeepAlives: true, // ✅ Keep items alive
                addRepaintBoundaries: true, // ✅ Isolate repaints
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
                  cacheExtent: 500, // ✅ Pre-render off-screen items
                  addAutomaticKeepAlives: true, // ✅ Keep items alive
                  addRepaintBoundaries: true, // ✅ Isolate repaints
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

  Widget _buildFeaturedSongCard(PlaylistSong song) {
    const double size = 140;
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    // ✅ ADD THESE LINES:
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    return GestureDetector(
      onTap: () async {
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
            ClipRRect(
              borderRadius: BorderRadius.circular(size * thumbnailRadius),
              child: Container(
                width: size - 24,
                height: size - 24,
                color: cardBackgroundColor.withOpacity(0.5),
                child: const Center(
                  child: Icon(Icons.music_note, color: Colors.grey, size: 40),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // ✅ UPDATE THIS TEXT:
            Text(
              song.title,
              style: AppTypography.subtitle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: textPrimaryColor, // ✅ ADDED
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // ✅ UPDATE THIS TEXT:
            Text(
              song.artist,
              style: AppTypography.caption(context).copyWith(
                color: textSecondaryColor, // ✅ ADDED
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
                  cacheExtent: 500, // ✅ Pre-render off-screen items
                  addAutomaticKeepAlives: true, // ✅ Keep items alive
                  addRepaintBoundaries: true, // ✅ Isolate repaints
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

  // Enhanced Miniplayer with Album Colors - Matching Reference Design
  // Replace your _buildMiniPlayer method with this code

  Widget _buildMiniPlayer(QuickPick song, MediaItem? currentMedia) {
    final thumbnailRadius = ref.watch(thumbnailRadiusProvider);

    // Get artwork URL
    final artworkUrl = currentMedia?.artUri?.toString() ?? song.thumbnail;

    return FutureBuilder<AlbumPalette?>(
      future: artworkUrl.isNotEmpty
          ? AlbumColorGenerator.fromAnySource(artworkUrl).catchError((e) {
              print('❌ Error extracting colors: $e');
              return null;
            })
          : Future.value(null),
      builder: (context, colorSnapshot) {
        // Get theme colors as fallback
        final themeData = Theme.of(context);
        final surfaceColor = themeData.colorScheme.surface;
        final onSurface = themeData.colorScheme.onSurface;

        // Show loading state while extracting colors
        if (colorSnapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: _miniplayerMinHeight,
            color: surfaceColor,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  onSurface.withOpacity(0.5),
                ),
              ),
            ),
          );
        }

        // Use album colors if available, otherwise use theme colors
        final palette = colorSnapshot.data;
        final dominantColor = palette?.dominant ?? surfaceColor;
        final mutedColor = palette?.muted ?? surfaceColor.withOpacity(0.8);

        // Use theme colors for text and controls
        const titleColor = Colors.white;
        const subtitleColor = Colors.white70;
        const controlColor = Colors.white;

        return GestureDetector(
          onTap: () {
            NewPlayerPage.open(
              context,
              song,
              heroTag: 'miniplayer-thumbnail-${song.videoId}',
            );
          },
          child: Container(
            height: _miniplayerMinHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  dominantColor.withOpacity(0.95),
                  mutedColor.withOpacity(0.85),
                ],
              ),
            ),
            child: StreamBuilder<PlaybackState>(
              stream: _audioService.playbackStateStream,
              builder: (context, playbackSnapshot) {
                final playbackState = playbackSnapshot.data;
                final isPlaying = playbackState?.playing ?? false;
                final processingState =
                    playbackState?.processingState ?? AudioProcessingState.idle;
                final isLoading =
                    processingState == AudioProcessingState.loading;

                return Stack(
                  children: [
                    // Progress bar as gradient overlay
                    StreamBuilder<Duration>(
                      stream: _audioService.positionStream,
                      builder: (context, positionSnapshot) {
                        final position = positionSnapshot.data ?? Duration.zero;
                        final duration =
                            currentMedia?.duration ?? Duration.zero;
                        final progress = duration.inMilliseconds > 0
                            ? position.inMilliseconds / duration.inMilliseconds
                            : 0.0;

                        return Positioned.fill(
                          child: Row(
                            children: [
                              // PLAYED portion
                              if (progress > 0)
                                Expanded(
                                  flex: (progress * 100).round().clamp(1, 100),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          dominantColor.withOpacity(0.95),
                                          mutedColor.withOpacity(0.85),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              // UNPLAYED portion
                              if (progress < 1)
                                Expanded(
                                  flex: ((1 - progress) * 100).round().clamp(
                                    1,
                                    100,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          dominantColor.withOpacity(0.4),
                                          mutedColor.withOpacity(0.3),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Main content
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Album Art
                          Hero(
                            tag: 'miniplayer-thumbnail-${song.videoId}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 54,
                                height: 54,
                                color: surfaceColor,
                                child: artworkUrl.isNotEmpty
                                    ? buildAlbumArtImage(
                                        artworkUrl: artworkUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _buildMiniThumbnailFallback(
                                              ref,
                                              thumbnailRadius,
                                            ),
                                      )
                                    : _buildMiniThumbnailFallback(
                                        ref,
                                        thumbnailRadius,
                                      ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 14),

                          // Song Info
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentMedia?.title ?? song.title,
                                  style: const TextStyle(
                                    color: titleColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currentMedia?.artist ?? song.artists,
                                  style: const TextStyle(
                                    color: subtitleColor,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Play/Pause Button
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: isLoading
                                ? const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              controlColor,
                                            ),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: controlColor,
                                      size: 28,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () async {
                                      if (isPlaying) {
                                        await _audioService.pause();
                                      } else {
                                        if (processingState ==
                                                AudioProcessingState.idle ||
                                            processingState ==
                                                AudioProcessingState.error) {
                                          await _audioService.playSong(song);
                                        } else {
                                          await _audioService.play();
                                        }
                                      }
                                    },
                                  ),
                          ),

                          const SizedBox(width: 4),

                          // Next Button
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              icon: const Icon(
                                Icons.skip_next,
                                color: controlColor,
                                size: 28,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => _audioService.skipToNext(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
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
    _debounceTimer?.cancel(); // ✅ Cancel timer first
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchHelper.dispose();
    _lastPlayedNotifier.dispose(); // ✅ Dispose notifier
    _cachedMediaItem = null; // ✅ Clear cache
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
