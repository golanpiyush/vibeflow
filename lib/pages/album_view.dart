// lib/pages/album_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:vibeflow/api_base/ytmusic_albums_scraper.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/artist_view.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/pages/player_page.dart';

class AlbumPage extends ConsumerStatefulWidget {
  final Album album;

  const AlbumPage({Key? key, required this.album}) : super(key: key);

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  final ScrollController _scrollController = ScrollController();
  final YTMusicAlbumsScraper _albumsScraper = YTMusicAlbumsScraper();

  Album? _fullAlbum;
  bool _isLoadingSongs = false;
  String? _errorMessage;

  // For versions
  List<Album> _versions = [];
  bool _isLoadingVersions = false;
  String? _versionsErrorMessage;
  bool _showVersions = false; // Toggle between songs and versions view

  @override
  void initState() {
    super.initState();
    print('📀 [AlbumPage] Album: ${widget.album.title}');
    print('📀 [AlbumPage] Songs count: ${widget.album.songs.length}');

    // If album has no songs, fetch full details
    if (widget.album.songs.isEmpty) {
      print('⚠️ [AlbumPage] No songs in album, fetching details...');
      _loadAlbumDetails();
    } else {
      _fullAlbum = widget.album;
    }
  }

  Future<void> _loadAlbumDetails() async {
    setState(() {
      _isLoadingSongs = true;
      _errorMessage = null;
    });

    try {
      final fetchedAlbum = await _albumsScraper.getAlbumDetails(
        widget.album.id,
      );

      if (mounted) {
        if (fetchedAlbum != null && fetchedAlbum.songs.isNotEmpty) {
          // Merge: Keep original metadata, use fetched songs
          setState(() {
            _fullAlbum = Album(
              id: widget.album.id,
              title: widget.album.title.isNotEmpty
                  ? widget.album.title
                  : fetchedAlbum.title,
              artist: widget.album.artist.isNotEmpty
                  ? widget.album.artist
                  : fetchedAlbum.artist,
              coverArt: widget.album.coverArt ?? fetchedAlbum.coverArt,
              year: widget.album.year > 0
                  ? widget.album.year
                  : fetchedAlbum.year,
              songs: fetchedAlbum.songs,
            );
            _isLoadingSongs = false;
          });
          print('✅ [AlbumPage] Loaded ${_fullAlbum?.songs.length ?? 0} songs');
        } else {
          setState(() {
            _fullAlbum = widget.album;
            _isLoadingSongs = false;
            _errorMessage = 'Could not load album songs';
          });
        }
      }
    } catch (e) {
      print('❌ [AlbumPage] Error loading album: $e');
      if (mounted) {
        setState(() {
          _fullAlbum = widget.album;
          _isLoadingSongs = false;
          _errorMessage = 'Error loading album';
        });
      }
    }
  }

