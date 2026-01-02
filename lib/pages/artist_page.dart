// lib/pages/artist_page.dart
import 'package:flutter/material.dart';
import 'package:vibeflow/api_base/ytmusic_artists_scraper.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/pages/album_page.dart';
import 'package:wikipedia/wikipedia.dart';

class ArtistPage extends StatefulWidget {
  final Artist artist;

  const ArtistPage({Key? key, required this.artist}) : super(key: key);

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

// In your _ArtistPageState class, add these fields:
class _ArtistPageState extends State<ArtistPage> {
  final ScrollController _scrollController = ScrollController();
  final YTMusicArtistsScraper _artistsScraper = YTMusicArtistsScraper();
  final YTMusicAlbumsScraper _albumsScraper = YTMusicAlbumsScraper();
  final Wikipedia _wikipedia = Wikipedia(); // Updated

  ArtistDetails? artistDetails;
  List<Album> artistAlbums = [];
  bool isLoading = true;
  String selectedTab = 'Overview';
  String artistBio = ''; // Add this
  bool isBioLoading = false; // Add this

  @override
  void initState() {
    super.initState();
    _loadArtistData();
    _loadArtistBio(); // Add this
  }

  Future<void> _loadArtistData() async {
    setState(() => isLoading = true);

    try {
      // Load artist details with top songs
      final details = await _artistsScraper.getArtistDetails(widget.artist.id);

      // Search for artist albums
      final albums = await _albumsScraper.searchAlbums(
        '${widget.artist.name} album',
        limit: 10,
      );

      setState(() {
        artistDetails = details;
        artistAlbums = albums;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading artist data: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadArtistBio() async {
    setState(() => isBioLoading = true);

    try {
      // Search Wikipedia for the artist
      final searchResults = await _wikipedia.searchQuery(
        searchQuery: widget.artist.name,
        limit: 1,
      );

      // Check if we have valid results
      if (searchResults != null &&
          searchResults.query != null &&
          searchResults.query!.search != null &&
          searchResults.query!.search!.isNotEmpty) {
        // Get the first search result
        final firstResult = searchResults.query!.search!.first;

        // Fetch full article summary using pageId
        if (firstResult.pageid != null) {
          final pageData = await _wikipedia.searchSummaryWithPageId(
            pageId: firstResult.pageid!,
          );

          // Extract the biography text
          if (pageData != null &&
              pageData.extract != null &&
              pageData.extract!.isNotEmpty) {
            setState(() {
              artistBio = pageData.extract!;
              isBioLoading = false;
            });
          }
        }
      }

      // Fallback to default bio
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(context),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.iconActive,
                            ),
                          )
                        : SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildArtistInfo(),
                                const SizedBox(height: AppSpacing.xl),
                                if (selectedTab == 'Overview') ...[
                                  _buildAlbumsSection(),
                                  const SizedBox(height: AppSpacing.xxxl),
                                  _buildBio(),
                                ] else if (selectedTab == 'Songs') ...[
                                  _buildSongsList(),
                                ] else if (selectedTab == 'Albums') ...[
                                  _buildAlbumsGrid(),
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

  Widget _buildSidebar(BuildContext context) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final tabs = ['Overview', 'Songs', 'Albums', 'Singles', 'Library'];

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
                  color: AppColors.iconActive,
                  shape: BoxShape.circle,
                ),
              ),
            if (isActive) const SizedBox(height: 16),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12), // Add spacing instead of Spacer
          Expanded(
            child: Text(
              widget.artist.name,
              style: AppTypography.pageTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.bookmark_border,
              color: AppColors.textPrimary,
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildArtistInfo() {
    final artist = artistDetails?.artist ?? widget.artist;

    return Column(
      children: [
        // Shuffle button
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              'Shuffle',
              style: AppTypography.subtitle.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Artist profile image
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cardBackground,
            ),
            child: ClipOval(
              child: artist.profileImage != null
                  ? Image.network(
                      artist.profileImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.person,
                            size: 120,
                            color: AppColors.iconInactive,
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons.person,
                        size: 120,
                        color: AppColors.iconInactive,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumsSection() {
    if (artistAlbums.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Albums', style: AppTypography.sectionHeader),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: artistAlbums.length,
            itemBuilder: (context, index) {
              final album = artistAlbums[index];
              return _buildAlbumCard(album);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(Album album) {
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
          final fullAlbum = await _albumsScraper.getAlbumDetails(album.id);
          if (mounted) Navigator.pop(context);

          if (fullAlbum != null && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AlbumPage(album: fullAlbum),
              ),
            );
          }
        } catch (e) {
          if (mounted) Navigator.pop(context);
        }
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
                color: AppColors.cardBackground,
                child: album.coverArt != null
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
            const SizedBox(height: 8),
            Text(
              album.title,
              style: AppTypography.subtitle.copyWith(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              album.year > 0 ? album.year.toString() : '',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBio() {
    // Show loading state
    if (isBioLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardBackground.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.iconActive,
            strokeWidth: 2,
          ),
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
        color: AppColors.cardBackground.withOpacity(0.3),
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
                  color: AppColors.iconActive,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  artistBio,
                  style: AppTypography.subtitle.copyWith(
                    color: AppColors.textPrimary.withOpacity(0.9),
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(Icons.radio, color: AppColors.iconInactive, size: 32),
          ),
        ],
      ),
    );
  }

  String _getArtistBio() {
    return artistBio;
  }

  Widget _buildSongsList() {
    if (artistDetails == null || artistDetails!.topSongs.isEmpty) {
      return Center(
        child: Text(
          'No songs available',
          style: AppTypography.subtitle.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return Column(
      children: artistDetails!.topSongs.map((song) {
        return _buildSongItem(song);
      }).toList(),
    );
  }

  Widget _buildSongItem(dynamic song) {
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

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(song: quickPick),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: AppColors.cardBackground,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: song.thumbnail != null && song.thumbnail.isNotEmpty
                    ? Image.network(
                        song.thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.music_note,
                              color: AppColors.iconInactive,
                              size: 24,
                            ),
                          );
                        },
                      )
                    : const Center(
                        child: Icon(
                          Icons.music_note,
                          color: AppColors.iconInactive,
                          size: 24,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    style: AppTypography.songTitle.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artists.join(', '),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (song.duration != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  song.duration.toString(),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsGrid() {
    if (artistAlbums.isEmpty) {
      return Center(
        child: Text(
          'No albums available',
          style: AppTypography.subtitle.copyWith(
            color: AppColors.textSecondary,
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
      itemCount: artistAlbums.length,
      itemBuilder: (context, index) {
        return _buildAlbumCard(artistAlbums[index]);
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
