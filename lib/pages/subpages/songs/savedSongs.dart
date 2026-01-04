import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/managers/download_maintener.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/player_page.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:lottie/lottie.dart';

class SavedSongsScreen extends StatefulWidget {
  const SavedSongsScreen({Key? key}) : super(key: key);

  @override
  State<SavedSongsScreen> createState() => _SavedSongsScreenState();
}

class _SavedSongsScreenState extends State<SavedSongsScreen> {
  final _audioService = AudioServices.instance;
  final _downloadService = DownloadService.instance;

  List<DownloadedSong> _savedSongs = [];
  bool _isLoading = true;
  DownloadStats? _stats;
  String _sortBy = 'date'; // 'date', 'title', 'artist', 'size'

  @override
  void initState() {
    super.initState();
    _loadSavedSongs();
    _loadStats();
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
      }
    } catch (e) {
      debugPrint('Error loading saved songs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  Future<void> _deleteSong(DownloadedSong song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Remove Song?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to remove "${song.title}" from saved songs?',
          style: const TextStyle(color: Colors.white70),
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
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
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
            backgroundColor: AppColors.iconActive,
          ),
        );

        _loadSavedSongs();
        _loadStats();
      }
    }
  }

  Future<void> _playSong(DownloadedSong downloadedSong) async {
    // Convert DownloadedSong to QuickPick
    final song = QuickPick(
      videoId: downloadedSong.videoId,
      title: downloadedSong.title,
      artists: downloadedSong.artist,
      thumbnail: downloadedSong.thumbnailPath ?? '',
      duration: null,
    );

    await _audioService.playSong(song);

    if (mounted) {
      Navigator.of(context).pushFade(PlayerScreen(song: song));
    }
  }

  Future<void> _runMaintenance() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.iconActive),
      ),
    );

    final report = await DownloadMaintenanceService.runMaintenance();

    if (mounted) {
      Navigator.pop(context); // Close loading dialog

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Maintenance Complete',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Orphaned files removed: ${report.orphanedFilesRemoved}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Corrupted files removed: ${report.corruptedFilesRemoved}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Empty metadata removed: ${report.emptyMetadataRemoved}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                'Storage used: ${(report.totalStorageUsed / (1024 * 1024)).toStringAsFixed(2)} MB',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
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
              child: const Text(
                'OK',
                style: TextStyle(color: AppColors.iconActive),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Saved Songs',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white),
            color: const Color(0xFF2A2A2A),
            onSelected: (value) {
              setState(() => _sortBy = value);
              _applySorting();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color: _sortBy == 'date'
                          ? AppColors.iconActive
                          : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Recent',
                      style: TextStyle(
                        color: _sortBy == 'date'
                            ? AppColors.iconActive
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'title',
                child: Row(
                  children: [
                    Icon(
                      Icons.sort_by_alpha,
                      color: _sortBy == 'title'
                          ? AppColors.iconActive
                          : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Title',
                      style: TextStyle(
                        color: _sortBy == 'title'
                            ? AppColors.iconActive
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'artist',
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: _sortBy == 'artist'
                          ? AppColors.iconActive
                          : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Artist',
                      style: TextStyle(
                        color: _sortBy == 'artist'
                            ? AppColors.iconActive
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'size',
                child: Row(
                  children: [
                    Icon(
                      Icons.storage,
                      color: _sortBy == 'size'
                          ? AppColors.iconActive
                          : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Size',
                      style: TextStyle(
                        color: _sortBy == 'size'
                            ? AppColors.iconActive
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF2A2A2A),
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: _runMaintenance,
                child: const Row(
                  children: [
                    Icon(Icons.cleaning_services, color: Colors.white),
                    SizedBox(width: 12),
                    Text(
                      'Run Maintenance',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.iconActive),
            )
          : Column(
              children: [
                // Stats Card
                if (_stats != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          icon: Icons.music_note,
                          label: 'Songs',
                          value: '${_stats!.totalDownloads}',
                        ),
                        _buildStatItem(
                          icon: Icons.storage,
                          label: 'Storage',
                          value: _stats!.formattedStorage,
                        ),
                      ],
                    ),
                  ),

                // Songs List
                Expanded(
                  child: _savedSongs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Lottie.asset(
                                'assets/animations/not_found.json',
                                width: 380,
                                height: 380,
                                repeat: true,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No saved songs yet',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap the heart icon to save songs',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            await _loadSavedSongs();
                            await _loadStats();
                          },
                          color: AppColors.iconActive,
                          child: ListView.builder(
                            itemCount: _savedSongs.length,
                            padding: const EdgeInsets.only(bottom: 20),
                            itemBuilder: (context, index) {
                              final song = _savedSongs[index];

                              return Dismissible(
                                key: Key(song.videoId),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: AppColors.error,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                  ),
                                ),
                                onDismissed: (direction) => _deleteSong(song),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      color: AppColors.cardBackground,
                                      child: song.thumbnailPath != null
                                          ? Image.file(
                                              File(song.thumbnailPath!),
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return const Icon(
                                                      Icons.music_note,
                                                      color: AppColors
                                                          .iconInactive,
                                                    );
                                                  },
                                            )
                                          : const Icon(
                                              Icons.music_note,
                                              color: AppColors.iconInactive,
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    song.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.artist,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.formattedFileSize,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.4),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        backgroundColor: const Color(
                                          0xFF1A1A1A,
                                        ),
                                        builder: (context) =>
                                            _buildSongOptions(song),
                                      );
                                    },
                                  ),
                                  onTap: () => _playSong(song),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppColors.iconActive, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSongOptions(DownloadedSong song) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow, color: Colors.white),
            title: const Text('Play', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _playSong(song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.error),
            title: const Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () {
              Navigator.pop(context);
              _deleteSong(song);
            },
          ),
        ],
      ),
    );
  }
}
