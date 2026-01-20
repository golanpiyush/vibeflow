// lib/pages/albums_grid_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/pages/album_view.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/subpages/songs/albums.dart';
import 'package:vibeflow/pages/subpages/songs/artists.dart';
import 'package:vibeflow/pages/subpages/songs/artists_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/widgets/shimmer_loadings.dart';

class AlbumsGridPage extends ConsumerStatefulWidget {
  const AlbumsGridPage({Key? key}) : super(key: key);

  @override
  ConsumerState<AlbumsGridPage> createState() => _AlbumsGridPageState();
}

class _AlbumsGridPageState extends ConsumerState<AlbumsGridPage> {
  final ScrollController _scrollController = ScrollController();
  final YTMusicAlbumsScraper _albumsScraper = YTMusicAlbumsScraper();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Album> albums = [];
  List<Album> filteredAlbums = [];
  bool isLoadingAlbums = true; // Start with true
  bool isSearchMode = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    if (!mounted) return;

    try {
      await for (final album in _albumsScraper.getMixedRandomAlbumsStream(
        limit: 25,
      )) {
        if (!mounted) return;

        setState(() {
          albums.add(album);
          if (!isSearchMode) {
            filteredAlbums = albums;
          }
          // Turn off loading after first album
          if (isLoadingAlbums) {
            isLoadingAlbums = false;
          }
        });
      }
    } catch (e, stack) {
      print('❌ Error loading albums: $e');
      print('Stack: ${stack.toString().split('\n').take(3).join('\n')}');
      if (!mounted) return;
      setState(() => isLoadingAlbums = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          if (query.isEmpty) {
            filteredAlbums = albums;
          } else {
            filteredAlbums = albums.where((album) {
              final titleMatch = album.title.toLowerCase().contains(
                query.toLowerCase(),
              );
              final artistMatch = album.artist.toLowerCase().contains(
                query.toLowerCase(),
              );
              return titleMatch || artistMatch;
            }).toList();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
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
                    child: isLoadingAlbums
                        ? _buildLoadingGrid()
                        : _buildAlbumsGrid(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 40.0),
        child: FloatingActionButton(
          onPressed: () {
            setState(() {
              isSearchMode = !isSearchMode;
              if (isSearchMode) {
                _searchFocusNode.requestFocus();
              } else {
                _searchController.clear();
                _searchFocusNode.unfocus();
                filteredAlbums = albums;
              }
            });
          },
          backgroundColor: ref.watch(themeIconActiveColorProvider),
          child: Icon(
            isSearchMode ? Icons.close : Icons.search,
            color: backgroundColor,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final double availableHeight = MediaQuery.of(context).size.height;
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
              isActive: true,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelActiveStyle,
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

    final pageTitleStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textPrimaryColor);
    final hintStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textSecondaryColor.withOpacity(0.5));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  filteredAlbums = albums;
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
                    decoration: InputDecoration(
                      hintText: 'Search albums...',
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
                    child: Text('Albums', style: pageTitleStyle),
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
          childAspectRatio: 0.75,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
        ),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(
                width: double.infinity,
                height: 160,
                borderRadius: AppSpacing.radiusMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 120, height: 14, borderRadius: 4),
              const SizedBox(height: 6),
              SkeletonBox(width: 80, height: 12, borderRadius: 4),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlbumsGrid() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final Color cardBackgroundColor = const Color.fromARGB(0, 0, 0, 0);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);

    if (filteredAlbums.isEmpty && !isLoadingAlbums) {
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
                isSearchMode ? 'No albums found' : 'No albums available',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textSecondaryColor),
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

    // Calculate total items: actual albums + loading placeholders
    final totalItems = isLoadingAlbums
        ? filteredAlbums.length +
              8 // Show 8 shimmer items while loading
        : filteredAlbums.length;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // Show actual album if available
        if (index < filteredAlbums.length) {
          return _buildAlbumCard(
            filteredAlbums[index],
            cardBackgroundColor,
            textPrimaryColor,
            textSecondaryColor,
            iconInactiveColor,
          );
        }

        // Show shimmer loading for remaining slots
        return ShimmerLoading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(
                width: double.infinity,
                height: 160,
                borderRadius: AppSpacing.radiusMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 120, height: 14, borderRadius: 4),
              const SizedBox(height: 6),
              SkeletonBox(width: 80, height: 12, borderRadius: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumCard(
    Album album,
    Color cardBackgroundColor,
    Color textPrimaryColor,
    Color textSecondaryColor,
    Color iconInactiveColor,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushFade(AlbumPage(album: album));
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardBackgroundColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Cover
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusMedium),
                ),
                child: album.coverArt != null
                    ? Image.network(
                        album.coverArt!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return ShimmerLoading(
                            child: SkeletonBox(
                              width: double.infinity,
                              height: double.infinity,
                              borderRadius: AppSpacing.radiusMedium,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: cardBackgroundColor,
                            child: Center(
                              child: Icon(
                                Icons.album,
                                size: 48,
                                color: iconInactiveColor,
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: cardBackgroundColor,
                        child: Center(
                          child: Icon(
                            Icons.album,
                            size: 48,
                            color: iconInactiveColor,
                          ),
                        ),
                      ),
              ),
            ),
            // Album Info
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album.title,
                    style: AppTypography.subtitle(context).copyWith(
                      color: textPrimaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    album.artist,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (album.year > 0) ...[
                    const SizedBox(height: 2),
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
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _albumsScraper.dispose();
    super.dispose();
  }
}
