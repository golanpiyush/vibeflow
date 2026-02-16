// lib/pages/subpages/songs/playlists.dart
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';

import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/playlist_model.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/subpages/songs/albums_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/artists_grid_page.dart';
import 'package:vibeflow/pages/subpages/songs/playlistDetail.dart';
import 'package:vibeflow/pages/subpages/songs/savedSongs.dart';
import 'package:vibeflow/providers/playlist_providers.dart';
import 'package:vibeflow/services/spotify_import_service.dart';
import 'package:vibeflow/services/ytmusic_import_service.dart';
import 'package:vibeflow/utils/material_transitions.dart';
import 'package:vibeflow/utils/page_transitions.dart';

// ─── Spotify import service provider ────────────────────────────────────────

final spotifyImportServiceProvider = Provider<SpotifyImportService>((ref) {
  return SpotifyImportService();
});

final ytmusicImportServiceProvider = Provider<YTMusicImportService>((ref) {
  return YTMusicImportService(
    ref: ref, // Pass the ref parameter
  );
});

enum _ImportState { idle, loading, success, error }

enum ImportSource { spotify, ytmusic }

// final _spotifyImportProvider =
//     StateNotifierProvider.autoDispose<
//       _SpotifyImportNotifier,
//       ({_ImportState state, String? error, SpotifyPlaylistData? data})
//     >((ref) {
//       return _SpotifyImportNotifier(ref.watch(spotifyImportServiceProvider));
//     });

// ─── Main screen ─────────────────────────────────────────────────────────────

class IntegratedPlaylistsScreen extends ConsumerStatefulWidget {
  const IntegratedPlaylistsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<IntegratedPlaylistsScreen> createState() =>
      _IntegratedPlaylistsScreenState();
}

class _IntegratedPlaylistsScreenState
    extends ConsumerState<IntegratedPlaylistsScreen> {
  // ── Search state ──────────────────────────────────────────────────────────
  bool isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openYTMusicImportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _YTMusicImportSheet(),
    ).then((_) => ref.invalidate(playlistsProvider));
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final backgroundColor = themeData.scaffoldBackgroundColor;
    final iconActiveColor = themeData.colorScheme.primary;
    final iconColor = themeData.colorScheme.onPrimary;

    final playlistsAsync = ref.watch(playlistsProvider);
    final hasAccessAsync = ref.watch(hasAccessCodeProvider);

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
                  Expanded(
                    child: playlistsAsync.when(
                      data: (playlists) {
                        final filtered = _searchQuery.isEmpty
                            ? playlists
                            : playlists
                                  .where(
                                    (p) => p.name.toLowerCase().contains(
                                      _searchQuery.toLowerCase(),
                                    ),
                                  )
                                  .toList();

                        if (filtered.isEmpty && !isSearchMode) {
                          return _buildEmptyState(hasAccessAsync);
                        }
                        if (filtered.isEmpty && isSearchMode) {
                          return _buildNoResultsState();
                        }
                        return _buildPlaylistGrid(filtered, hasAccessAsync);
                      },
                      loading: () => _buildLoadingGrid(),
                      error: (error, stack) => _buildErrorState(),
                    ),
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
              heroTag: 'create_playlist',
              onPressed: _createNewPlaylist,
              backgroundColor: iconActiveColor,
              foregroundColor: iconColor,
              child: const Icon(Icons.add),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'search_playlists',
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
  // ── Sidebar ───────────────────────────────────────────────────────────────

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
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: labelStyle,
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
              isActive: true,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: labelActiveStyle,
              onTap: () {},
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
                      hintText: 'Search playlists...',
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
                    child: Text('Your Playlists', style: pageTitleStyle),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AsyncValue<bool> hasAccessAsync) {
    final themeData = Theme.of(context);
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final textSecondaryColor = themeData.colorScheme.onSurfaceVariant;
    final iconActiveColor = themeData.colorScheme.primary;
    final backgroundColor = themeData.scaffoldBackgroundColor;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 280,
              width: 280,
              child: Lottie.asset(
                'assets/animations/not_found.json',
                fit: BoxFit.contain,
                animate: true,
                repeat: true,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Playlists Yet',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textPrimaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first playlist or import\none from Spotify or YouTube Music',
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: _createNewPlaylist,
                  icon: const Icon(Icons.link, size: 20),
                  label: const Text('Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconActiveColor,
                    foregroundColor: backgroundColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ImportButtons(
                  hasSpotifyAccess: hasAccessAsync.when(
                    data: (v) => v,
                    loading: () => false,
                    error: (_, __) => false,
                  ),
                  onSpotifyPressed: _openSpotifyImportSheet,
                  onYTMusicPressed: _openYTMusicImportSheet,
                ),
              ],
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
              'No playlists found',
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

  Widget _buildErrorState() {
    final themeData = Theme.of(context);
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final textSecondaryColor = themeData.colorScheme.onSurfaceVariant;

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
  // ── Content widgets ───────────────────────────────────────────────────────

  Widget _buildLoadingGrid() {
    final cardBg = ref.watch(themeCardBackgroundColorProvider);
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: AppSpacing.lg,
        mainAxisSpacing: AppSpacing.xl,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: cardBg,
          highlightColor: cardBg.withOpacity(0.5),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaylistGrid(
    List<Playlist> playlists,
    AsyncValue<bool> hasAccessAsync,
  ) {
    final hasAccess = hasAccessAsync.when(
      data: (v) => v,
      loading: () => false,
      error: (_, __) => false,
    );

    // Calculate total items: playlists + import cards
    final importCardCount = hasAccess
        ? 2
        : 1; // Spotify + YT Music OR just YT Music
    final totalItems = playlists.length + importCardCount;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        120,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: AppSpacing.lg,
        mainAxisSpacing: AppSpacing.xl,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // First card: YouTube Music import (always visible)
        if (index == 0) {
          return _YTMusicImportCard(onTap: _openYTMusicImportSheet);
        }

        // Second card: Spotify import (only if has access)
        if (hasAccess && index == 1) {
          return _SpotifyImportCard(onTap: _openSpotifyImportSheet);
        }

        // Regular playlist cards
        final playlistIndex = hasAccess ? index - 2 : index - 1;
        return _PlaylistCard(
          playlist: playlists[playlistIndex],
          onTap: () => _openPlaylist(playlists[playlistIndex]),
        );
      },
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _openPlaylist(Playlist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaylistDetailScreen(playlistId: playlist.id!),
      ),
    ).then((_) => ref.invalidate(playlistsProvider));
  }

  void _openSpotifyImportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _SpotifyImportSheet(),
    ).then((_) => ref.invalidate(playlistsProvider));
  }

  Future<void> _createNewPlaylist() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    // Get theme values from providers correctly
    final themeData = Theme.of(context);
    final iconActiveColor = themeData.colorScheme.primary;
    final bgColor = themeData.scaffoldBackgroundColor;
    final cardBg = themeData.cardColor;
    final textPrimary = themeData.colorScheme.onSurface;
    final textSecondary = themeData.colorScheme.onSurfaceVariant;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Create Playlist',
          style: AppTypography.subtitle(
            context,
          ).copyWith(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                hintText: 'Playlist name',
                hintStyle: TextStyle(color: textSecondary.withOpacity(0.5)),
                filled: true,
                fillColor: bgColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: iconActiveColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              maxLines: 3,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                hintText: 'Description (optional)',
                hintStyle: TextStyle(color: textSecondary.withOpacity(0.5)),
                filled: true,
                fillColor: bgColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: iconActiveColor, width: 2),
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
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'description': descController.text.trim(),
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: iconActiveColor,
              foregroundColor: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result['name']!.trim().isNotEmpty) {
      try {
        final repo = await ref.read(playlistRepositoryFutureProvider.future);
        await repo.createPlaylist(
          name: result['name']!.trim(),
          description: result['description']?.trim().isNotEmpty == true
              ? result['description']!.trim()
              : null,
        );
        ref.invalidate(playlistsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Created "${result['name']}"')),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Error: $e')),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    bool autofocus = false,
    int maxLines = 1,
    required Color accentColor,
    required Color textColor,
    required Color hintColor,
    required Color fillColor,
  }) {
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      style: TextStyle(color: textColor),
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor.withOpacity(0.4)),
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
      ),
    );
  }
}

