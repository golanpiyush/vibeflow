import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vibeflow/api_base/scrapper.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/managers/download_maintener.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/pages/newPlayerPage.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/services/playback_governance.dart';
import 'package:lottie/lottie.dart';

class SavedSongsScreen extends StatefulWidget {
  const SavedSongsScreen({Key? key}) : super(key: key);

  @override
  State<SavedSongsScreen> createState() => _SavedSongsScreenState();
}

class _SavedSongsScreenState extends State<SavedSongsScreen> {
  final _audioService = AudioServices.instance;
  final _downloadService = DownloadService.instance;
  final _scraper = YouTubeMusicScraper();

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
        // Only prefetch network thumbnails for songs without local thumbnails
        _prefetchMissingThumbnails();
      }
    } catch (e) {
      debugPrint('Error loading saved songs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Prefetch network thumbnails only for songs missing local thumbnails
  Future<void> _prefetchMissingThumbnails() async {
    for (final song in _savedSongs) {
      // Skip if already cached
      if (_thumbnailCache.containsKey(song.videoId)) continue;

      // Skip if has local thumbnail
      final localThumb = _getLocalThumbnailPath(song);
      if (localThumb != null && File(localThumb).existsSync()) continue;

      try {
        final thumbnail = await _scraper.getThumbnailUrl(song.videoId);
        _thumbnailCache[song.videoId] = thumbnail;
      } catch (e) {
        print('⚠️ Failed to fetch thumbnail for ${song.videoId}: $e');
      }
    }

    if (mounted) setState(() {}); // Refresh UI with loaded thumbnails
  }

  /// Helper to get local thumbnail path from DownloadedSong
  String? _getLocalThumbnailPath(DownloadedSong song) {
    // Try to access thumbnailPath property - adjust based on your actual model
    try {
      return (song as dynamic).thumbnailPath as String?;
    } catch (e) {
      return null;
    }
  }

  /// Helper to get local audio file path from DownloadedSong
  String? _getLocalAudioPath(DownloadedSong song) {
    // Try to access filePath or audioPath property - adjust based on your actual model
    try {
      // Try common property names
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

  Future<void> _playSong(DownloadedSong downloadedSong, int index) async {
    try {
      // Determine thumbnail to use
      String thumbnail;
      final localThumbPath = _getLocalThumbnailPath(downloadedSong);

      if (localThumbPath != null && File(localThumbPath).existsSync()) {
        // Use local file path
        thumbnail = localThumbPath;
        print('🖼️ [SavedSongs] Using local thumbnail: $thumbnail');
      } else {
        // Fallback to network thumbnail
        thumbnail = _thumbnailCache[downloadedSong.videoId] ?? '';
        if (thumbnail.isEmpty) {
          thumbnail = await _scraper.getThumbnailUrl(downloadedSong.videoId);
          _thumbnailCache[downloadedSong.videoId] = thumbnail;
        }
        print('🌐 [SavedSongs] Using network thumbnail: $thumbnail');
      }

      // Convert DownloadedSong to QuickPick
      final song = QuickPick(
        videoId: downloadedSong.videoId,
        title: downloadedSong.title,
        artists: downloadedSong.artist,
        thumbnail: thumbnail,
        duration: null,
      );

      // Check if we have local audio file
      final localAudioPath = _getLocalAudioPath(downloadedSong);
      if (localAudioPath != null && File(localAudioPath).existsSync()) {
        print('🎵 [SavedSongs] Local audio available: $localAudioPath');
        // Store the local path in Song model's audioUrl field
        final songModel = song.toSong();
        songModel.audioUrl = localAudioPath;
      } else {
        print(
          '⚠️ [SavedSongs] Local audio not found, will stream from network',
        );
      }

      // Create queue from saved songs starting at selected index
      final queue = <QuickPick>[];

      // Add all songs from selected index to end
      for (int i = index; i < _savedSongs.length; i++) {
        final queueSong = _savedSongs[i];

        // Determine thumbnail for queue item
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

        // Set local audio path if available
        final queueLocalAudio = _getLocalAudioPath(queueSong);
        if (queueLocalAudio != null && File(queueLocalAudio).existsSync()) {
          final queueSongModel = queueItem.toSong();
          queueSongModel.audioUrl = queueLocalAudio;
        }

        queue.add(queueItem);
      }

      // Get audio handler
      final handler = getAudioHandler();
      if (handler == null) {
        throw Exception('Audio handler not available');
      }

      print('🎵 [SavedSongs] Playing queue of ${queue.length} songs');
      print('📋 [SavedSongs] Starting from: ${song.title}');

      // Count how many songs have local audio
      int localCount = 0;
      for (final q in queue) {
        final qSong = q.toSong();
        if (qSong.audioUrl != null && qSong.audioUrl!.isNotEmpty) {
          localCount++;
        }
      }
      print('💾 [SavedSongs] Local files: $localCount/${queue.length}');

      // 🔥 CRITICAL: Play the queue as a playlist
      // This will clear radio and set playlist mode
      await handler.playPlaylistQueue(queue, startIndex: 0);

      // After queue setup, open player
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
          ),
        );
      }
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
      Navigator.pop(context);

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

                              // Determine which thumbnail to use
                              String? displayThumbnail;
                              bool isLocalThumbnail = false;

                              final localThumbPath = _getLocalThumbnailPath(
                                song,
                              );
                              if (localThumbPath != null &&
                                  File(localThumbPath).existsSync()) {
                                displayThumbnail = localThumbPath;
                                isLocalThumbnail = true;
                              } else {
                                displayThumbnail =
                                    _thumbnailCache[song.videoId];
                              }

                              // Check if local audio exists
                              final localAudioPath = _getLocalAudioPath(song);
                              final hasLocalAudio =
                                  localAudioPath != null &&
                                  File(localAudioPath).existsSync();

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
                                      child: displayThumbnail != null
                                          ? (isLocalThumbnail
                                                ? Image.file(
                                                    File(displayThumbnail),
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return const Icon(
                                                            Icons.music_note,
                                                            color: AppColors
                                                                .iconInactive,
                                                          );
                                                        },
                                                  )
                                                : Image.network(
                                                    displayThumbnail,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return const Icon(
                                                            Icons.music_note,
                                                            color: AppColors
                                                                .iconInactive,
                                                          );
                                                        },
                                                  ))
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
                                      Row(
                                        children: [
                                          // Show offline indicator if audio file exists
                                          if (hasLocalAudio) ...[
                                            const Icon(
                                              Icons.offline_pin,
                                              size: 12,
                                              color: AppColors.iconActive,
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            song.formattedFileSize,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.4,
                                              ),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
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
                                            _buildSongOptions(song, index),
                                      );
                                    },
                                  ),
                                  onTap: () => _playSong(song, index),
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

  Widget _buildSongOptions(DownloadedSong song, int index) {
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
              _playSong(song, index);
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

  @override
  void dispose() {
    _scraper.dispose();
    super.dispose();
  }
}
