// lib/pages/subpages/songs/playlistDetail.dart - FIXED WITH MATERIAL WIDGET & VISUALIZER
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/playlist_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/subpages/songs/albums_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/artists_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/providers/playlist_providers.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int playlistId;

  const PlaylistDetailScreen({Key? key, required this.playlistId})
    : super(key: key);

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  bool _isReordering = false;

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final playlistAsync = ref.watch(
      playlistWithSongsProvider(widget.playlistId),
    );

    return Scaffold(
      backgroundColor: themeData.scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            // ── Vertical sidebar ───────────────────────────────────────────
            _buildSidebar(context, themeData),

            // ── Main content ───────────────────────────────────────────────
            Expanded(
              child: playlistAsync.when(
                data: (playlistWithSongs) {
                  if (playlistWithSongs == null) {
                    return _buildNotFoundState(themeData);
                  }
                  return _buildContent(playlistWithSongs, themeData);
                },
                loading: () => _buildLoadingState(themeData),
                error: (error, stack) => _buildErrorState(error, themeData),
              ),
            ),
          ],
        ),
      ),

      // ── Floating Action Buttons ───────────────────────────────────────
      floatingActionButton: playlistAsync.maybeWhen(
        data: (data) => data != null ? _buildFABs(data, themeData) : null,
        orElse: () => null,
      ),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar(BuildContext context, ThemeData themeData) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconColor = ref.watch(themeTextPrimaryColorProvider);
    final textColor = ref.watch(themeTextPrimaryColorProvider);

    final labelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: textColor);

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),

            // Appearance icon
            _buildSidebarItem(
              icon: Icons.edit_square,
              label: '',
              isActive: false,
              iconColor: iconColor,
              labelStyle: labelStyle,
              onTap: () =>
                  Navigator.of(context).pushFade(const AppearancePage()),
            ),
            const SizedBox(height: 32),

            _buildSidebarItem(
              label: 'Quick picks',
              iconColor: iconColor,
              labelStyle: labelStyle,
              onTap: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
            const SizedBox(height: 24),

            _buildSidebarItem(
              label: 'Songs',
              iconColor: iconColor,
              labelStyle: labelStyle,
              onTap: () {
                Navigator.of(context).pushReplacementMaterialVertical(
                  const SavedSongsScreen(),
                  slideUp: true,
                  enableParallax: true,
                );
              },
            ),
            const SizedBox(height: 24),

            _buildSidebarItem(
              label: 'Playlists',
              iconColor: iconColor,
              labelStyle: labelStyle,
              onTap: () {
                Navigator.of(context).pushReplacementMaterialVertical(
                  const IntegratedPlaylistsScreen(),
                  slideUp: true,
                  enableParallax: true,
                );
              },
            ),
            const SizedBox(height: 24),

            _buildSidebarItem(
              label: 'Artists',
              iconColor: iconColor,
              labelStyle: labelStyle,
              onTap: () {
                Navigator.of(context).pushReplacementMaterialVertical(
                  const ArtistsGridPage(),
                  slideUp: true,
                  enableParallax: true,
                );
              },
            ),
            const SizedBox(height: 24),

            _buildSidebarItem(
              label: 'Albums',
              iconColor: iconColor,
              labelStyle: labelStyle,
              onTap: () {
                Navigator.of(context).pushReplacementMaterialVertical(
                  const AlbumsGridPage(),
                  slideUp: true,
                );
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
    required Color iconColor,
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
                color: iconColor.withOpacity(isActive ? 1.0 : 0.6),
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

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent(
    PlaylistWithSongs playlistWithSongs,
    ThemeData themeData,
  ) {
    final playlist = playlistWithSongs.playlist;
    final songs = playlistWithSongs.songs;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.xxxl),
        _buildTopBar(playlist, themeData),
        Expanded(
          child: CustomScrollView(
            slivers: [
              // Playlist header
              SliverToBoxAdapter(
                child: _buildPlaylistHeader(playlist, songs, themeData),
              ),

              // Controls
              SliverToBoxAdapter(child: _buildControls(songs, themeData)),

              // Song list
              if (songs.isEmpty)
                SliverFillRemaining(child: _buildEmptySongsState(themeData))
              else if (_isReordering)
                SliverReorderableList(
                  itemCount: songs.length,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderSong(playlist.id!, songs, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return ReorderableDragStartListener(
                      key: Key(song.videoId),
                      index: index,
                      child: _buildSongTile(
                        song,
                        index,
                        playlist.id!,
                        true,
                        themeData,
                      ),
                    );
                  },
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final song = songs[index];
                    return _buildSongTile(
                      song,
                      index,
                      playlist.id!,
                      false,
                      themeData,
                    );
                  }, childCount: songs.length),
                ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(Playlist playlist, ThemeData themeData) {
    final textColor = ref.watch(themeTextPrimaryColorProvider);
    final iconColor = ref.watch(themeTextPrimaryColorProvider);

    final pageTitleStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textColor);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back, color: iconColor, size: 28),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                playlist.name,
                style: pageTitleStyle.copyWith(fontSize: 20),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: iconColor, size: 24),
            onPressed: () => _showPlaylistOptions(playlist, themeData),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistHeader(
    Playlist playlist,
    List<DbSong> songs,
    ThemeData themeData,
  ) {
    final textPrimary = ref.watch(themeTextPrimaryColorProvider);
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          // Cover image
          GestureDetector(
            onTap: () => _changeCover(playlist, themeData),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: playlist.coverImagePath != null
                    ? Image.file(
                        File(playlist.coverImagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildCoverPlaceholder(themeData),
                      )
                    : (songs.isNotEmpty && songs.first.thumbnail.isNotEmpty
                          ? Image.network(
                              songs.first.thumbnail.split('=').first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildCoverPlaceholder(themeData),
                            )
                          : _buildCoverPlaceholder(themeData)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Playlist name
          Text(
            playlist.name,
            style: AppTypography.songTitle(
              context,
            ).copyWith(color: textPrimary, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (playlist.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              playlist.description!,
              style: AppTypography.body(context).copyWith(color: textSecondary),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 12),

          Text(
            '${playlist.songCount} songs • ${_formatDuration(playlist.totalDuration)}',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondary.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverPlaceholder(ThemeData themeData) {
    return Image.asset(
      'assets/imgs/funny_dawg.jpg',
      fit: BoxFit.cover,
      width: 200,
      height: 200,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Asset not found: $error');
        return Container(
          width: 200,
          height: 200,
          color: Colors.red, // visible red = asset path is wrong
          child: const Center(
            child: Text('IMG ERROR', style: TextStyle(color: Colors.white)),
          ),
        );
      },
    );
  }

  Widget _buildControls(List<DbSong> songs, ThemeData themeData) {
    final primaryColor = themeData.primaryColor;
    final backgroundColor = themeData.scaffoldBackgroundColor;
    final textColor = ref.watch(themeTextPrimaryColorProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: songs.isEmpty ? null : () => _playAll(songs),
              icon: const Icon(Icons.play_arrow, size: 22),
              label: const Text('Play All'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: backgroundColor,
                disabledBackgroundColor: textColor.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isReordering ? Icons.check : Icons.swap_vert,
                color: textColor,
                size: 24,
              ),
              onPressed: songs.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _isReordering = !_isReordering;
                      });
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(
    DbSong song,
    int index,
    int playlistId,
    bool showDragHandle,
    ThemeData themeData,
  ) {
    final textPrimary = ref.watch(themeTextPrimaryColorProvider);
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);
    final primaryColor = themeData.primaryColor;
    final cardBg = themeData.cardColor;
    final activeColor = ref.watch(themeIconActiveColorProvider);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 4,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: StreamBuilder<String?>(
          stream: _getCurrentPlayingSongStream(),
          builder: (context, snapshot) {
            final currentVideoId = snapshot.data;
            final isCurrentlyPlaying = currentVideoId == song.videoId;

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: showDragHandle ? null : () => _playSong(song, index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isCurrentlyPlaying
                      ? activeColor.withOpacity(0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // Leading
                    if (showDragHandle)
                      Icon(Icons.drag_handle, color: textSecondary, size: 24)
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: cardBg),
                          child: song.thumbnail.isNotEmpty
                              ? Image.network(
                                  song.thumbnail.split('=').first,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    'assets/imgs/funny_dawg.jpg',
                                    fit: BoxFit.cover,
                                    width: 50,
                                    height: 50,
                                  ),
                                )
                              : Image.asset(
                                  'assets/imgs/funny_dawg.jpg',
                                  fit: BoxFit.cover,
                                  width: 50,
                                  height: 50,
                                ),
                        ),
                      ),
                    const SizedBox(width: 12),

                    // Title and subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            style: AppTypography.body(context).copyWith(
                              color: isCurrentlyPlaying
                                  ? activeColor
                                  : textPrimary,
                              fontWeight: isCurrentlyPlaying
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artistsString,
                            style: AppTypography.caption(context).copyWith(
                              color: isCurrentlyPlaying
                                  ? activeColor
                                  : textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Trailing
                    if (!showDragHandle)
                      if (isCurrentlyPlaying)
                        Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(left: 8),
                          child: _MiniMusicVisualizer(color: activeColor),
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: textSecondary,
                            size: 20,
                          ),
                          onPressed: () =>
                              _showSongOptions(song, playlistId, themeData),
                        ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Stream<String?> _getCurrentPlayingSongStream() {
    final handler = getAudioHandler();
    if (handler == null) {
      return Stream.value(null);
    }
    return handler.mediaItem.map((item) => item?.id);
  }

  // ── States ────────────────────────────────────────────────────────────────

  Widget _buildLoadingState(ThemeData themeData) {
    final primaryColor = themeData.primaryColor;
    return Center(child: CircularProgressIndicator(color: primaryColor));
  }

  Widget _buildNotFoundState(ThemeData themeData) {
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.playlist_remove,
            size: 80,
            color: textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Playlist not found',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error, ThemeData themeData) {
    final textPrimary = ref.watch(themeTextPrimaryColorProvider);
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);
    final errorColor = themeData.colorScheme.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: errorColor.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading playlist',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString().length > 100
                  ? '${error.toString().substring(0, 100)}...'
                  : error.toString(),
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondary),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySongsState(ThemeData themeData) {
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note_outlined,
            size: 80,
            color: textSecondary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No songs yet',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Add songs to start listening',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondary.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildFABs(PlaylistWithSongs playlistWithSongs, ThemeData themeData) {
    final primaryColor = themeData.primaryColor;
    final backgroundColor = themeData.scaffoldBackgroundColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 40.0),
      child: FloatingActionButton(
        heroTag: 'reorder_songs',
        onPressed: playlistWithSongs.songs.isEmpty
            ? null
            : () {
                setState(() {
                  _isReordering = !_isReordering;
                });
              },
        backgroundColor: playlistWithSongs.songs.isEmpty
            ? primaryColor.withOpacity(0.3)
            : primaryColor,
        child: Icon(
          _isReordering ? Icons.check : Icons.swap_vert,
          color: backgroundColor,
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _showPlaylistOptions(Playlist playlist, ThemeData themeData) {
    final cardBg = themeData.cardColor;
    final textPrimary = themeData.textTheme.bodyLarge?.color ?? Colors.white;
    final errorColor = themeData.colorScheme.error;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: textPrimary),
              title: Text('Edit Details', style: TextStyle(color: textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _editPlaylist(playlist, themeData);
              },
            ),
            ListTile(
              leading: Icon(Icons.image, color: textPrimary),
              title: Text('Change Cover', style: TextStyle(color: textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _changeCover(playlist, themeData);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: errorColor),
              title: Text(
                'Delete Playlist',
                style: TextStyle(color: errorColor),
              ),
              onTap: () {
                Navigator.pop(context);
                _deletePlaylist(playlist, themeData);
              },
            ),
            const SizedBox(height: 75),
          ],
        ),
      ),
    );
  }

  void _showSongOptions(DbSong song, int playlistId, ThemeData themeData) {
    final cardBg = themeData.cardColor;
    final textPrimary = themeData.textTheme.bodyLarge?.color ?? Colors.white;
    final errorColor = themeData.colorScheme.error;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.remove_circle_outline, color: errorColor),
              title: Text(
                'Remove from Playlist',
                style: TextStyle(color: textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                _removeSong(song, playlistId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPlaylist(Playlist playlist, ThemeData themeData) async {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description);

    final cardBg = themeData.cardColor;
    final textPrimary = themeData.textTheme.bodyLarge?.color ?? Colors.white;
    final textSecondary =
        themeData.textTheme.bodyMedium?.color ?? Colors.white70;
    final primaryColor = themeData.primaryColor;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit Playlist',
          style: AppTypography.subtitle(
            context,
          ).copyWith(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: textSecondary),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              style: TextStyle(color: textPrimary),
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                labelStyle: TextStyle(color: textSecondary),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: primaryColor),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, {
                'name': nameController.text,
                'description': descController.text,
              });
            },
            child: Text('Save', style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );

    if (result != null && result['name']!.trim().isNotEmpty) {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);
      await repo.updatePlaylist(
        playlist.copyWith(
          name: result['name']!.trim(),
          description: result['description']?.trim(),
        ),
      );
      ref.invalidate(playlistWithSongsProvider(widget.playlistId));
    }
  }

  Future<void> _changeCover(Playlist playlist, ThemeData themeData) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName =
          'playlist_${playlist.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = path.join(appDir.path, 'covers', fileName);

      final coversDir = Directory(path.join(appDir.path, 'covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      await File(image.path).copy(savedPath);

      final repo = await ref.read(playlistRepositoryFutureProvider.future);
      await repo.updatePlaylist(
        playlist.copyWith(coverImagePath: savedPath, coverType: 'custom'),
      );

      ref.invalidate(playlistWithSongsProvider(widget.playlistId));
    }
  }

  Future<void> _deletePlaylist(Playlist playlist, ThemeData themeData) async {
    final cardBg = themeData.cardColor;
    final textPrimary = themeData.textTheme.bodyLarge?.color ?? Colors.white;
    final textSecondary =
        themeData.textTheme.bodyMedium?.color ?? Colors.white70;
    final errorColor = themeData.colorScheme.error;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Playlist?',
          style: AppTypography.subtitle(context).copyWith(color: textPrimary),
        ),
        content: Text(
          'This will permanently delete "${playlist.name}" and remove all songs from it.',
          style: AppTypography.body(context).copyWith(color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: errorColor)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);
      await repo.deletePlaylist(playlist.id!);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _reorderSong(
    int playlistId,
    List<DbSong> songs,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final song = songs[oldIndex];
    final repo = await ref.read(playlistRepositoryFutureProvider.future);

    if (song.id != null) {
      await repo.reorderSongInPlaylist(
        playlistId: playlistId,
        songId: song.id!,
        newPosition: newIndex,
      );
    }

    ref.invalidate(playlistWithSongsProvider(playlistId));
  }

  Future<void> _removeSong(DbSong song, int playlistId) async {
    final repo = await ref.read(playlistRepositoryFutureProvider.future);
    final iconActive = ref.read(themeIconActiveColorProvider);

    if (song.id != null) {
      await repo.removeSongFromPlaylist(
        playlistId: playlistId,
        songId: song.id!,
      );

      ref.invalidate(playlistWithSongsProvider(playlistId));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Removed from playlist'),
          backgroundColor: iconActive,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _playAll(List<DbSong> songs) {
    final handler = getAudioHandler();
    if (handler == null) {
      print('❌ Audio handler not available');
      return;
    }

    final quickPicks = songs.map((dbSong) {
      return QuickPick(
        videoId: dbSong.videoId,
        title: dbSong.title,
        artists: dbSong.artistsString,
        thumbnail: dbSong.thumbnail,
        duration: dbSong.duration,
      );
    }).toList();

    handler.playPlaylistQueue(
      quickPicks,
      startIndex: 0,
      playlistId: widget.playlistId.toString(),
    );

    print('▶️ Playing all ${quickPicks.length} songs from playlist');
  }

  void _playSong(DbSong song, int index) {
    final handler = getAudioHandler();
    if (handler == null) {
      print('❌ Audio handler not available');
      return;
    }

    final playlistAsync = ref.read(
      playlistWithSongsProvider(widget.playlistId),
    );

    playlistAsync.whenData((playlistWithSongs) {
      if (playlistWithSongs == null) return;

      final songs = playlistWithSongs.songs;

      final quickPicks = songs.map((dbSong) {
        return QuickPick(
          videoId: dbSong.videoId,
          title: dbSong.title,
          artists: dbSong.artistsString,
          thumbnail: dbSong.thumbnail,
          duration: dbSong.duration,
        );
      }).toList();

      handler.playPlaylistQueue(
        quickPicks,
        startIndex: index,
        playlistId: widget.playlistId.toString(),
      );

      print('▶️ Playing playlist from song ${index + 1}/${quickPicks.length}');
    });
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

// ─── Mini Music Visualizer Widget ─────────────────────────────────────────────

class _MiniMusicVisualizer extends StatefulWidget {
  final Color color;

  const _MiniMusicVisualizer({required this.color});

  @override
  State<_MiniMusicVisualizer> createState() => _MiniMusicVisualizerState();
}

class _MiniMusicVisualizerState extends State<_MiniMusicVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildBar(_getBarHeight(value, 0)),
            const SizedBox(width: 2.5),
            _buildBar(_getBarHeight(value, 0.25)),
            const SizedBox(width: 2.5),
            _buildBar(_getBarHeight(value, 0.5)),
            const SizedBox(width: 2.5),
            _buildBar(_getBarHeight(value, 0.75)),
          ],
        );
      },
    );
  }

  double _getBarHeight(double animationValue, double offset) {
    // Create a wave effect with phase offset for each bar
    final phase = (animationValue + offset) % 1.0;
    // Use sine wave for smooth, natural motion
    final height = 0.3 + (0.7 * ((1 + math.sin(phase * 2 * math.pi)) / 2));
    return height;
  }

  Widget _buildBar(double heightFactor) {
    return Container(
      width: 3.5,
      height: 20 * heightFactor,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: widget.color.withOpacity(0.3),
            blurRadius: 2,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}