  Future<void> _loadVersions() async {
    if (_versions.isNotEmpty) return; // Already loaded

    setState(() {
      _isLoadingVersions = true;
      _versionsErrorMessage = null;
    });

    try {
      // Use the improved YTMusicAlbumsScraper to get album versions
      final versions = await _albumsScraper.searchAlbums(
        '${widget.album.title} ${widget.album.artist}',
        limit: 20,
      );

      // Filter out the current album and any duplicates
      final filteredVersions = versions
          .where(
            (album) =>
                album.id != widget.album.id &&
                    album.title.toLowerCase().contains(
                      widget.album.title.toLowerCase(),
                    ) ||
                album.artist.toLowerCase().contains(
                  widget.album.artist.toLowerCase(),
                ),
          )
          .toList();

      // Remove duplicates by ID
      final uniqueVersions = <Album>[];
      final seenIds = <String>{};
      for (final album in filteredVersions) {
        if (!seenIds.contains(album.id)) {
          seenIds.add(album.id);
          uniqueVersions.add(album);
        }
      }

      if (mounted) {
        setState(() {
          _versions = uniqueVersions;
          _isLoadingVersions = false;
        });
        print(
          '✅ [AlbumPage] Loaded ${_versions.length} versions for "${widget.album.title}"',
        );
      }
    } catch (e) {
      print('❌ [AlbumPage] Error loading versions: $e');
      if (mounted) {
        setState(() {
          _isLoadingVersions = false;
          _versionsErrorMessage = 'Failed to load album versions';
        });
      }
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
      print('Error parsing duration: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final backgroundColor = themeData.scaffoldBackgroundColor;

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
                          _buildAlbumInfo(ref),
                          const SizedBox(height: AppSpacing.xl),
                          _showVersions
                              ? _buildVersionsGrid(ref)
                              : _buildSongsList(ref),
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
    final themeData = Theme.of(context);
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = themeData.colorScheme.primary;
    final sidebarLabelColor = themeData.colorScheme.onSurface;
    final sidebarLabelActiveColor = themeData.colorScheme.primary;

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
            _buildSidebarItem(
              label: 'Songs',
              isActive: !_showVersions,
              iconActiveColor: iconActiveColor,
              labelStyle: _showVersions
                  ? sidebarLabelStyle
                  : sidebarLabelActiveStyle,
              onTap: () {
                setState(() {
                  _showVersions = false;
                });
              },
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              label: 'Other versions',
              isActive: _showVersions,
              iconActiveColor: iconActiveColor,
              labelStyle: _showVersions
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              onTap: () {
                setState(() {
                  _showVersions = true;
                });
                if (_versions.isEmpty && !_isLoadingVersions) {
                  _loadVersions();
                }
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(WidgetRef ref) {
    final themeData = Theme.of(context);
    final textPrimaryColor = themeData.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 60, bottom: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.chevron_left, color: textPrimaryColor, size: 28),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                widget.album.title,
                style: AppTypography.pageTitle(
                  context,
                ).copyWith(color: textPrimaryColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.bookmark_border, color: textPrimaryColor),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required String label,
    required bool isActive,
    required Color iconActiveColor,
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

  Widget _buildAlbumInfo(WidgetRef ref) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    // Use full album if available, otherwise use initial album
    final displayAlbum = _fullAlbum ?? widget.album;

    return Column(
      children: [
        // Enqueue button
        // Center(
        //   child: GestureDetector(
        //     onTap: () {
        //       ScaffoldMessenger.of(context).showSnackBar(
        //         SnackBar(
        //           content: Text(
        //             'Enqueue feature coming soon',
        //             style: TextStyle(color: textPrimaryColor),
        //           ),
        //           backgroundColor: cardBackgroundColor,
        //           duration: const Duration(seconds: 1),
        //         ),
        //       );
        //     },
        //     // child: Container(
        //     //   padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        //     //   decoration: BoxDecoration(
        //     //     color: cardBackgroundColor,
        //     //     borderRadius: BorderRadius.circular(24),
        //     //   ),
        //     //   // child: Text(
        //     //   //   'Enqueue',
        //     //   //   style: AppTypography.subtitle(context).copyWith(
        //     //   //     color: textPrimaryColor,
        //     //   //     fontWeight: FontWeight.w600,
        //     //   //   ),
        //     //   // ),
        //     // ),
        //   ),
        // ),
        const SizedBox(height: AppSpacing.lg),

        // Album cover with shimmer
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child:
                displayAlbum.coverArt != null &&
                    displayAlbum.coverArt!.isNotEmpty
                ? Image.network(
                    displayAlbum.coverArt!,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return ShimmerWidget(
                        baseColor: cardBackgroundColor,
                        highlightColor: iconActiveColor.withOpacity(0.3),
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: cardBackgroundColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.album,
                            size: 80,
                            color: iconInactiveColor,
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: cardBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.album,
                        size: 80,
                        color: iconInactiveColor,
                      ),
                    ),
                  ),
          ),
        ),

        // Album year
        if (displayAlbum.year > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            displayAlbum.year.toString(),
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondaryColor),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildVersionsGrid(WidgetRef ref) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    // Show loading shimmer
    if (_isLoadingVersions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerWidget(
            baseColor: cardBackgroundColor,
            highlightColor: iconActiveColor.withOpacity(0.3),
            child: Container(
              width: 150,
              height: 16,
              decoration: BoxDecoration(
                color: cardBackgroundColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.7,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              return ShimmerWidget(
                baseColor: cardBackgroundColor,
                highlightColor: iconActiveColor.withOpacity(0.3),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    // Show error
    if (_versionsErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: textSecondaryColor.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _versionsErrorMessage!,
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textSecondaryColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadVersions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconActiveColor,
                ),
                child: Text('Retry', style: TextStyle(color: textPrimaryColor)),
              ),
            ],
          ),
        ),
      );
    }

    // Show empty state
    if (_versions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            children: [
              // Lottie animation for "not found" state
              SizedBox(
                height: 250,
                width: 250,
                child: Lottie.asset(
                  'assets/animations/not_found.json',
                  fit: BoxFit.contain,
                  animate: true,
                  repeat: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No other versions found',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textSecondaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                'This album has no alternate versions',
                style: AppTypography.caption(
                  context,
                ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      );
    }

    // Show versions grid
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Found ${_versions.length} other version${_versions.length != 1 ? 's' : ''}',
          style: AppTypography.subtitle(
            context,
          ).copyWith(color: textSecondaryColor),
        ),
        const SizedBox(height: AppSpacing.lg),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.7,
          ),
          itemCount: _versions.length,
          itemBuilder: (context, index) {
            return _buildVersionCard(_versions[index], ref);
          },
        ),
      ],
    );
  }

