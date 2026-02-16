// lib/pages/artists_grid_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:vibeflow/api_base/ytmusic_artists_scraper.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/artist_view.dart';
import 'package:vibeflow/pages/subpages/songs/albums_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/widgets/shimmer_loadings.dart';

class ArtistsGridPage extends ConsumerStatefulWidget {
  const ArtistsGridPage({Key? key}) : super(key: key);

  @override
  ConsumerState<ArtistsGridPage> createState() => _ArtistsGridPageState();
}

class _ArtistsGridPageState extends ConsumerState<ArtistsGridPage> {
  final ScrollController _scrollController = ScrollController();
  final YTMusicArtistsScraper _artistsScraper = YTMusicArtistsScraper();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Artist> artists = [];
  List<Artist> filteredArtists = [];
  bool isLoadingArtists = false;
  bool isSearchMode = false;
  Timer? _debounceTimer;
  bool isLoadingMore = false;
  bool hasMoreArtists = true;
  bool isSearching = false;
  static const int artistsPerPage = 50;
  int currentOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadArtists();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadArtists() async {
    if (!mounted || isLoadingArtists || isLoadingMore) {
      print('⏸️ Skipping load - already loading');
      return;
    }

    setState(() {
      if (currentOffset == 0) {
        isLoadingArtists = true;
      } else {
        isLoadingMore = true;
      }
    });

    try {
      print('🔄 Loading artists with offset: $currentOffset');

      final fetchedArtists = await _artistsScraper.getTrendingArtists(
        limit: artistsPerPage,
        offset: currentOffset,
      );

      print(
        '✅ Fetched ${fetchedArtists.length} artists (offset: $currentOffset)',
      );

      if (!mounted) return;

      if (fetchedArtists.isEmpty) {
        print('⚠️ No more artists to load');
        setState(() {
          hasMoreArtists = false;
          isLoadingArtists = false;
          isLoadingMore = false;
        });
        return;
      }

      setState(() {
        if (currentOffset == 0) {
          // Initial load
          artists = fetchedArtists;
          filteredArtists = List.from(fetchedArtists);
        } else {
          // Pagination - add new artists
          final existingIds = artists.map((a) => a.id).toSet();
          final newArtists = fetchedArtists
              .where((a) => !existingIds.contains(a.id))
              .toList();

          print('📦 Adding ${newArtists.length} new unique artists');

          artists.addAll(newArtists);

          // Re-apply search filter if in search mode
          if (_searchController.text.isEmpty) {
            filteredArtists = List.from(artists);
          } else {
            final query = _searchController.text.toLowerCase();
            filteredArtists = artists.where((artist) {
              return artist.name.toLowerCase().contains(query);
            }).toList();
          }
        }

        // Update pagination state
        // Always increment offset by the requested page size
        currentOffset += artistsPerPage;

        // Keep loading more unless we got fewer artists than requested
        hasMoreArtists = fetchedArtists.length >= artistsPerPage;

        isLoadingArtists = false;
        isLoadingMore = false;
      });

      print(
        '📋 Total: ${artists.length} artists, Filtered: ${filteredArtists.length}, HasMore: $hasMoreArtists',
      );
    } catch (e, stack) {
      print('❌ Error loading artists: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      if (!mounted) return;
      setState(() {
        isLoadingArtists = false;
        isLoadingMore = false;
        hasMoreArtists = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      if (!isLoadingMore && hasMoreArtists && !isSearchMode) {
        print('📜 Scroll threshold reached, loading more...');
        _loadArtists();
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      if (query.isEmpty) {
        setState(() {
          filteredArtists = List.from(artists);
          isSearching = false;
        });
        return;
      }

      // First, perform local search
      final lowerQuery = query.toLowerCase();
      final localResults = artists.where((artist) {
        return artist.name.toLowerCase().contains(lowerQuery);
      }).toList();

      setState(() {
        filteredArtists = localResults;
      });

      // If local results are insufficient (less than 5), perform API search
      if (localResults.length < 5) {
        setState(() {
          isSearching = true;
        });

        try {
          print('🔍 Performing API search for: "$query"');
          final searchResults = await _artistsScraper.searchArtists(
            query,
            limit: 20,
          );

          if (!mounted) return;

          // Merge local and API results, removing duplicates
          final existingIds = localResults.map((a) => a.id).toSet();
          final uniqueApiResults = searchResults
              .where((a) => !existingIds.contains(a.id))
              .toList();

          setState(() {
            filteredArtists = [...localResults, ...uniqueApiResults];
            isSearching = false;
          });

          print(
            '✅ Search complete: ${localResults.length} local + ${uniqueApiResults.length} API = ${filteredArtists.length} total',
          );
        } catch (e) {
          print('❌ API search error: $e');
          if (!mounted) return;
          setState(() {
            isSearching = false;
          });
        }
      } else {
        print(
          '🔍 Local search: ${localResults.length} artists found for "$query"',
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final backgroundColor = themeData.scaffoldBackgroundColor;
    final iconActiveColor = themeData.colorScheme.primary;
    final iconColor = themeData.colorScheme.onPrimary;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(context),
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xxxl),
                  _buildTopBar(ref),
                  Expanded(
                    child: isLoadingArtists
                        ? _buildLoadingGrid()
                        : _buildArtistsGrid(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 95),
        child: FloatingActionButton(
          onPressed: () {
            setState(() {
              isSearchMode = !isSearchMode;
              if (isSearchMode) {
                _searchFocusNode.requestFocus();
              } else {
                _searchController.clear();
                _searchFocusNode.unfocus();
                filteredArtists = List.from(artists);
              }
            });
          },
          backgroundColor: iconActiveColor,
          foregroundColor: iconColor,
          child: Icon(isSearchMode ? Icons.close : Icons.search),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final themeData = Theme.of(context);
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = themeData.colorScheme.primary;
    final iconInactiveColor = themeData.colorScheme.onSurfaceVariant;
    final sidebarLabelColor = themeData.colorScheme.onSurface;
    final sidebarLabelActiveColor = themeData.colorScheme.primary;

    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: sidebarLabelActiveColor);

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
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              onTap: () {
                Navigator.of(context).pushFade(const AppearancePage());
              },
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              label: 'Quick picks',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              onTap: () {
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Songs',
              isActive: false,
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
              isActive: false,
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
              isActive: true,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelActiveStyle,
              onTap: () {},
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Albums',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              onTap: () {
                Navigator.of(
                  context,
                ).pushMaterialVertical(const AlbumsGridPage(), slideUp: true);
              },
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
      behavior: HitTestBehavior.opaque,
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
                style: labelStyle.copyWith(
                  fontSize: 16,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(WidgetRef ref) {
    final themeData = Theme.of(context);
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final textSecondaryColor = themeData.colorScheme.onSurfaceVariant;
    final iconActiveColor = themeData.colorScheme.primary;
    final backgroundColor = themeData.scaffoldBackgroundColor;
    final cursorColor = themeData.colorScheme.primary;

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
          if (isSearchMode)
            IconButton(
              onPressed: () {
                setState(() {
                  isSearchMode = false;
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                  filteredArtists = List.from(artists);
                });
              },
              icon: Icon(Icons.arrow_back, color: iconActiveColor, size: 28),
            )
          else
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.arrow_back, color: iconActiveColor, size: 28),
            ),
          Expanded(
            child: isSearchMode
                ? TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textAlign: TextAlign.right,
                    style: pageTitleStyle,
                    cursorColor: cursorColor,
                    decoration: InputDecoration(
                      hintText: 'Search artists...',
                      hintStyle: hintStyle,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _onSearchChanged,
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: Text('Artists', style: pageTitleStyle),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingGrid() {
    return ShimmerLoading(
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: AppSpacing.lg,
          mainAxisSpacing: AppSpacing.xl,
        ),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBox(width: 100, height: 100, borderRadius: 50),
              const SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 100, height: 14, borderRadius: 4),
              const SizedBox(height: 6),
              SkeletonBox(width: 70, height: 10, borderRadius: 4),
            ],
          );
        },
      ),
    );
  }

  Widget _buildArtistsGrid() {
    final themeData = Theme.of(context);
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final textSecondaryColor = themeData.colorScheme.onSurfaceVariant;

    if (filteredArtists.isEmpty && !isLoadingArtists && !isSearching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 380,
                width: 380,
                child: Lottie.asset(
                  'assets/animations/not_found.json',
                  fit: BoxFit.contain,
                  animate: true,
                  repeat: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isSearchMode ? 'No artists found' : 'No artists available',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
              if (isSearchMode) ...[
                const SizedBox(height: 8),
                Text(
                  'Try a different search term',
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: AppSpacing.lg,
        mainAxisSpacing: AppSpacing.xl,
      ),
      itemCount:
          filteredArtists.length + ((isLoadingMore || isSearching) ? 2 : 0),
      itemBuilder: (context, index) {
        if (index >= filteredArtists.length) {
          final themeData = Theme.of(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  themeData.colorScheme.primary,
                ),
              ),
            ),
          );
        }
        return _buildArtistCard(filteredArtists[index]);
      },
    );
  }

  Widget _buildArtistCard(Artist artist) {
    final themeData = Theme.of(context);
    final cardBackgroundColor = themeData.colorScheme.surfaceVariant;
    final iconInactiveColor = themeData.colorScheme.onSurfaceVariant;
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final textSecondaryColor = themeData.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistPage(artist: artist, artistName: ''),
          ),
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
            ).copyWith(color: textPrimaryColor, fontWeight: FontWeight.w600),
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
    );
  }
}
