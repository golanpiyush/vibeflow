// lib/widgets/playlist_bottomSheet.dart - FIXED VERSION
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/playlist_model.dart';
import 'package:vibeflow/providers/playlist_providers.dart';

/// Bottom sheet shown when user taps "Add to Playlist"
class AddToPlaylistSheet extends ConsumerStatefulWidget {
  final DbSong song;

  const AddToPlaylistSheet({Key? key, required this.song}) : super(key: key);

  @override
  ConsumerState<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<AddToPlaylistSheet> {
  bool _isCreatingPlaylist = false;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAndAutoAdd();
  }

  /// Auto-add logic: if no playlists exist, show create form immediately
  Future<void> _checkAndAutoAdd() async {
    final playlistsAsync = ref.read(playlistsProvider);

    await playlistsAsync.when(
      data: (playlists) async {
        if (playlists.isEmpty) {
          setState(() {
            _isCreatingPlaylist = true;
          });
        }
      },
      loading: () {},
      error: (e, stack) {},
    );
  }

  Future<void> _createPlaylistAndAdd(String name) async {
    if (name.trim().isEmpty) return;

    try {
      // Use the async provider
      final repo = await ref.read(playlistRepositoryFutureProvider.future);

      // Create playlist
      final newPlaylist = await repo.createPlaylist(
        name: name.trim(),
        description: 'Created ${DateTime.now().toString().split(' ')[0]}',
      );

      // Add song to new playlist
      await repo.addSongToPlaylist(
        playlistId: newPlaylist.id!,
        song: widget.song,
      );

      // Refresh playlists
      ref.invalidate(playlistsProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added to "$name"'),
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

  Future<void> _addToPlaylist(Playlist playlist) async {
    try {
      // Use the async provider
      final repo = await ref.read(playlistRepositoryFutureProvider.future);

      final success = await repo.addSongToPlaylist(
        playlistId: playlist.id!,
        song: widget.song,
      );

      if (mounted) {
        Navigator.pop(context);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added to "${playlist.name}"'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Already in "${playlist.name}"'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      // Refresh playlists to update song counts
      ref.invalidate(playlistsProvider);
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

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.playlist_add, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Add to Playlist',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.song.title,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFF2A2A2A), height: 1),

            // Content
            Flexible(
              child: playlistsAsync.when(
                data: (playlists) {
                  if (_isCreatingPlaylist) {
                    return _buildCreatePlaylistForm();
                  }

                  if (playlists.isEmpty) {
                    return _buildEmptyState();
                  }

                  return _buildPlaylistList(playlists);
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
                error: (error, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red.withOpacity(0.7),
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Error loading playlists',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString().length > 50
                              ? '${error.toString().substring(0, 50)}...'
                              : error.toString(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Create Playlist Button (only show if playlists exist)
            if (!_isCreatingPlaylist)
              playlistsAsync.when(
                data: (playlists) {
                  if (playlists.isEmpty) return const SizedBox.shrink();
                  return _buildCreateButton();
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.playlist_play_rounded,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No playlists yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first playlist to get started',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistList(List<Playlist> playlists) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _PlaylistTile(
          playlist: playlist,
          onTap: () => _addToPlaylist(playlist),
        );
      },
    );
  }

  Widget _buildCreatePlaylistForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create New Playlist',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFFF4458),
                  width: 2,
                ),
              ),
            ),
            onSubmitted: (value) => _createPlaylistAndAdd(value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isCreatingPlaylist = false;
                      _nameController.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _createPlaylistAndAdd(_nameController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4458),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Create & Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreateButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: const Color(0xFF2A2A2A))),
      ),
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _isCreatingPlaylist = true;
          });
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Create New Playlist'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.1),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

/// Individual playlist tile
class _PlaylistTile extends ConsumerWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _PlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: _buildPlaylistCover(),
      title: Text(
        playlist.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.songCount} songs',
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
      ),
      trailing: Icon(
        Icons.add_circle_outline,
        color: Colors.white.withOpacity(0.7),
        size: 22,
      ),
    );
  }

  Widget _buildPlaylistCover() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _getGradientColors(),
        ),
      ),
      child: playlist.coverImagePath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                playlist.coverImagePath!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildIcon(),
              ),
            )
          : _buildIcon(),
    );
  }

  Widget _buildIcon() {
    return Icon(
      playlist.isFavorite ? Icons.favorite : Icons.playlist_play,
      color: Colors.white,
      size: 28,
    );
  }

  List<Color> _getGradientColors() {
    if (playlist.isFavorite) {
      return [const Color(0xFFFF4458), const Color(0xFFFF6B7A)];
    }
    return [const Color(0xFF6B4CE8), const Color(0xFF8B6CE8)];
  }
}