  Widget _buildVersionCard(Album album, WidgetRef ref) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return GestureDetector(
      onTap: () {
        // Navigate to the selected album version
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AlbumPage(album: album)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardBackgroundColor.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album cover
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Container(
                  width: double.infinity,
                  color: cardBackgroundColor,
                  child: album.coverArt != null && album.coverArt!.isNotEmpty
                      ? Image.network(
                          album.coverArt!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return ShimmerWidget(
                              baseColor: cardBackgroundColor,
                              highlightColor: iconActiveColor.withOpacity(0.3),
                              child: Container(color: cardBackgroundColor),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                Icons.album,
                                size: 48,
                                color: iconInactiveColor,
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Icon(
                            Icons.album,
                            size: 48,
                            color: iconInactiveColor,
                          ),
                        ),
                ),
              ),
            ),
            // Album info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    style: AppTypography.subtitle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: textPrimaryColor,
                    ),
                    maxLines: 2,
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
                    const SizedBox(height: 4),
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

  Widget _buildSongsList(WidgetRef ref) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    // Show loading shimmer while fetching songs
    if (_isLoadingSongs) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(8, (index) {
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
                      color: cardBackgroundColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ShimmerWidget(
                        baseColor: cardBackgroundColor,
                        highlightColor: iconActiveColor.withOpacity(0.3),
                        child: Container(
                          width: double.infinity,
                          height: 15,
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
                          width: 180,
                          height: 13,
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ShimmerWidget(
                  baseColor: cardBackgroundColor,
                  highlightColor: iconActiveColor.withOpacity(0.3),
                  child: Container(
                    width: 35,
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
        }),
      );
    }

    // Show error message
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: textSecondaryColor.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textSecondaryColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAlbumDetails,
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconActiveColor,
                ),
                child: Text('Retry', style: TextStyle(color: textPrimaryColor)),
              ),
            ],
          ),
        ),
      );
    }

    // Show empty state
    final songs = _fullAlbum?.songs ?? [];
    if (songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            children: [
              Icon(
                Icons.music_off,
                size: 64,
                color: textSecondaryColor.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No songs available',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textSecondaryColor),
              ),
            ],
          ),
        ),
      );
    }

    // Show songs list
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: songs.asMap().entries.map((entry) {
        final index = entry.key;
        final song = entry.value;
        return _buildSongItem(song, index + 1, ref);
      }).toList(),
    );
  }

  Widget _buildSongItem(dynamic song, int trackNumber, WidgetRef ref) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    // Use song thumbnail if available, otherwise use album cover art
    final displayAlbum = _fullAlbum ?? widget.album;
    final thumbnailUrl = (song.thumbnail != null && song.thumbnail.isNotEmpty)
        ? song.thumbnail
        : displayAlbum.coverArt;

    return GestureDetector(
      onTap: () {
        // Parse duration
        int? durationSeconds;
        if (song.duration != null) {
          if (song.duration is int) {
            durationSeconds = song.duration as int;
          } else if (song.duration is String) {
            durationSeconds = _parseDurationToSeconds(song.duration as String);
          }
        }

        // Create QuickPick and navigate to player
        final quickPick = QuickPick(
          videoId: song.videoId,
          title: song.title,
          artists: song.artists.join(', '),
          thumbnail: thumbnailUrl ?? '',
          duration: song.duration,
        );

        NewPlayerPage.open(context, quickPick);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            // Thumbnail with shimmer
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: cardBackgroundColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                    ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return ShimmerWidget(
                            baseColor: cardBackgroundColor,
                            highlightColor: iconActiveColor.withOpacity(0.3),
                            child: Container(
                              width: 56,
                              height: 56,
                              color: cardBackgroundColor,
                            ),
                          );
                        },
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

            // Song info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.5,
                    ),
                    child: Text(
                      song.title,
                      style: AppTypography.songTitle(context).copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        color: textPrimaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.5,
                    ),
                    child: Text(
                      song.artists.join(', '),
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: textSecondaryColor, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Duration
            if (song.duration != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    song.duration.toString(),
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
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
    _albumsScraper.dispose();
    super.dispose();
  }
}

// ============================================
// Shimmer Widget Class
// ============================================
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
