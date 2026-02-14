// lib/pages/subpages/songs/playlists.dart - FIXED VERSION
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/playlist_model.dart';
import 'package:vibeflow/pages/subpages/songs/playlistDetail.dart';
import 'package:vibeflow/providers/playlist_providers.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:vibeflow/services/spotify_import_service.dart';

final spotifyImportServiceProvider = Provider<SpotifyImportService>((ref) {
  return SpotifyImportService();
});

enum _ImportState { idle, loading, success, error }

class _SpotifyImportNotifier
    extends
        StateNotifier<
          ({_ImportState state, String? error, SpotifyPlaylistData? data})
        > {
  final SpotifyImportService _service;

  _SpotifyImportNotifier(this._service)
    : super((state: _ImportState.idle, error: null, data: null));

  Future<void> importPlaylist(String link) async {
    state = (state: _ImportState.loading, error: null, data: null);
    try {
      final data = await _service.importPlaylist(link);
      state = (state: _ImportState.success, error: null, data: data);
    } on SpotifyImportException catch (e) {
      state = (state: _ImportState.error, error: e.message, data: null);
    } catch (e) {
      state = (
        state: _ImportState.error,
        error: 'Something went wrong. Please try again.',
        data: null,
      );
    }
  }

  void reset() {
    state = (state: _ImportState.idle, error: null, data: null);
  }
}

final _spotifyImportProvider =
    StateNotifierProvider.autoDispose<
      _SpotifyImportNotifier,
      ({_ImportState state, String? error, SpotifyPlaylistData? data})
    >((ref) {
      return _SpotifyImportNotifier(ref.watch(spotifyImportServiceProvider));
    });

class IntegratedPlaylistsScreen extends ConsumerStatefulWidget {
  const IntegratedPlaylistsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<IntegratedPlaylistsScreen> createState() =>
      _IntegratedPlaylistsScreenState();
}

class _IntegratedPlaylistsScreenState
    extends ConsumerState<IntegratedPlaylistsScreen> {
  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final hasAccessAsync = ref.watch(hasAccessCodeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: playlistsAsync.when(
                data: (playlists) {
                  if (playlists.isEmpty) {
                    return _buildEmptyState(hasAccessAsync);
                  }
                  return _buildPlaylistGrid(playlists, hasAccessAsync);
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                error: (error, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 60,
                          color: Colors.white.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading playlists',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewPlaylist,
        backgroundColor: const Color(0xFFFF4458),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Create Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          const Text(
            'Your Playlists',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AsyncValue<bool> hasAccessAsync) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF4458).withOpacity(0.3),
                    const Color(0xFF6B4CE8).withOpacity(0.3),
                  ],
                ),
              ),
              child: Icon(
                Icons.playlist_play_rounded,
                size: 60,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Playlists Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create your first playlist or import\none from Spotify',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _createNewPlaylist,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4458),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                hasAccessAsync.when(
                  data: (hasAccess) => hasAccess
                      ? _SpotifyImportButton(onPressed: _openSpotifyImportSheet)
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ),
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      // +1 for the Spotify import card (only shown if user has access)
      itemCount: playlists.length + (hasAccess ? 1 : 0),
      itemBuilder: (context, index) {
        // The Spotify import card is always the LAST item in the grid
        if (hasAccess && index == playlists.length) {
          return _SpotifyImportCard(onTap: _openSpotifyImportSheet);
        }
        return _PlaylistCard(
          playlist: playlists[index],
          onTap: () => _openPlaylist(playlists[index]),
        );
      },
    );
  }

  void _openPlaylist(Playlist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaylistDetailScreen(playlistId: playlist.id!),
      ),
    ).then((_) {
      ref.invalidate(playlistsProvider);
    });
  }

  void _openSpotifyImportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _SpotifyImportSheet(),
    ).then((_) {
      ref.invalidate(playlistsProvider);
    });
  }

  Future<void> _createNewPlaylist() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Create Playlist',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(nameController, 'Playlist name', autofocus: true),
            const SizedBox(height: 16),
            _buildTextField(
              descController,
              'Description (optional)',
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, {
                  'name': nameController.text,
                  'description': descController.text,
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4458),
              foregroundColor: Colors.white,
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
          description: result['description']?.trim(),
        );
        ref.invalidate(playlistsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created "${result['name']}"'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
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
  }) {
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      style: const TextStyle(color: Colors.white),
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF4458), width: 2),
        ),
      ),
    );
  }
}

