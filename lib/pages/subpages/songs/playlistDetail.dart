// lib/pages/subpages/songs/playlistDetail.dart - FIXED VERSION
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/playlist_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/providers/playlist_providers.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';

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
    final playlistAsync = ref.watch(
      playlistWithSongsProvider(widget.playlistId),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: playlistAsync.when(
        data: (playlistWithSongs) {
          if (playlistWithSongs == null) {
            return const Center(
              child: Text(
                'Playlist not found',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          return _buildContent(playlistWithSongs);
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 60,
                  color: Colors.red.withOpacity(0.7),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading playlist',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString().length > 100
                      ? '${error.toString().substring(0, 100)}...'
                      : error.toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(PlaylistWithSongs playlistWithSongs) {
    final playlist = playlistWithSongs.playlist;
    final songs = playlistWithSongs.songs;

    return CustomScrollView(
      slivers: [
        // Header with cover
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () => _showPlaylistOptions(playlist),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: _buildPlaylistHeader(playlist, songs),
          ),
        ),

        // Controls
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: songs.isEmpty ? null : () => _playAll(songs),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4458),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    _isReordering ? Icons.check : Icons.swap_vert,
                    color: Colors.white,
                  ),
                  onPressed: songs.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _isReordering = !_isReordering;
                          });
                        },
                ),
              ],
            ),
          ),
        ),

        // Song list
        if (songs.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note_outlined,
                    size: 80,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No songs yet',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add songs to start listening',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          )
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
                child: _buildSongTile(song, index, playlist.id!, true),
              );
            },
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final song = songs[index];
              return _buildSongTile(song, index, playlist.id!, false);
            }, childCount: songs.length),
          ),
      ],
    );
  }

  Widget _buildPlaylistHeader(Playlist playlist, List<DbSong> songs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF6B4CE8).withOpacity(0.8), Colors.black],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          // ✅ FIX
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min, // ✅ IMPORTANT
              children: [
                // Cover image
                GestureDetector(
                  onTap: () => _changeCover(playlist),
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: playlist.coverImagePath != null
                          ? Image.file(
                              File(playlist.coverImagePath!),
                              fit: BoxFit.cover,
                            )
                          : songs.isNotEmpty && songs.first.thumbnail.isNotEmpty
                          ? Image.network(
                              songs.first.thumbnail,
                              fit: BoxFit.cover,
                            )
                          : _buildCoverPlaceholder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  playlist.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2, // ✅ EXTRA SAFETY
                  overflow: TextOverflow.ellipsis,
                ),

                if (playlist.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    playlist.description!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 12),

                Text(
                  '${playlist.songCount} songs • ${_formatDuration(playlist.totalDuration)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF6B4CE8), const Color(0xFF8B6CE8)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.playlist_play, size: 80, color: Colors.white),
      ),
    );
  }

  Widget _buildSongTile(
    DbSong song,
    int index,
    int playlistId,
    bool showDragHandle,
  ) {
    return ListTile(
      key: Key(song.videoId),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: showDragHandle
          ? const Icon(Icons.drag_handle, color: Colors.white54)
          : Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                image: song.thumbnail.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(song.thumbnail),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: Colors.white12,
              ),
              child: song.thumbnail.isEmpty
                  ? const Icon(Icons.music_note, color: Colors.white54)
                  : null,
            ),
      title: Text(
        song.title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.artistsString,
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: !showDragHandle
          ? IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onPressed: () => _showSongOptions(song, playlistId),
            )
          : null,
      onTap: showDragHandle ? null : () => _playSong(song, index),
    );
  }

  void _showPlaylistOptions(Playlist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white),
              title: const Text(
                'Edit Details',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _editPlaylist(playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.white),
              title: const Text(
                'Change Cover',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _changeCover(playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Playlist',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deletePlaylist(playlist);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSongOptions(DbSong song, int playlistId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.remove_circle_outline,
                color: Colors.red,
              ),
              title: const Text(
                'Remove from Playlist',
                style: TextStyle(color: Colors.white),
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

  Future<void> _editPlaylist(Playlist playlist) async {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Edit Playlist',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, {
                'name': nameController.text,
                'description': descController.text,
              });
            },
            child: const Text(
              'Save',
              style: TextStyle(color: Color(0xFFFF4458)),
            ),
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

  Future<void> _changeCover(Playlist playlist) async {
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

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Delete Playlist?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will permanently delete "${playlist.name}" and remove all songs from it.',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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

    if (song.id != null) {
      await repo.removeSongFromPlaylist(
        playlistId: playlistId,
        songId: song.id!,
      );

      ref.invalidate(playlistWithSongsProvider(playlistId));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removed from playlist'),
          backgroundColor: Colors.green,
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

    // Convert DbSong list to QuickPick list
    final quickPicks = songs.map((dbSong) {
      return QuickPick(
        videoId: dbSong.videoId,
        title: dbSong.title,
        artists: dbSong.artistsString,
        thumbnail: dbSong.thumbnail,
        duration: dbSong.duration, // Use duration field directly
      );
    }).toList();

    // Play the entire playlist from the beginning
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

      // Convert DbSong list to QuickPick list
      final quickPicks = songs.map((dbSong) {
        return QuickPick(
          videoId: dbSong.videoId,
          title: dbSong.title,
          artists: dbSong.artistsString,
          thumbnail: dbSong.thumbnail,
          duration: dbSong.duration, // Use duration field directly
        );
      }).toList();

      // Play the playlist starting from the selected index
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
