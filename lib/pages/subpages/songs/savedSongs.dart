import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:shimmer/shimmer.dart';

import 'package:vibeflow/api_base/scrapper.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/managers/download_maintener.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/pages/subpages/songs/albums_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/artists_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/playlists.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';

class SavedSongsScreen extends ConsumerStatefulWidget {
  const SavedSongsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SavedSongsScreen> createState() => _SavedSongsScreenState();
}

class _SavedSongsScreenState extends ConsumerState<SavedSongsScreen> {
  final _audioService = AudioServices.instance;
  final _downloadService = DownloadService.instance;
  final _scraper = YouTubeMusicScraper();

  // ── Search state ──────────────────────────────────────────────────────────
  bool isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  List<DownloadedSong> _savedSongs = [];
  bool _isLoading = true;
  DownloadStats? _stats;
  String _sortBy = 'date';

  // Cache for thumbnails (only for fallback when local thumbnail is missing)
  final Map<String, String> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _loadSavedSongs();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scraper.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSongs() async {
    setState(() => _isLoading = true);

    try {
      final songs = await _downloadService.getDownloadedSongs();

      if (mounted) {
        setState(() {
          _savedSongs = songs;
          _isLoading = false;
        });

        _applySorting();
        _prefetchMissingThumbnails();
      }
    } catch (e) {
      debugPrint('Error loading saved songs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _prefetchMissingThumbnails() async {
    for (final song in _savedSongs) {
      if (_thumbnailCache.containsKey(song.videoId)) continue;

      final localThumb = _getLocalThumbnailPath(song);
      if (localThumb != null && File(localThumb).existsSync()) continue;

      try {
        final thumbnail = await _scraper.getThumbnailUrl(song.videoId);
        _thumbnailCache[song.videoId] = thumbnail;
      } catch (e) {
        print('⚠️ Failed to fetch thumbnail for ${song.videoId}: $e');
      }
    }

    if (mounted) setState(() {});
  }

  String? _getLocalThumbnailPath(DownloadedSong song) {
    try {
      return (song as dynamic).thumbnailPath as String?;
    } catch (e) {
      return null;
    }
  }

  String? _getLocalAudioPath(DownloadedSong song) {
    try {
      if ((song as dynamic).filePath != null) {
        return (song as dynamic).filePath as String?;
      }
      if ((song as dynamic).audioPath != null) {
        return (song as dynamic).audioPath as String?;
      }
      if ((song as dynamic).path != null) {
        return (song as dynamic).path as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadStats() async {
    final stats = await DownloadMaintenanceService.getDownloadStats();
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  void _applySorting() {
    setState(() {
      switch (_sortBy) {
        case 'title':
          _savedSongs.sort((a, b) => a.title.compareTo(b.title));
          break;
        case 'artist':
          _savedSongs.sort((a, b) => a.artist.compareTo(b.artist));
          break;
        case 'size':
          _savedSongs.sort((a, b) => b.fileSize.compareTo(a.fileSize));
          break;
        case 'date':
        default:
          _savedSongs.sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
          break;
      }
    });
  }

  Future<void> _playSong(DownloadedSong downloadedSong, int index) async {
    try {
      String thumbnail;
      final localThumbPath = _getLocalThumbnailPath(downloadedSong);

      if (localThumbPath != null && File(localThumbPath).existsSync()) {
        thumbnail = localThumbPath;
        print('🖼️ [SavedSongs] Using local thumbnail: $thumbnail');
      } else {
        thumbnail = _thumbnailCache[downloadedSong.videoId] ?? '';
        if (thumbnail.isEmpty) {
          thumbnail = await _scraper.getThumbnailUrl(downloadedSong.videoId);
          _thumbnailCache[downloadedSong.videoId] = thumbnail;
        }
        print('🌐 [SavedSongs] Using network thumbnail: $thumbnail');
      }

      final song = QuickPick(
        videoId: downloadedSong.videoId,
        title: downloadedSong.title,
        artists: downloadedSong.artist,
        thumbnail: thumbnail,
        duration: null,
      );

      final localAudioPath = _getLocalAudioPath(downloadedSong);
      if (localAudioPath != null && File(localAudioPath).existsSync()) {
        print('🎵 [SavedSongs] Local audio available: $localAudioPath');
        final songModel = song.toSong();
        songModel.audioUrl = localAudioPath;
      } else {
        print(
          '⚠️ [SavedSongs] Local audio not found, will stream from network',
        );
      }

      final queue = <QuickPick>[];

      for (int i = index; i < _savedSongs.length; i++) {
        final queueSong = _savedSongs[i];

        String queueThumbnail;
        final queueLocalThumb = _getLocalThumbnailPath(queueSong);

        if (queueLocalThumb != null && File(queueLocalThumb).existsSync()) {
          queueThumbnail = queueLocalThumb;
        } else {
          queueThumbnail = _thumbnailCache[queueSong.videoId] ?? '';
          if (queueThumbnail.isEmpty) {
            queueThumbnail = await _scraper.getThumbnailUrl(queueSong.videoId);
            _thumbnailCache[queueSong.videoId] = queueThumbnail;
          }
        }

        final queueItem = QuickPick(
          videoId: queueSong.videoId,
          title: queueSong.title,
          artists: queueSong.artist,
          thumbnail: queueThumbnail,
          duration: null,
        );

        final queueLocalAudio = _getLocalAudioPath(queueSong);
        if (queueLocalAudio != null && File(queueLocalAudio).existsSync()) {
          final queueSongModel = queueItem.toSong();
          queueSongModel.audioUrl = queueLocalAudio;
        }

        queue.add(queueItem);
      }

      final handler = getAudioHandler();
      if (handler == null) {
        throw Exception('Audio handler not available');
      }

      print('🎵 [SavedSongs] Playing queue of ${queue.length} songs');
      print('📋 [SavedSongs] Starting from: ${song.title}');

      int localCount = 0;
      for (final q in queue) {
        final qSong = q.toSong();
        if (qSong.audioUrl != null && qSong.audioUrl!.isNotEmpty) {
          localCount++;
        }
      }
      print('💾 [SavedSongs] Local files: $localCount/${queue.length}');

      await handler.playPlaylistQueue(queue, startIndex: 0);

      if (mounted) {
        await NewPlayerPage.open(
          context,
          song,
          heroTag: 'saved-${song.videoId}',
        );
      }
    } catch (e) {
      print('❌ [SavedSongs] Error playing song: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play song: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteSong(DownloadedSong song) async {
    final cardBg = ref.read(themeCardBackgroundColorProvider);
    final textPrimary = ref.read(themeTextPrimaryColorProvider);
    final textSecondary = ref.read(themeTextSecondaryColorProvider);
    final iconActive = ref.read(themeIconActiveColorProvider);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove Song?',
          style: AppTypography.subtitle(context).copyWith(color: textPrimary),
        ),
        content: Text(
          'Are you sure you want to remove "${song.title}" from saved songs?',
          style: AppTypography.subtitle(context).copyWith(color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _downloadService.deleteDownload(song.videoId);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${song.title}"'),
            backgroundColor: iconActive,
            behavior: SnackBarBehavior.floating,
          ),
        );

        _loadSavedSongs();
        _loadStats();
      }
    }
  }

  Future<void> _runMaintenance() async {
    final iconActive = ref.read(themeIconActiveColorProvider);
    final cardBg = ref.read(themeCardBackgroundColorProvider);
    final textPrimary = ref.read(themeTextPrimaryColorProvider);
    final textSecondary = ref.read(themeTextSecondaryColorProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: iconActive)),
    );

    final report = await DownloadMaintenanceService.runMaintenance();

    if (mounted) {
      Navigator.pop(context);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Maintenance Complete',
            style: AppTypography.subtitle(context).copyWith(color: textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Orphaned files removed: ${report.orphanedFilesRemoved}',
                style: AppTypography.caption(
                  context,
                ).copyWith(color: textSecondary),
              ),
              Text(
                'Corrupted files removed: ${report.corruptedFilesRemoved}',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textSecondary),
              ),
              Text(
                'Empty metadata removed: ${report.emptyMetadataRemoved}',
                style: AppTypography.caption(
                  context,
                ).copyWith(color: textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Storage used: ${(report.totalStorageUsed / (1024 * 1024)).toStringAsFixed(2)} MB',
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: textPrimary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _loadSavedSongs();
                _loadStats();
              },
              child: Text('OK', style: TextStyle(color: iconActive)),
            ),
          ],
        ),
      );
    }
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
                  _buildTopBar(),
                  if (_stats != null) _buildStatsBar(),
                  Expanded(
                    child: _isLoading ? _buildLoadingList() : _buildSongsList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'maintenance',
              onPressed: _runMaintenance,
              backgroundColor: iconActiveColor,
              foregroundColor: iconColor,
              child: const Icon(Icons.cleaning_services),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'search_songs',
              onPressed: () {
                setState(() {
                  isSearchMode = !isSearchMode;
                  if (isSearchMode) {
                    _searchFocusNode.requestFocus();
                  } else {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                    _searchQuery = '';
                  }
                });
              },
              backgroundColor: iconActiveColor,
              foregroundColor: iconColor,
              child: Icon(isSearchMode ? Icons.close : Icons.search),
            ),
          ],
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

    final labelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final labelActiveStyle = AppTypography.sidebarLabelActive(
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
              labelStyle: labelStyle,
              onTap: () =>
                  Navigator.of(context).pushFade(const AppearancePage()),
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              label: 'Quick picks',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: labelStyle,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Songs',
              isActive: true,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: labelActiveStyle,
              onTap: () {},
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Playlists',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: labelStyle,
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
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: labelStyle,
              onTap: () {
                Navigator.of(context).pushMaterialVertical(
                  const ArtistsGridPage(),
                  slideUp: true,
                  enableParallax: true,
                );
              },
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Albums',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: labelStyle,
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

  Widget _buildTopBar() {
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
                  _searchQuery = '';
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
                      hintText: 'Search songs...',
                      hintStyle: hintStyle,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: Text('Saved Songs', style: pageTitleStyle),
                  ),
          ),
          if (!isSearchMode)
            PopupMenuButton<String>(
              icon: Icon(Icons.sort, color: iconActiveColor, size: 24),
              color: themeData.colorScheme.surfaceVariant,
              onSelected: (value) {
                setState(() => _sortBy = value);
                _applySorting();
              },
              itemBuilder: (context) => [
                _buildSortMenuItem('date', Icons.access_time, 'Recent'),
                _buildSortMenuItem('title', Icons.sort_by_alpha, 'Title'),
                _buildSortMenuItem('artist', Icons.person, 'Artist'),
                _buildSortMenuItem('size', Icons.storage, 'Size'),
              ],
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    final themeData = Theme.of(context);
    final isSelected = _sortBy == value;
    final iconActive = themeData.colorScheme.primary;
    final textPrimary = themeData.colorScheme.onSurface;
    final textSecondary = themeData.colorScheme.onSurfaceVariant;

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: isSelected ? iconActive : textSecondary),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(color: isSelected ? iconActive : textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final themeData = Theme.of(context);
    final cardBg = themeData.colorScheme.surfaceVariant;
    final iconActive = themeData.colorScheme.primary;
    final textPrimary = themeData.colorScheme.onSurface;
    final textSecondary = themeData.colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.music_note,
            label: 'Songs',
            value: '${_stats!.totalDownloads}',
            iconColor: iconActive,
            textColor: textPrimary,
            labelColor: textSecondary,
          ),
          _buildStatItem(
            icon: Icons.storage,
            label: 'Storage',
            value: _stats!.formattedStorage,
            iconColor: iconActive,
            textColor: textPrimary,
            labelColor: textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    required Color textColor,
    required Color labelColor,
  }) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.subtitle(
            context,
          ).copyWith(color: textColor, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: AppTypography.caption(context).copyWith(color: labelColor),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final themeData = Theme.of(context);
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final textSecondaryColor = themeData.colorScheme.onSurfaceVariant;

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
              'No Saved Songs Yet',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the heart icon to save songs',
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    final themeData = Theme.of(context);
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final textSecondaryColor = themeData.colorScheme.onSurfaceVariant;

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
              'No songs found',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimaryColor),
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

  // ── Content widgets ───────────────────────────────────────────────────────

  Widget _buildLoadingList() {
    final cardBg = ref.watch(themeCardBackgroundColorProvider);

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: 10,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: cardBg,
          highlightColor: cardBg.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        color: cardBg,
                      ),
                      const SizedBox(height: 8),
                      Container(height: 14, width: 120, color: cardBg),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongsList() {
    // Apply search filter
    final filtered = _searchQuery.isEmpty
        ? _savedSongs
        : _savedSongs
              .where(
                (s) =>
                    s.title.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ||
                    s.artist.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();

    if (filtered.isEmpty && isSearchMode) {
      return _buildNoResultsState();
    }

    if (filtered.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadSavedSongs();
        await _loadStats();
      },
      color: ref.watch(themeIconActiveColorProvider),
      child: ListView.builder(
        itemCount: filtered.length,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          120,
        ),
        itemBuilder: (context, index) {
          final song = filtered[index];
          final originalIndex = _savedSongs.indexOf(song);
          return _SongTile(
            song: song,
            onTap: () => _playSong(song, originalIndex),
            onDelete: () => _deleteSong(song),
            thumbnailCache: _thumbnailCache,
            getLocalThumbnailPath: _getLocalThumbnailPath,
            getLocalAudioPath: _getLocalAudioPath,
          );
        },
      ),
    );
  }

  Widget _buildErrorState() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: textSecondaryColor.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading playlists',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimaryColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Song tile widget ─────────────────────────────────────────────────────────

