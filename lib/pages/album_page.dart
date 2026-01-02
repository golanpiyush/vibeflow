// lib/pages/album_page.dart
import 'package:flutter/material.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/models/album_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/player_page.dart';

class AlbumPage extends StatefulWidget {
  final Album album;

  const AlbumPage({Key? key, required this.album}) : super(key: key);

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Debug: Print album info
    print('📀 [AlbumPage] Album: ${widget.album.title}');
    print('📀 [AlbumPage] Songs count: ${widget.album.songs.length}');
    if (widget.album.songs.isEmpty) {
      print('⚠️ [AlbumPage] No songs in album!');
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
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAlbumInfo(),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSongsList(),
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

    return SizedBox(
      width: 80,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(label: 'Songs'),
            const SizedBox(height: 32),
            _buildSidebarItem(label: 'Other versions', isActive: false),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({required String label, bool isActive = true}) {
    return SizedBox(
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
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          // Album title
          Text(
            widget.album.title,
            style: AppTypography.pageTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          // Share and bookmark buttons
          IconButton(
            icon: const Icon(
              Icons.bookmark_border,
              color: AppColors.textPrimary,
            ),
            onPressed: () {
              // TODO: Implement bookmark
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.textPrimary),
            onPressed: () {
              // TODO: Implement share
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumInfo() {
    return Column(
      children: [
        // Enqueue button
        Center(
          child: GestureDetector(
            onTap: () {
              // TODO: Implement enqueue functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enqueue feature coming soon'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                'Enqueue',
                style: AppTypography.subtitle.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Album cover (optional, if you want to show it)
        if (widget.album.coverArt != null && widget.album.coverArt!.isNotEmpty)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.album.coverArt!,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 200,
                    height: 200,
                    color: AppColors.cardBackground,
                    child: const Center(
                      child: Icon(
                        Icons.album,
                        size: 80,
                        color: AppColors.iconInactive,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Album artist
        if (widget.album.artist.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.album.artist,
            style: AppTypography.subtitle.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        // Album year
        if (widget.album.year > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.album.year.toString(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildSongsList() {
    if (widget.album.songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Text(
            'No songs available',
            style: AppTypography.subtitle.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.album.songs.asMap().entries.map((entry) {
        final index = entry.key;
        final song = entry.value;
        return _buildSongItem(song, index + 1);
      }).toList(),
    );
  }

  Widget _buildSongItem(dynamic song, int trackNumber) {
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
            // Thumbnail
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

            // Song info
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

            // Duration
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