// ── Spotify Import Card (grid cell) ──────────────────────────────────────

class _SpotifyImportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SpotifyImportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF1DB954).withOpacity(0.4),
            width: 1.5,
          ),
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
                  'assets/spotify_icon.png', // drop the Spotify icon in assets
                  width: 32,
                  height: 32,
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
            Text(
              'Paste a playlist link',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
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

// ── Spotify Import Bottom Sheet ───────────────────────────────────────────

class _SpotifyImportSheet extends ConsumerStatefulWidget {
  const _SpotifyImportSheet();

  @override
  ConsumerState<_SpotifyImportSheet> createState() =>
      _SpotifyImportSheetState();
}

class _SpotifyImportSheetState extends ConsumerState<_SpotifyImportSheet> {
  final _linkController = TextEditingController();
  final _focusNode = FocusNode();

  // ✅ ADD THESE NEW FIELDS
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
              // Handle
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
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1DB954).withOpacity(0.15),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.add_link,
                                color: Color(0xFF1DB954),
                                size: 22,
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
                                'Public playlists only',
                                style: TextStyle(
                                  color: Color(0xFF1DB954),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Link input
                      TextField(
                        controller: _linkController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'https://open.spotify.com/playlist/...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          prefixIcon: const Icon(
                            Icons.link,
                            color: Color(0xFF1DB954),
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
                                        .read(_spotifyImportProvider.notifier)
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
                              color: Color(0xFF1DB954),
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFFF4458),
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        enabled: importState.state != _ImportState.loading,
                      ),
                      const SizedBox(height: 16),

                      // Import button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              importState.state == _ImportState.loading ||
                                  _linkController.text.trim().isEmpty
                              ? null
                              : _startImport,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            disabledBackgroundColor: const Color(
                              0xFF1DB954,
                            ).withOpacity(0.3),
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

                      // ✅ ADD THIS: Background import button
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
                              foregroundColor: const Color(0xFF1DB954),
                              side: const BorderSide(
                                color: Color(0xFF1DB954),
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

                      // Error message
                      if (importState.state == _ImportState.error) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: importState.error!),
                      ],

                      // Shimmer loading state
                      if (importState.state == _ImportState.loading) ...[
                        const SizedBox(height: 28),
                        _SpotifyShimmerPreview(),
                      ],

                      // Success preview
                      if (importState.state == _ImportState.success &&
                          importState.data != null) ...[
                        const SizedBox(height: 28),
                        _SpotifyPlaylistPreview(
                          data: importState.data!,
                          onSave: _saveImportedPlaylist,
                        ),
                      ],

                      // Help text
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
        _helpStep('1', 'Open Spotify and find a public playlist'),
        _helpStep('2', 'Tap ··· → Share → Copy link'),
        _helpStep('3', 'Paste it above and hit Import'),
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

  void _startImport() {
    FocusScope.of(context).unfocus();

    // ✅ Start the 4-second timer
    setState(() {
      _showBackgroundOption = false;
    });

    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showBackgroundOption = true;
        });
      }
    });

    ref
        .read(_spotifyImportProvider.notifier)
        .importPlaylist(_linkController.text.trim());
  }

  void _continueInBackground() {
    // Cancel the timer
    _backgroundTimer?.cancel();

    // Close the bottom sheet
    Navigator.pop(context);

    // Show persistent snackbar
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
            const Expanded(
              child: Text(
                'Importing playlist in background...',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1DB954),
        duration: const Duration(minutes: 5), // Long duration
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    // ✅ Listen to import completion in background
    _listenForBackgroundCompletion();
  }

  void _listenForBackgroundCompletion() {
    // Get the current import state stream
    final stateStream = ref.read(_spotifyImportProvider.notifier).stream;

    // Listen for state changes
    final subscription = stateStream.listen((state) async {
      if (state.state == _ImportState.success && state.data != null) {
        // Import succeeded - save the playlist
        debugPrint('🎉 Background import completed successfully');

        // Dismiss the loading snackbar
        ScaffoldMessenger.of(context).clearSnackBars();

        // Save the imported playlist
        try {
          await _saveImportedPlaylistBackground(state.data!);
        } catch (e) {
          debugPrint('❌ Background save failed: $e');
          if (mounted) {
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
      } else if (state.state == _ImportState.error) {
        // Import failed
        debugPrint('❌ Background import failed: ${state.error}');

        // Dismiss the loading snackbar
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
    });

    // Clean up subscription after 5 minutes (timeout)
    Future.delayed(const Duration(minutes: 5), () {
      subscription.cancel();
    });
  }

  Future<void> _saveImportedPlaylistBackground(SpotifyPlaylistData data) async {
    try {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);

      // ── Step 1: Download cover image to local storage ────────────────────
      String? localCoverPath;
      if (data.coverImageUrl != null) {
        localCoverPath = await _downloadCoverImage(
          url: data.coverImageUrl!,
          playlistId: data.id,
        );
      }

      // ── Step 2: Create the playlist row ──────────────────────────────────
      final playlist = await repo.createPlaylist(
        name: data.name,
        description: (data.description?.isNotEmpty == true)
            ? data.description
            : null,
        coverImagePath: localCoverPath,
        coverType: localCoverPath != null ? 'custom' : 'mosaic',
      );

      debugPrint(
        '🎵 Converting ${data.tracks.length} tracks to DbSong format...',
      );

      // ── Step 3: Convert Spotify tracks → DbSong ──────────────────────────
      final dbSongs = <DbSong>[];
      for (int i = 0; i < data.tracks.length; i++) {
        final track = data.tracks[i];

        // Validate video ID
        if (track.id.startsWith('spotify:') ||
            track.id.startsWith('spotify-') ||
            track.id.contains('spotify')) {
          debugPrint(
            '⚠️ Skipping track ${i + 1}: ${track.title} - Invalid video ID: ${track.id}',
          );
          continue;
        }

        final dbSong = _spotifyTrackToDbSong(track);
        debugPrint(
          '✅ Song ${i + 1}: ${track.title} -> videoId: ${dbSong.videoId}',
        );
        dbSongs.add(dbSong);
      }

      if (dbSongs.isEmpty) {
        throw Exception(
          'No valid tracks to import. All video IDs were invalid.',
        );
      }

      debugPrint('💾 Saving ${dbSongs.length} songs to playlist...');

      // ── Step 4: Batch insert all songs ───────────────────────────────────
      await repo.addSongsToPlaylistBatch(
        playlistId: playlist.id!,
        songs: dbSongs,
      );

      debugPrint('✅ Successfully saved ${dbSongs.length} songs');

      // ── Step 5: Refresh playlist list ────────────────────────────────────
      ref.invalidate(playlistsProvider);

      // ── Step 6: Show success notification ────────────────────────────────
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '"${data.name}" imported · ${dbSongs.length} songs',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1DB954),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pop(context); // Close any open sheets
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        PlaylistDetailScreen(playlistId: playlist.id!),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Background import error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _saveImportedPlaylist(SpotifyPlaylistData data) async {
    // Show a blocking progress dialog so the user knows we're working
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SavingDialog(),
    );

    try {
      final repo = await ref.read(playlistRepositoryFutureProvider.future);

      // ── Step 1: Download cover image to local storage ────────────────────
      String? localCoverPath;
      if (data.coverImageUrl != null) {
        localCoverPath = await _downloadCoverImage(
          url: data.coverImageUrl!,
          playlistId: data.id,
        );
      }

      // ── Step 2: Create the playlist row ──────────────────────────────────
      final playlist = await repo.createPlaylist(
        name: data.name,
        description: (data.description?.isNotEmpty == true)
            ? data.description
            : null,
        coverImagePath: localCoverPath, // local path or null
        coverType: localCoverPath != null ? 'custom' : 'mosaic',
      );

      debugPrint(
        '🎵 Converting ${data.tracks.length} tracks to DbSong format...',
      );

      // ── Step 3: Convert Spotify tracks → DbSong ──────────────────────────
      final dbSongs = <DbSong>[];
      for (int i = 0; i < data.tracks.length; i++) {
        final track = data.tracks[i];

        // ✅ CRITICAL VALIDATION: Ensure video ID is a valid YouTube ID
        if (track.id.startsWith('spotify:') ||
            track.id.startsWith('spotify-') ||
            track.id.contains('spotify')) {
          debugPrint(
            '⚠️ Skipping track ${i + 1}: ${track.title} - Invalid video ID: ${track.id}',
          );
          continue;
        }

        final dbSong = _spotifyTrackToDbSong(track);
        debugPrint(
          '✅ Song ${i + 1}: ${track.title} -> videoId: ${dbSong.videoId}',
        );
        dbSongs.add(dbSong);
      }

      if (dbSongs.isEmpty) {
        throw Exception(
          'No valid tracks to import. All video IDs were invalid.',
        );
      }

      debugPrint('💾 Saving ${dbSongs.length} songs to playlist...');

      // ── Step 4: Batch insert all songs ───────────────────────────────────
      await repo.addSongsToPlaylistBatch(
        playlistId: playlist.id!,
        songs: dbSongs,
      );

      debugPrint('✅ Successfully saved ${dbSongs.length} songs');

      // ── Step 5: Dismiss dialog & show success ─────────────────────────────
      if (mounted) {
        Navigator.pop(context); // close progress dialog
        Navigator.pop(context); // close import bottom sheet

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
    } catch (e, stackTrace) {
      debugPrint('❌ Import error: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        Navigator.pop(context); // close progress dialog on error too

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

  // ── Converts a Spotify track into the DbSong format your repo expects ───────
  // SpotifyTrackData has no videoId (it's from Spotify, not YouTube).
  // We store the Spotify track ID in the videoId field so the song is
  // persistable. When the user tries to PLAY it your app can search YouTube
  // for the title+artist the same way it does for regular songs.
  // REPLACE the _spotifyTrackToDbSong method:
  DbSong _spotifyTrackToDbSong(SpotifyTrackData track) {
    // track.id is already the YouTube video ID from the backend
    debugPrint('   Converting: ${track.title} (videoId: ${track.id})');

    return DbSong(
      videoId: track.id, // ✅ This is the YouTube video ID from backend
      title: track.title,
      artists: track.artists,
      thumbnail: track.albumArtUrl ?? '', // HQ album art from Spotify
      duration: _durationToString(track.duration),
      addedAt: track.addedAt ?? DateTime.now(),
      playCount: 0,
      isActive: true,
    );
  }

  // Converts Duration to the "m:ss" string your DbSong.duration field stores
  String _durationToString(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // Downloads the HQ cover image and saves it to the app's documents directory.
  // Returns the local file path on success, or null if the download fails.
  Future<String?> _downloadCoverImage({
    required String url,
    required String playlistId,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/playlist_covers/spotify_$playlistId.jpg');

      // Make sure the folder exists
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);

      return file.path;
    } catch (e) {
      // Cover download failure is non-fatal; playlist still gets created
      debugPrint('⚠️ Cover download failed: $e');
      return null;
    }
  }
}

// ── Small progress dialog shown while saving ─────────────────────────────────
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
// ── Shimmer loading skeleton ──────────────────────────────────────────────

class _SpotifyShimmerPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF2A2A2A),
      highlightColor: const Color(0xFF3A3A3A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover + title row
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
          // Stats row
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
          // Track list items
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

  Widget _shimmerChip() {
    return Container(
      height: 28,
      width: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

// ── Playlist preview after successful fetch ───────────────────────────────

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
        // Playlist header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HQ Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: data.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: data.coverImageUrl!,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 90,
                        height: 90,
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white30,
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white30,
                        ),
                      ),
                    )
                  : Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.playlist_play,
                        color: Colors.white30,
                        size: 36,
                      ),
                    ),
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

        // Stats chips
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

        // Track preview list (first 5)
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

        // Save button
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
          // Thumbnail
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
          // Title + artists
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
          // Duration
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

  Widget _thumbPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Error banner ──────────────────────────────────────────────────────────

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

// ── Original PlaylistCard (unchanged) ────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _PlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
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
                child: _buildCover(),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (playlist.isFavorite)
                          const Icon(
                            Icons.favorite,
                            color: Color(0xFFFF4458),
                            size: 16,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
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

  Widget _buildCover() {
    if (playlist.coverImagePath != null) {
      return Image.file(
        File(playlist.coverImagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildGradient(),
      );
    }
    return _buildGradient();
  }

  Widget _buildGradient() {
    final colors = playlist.isFavorite
        ? [const Color(0xFFFF4458), const Color(0xFFFF6B7A)]
        : [const Color(0xFF6B4CE8), const Color(0xFF8B6CE8)];

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
          color: Colors.white.withOpacity(0.8),
        ),
      ),
    );
  }
}