class _SongTile extends ConsumerWidget {
  final DownloadedSong song;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Map<String, String> thumbnailCache;
  final String? Function(DownloadedSong) getLocalThumbnailPath;
  final String? Function(DownloadedSong) getLocalAudioPath;

  const _SongTile({
    required this.song,
    required this.onTap,
    required this.onDelete,
    required this.thumbnailCache,
    required this.getLocalThumbnailPath,
    required this.getLocalAudioPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = Theme.of(context);
    final cardBg = themeData.colorScheme.surfaceVariant;
    final textPrimary = themeData.colorScheme.onSurface;
    final textSecondary = themeData.colorScheme.onSurfaceVariant;
    final iconActive = themeData.colorScheme.primary;

    // Determine which thumbnail to use
    String? displayThumbnail;
    bool isLocalThumbnail = false;

    final localThumbPath = getLocalThumbnailPath(song);
    if (localThumbPath != null && File(localThumbPath).existsSync()) {
      displayThumbnail = localThumbPath;
      isLocalThumbnail = true;
    } else {
      displayThumbnail = thumbnailCache[song.videoId];
    }

    // Check if local audio exists
    final localAudioPath = getLocalAudioPath(song);
    final hasLocalAudio =
        localAudioPath != null && File(localAudioPath).existsSync();

    return Dismissible(
      key: Key(song.videoId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 56,
              height: 56,
              color: cardBg,
              child: displayThumbnail != null
                  ? (isLocalThumbnail
                        ? Image.file(
                            File(displayThumbnail),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.music_note,
                                color: textSecondary.withOpacity(0.5),
                              );
                            },
                          )
                        : Image.network(
                            displayThumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.music_note,
                                color: textSecondary.withOpacity(0.5),
                              );
                            },
                          ))
                  : Icon(
                      Icons.music_note,
                      color: textSecondary.withOpacity(0.5),
                    ),
            ),
          ),
          title: Text(
            song.title,
            style: AppTypography.songTitle(
              context,
            ).copyWith(color: textPrimary, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.artist,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (hasLocalAudio) ...[
                    Icon(Icons.offline_pin, size: 12, color: iconActive),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    song.formattedFileSize,
                    style: AppTypography.caption(context).copyWith(
                      color: textSecondary.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: IconButton(
            icon: Icon(Icons.more_vert, color: textPrimary),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: cardBg,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(Icons.play_arrow, color: textPrimary),
                        title: Text(
                          'Play',
                          style: TextStyle(color: textPrimary),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onTap();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete, color: Colors.red),
                        title: const Text(
                          'Remove',
                          style: TextStyle(color: Colors.red),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onDelete();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
