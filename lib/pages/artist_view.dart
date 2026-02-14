// lib/pages/artist_page.dart
// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/api_base/ytmusic_artists_scraper.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/pages/album_view.dart';
import 'package:wikipedia/wikipedia.dart';

class ArtistPage extends ConsumerStatefulWidget {
  final Artist artist;

  const ArtistPage({Key? key, required this.artist, required String artistName})
    : super(key: key);

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  final ScrollController _scrollController = ScrollController();
  final YTMusicArtistsScraper _artistsScraper = YTMusicArtistsScraper();
  final YTMusicAlbumsScraper _albumsScraper = YTMusicAlbumsScraper();
  final Wikipedia _wikipedia = Wikipedia();

  ArtistDetails? artistDetails;
  List<Album> artistAlbums = [];
  List<Album> artistSingles = [];
  bool isLoading = true;
  String selectedTab = 'Overview';
  String artistBio = '';
  bool isBioLoading = false;
  bool showAllSongsInTab = false;
  List<dynamic> tabAllSongs = [];
  bool isLoadingTabAllSongs = false;

  @override
  void initState() {
    super.initState();
    _loadArtistData();
    _loadArtistBio();
  }

  Future<void> _loadArtistData() async {
    setState(() => isLoading = true);
    try {
      // Use getArtistDetailsExtended to get ALL songs, albums, and singles
      final extendedDetails = await _artistsScraper.getArtistDetailsExtended(
        widget.artist.id,
      );

      if (extendedDetails != null) {
        // Fetch albums separately for more results
        final albums = await _albumsScraper.searchAlbums(
          '${widget.artist.name} album',
          limit: 50,
        );

        // Fetch singles separately
        final singles = await _albumsScraper.searchAlbums(
          '${widget.artist.name} single',
          limit: 50,
        );

        setState(() {
          // Create ArtistDetails from extended details
          artistDetails = ArtistDetails(
            artist: extendedDetails.artist,
            topSongs: extendedDetails.topSongs, // First 10 songs
            albums: extendedDetails.albums.isNotEmpty
                ? extendedDetails.albums
                : albums,
          );

          // Store all songs separately
          tabAllSongs = extendedDetails.allSongs;

          artistAlbums = extendedDetails.albums.isNotEmpty
              ? extendedDetails.albums
              : albums;

          artistSingles = extendedDetails.singles.isNotEmpty
              ? extendedDetails.singles
              : singles;

          isLoading = false;
        });

        print(
          '✅ Loaded artist with ${extendedDetails.allSongs.length} total songs, '
          '${artistAlbums.length} albums, ${artistSingles.length} singles',
        );
      } else {
        // Fallback to regular getArtistDetails if extended fails
        final details = await _artistsScraper.getArtistDetails(
          widget.artist.id,
        );

        final albums = await _albumsScraper.searchAlbums(
          '${widget.artist.name} album',
          limit: 50,
        );

        final singles = await _albumsScraper.searchAlbums(
          '${widget.artist.name} single',
          limit: 50,
        );

        setState(() {
          artistDetails = details;
          artistAlbums = albums;
          artistSingles = singles;
          tabAllSongs = details?.topSongs ?? [];
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading artist data: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadArtistBio() async {
    setState(() => isBioLoading = true);

    try {
      final searchResults = await _wikipedia.searchQuery(
        searchQuery: widget.artist.name,
        limit: 1,
      );

      if (searchResults != null &&
          searchResults.query != null &&
          searchResults.query!.search != null &&
          searchResults.query!.search!.isNotEmpty) {
        final firstResult = searchResults.query!.search!.first;

        if (firstResult.pageid != null) {
          final pageData = await _wikipedia.searchSummaryWithPageId(
            pageId: firstResult.pageid!,
          );

          if (pageData != null &&
              pageData.extract != null &&
              pageData.extract!.isNotEmpty) {
            setState(() {
              artistBio = pageData.extract!;
              isBioLoading = false;
            });
            return;
          }
        }
      }

      setState(() {
        artistBio = _getDefaultBio();
        isBioLoading = false;
      });
    } catch (e) {
      print('Error loading bio from Wikipedia: $e');
      setState(() {
        artistBio = _getDefaultBio();
        isBioLoading = false;
      });
    }
  }

  String _getDefaultBio() {
    final artistName = widget.artist.name;
    return '$artistName is a talented artist known for their unique sound and creative contributions to the music industry. '
        'With a dedicated fanbase of ${widget.artist.subscribers}, they continue to produce music that resonates with audiences worldwide. '
        'Their work spans various genres and collaborations, making them a versatile and influential figure in modern music.';
  }

  Future<void> _loadAllSongsForTab() async {
    // If already loading, don't start another load
    if (isLoadingTabAllSongs) {
      print('⏸️ Already loading songs');
      return;
    }

    // Check if we already have loaded all songs and they're more than just top songs
    if (tabAllSongs.isNotEmpty && tabAllSongs.length > 10) {
      print('📦 Using cached all songs: ${tabAllSongs.length}');
      setState(() {
        showAllSongsInTab = true;
      });
      return;
    }

    setState(() {
      isLoadingTabAllSongs = true;
      showAllSongsInTab = true; // Show the expanded view immediately
    });

    try {
      print('🎵 Fetching ALL songs using getArtistDetailsExtended...');
      print('Artist ID: ${widget.artist.id}');

      final extendedDetails = await _artistsScraper.getArtistDetailsExtended(
        widget.artist.id,
      );

      if (!mounted) return;

      if (extendedDetails != null && extendedDetails.allSongs.isNotEmpty) {
        print(
          '✅ Successfully loaded ${extendedDetails.allSongs.length} total songs',
        );
        setState(() {
          tabAllSongs = extendedDetails.allSongs;
          isLoadingTabAllSongs = false;
        });
      } else {
        print('⚠️ getArtistDetailsExtended returned null or empty');
        print(
          'Fallback: Using ${artistDetails?.topSongs.length ?? 0} top songs',
        );
        setState(() {
          tabAllSongs = artistDetails?.topSongs ?? [];
          isLoadingTabAllSongs = false;
        });
      }
    } catch (e, stackTrace) {
      print('❌ Error loading all songs: $e');
      print(
        'Stack trace: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );

      if (!mounted) return;

      setState(() {
        tabAllSongs = artistDetails?.topSongs ?? [];
        isLoadingTabAllSongs = false;
      });
    }
  }

  int? _parseDurationToSeconds(String duration) {
    try {
      final parts = duration.split(':').map(int.parse).toList();
      if (parts.length == 2) {
        return parts[0] * 60 + parts[1];
      } else if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(context, ref),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(ref),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildArtistInfo(ref),
                          const SizedBox(height: AppSpacing.xl),
                          if (selectedTab == 'Overview') ...[
                            _buildAlbumsSection(ref),
                            const SizedBox(height: AppSpacing.xxxl),
                            _buildBio(ref),
                          ] else if (selectedTab == 'Songs') ...[
                            _buildSongsList(ref),
                          ] else if (selectedTab == 'Albums') ...[
                            _buildAlbumsGrid(ref),
                          ] else if (selectedTab == 'Singles') ...[
                            _buildSinglesGrid(ref), // Added singles grid
                          ],

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
    );
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final tabs = ['Overview', 'Songs', 'Albums', 'Singles', 'Library'];
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final sidebarLabelColor = ref.watch(themeTextPrimaryColorProvider);
    final sidebarLabelActiveColor = ref.watch(themeIconActiveColorProvider);

    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: sidebarLabelActiveColor);

    return SizedBox(
      width: 80,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            ...tabs.map((tab) {
              final isActive = selectedTab == tab;
              return Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: _buildSidebarItem(
                  label: tab,
                  isActive: isActive,
                  iconActiveColor: iconActiveColor,
                  labelStyle: isActive
                      ? sidebarLabelActiveStyle
                      : sidebarLabelStyle,
                  onTap: () {
                    setState(() => selectedTab = tab);
                  },
                ),
              );
            }).toList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required String label,
    required bool isActive,
    required Color iconActiveColor,
    required TextStyle labelStyle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: iconActiveColor,
                  shape: BoxShape.circle,
                ),
              ),
            if (isActive) const SizedBox(height: 16),
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

  Widget _buildHeader(WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 60), // Add top padding of 60
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: textPrimaryColor),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(
              width: 16,
            ), // Spacing between back button and artist name
            Expanded(
              child: Text(
                widget.artist.name,
                style: AppTypography.pageTitle(
                  context,
                ).copyWith(color: textPrimaryColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.bookmark_border, color: textPrimaryColor),
              onPressed: () {},
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.share, color: textPrimaryColor),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistInfo(WidgetRef ref) {
    final artist = artistDetails?.artist ?? widget.artist;
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return Column(
      children: [
        // Shuffle button
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: cardBackgroundColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              'Shuffle',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimaryColor, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Artist profile image with shimmer
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cardBackgroundColor,
            ),
            child: ClipOval(
              child: (artist.profileImage != null && !isLoading)
                  ? Image.network(
                      artist.profileImage!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return ShimmerWidget(
                          baseColor: cardBackgroundColor,
                          highlightColor: iconActiveColor.withOpacity(0.3),
                          child: Container(
                            width: 280,
                            height: 280,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cardBackgroundColor,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.person,
                            size: 120,
                            color: iconInactiveColor,
                          ),
                        );
                      },
                    )
                  : ShimmerWidget(
                      baseColor: cardBackgroundColor,
                      highlightColor: iconActiveColor.withOpacity(0.3),
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cardBackgroundColor,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumsSection(WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Albums',
          style: AppTypography.sectionHeader(
            context,
          ).copyWith(color: textPrimaryColor),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 200,
          child: isLoading
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 140,
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerWidget(
                            baseColor: cardBackgroundColor,
                            highlightColor: iconActiveColor.withOpacity(0.3),
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: cardBackgroundColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ShimmerWidget(
                            baseColor: cardBackgroundColor,
                            highlightColor: iconActiveColor.withOpacity(0.3),
                            child: Container(
                              width: 100,
                              height: 14,
                              decoration: BoxDecoration(
                                color: cardBackgroundColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ShimmerWidget(
                            baseColor: cardBackgroundColor,
                            highlightColor: iconActiveColor.withOpacity(0.3),
                            child: Container(
                              width: 60,
                              height: 12,
                              decoration: BoxDecoration(
                                color: cardBackgroundColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : artistAlbums.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: artistAlbums.length,
                  itemBuilder: (context, index) {
                    final album = artistAlbums[index];
                    return _buildAlbumCard(album, ref);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(Album album, WidgetRef ref) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AlbumPage(album: album)),
        );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 140,
                height: 140,
                color: cardBackgroundColor,
                child: album.coverArt != null
                    ? Image.network(
                        album.coverArt!,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return ShimmerWidget(
                            baseColor: cardBackgroundColor,
                            highlightColor: iconActiveColor.withOpacity(0.3),
                            child: Container(
                              width: 140,
                              height: 140,
                              color: cardBackgroundColor,
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
            const SizedBox(height: 8),
            Text(
              album.title,
              style: AppTypography.subtitle(
                context,
              ).copyWith(fontSize: 14, color: textPrimaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              album.year > 0 ? album.year.toString() : '',
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSinglesGrid(WidgetRef ref) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    if (isLoading) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerWidget(
                  baseColor: cardBackgroundColor,
                  highlightColor: iconActiveColor.withOpacity(0.3),
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: cardBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ShimmerWidget(
                  baseColor: cardBackgroundColor,
                  highlightColor: iconActiveColor.withOpacity(0.3),
                  child: Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: cardBackgroundColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (artistSingles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No singles available',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textSecondaryColor),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: artistSingles.length,
      itemBuilder: (context, index) {
        return _buildAlbumCard(artistSingles[index], ref);
      },
    );
  }

  Widget _buildBio(WidgetRef ref) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);

    // Show loading state with shimmer
    if (isBioLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBackgroundColor.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconActiveColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerWidget(
                        baseColor: cardBackgroundColor,
                        highlightColor: iconActiveColor.withOpacity(0.3),
                        child: Container(
                          width: double.infinity,
                          height: 14,
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ShimmerWidget(
                        baseColor: cardBackgroundColor,
                        highlightColor: iconActiveColor.withOpacity(0.3),
                        child: Container(
                          width: double.infinity,
                          height: 14,
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ShimmerWidget(
                        baseColor: cardBackgroundColor,
                        highlightColor: iconActiveColor.withOpacity(0.3),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.7,
                          height: 14,
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.bottomRight,
              child: ShimmerWidget(
                baseColor: cardBackgroundColor,
                highlightColor: iconActiveColor.withOpacity(0.3),
                child: Icon(
                  Icons.radio,
                  color: iconInactiveColor.withOpacity(0.3),
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Hide if no bio
    if (artistBio.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBackgroundColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: iconActiveColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  artistBio,
                  style: AppTypography.subtitle(context).copyWith(
                    color: textPrimaryColor.withOpacity(0.9),
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(Icons.radio, color: iconInactiveColor, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildSongsList(WidgetRef ref) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    // Initial loading state
    if (isLoading) {
      return Column(
        children: List.generate(5, (index) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ShimmerWidget(
                  baseColor: cardBackgroundColor,
                  highlightColor: iconActiveColor.withOpacity(0.3),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: cardBackgroundColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerWidget(
                        baseColor: cardBackgroundColor,
                        highlightColor: iconActiveColor.withOpacity(0.3),
                        child: Container(
                          width: double.infinity,
                          height: 14,
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ShimmerWidget(
                        baseColor: cardBackgroundColor,
                        highlightColor: iconActiveColor.withOpacity(0.3),
                        child: Container(
                          width: 100,
                          height: 12,
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      );
    }

    // No songs available
    if (artistDetails == null || artistDetails!.topSongs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No songs available',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textSecondaryColor),
          ),
        ),
      );
    }

    // Determine which songs to show
    final songsToShow = showAllSongsInTab && tabAllSongs.isNotEmpty
        ? tabAllSongs
        : artistDetails!.topSongs;

    final songCount = showAllSongsInTab && tabAllSongs.isNotEmpty
        ? tabAllSongs.length
        : artistDetails!.topSongs.length;

    // Build the songs list
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with count and View All / View Less button
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$songCount songs',
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor, fontSize: 18),
              ),
              GestureDetector(
                onTap: () async {
                  print('🔘 View All button tapped');
                  print(
                    'Current state - showAllSongsInTab: $showAllSongsInTab',
                  );
                  print('Current tabAllSongs length: ${tabAllSongs.length}');

                  if (showAllSongsInTab) {
                    // Collapse back to top songs
                    print('📥 Collapsing to top songs');
                    setState(() {
                      showAllSongsInTab = false;
                    });
                  } else {
                    // Expand to show all songs
                    print('📤 Expanding to show all songs');
                    await _loadAllSongsForTab();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: iconActiveColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        showAllSongsInTab ? 'View Less' : 'View All',
                        style: AppTypography.subtitle(context).copyWith(
                          color: iconActiveColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        showAllSongsInTab
                            ? Icons.keyboard_arrow_up
                            : Icons.arrow_forward_ios,
                        size: 12,
                        color: iconActiveColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Loading state when fetching all songs
        if (isLoadingTabAllSongs) ...[
          ...List.generate(10, (index) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  ShimmerWidget(
                    baseColor: cardBackgroundColor,
                    highlightColor: iconActiveColor.withOpacity(0.3),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: cardBackgroundColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerWidget(
                          baseColor: cardBackgroundColor,
                          highlightColor: iconActiveColor.withOpacity(0.3),
                          child: Container(
                            width: double.infinity,
                            height: 14,
                            decoration: BoxDecoration(
                              color: cardBackgroundColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ShimmerWidget(
                          baseColor: cardBackgroundColor,
                          highlightColor: iconActiveColor.withOpacity(0.3),
                          child: Container(
                            width: 100,
                            height: 12,
                            decoration: BoxDecoration(
                              color: cardBackgroundColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ]
        // Songs list
        else ...[
          ...songsToShow.map((song) {
            return _buildSongItem(song, ref);
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildSongItem(dynamic song, WidgetRef ref) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return GestureDetector(
      onTap: () {
        int? durationSeconds;
        if (song.duration != null) {
          if (song.duration is int) {
            durationSeconds = song.duration as int;
          } else if (song.duration is String) {
            durationSeconds = _parseDurationToSeconds(song.duration as String);
          }
        }

        final quickPick = QuickPick(
          videoId: song.videoId,
          title: song.title,
          artists: song.artists.join(', '),
          thumbnail: song.thumbnail,
          duration: song.duration,
        );

        NewPlayerPage.open(context, quickPick);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            // Thumbnail - fixed width
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: cardBackgroundColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: song.thumbnail != null && song.thumbnail.isNotEmpty
                    ? Image.network(
                        song.thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.music_note,
                              color: iconInactiveColor,
                              size: 24,
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Icon(
                          Icons.music_note,
                          color: iconInactiveColor,
                          size: 24,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Main content - takes remaining space
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Song title
                  Text(
                    song.title,
                    style: AppTypography.songTitle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: textPrimaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Artist names
                  Text(
                    song.artists.join(', '),
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Duration - fixed width
            if (song.duration != null)
              Container(
                constraints: const BoxConstraints(minWidth: 40),
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  song.duration.toString(),
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: textSecondaryColor, fontSize: 12),
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsGrid(WidgetRef ref) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    if (artistAlbums.isEmpty) {
      return Center(
        child: Text(
          'No albums available',
          style: AppTypography.subtitle(
            context,
          ).copyWith(color: textSecondaryColor),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: artistAlbums.length,
      itemBuilder: (context, index) {
        return _buildAlbumCard(artistAlbums[index], ref);
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// Shimmer Widget Class
class ShimmerWidget extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerWidget({
    Key? key,
    required this.child,
    required this.baseColor,
    required this.highlightColor,
  }) : super(key: key);

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [
                0.0,
                _animation.value / 4 + 0.5,
                (_animation.value / 4 + 0.5) + 0.1,
                1.0,
              ],
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.highlightColor,
                widget.baseColor,
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}