// ─── Spotify Import Card (grid cell) ─────────────────────────────────────────

class _SpotifyImportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SpotifyImportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color.fromARGB(41, 0, 0, 0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1DB954).withOpacity(0.15),
              ),
              child: Center(
                child: Image.asset(
                  'assets/icons/spotify.png',
                  width: 72,
                  height: 72,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFF1DB954),
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Import from\nSpotify',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1DB954),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Consumer(
              builder: (context, ref, child) {
                final textSecondary = ref.watch(
                  themeTextSecondaryColorProvider,
                );
                return Text(
                  'Paste a playlist link',
                  style: TextStyle(
                    color: textSecondary.withOpacity(0.4),
                    fontSize: 11,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotifyImportButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SpotifyImportButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_link, size: 20),
      label: const Text('Spotify'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1DB954),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}

// ─── Spotify Import Bottom Sheet ──────────────────────────────────────────────

class _SpotifyImportSheet extends ConsumerStatefulWidget {
  const _SpotifyImportSheet();

  @override
  ConsumerState<_SpotifyImportSheet> createState() =>
      _SpotifyImportSheetState();
}

class _SpotifyImportSheetState extends ConsumerState<_SpotifyImportSheet> {
  final _linkController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showBackgroundOption = false;
  Timer? _backgroundTimer;
  Timer? _backgroundCheckTimer;

  // ✨ NEW: Cache for text field state to reduce rebuilds
  bool _hasText = false;

  @override
  void initState() {
    super.initState();

    // ✨ OPTIMIZATION: Request focus after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    // ✨ OPTIMIZATION: Listen to text changes efficiently
    _linkController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _linkController.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    _linkController.removeListener(_onTextChanged);
    _linkController.dispose();
    _focusNode.dispose();
    _backgroundTimer?.cancel();
    _backgroundCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(_spotifyImportProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF181818),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ✨ OPTIMIZATION: Static drag handle (no rebuilds)
              const _DragHandle(),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✨ OPTIMIZATION: Static header (no rebuilds)
                      const _SpotifyImportHeader(),

                      const SizedBox(height: 28),

                      // ✨ OPTIMIZATION: Reduced rebuilds on text field
                      _OptimizedTextField(
                        controller: _linkController,
                        focusNode: _focusNode,
                        hasText: _hasText,
                        isEnabled: importState.state != _ImportState.loading,
                        onClear: () {
                          _linkController.clear();
                          ref.read(_spotifyImportProvider.notifier).reset();
                        },
                      ),

                      const SizedBox(height: 16),

                      _ImportButton(
                        isLoading: importState.state == _ImportState.loading,
                        isEnabled: _hasText,
                        onPressed: _startImport,
                        color: const Color(0xFF1DB954),
                      ),

                      // Progressive loading indicator
                      if (importState.state == _ImportState.loading &&
                          importState.progress != null) ...[
                        const SizedBox(height: 20),
                        _ProgressiveLoadingIndicator(
                          progress: importState.progress!,
                        ),
                      ],

                      // Background option
                      if (importState.state == _ImportState.loading &&
                          _showBackgroundOption) ...[
                        const SizedBox(height: 12),
                        _BackgroundButton(
                          onPressed: _continueInBackground,
                          color: const Color(0xFF1DB954),
                        ),
                      ],

                      if (importState.state == _ImportState.error) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: importState.error!),
                      ],

                      if (importState.state == _ImportState.success &&
                          importState.data != null) ...[
                        const SizedBox(height: 28),
                        _SpotifyPlaylistPreview(
                          data: importState.data!,
                          onSave: _saveImportedPlaylist,
                        ),
                      ],

                      if (importState.state == _ImportState.idle) ...[
                        const SizedBox(height: 24),
                        const _SpotifyHelpText(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startImport() {
    FocusScope.of(context).unfocus();
    setState(() => _showBackgroundOption = false);
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showBackgroundOption = true);
    });
    ref
        .read(_spotifyImportProvider.notifier)
        .importPlaylist(_linkController.text.trim());
  }

  void _continueInBackground() {
    _backgroundTimer?.cancel();

    final currentState = ref.read(_spotifyImportProvider);

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Importing playlist... ${currentState.progress?.current ?? 0}/${currentState.progress?.total ?? 0}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1DB954),
        duration: const Duration(minutes: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Cancel',
          textColor: Colors.white,
          onPressed: () {
            _backgroundCheckTimer?.cancel();
            ref.read(_spotifyImportProvider.notifier).reset();
            ScaffoldMessenger.of(context).clearSnackBars();
          },
        ),
      ),
    );

    _listenForBackgroundCompletionFixed();
  }

  void _listenForBackgroundCompletionFixed() {
    bool hasProcessedCompletion = false;
    Timer? checkTimer;

    void checkState() {
      if (!mounted || hasProcessedCompletion) {
        checkTimer?.cancel();
        return;
      }

      final state = ref.read(_spotifyImportProvider);

      if (state.state == _ImportState.success && state.data != null) {
        hasProcessedCompletion = true;
        checkTimer?.cancel();

        ScaffoldMessenger.of(context).clearSnackBars();

        _saveImportedPlaylistBackground(state.data!)
            .then((_) {
              // Success handled in save method
            })
            .catchError((error) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Import failed: $error'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            });
      } else if (state.state == _ImportState.error) {
        hasProcessedCompletion = true;
        checkTimer?.cancel();

        ScaffoldMessenger.of(context).clearSnackBars();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import failed: ${state.error ?? "Unknown error"}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
      // ✨ FIX: Update progress in snackbar with detailed info
      else if (state.state == _ImportState.loading && state.progress != null) {
        if (mounted && state.progress!.total > 0) {
          ScaffoldMessenger.of(context).clearSnackBars();

          // ✨ NEW: Show detailed progress with track name
          final progress = state.progress!;
          final percentage = ((progress.current / progress.total) * 100)
              .toInt();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Importing... ${progress.current}/${progress.total} ($percentage%)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (progress.trackName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      progress.trackName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              backgroundColor: const Color(0xFF1DB954),
              duration: const Duration(minutes: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              action: SnackBarAction(
                label: 'Cancel',
                textColor: Colors.white,
                onPressed: () {
                  checkTimer?.cancel();
                  ref.read(_spotifyImportProvider.notifier).reset();
                  ScaffoldMessenger.of(context).clearSnackBars();
                },
              ),
            ),
          );
        }
      }
    }

    // ✨ FIX: Check more frequently (every 200ms instead of 500ms)
    checkTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      checkState();
    });

    // Cleanup after 5 minutes max
    Future.delayed(const Duration(minutes: 5), () {
      if (!hasProcessedCompletion) {
        checkTimer?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Import timed out. Please try again.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  Future<void> _saveImportedPlaylistBackground(SpotifyPlaylistData data) async {
    try {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);

      // Download cover image
      String? localCoverPath;
      if (data.coverImageUrl != null) {
        try {
          localCoverPath = await _downloadCoverImage(
            url: data.coverImageUrl!,
            playlistId: data.id,
          );
        } catch (e) {
          debugPrint('⚠️ Failed to download cover: $e');
          // Continue without cover image
        }
      }

      // Create playlist
      final playlist = await repo.createPlaylist(
        name: data.name,
        description: (data.description?.isNotEmpty == true)
            ? data.description
            : null,
        coverImagePath: localCoverPath,
        coverType: localCoverPath != null ? 'custom' : 'mosaic',
      );

      // Convert tracks to DbSong
      final dbSongs = <DbSong>[];
      for (final track in data.tracks) {
        // Skip invalid tracks
        if (track.id.contains('spotify')) {
          debugPrint('⏭️ Skipping invalid track: ${track.title}');
          continue;
        }

        dbSongs.add(_spotifyTrackToDbSong(track));
      }

      if (dbSongs.isEmpty) {
        throw Exception('No valid tracks to import.');
      }

      // Add songs to playlist
      await repo.addSongsToPlaylistBatch(
        playlistId: playlist.id!,
        songs: dbSongs,
      );

      // Refresh playlists
      ref.invalidate(playlistsProvider);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '"${data.name}" imported successfully\n${dbSongs.length} songs added',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1DB954),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Background save failed: $e');
      rethrow;
    }
  }

  Future<void> _saveImportedPlaylist(SpotifyPlaylistData data) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SavingDialog(),
    );
    try {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);
      String? localCoverPath;
      if (data.coverImageUrl != null) {
        localCoverPath = await _downloadCoverImage(
          url: data.coverImageUrl!,
          playlistId: data.id,
        );
      }
      final playlist = await repo.createPlaylist(
        name: data.name,
        description: (data.description?.isNotEmpty == true)
            ? data.description
            : null,
        coverImagePath: localCoverPath,
        coverType: localCoverPath != null ? 'custom' : 'mosaic',
      );
      final dbSongs = <DbSong>[];
      for (final track in data.tracks) {
        if (track.id.contains('spotify')) continue;
        dbSongs.add(_spotifyTrackToDbSong(track));
      }
      if (dbSongs.isEmpty) throw Exception('No valid tracks to import.');
      await repo.addSongsToPlaylistBatch(
        playlistId: playlist.id!,
        songs: dbSongs,
      );
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${data.name}" imported · ${dbSongs.length} songs'),
            backgroundColor: const Color(0xFF1DB954),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  DbSong _spotifyTrackToDbSong(SpotifyTrackData track) {
    return DbSong(
      videoId: track.id,
      title: track.title,
      artists: track.artists,
      thumbnail: track.albumArtUrl ?? '',
      duration: _durationToString(track.duration),
      addedAt: track.addedAt ?? DateTime.now(),
      playCount: 0,
      isActive: true,
    );
  }

  String _durationToString(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<String?> _downloadCoverImage({
    required String url,
    required String playlistId,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/playlist_covers/spotify_$playlistId.jpg');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }
}

// ─── Saving dialog ────────────────────────────────────────────────────────────

class _SavingDialog extends StatelessWidget {
  const _SavingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF1DB954),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Importing playlist…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Saving songs & cover art',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shimmer preview ──────────────────────────────────────────────────────────

// ─── NEW: Optimized Static Widgets (No Rebuilds) ────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SpotifyImportHeader extends StatelessWidget {
  const _SpotifyImportHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1DB954).withOpacity(0.15),
          ),
          child: Center(
            child: Image.asset(
              'assets/icons/spotify.png',
              height: 42,
              width: 42,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import Spotify Playlist',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Spotify Public playlists only',
              style: TextStyle(color: Color(0xFF1DB954), fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _OptimizedTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final bool isEnabled;
  final VoidCallback onClear;

  const _OptimizedTextField({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.isEnabled,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: isEnabled,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'https://open.spotify.com/playlist/...',
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.3),
          fontSize: 13,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        prefixIcon: const Icon(Icons.link, color: Color(0xFF1DB954), size: 20),
        suffixIcon: hasText
            ? IconButton(
                icon: Icon(
                  Icons.clear,
                  color: Colors.white.withOpacity(0.4),
                  size: 18,
                ),
                onPressed: onClear,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1DB954), width: 1.5),
        ),
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  final bool isLoading;
  final bool isEnabled;
  final VoidCallback onPressed;
  final Color color;

  const _ImportButton({
    required this.isLoading,
    required this.isEnabled,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading || !isEnabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withOpacity(0.3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Import Playlist',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

class _BackgroundButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color color;

  const _BackgroundButton({required this.onPressed, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.cloud_download_outlined, size: 18),
        label: const Text('Continue in Background'),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _SpotifyHelpText extends StatelessWidget {
  const _SpotifyHelpText();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to get the link:',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        const _HelpStep(
          num: '1',
          text: 'Open Spotify and find a public playlist',
        ),
        const _HelpStep(num: '2', text: 'Tap ··· → Share → Copy link'),
        const _HelpStep(num: '3', text: 'Paste it above and hit Import'),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 14,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(width: 6),
            Text(
              'Private playlists cannot be imported',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HelpStep extends StatelessWidget {
  final String num;
  final String text;

  const _HelpStep({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1DB954).withOpacity(0.2),
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Playlist preview ─────────────────────────────────────────────────────────

class _SpotifyPlaylistPreview extends StatelessWidget {
  final SpotifyPlaylistData data;
  final Future<void> Function(SpotifyPlaylistData) onSave;
  const _SpotifyPlaylistPreview({required this.data, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final minutes = data.totalDuration.inMinutes;
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: data.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: data.coverImageUrl!,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _coverPlaceholder(),
                      errorWidget: (_, __, ___) => _coverPlaceholder(),
                    )
                  : _coverPlaceholder(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (data.description != null &&
                      data.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      data.description!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'By ${data.ownerName}',
                    style: const TextStyle(
                      color: Color(0xFF1DB954),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(
              icon: Icons.music_note,
              label: '${data.totalTracks} songs',
            ),
            _StatChip(icon: Icons.timer_outlined, label: durationStr),
            if (data.addedAt != null)
              _StatChip(
                icon: Icons.calendar_today_outlined,
                label: _formatDate(data.addedAt!),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Preview',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        ...data.tracks.take(5).map((t) => _TrackPreviewTile(track: t)),
        if (data.tracks.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              '+ ${data.tracks.length - 5} more songs',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => onSave(data),
            icon: const Icon(Icons.download_done_rounded, size: 20),
            label: Text('Save "${data.name}"'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder() => Container(
    width: 90,
    height: 90,
    decoration: BoxDecoration(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.playlist_play, color: Colors.white30, size: 36),
  );

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF1DB954)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackPreviewTile extends StatelessWidget {
  final SpotifyTrackData track;
  const _TrackPreviewTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.albumArtUrl != null
                ? CachedNetworkImage(
                    imageUrl: track.albumArtUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _thumbPlaceholder(),
                    errorWidget: (_, __, ___) => _thumbPlaceholder(),
                  )
                : _thumbPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  track.artists.join(', '),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            _formatDuration(track.duration),
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
  );

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _ProgressiveLoadingIndicator extends StatelessWidget {
  final _ImportProgress progress;

  const _ProgressiveLoadingIndicator({required this.progress});

  @override
  Widget build(BuildContext context) {
    final percentage = progress.percentage;
    final showPercentage = progress.total > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: showPercentage ? percentage : null,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF1DB954),
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),

          // Track count and percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  progress.trackName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showPercentage)
                Text(
                  '${progress.current}/${progress.total}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),

          // Percentage text
          if (showPercentage) ...[
            const SizedBox(height: 4),
            Text(
              '${(percentage * 100).toInt()}% complete',
              style: TextStyle(
                color: const Color(0xFF1DB954).withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportButtons extends StatelessWidget {
  final bool hasSpotifyAccess;
  final VoidCallback onSpotifyPressed;
  final VoidCallback onYTMusicPressed;

  const _ImportButtons({
    required this.hasSpotifyAccess,
    required this.onSpotifyPressed,
    required this.onYTMusicPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: onYTMusicPressed,
          icon: Image.asset(
            'assets/icons/ytmusic.png',
            width: 20,
            height: 20,
            // Optional: if you want to tint the icon
          ),
          label: const Text('YT Music'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(55, 244, 67, 54),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        // if (hasSpotifyAccess) ...[
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: onSpotifyPressed,
          icon: Image.asset(
            'assets/icons/spotify.png', // Make sure this path matches your actual asset file
            width: 20,
            height: 20,
          ),
          label: const Text('Spotify'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(92, 84, 255, 144),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        // ],
      ],
    );
  }
}

// ─── Error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4458).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF4458).withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4458), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFF4458),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Playlist card ────────────────────────────────────────────────────────────

class _PlaylistCard extends ConsumerWidget {
  // Changed to ConsumerWidget
  final Playlist playlist;
  final VoidCallback onTap;
  const _PlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Added WidgetRef
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color.fromARGB(41, 0, 0, 0), // Transparent background
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: _buildCover(theme, colorScheme), // Pass theme
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            playlist.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (playlist.isFavorite)
                          Icon(
                            Icons.favorite,
                            color: colorScheme.error,
                            size: 16,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(ThemeData theme, ColorScheme colorScheme) {
    if (playlist.coverImagePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(playlist.coverImagePath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildGradient(theme, colorScheme),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: _buildGradient(theme, colorScheme),
    );
  }

  Widget _buildGradient(ThemeData theme, ColorScheme colorScheme) {
    final colors = playlist.isFavorite
        ? [colorScheme.error, colorScheme.error.withOpacity(0.7)]
        : [colorScheme.primary, colorScheme.secondary];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(
          playlist.isFavorite ? Icons.favorite : Icons.playlist_play,
          size: 50,
          color: colorScheme.onPrimary.withOpacity(0.8),
        ),
      ),
    );
  }
}

// ✨ NEW: Progress tracking model
class _ImportProgress {
  final int current;
  final int total;
  final String trackName;

  const _ImportProgress({
    required this.current,
    required this.total,
    required this.trackName,
  });

  double get percentage => total > 0 ? (current / total) : 0.0;
}

class _SpotifyImportNotifier
    extends
        StateNotifier<
          ({
            _ImportState state,
            String? error,
            SpotifyPlaylistData? data,
            _ImportProgress? progress, // ✨ NEW: Progress field
          })
        > {
  final SpotifyImportService _service;

  _SpotifyImportNotifier(this._service)
    : super((
        state: _ImportState.idle,
        error: null,
        data: null,
        progress: null, // ✨ NEW
      ));

  Future<void> importPlaylist(String link) async {
    if (!mounted) return;
    state = (
      state: _ImportState.loading,
      error: null,
      data: null,
      progress: const _ImportProgress(
        current: 0,
        total: 0,
        trackName: 'Starting...',
      ),
    );

    try {
      final data = await _service.importPlaylist(
        link,
        onProgress: (current, total, trackName) {
          if (!mounted) return;
          // ✨ NEW: Update state with real-time progress
          state = (
            state: _ImportState.loading,
            error: null,
            data: null,
            progress: _ImportProgress(
              current: current,
              total: total,
              trackName: trackName,
            ),
          );
        },
      );
      if (!mounted) return;
      state = (
        state: _ImportState.success,
        error: null,
        data: data,
        progress: null,
      );
    } on SpotifyImportException catch (e) {
      if (!mounted) return;
      state = (
        state: _ImportState.error,
        error: e.message,
        data: null,
        progress: null,
      );
    } catch (e) {
      if (!mounted) return;
      state = (
        state: _ImportState.error,
        error: 'Something went wrong. Please try again.',
        data: null,
        progress: null,
      );
    }
  }

  void reset() {
    if (!mounted) return;
    state = (state: _ImportState.idle, error: null, data: null, progress: null);
  }
}

class _ImportData<T> {
  final _ImportState state;
  final String? error;
  final T? data;
  final ImportSource source;

  _ImportData({
    required this.state,
    this.error,
    this.data,
    required this.source,
  });
}

class _YTMusicImportNotifier
    extends StateNotifier<_ImportData<YTMusicPlaylistData>> {
  final YTMusicImportService _service;

  _YTMusicImportNotifier(this._service)
    : super(
        _ImportData(state: _ImportState.idle, source: ImportSource.ytmusic),
      );

  Future<void> importPlaylist(String input) async {
    state = _ImportData(
      state: _ImportState.loading,
      source: ImportSource.ytmusic,
    );
    try {
      final data = await _service.importPlaylist(input);
      state = _ImportData(
        state: _ImportState.success,
        data: data,
        source: ImportSource.ytmusic,
      );
    } on YTMusicImportException catch (e) {
      state = _ImportData(
        state: _ImportState.error,
        error: e.message,
        source: ImportSource.ytmusic,
      );
    } catch (e) {
      state = _ImportData(
        state: _ImportState.error,
        error: 'Something went wrong. Please try again.',
        source: ImportSource.ytmusic,
      );
    }
  }

  void reset() {
    state = _ImportData(state: _ImportState.idle, source: ImportSource.ytmusic);
  }
}

final _spotifyImportProvider =
    StateNotifierProvider.autoDispose<
      _SpotifyImportNotifier,
      ({
        _ImportState state,
        String? error,
        SpotifyPlaylistData? data,
        _ImportProgress? progress, // ✨ NEW
      })
    >((ref) {
      return _SpotifyImportNotifier(ref.watch(spotifyImportServiceProvider));
    });
final _ytmusicImportProvider =
    StateNotifierProvider.autoDispose<
      _YTMusicImportNotifier,
      _ImportData<YTMusicPlaylistData>
    >((ref) {
      return _YTMusicImportNotifier(ref.watch(ytmusicImportServiceProvider));
    });

class _YTMusicImportCard extends StatelessWidget {
  final VoidCallback onTap;

  const _YTMusicImportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color.fromARGB(41, 0, 0, 0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.15),
              ),
              child: Center(
                child: Image.asset(
                  'assets/icons/ytmusic.png', // 👈 your png path
                  width: 72,
                  height: 72,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Import from\nYouTube Music',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Consumer(
              builder: (context, ref, child) {
                final textSecondary = ref.watch(
                  themeTextSecondaryColorProvider,
                );
                return Text(
                  'Paste playlist link or ID',
                  style: TextStyle(
                    color: textSecondary.withOpacity(0.4),
                    fontSize: 11,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _YTMusicImportSheet extends ConsumerStatefulWidget {
  const _YTMusicImportSheet();

  @override
  ConsumerState<_YTMusicImportSheet> createState() =>
      _YTMusicImportSheetState();
}

class _YTMusicImportSheetState extends ConsumerState<_YTMusicImportSheet> {
  final _linkController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showBackgroundOption = false;
  Timer? _backgroundTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _linkController.dispose();
    _focusNode.dispose();
    _backgroundTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(_ytmusicImportProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF181818),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withOpacity(0.15),
                            ),
                            child: Center(
                              child: Center(
                                child: Image.asset(
                                  'assets/icons/ytmusic.png',
                                  height: 42,
                                  width: 42,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Import YouTube Music Playlist',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'YouTube Public playlists only',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _linkController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'YouTube Music playlist link or ID',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          prefixIcon: const Icon(
                            Icons.link,
                            color: Colors.red,
                            size: 20,
                          ),
                          suffixIcon: _linkController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: Colors.white.withOpacity(0.4),
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _linkController.clear();
                                    ref
                                        .read(_ytmusicImportProvider.notifier)
                                        .reset();
                                    setState(() {});
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        enabled: importState.state != _ImportState.loading,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              importState.state == _ImportState.loading ||
                                  _linkController.text.trim().isEmpty
                              ? null
                              : _startImport,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            disabledBackgroundColor: Colors.red.withOpacity(
                              0.3,
                            ),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: importState.state == _ImportState.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Import Playlist',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      if (importState.state == _ImportState.loading &&
                          _showBackgroundOption) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _continueInBackground,
                            icon: const Icon(
                              Icons.cloud_download_outlined,
                              size: 18,
                            ),
                            label: const Text('Continue in Background'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(
                                color: Colors.red,
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (importState.state == _ImportState.error) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: importState.error!),
                      ],

                      if (importState.state == _ImportState.success &&
                          importState.data != null) ...[
                        const SizedBox(height: 28),
                        _YTMusicPlaylistPreview(
                          data: importState.data!,
                          onSave: _saveImportedPlaylist,
                        ),
                      ],
                      if (importState.state == _ImportState.idle) ...[
                        const SizedBox(height: 24),
                        _buildHelpText(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHelpText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to get the link:',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        _helpStep('1', 'Open YouTube Music app or website'),
        _helpStep('2', 'Find a public playlist'),
        _helpStep('3', 'Tap Share → Copy link'),
        _helpStep('4', 'Paste it above and hit Import'),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 14,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(width: 6),
            Text(
              'Private playlists cannot be imported',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _helpStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.2),
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startImport() {
    FocusScope.of(context).unfocus();
    setState(() => _showBackgroundOption = false);
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showBackgroundOption = true);
    });
    ref
        .read(_ytmusicImportProvider.notifier)
        .importPlaylist(_linkController.text.trim());
  }

  void _continueInBackground() {
    _backgroundTimer?.cancel();

    final currentState = ref.read(_spotifyImportProvider);

    Navigator.pop(context);

    // ✨ FIX: Show more detailed initial message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Importing in background...',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (currentState.progress != null &&
                currentState.progress!.total > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${currentState.progress!.current}/${currentState.progress!.total} songs',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFF1DB954),
        duration: const Duration(minutes: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Cancel',
          textColor: Colors.white,
          onPressed: () {
            ref.read(_spotifyImportProvider.notifier).reset();
            ScaffoldMessenger.of(context).clearSnackBars();
          },
        ),
      ),
    );

    _listenForBackgroundCompletionFixed();
  }

  void _listenForBackgroundCompletionFixed() {
    bool hasProcessedCompletion = false;
    Timer? checkTimer;

    void checkState() {
      if (!mounted || hasProcessedCompletion) {
        checkTimer?.cancel();
        return;
      }

      final state = ref.read(_spotifyImportProvider);

      if (state.state == _ImportState.success && state.data != null) {
        hasProcessedCompletion = true;
        checkTimer?.cancel();

        ScaffoldMessenger.of(context).clearSnackBars();

        _saveImportedPlaylistBackground(state.data! as YTMusicPlaylistData)
            .then((_) {
              // Success handled in save method
            })
            .catchError((error) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Import failed: $error'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            });
      } else if (state.state == _ImportState.error) {
        hasProcessedCompletion = true;
        checkTimer?.cancel();

        ScaffoldMessenger.of(context).clearSnackBars();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import failed: ${state.error ?? "Unknown error"}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
      // ✨ FIX: Update progress in snackbar with detailed info
      else if (state.state == _ImportState.loading && state.progress != null) {
        if (mounted && state.progress!.total > 0) {
          ScaffoldMessenger.of(context).clearSnackBars();

          // ✨ NEW: Show detailed progress with track name
          final progress = state.progress!;
          final percentage = ((progress.current / progress.total) * 100)
              .toInt();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Importing... ${progress.current}/${progress.total} ($percentage%)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (progress.trackName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      progress.trackName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              backgroundColor: const Color(0xFF1DB954),
              duration: const Duration(minutes: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              action: SnackBarAction(
                label: 'Cancel',
                textColor: Colors.white,
                onPressed: () {
                  checkTimer?.cancel();
                  ref.read(_spotifyImportProvider.notifier).reset();
                  ScaffoldMessenger.of(context).clearSnackBars();
                },
              ),
            ),
          );
        }
      }
    }

    // ✨ FIX: Check more frequently (every 200ms instead of 500ms)
    checkTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      checkState();
    });

    // Cleanup after 5 minutes max
    Future.delayed(const Duration(minutes: 5), () {
      if (!hasProcessedCompletion) {
        checkTimer?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Import timed out. Please try again.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  Future<void> _saveImportedPlaylistBackground(YTMusicPlaylistData data) async {
    try {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);
      String? localCoverPath;
      if (data.coverImageUrl != null) {
        localCoverPath = await _downloadCoverImage(
          url: data.coverImageUrl!,
          playlistId: data.id,
        );
      }
      final playlist = await repo.createPlaylist(
        name: data.name,
        description: (data.description?.isNotEmpty == true)
            ? data.description
            : null,
        coverImagePath: localCoverPath,
        coverType: localCoverPath != null ? 'custom' : 'mosaic',
      );
      final dbSongs = <DbSong>[];
      for (final track in data.tracks) {
        dbSongs.add(_ytmusicTrackToDbSong(track));
      }
      if (dbSongs.isEmpty) throw Exception('No valid tracks to import.');
      await repo.addSongsToPlaylistBatch(
        playlistId: playlist.id!,
        songs: dbSongs,
      );
      ref.invalidate(playlistsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${data.name}" imported · ${dbSongs.length} songs'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveImportedPlaylist(YTMusicPlaylistData data) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SavingDialog(),
    );
    try {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);
      String? localCoverPath;
      if (data.coverImageUrl != null) {
        localCoverPath = await _downloadCoverImage(
          url: data.coverImageUrl!,
          playlistId: data.id,
        );
      }
      final playlist = await repo.createPlaylist(
        name: data.name,
        description: (data.description?.isNotEmpty == true)
            ? data.description
            : null,
        coverImagePath: localCoverPath,
        coverType: localCoverPath != null ? 'custom' : 'mosaic',
      );
      final dbSongs = <DbSong>[];
      for (final track in data.tracks) {
        dbSongs.add(_ytmusicTrackToDbSong(track));
      }
      if (dbSongs.isEmpty) throw Exception('No valid tracks to import.');
      await repo.addSongsToPlaylistBatch(
        playlistId: playlist.id!,
        songs: dbSongs,
      );
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${data.name}" imported · ${dbSongs.length} songs'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  DbSong _ytmusicTrackToDbSong(YTMusicTrackData track) {
    return DbSong(
      videoId: track.id,
      title: track.title,
      artists: track.artists,
      thumbnail: track.albumArtUrl ?? '',
      duration: _durationToString(track.duration),
      addedAt: track.addedAt ?? DateTime.now(),
      playCount: 0,
      isActive: true,
    );
  }

  String _durationToString(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<String?> _downloadCoverImage({
    required String url,
    required String playlistId,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/playlist_covers/ytmusic_$playlistId.jpg');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }
}

// ─── YouTube Music Shimmer Preview ───────────────────────────────────────────

class _YTMusicShimmerPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF2A2A2A),
      highlightColor: const Color(0xFF3A3A3A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 18,
                      width: double.infinity,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    Container(height: 14, width: 120, color: Colors.white),
                    const SizedBox(height: 10),
                    Container(height: 12, width: 80, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _shimmerChip(),
              const SizedBox(width: 10),
              _shimmerChip(),
              const SizedBox(width: 10),
              _shimmerChip(),
            ],
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < 5; i++) ...[
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  color: Colors.white,
                  margin: const EdgeInsets.only(right: 12),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 13,
                        width: double.infinity,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 7),
                      Container(
                        height: 11,
                        width: 100 + (i * 15.0),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _shimmerChip() => Container(
    height: 28,
    width: 70,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
  );
}

// ─── YouTube Music Playlist Preview ──────────────────────────────────────────

class _YTMusicPlaylistPreview extends StatelessWidget {
  final YTMusicPlaylistData data;
  final Future<void> Function(YTMusicPlaylistData) onSave;
  const _YTMusicPlaylistPreview({required this.data, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final minutes = data.totalDuration.inMinutes;
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: data.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: data.coverImageUrl!,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _coverPlaceholder(),
                      errorWidget: (_, __, ___) => _coverPlaceholder(),
                    )
                  : _coverPlaceholder(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (data.description != null &&
                      data.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      data.description!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'By ${data.ownerName}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(
              icon: Icons.music_note,
              label: '${data.totalTracks} songs',
            ),
            _StatChip(icon: Icons.timer_outlined, label: durationStr),
            if (data.addedAt != null)
              _StatChip(
                icon: Icons.calendar_today_outlined,
                label: _formatDate(data.addedAt!),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Preview',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        ...data.tracks.take(5).map((t) => _YTMusicTrackPreviewTile(track: t)),
        if (data.tracks.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              '+ ${data.tracks.length - 5} more songs',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => onSave(data),
            icon: const Icon(Icons.download_done_rounded, size: 20),
            label: Text('Save "${data.name}"'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder() => Container(
    width: 90,
    height: 90,
    decoration: BoxDecoration(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.playlist_play, color: Colors.white30, size: 36),
  );

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

class _YTMusicTrackPreviewTile extends StatelessWidget {
  final YTMusicTrackData track;
  const _YTMusicTrackPreviewTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.albumArtUrl != null
                ? CachedNetworkImage(
                    imageUrl: track.albumArtUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _thumbPlaceholder(),
                    errorWidget: (_, __, ___) => _thumbPlaceholder(),
                  )
                : _thumbPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  track.artists.join(', '),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            _formatDuration(track.duration),
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
  );

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
