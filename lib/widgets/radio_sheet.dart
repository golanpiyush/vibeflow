import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';

class EnhancedRadioSheet extends StatefulWidget {
  final String currentVideoId;
  final String currentTitle;
  final String currentArtist;
  final AudioServices audioService;

  const EnhancedRadioSheet({
    Key? key,
    required this.currentVideoId,
    required this.currentTitle,
    required this.currentArtist,
    required this.audioService,
  }) : super(key: key);

  @override
  State<EnhancedRadioSheet> createState() => _EnhancedRadioSheetState();
}

class _EnhancedRadioSheetState extends State<EnhancedRadioSheet>
    with SingleTickerProviderStateMixin {
  final RadioService _radioService = RadioService();
  List<QuickPick> radioSongs = [];
  List<QuickPick> queueSongs = [];
  bool isLoading = true;
  String? errorMessage;

  late TabController _tabController;
  bool _isEditMode = false;

  // For drag and drop
  int? _draggingIndex;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // ❌ DELETE: _loadRadio();
    _loadQueue();

    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadQueue() async {
    final handler = getAudioHandler();
    if (handler == null) {
      setState(() {
        queueSongs = [];
      });
      return;
    }

    // ✅ Get queue from handler
    final queue = handler.queue.value;

    setState(() {
      queueSongs = queue.map((mediaItem) {
        return QuickPick(
          videoId: mediaItem.id,
          title: mediaItem.title,
          artists: mediaItem.artist ?? 'Unknown Artist',
          thumbnail: mediaItem.artUri?.toString() ?? '',
          duration: mediaItem.duration != null
              ? _formatDuration(mediaItem.duration!)
              : null,
        );
      }).toList();
    });

    print('✅ [RadioSheet] Loaded ${queueSongs.length} songs from queue');
  }

  Future<void> _forceRefreshRadio() async {
    print('🔄 [RadioSheet] Force refreshing radio...');

    final handler = getAudioHandler();
    if (handler == null) return;

    final currentMedia = handler.mediaItem.value;
    if (currentMedia == null) return;

    final currentSong = QuickPick(
      videoId: currentMedia.id,
      title: currentMedia.title,
      artists: currentMedia.artist ?? 'Unknown Artist',
      thumbnail: currentMedia.artUri?.toString() ?? '',
      duration: currentMedia.duration?.inSeconds.toString(),
    );

    // Manually trigger radio load
    await handler.playSong(currentSong, sourceType: RadioSourceType.quickPick);

    // Wait for load
    await Future.delayed(const Duration(milliseconds: 500));
  }

  String _calculateTotalDuration(List<QuickPick> songs) {
    int totalSeconds = 0;

    for (final song in songs) {
      final duration = song.duration;
      if (duration == null || duration.isEmpty) continue;

      // ✅ FIX: Handle different duration formats
      try {
        final parts = duration
            .split(':')
            .map((e) => int.tryParse(e.trim()) ?? 0)
            .toList();

        if (parts.length == 3) {
          // hh:mm:ss format
          totalSeconds += parts[0] * 3600 + parts[1] * 60 + parts[2];
        } else if (parts.length == 2) {
          // mm:ss format
          totalSeconds += parts[0] * 60 + parts[1];
        } else if (parts.length == 1) {
          // Just seconds
          totalSeconds += parts[0];
        }

        print(
          '   Duration parsed: $duration -> ${parts} -> $totalSeconds total seconds',
        );
      } catch (e) {
        print('⚠️ Failed to parse duration: $duration - $e');
      }
    }

    print(
      '📊 Total duration: $totalSeconds seconds from ${songs.length} songs',
    );

    if (totalSeconds == 0) return '0 min';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;

    if (hours > 0) {
      return '$hours hr ${minutes} min';
    } else {
      return '$minutes min';
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
  }

  void _reorderQueue(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = queueSongs.removeAt(oldIndex);
      queueSongs.insert(newIndex, item);
    });
  }

  Future<void> _saveQueueOrder() async {
    final videoIds = queueSongs.map((s) => s.videoId).toList();
    print('💾 Saving queue order: $videoIds');

    setState(() {
      _isEditMode = false;
    });

    if (mounted) {
      final primaryColor = Theme.of(context).colorScheme.primary;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Queue order saved'),
          duration: const Duration(seconds: 2),
          backgroundColor: primaryColor,
        ),
      );
    }
  }

  Future<void> _playNow(QuickPick song) async {
    try {
      // Use playSongFromRadio to maintain radio queue
      await widget.audioService.playSongFromRadio(song);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      print('Error playing song: $e');
    }
  }

  Future<void> _addToQueue(QuickPick song) async {
    try {
      await widget.audioService.addToQueue(song);
      await _loadQueue();

      if (mounted) {
        final primaryColor = Theme.of(context).colorScheme.primary;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${song.title}" to queue'),
            duration: const Duration(seconds: 2),
            backgroundColor: primaryColor,
          ),
        );
      }
    } catch (e) {
      print('Error adding to queue: $e');
    }
  }

  Future<void> _removeFromQueue(QuickPick song) async {
    setState(() {
      queueSongs.removeWhere((s) => s.videoId == song.videoId);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${song.title}" from queue'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _radioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get theme colors
    final themeData = Theme.of(context);
    final bgColor = themeData.scaffoldBackgroundColor;
    final surfaceColor = themeData.colorScheme.surface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surfaceColor, bgColor],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildRadioTab(), _buildQueueTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;
    final surfaceVariant = themeData.colorScheme.surfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: onSurface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title and close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.radio, color: primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Now Playing',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  if (_tabController.index == 1 && queueSongs.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _isEditMode ? Icons.check : Icons.edit,
                        color: _isEditMode ? primaryColor : onSurface,
                      ),
                      onPressed: _isEditMode
                          ? _saveQueueOrder
                          : _toggleEditMode,
                    ),
                  IconButton(
                    icon: Icon(Icons.close, color: onSurface),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final handler = getAudioHandler();
    final customState =
        handler?.customState.value as Map<String, dynamic>? ?? {};
    final radioQueueData = customState['radio_queue'] as List<dynamic>? ?? [];

    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onPrimary = themeData.colorScheme.onPrimary;
    final onSurface = themeData.colorScheme.onSurface;
    final surfaceVariant = themeData.colorScheme.surfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: onPrimary,
        unselectedLabelColor: onSurface.withOpacity(0.7),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.radio, size: 18),
                const SizedBox(width: 8),
                Text('Radio (${radioQueueData.length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.queue_music, size: 18),
                const SizedBox(width: 8),
                Text('Queue (${queueSongs.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioTab() {
    final handler = getAudioHandler();

    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;
    final surfaceVariant = themeData.colorScheme.surfaceVariant;

    if (handler == null) {
      return Center(
        child: Text(
          'Audio handler not available',
          style: TextStyle(color: onSurface.withOpacity(0.5), fontSize: 16),
        ),
      );
    }

    return StreamBuilder<dynamic>(
      stream: handler.customState.stream,
      builder: (context, snapshot) {
        final customState = snapshot.data as Map<String, dynamic>? ?? {};
        final radioQueueData =
            customState['radio_queue'] as List<dynamic>? ?? [];

        // Empty state
        if (radioQueueData.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                ),
                const SizedBox(height: 24),
                Icon(Icons.radio, size: 48, color: onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(
                  'Loading radio queue...',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.7),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Finding similar songs for you',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.4),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _forceRefreshRadio,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tap to load radio'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: themeData.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          );
        }

        // Convert radio queue data to QuickPick objects
        final songs = radioQueueData.map((songData) {
          final data = songData as Map<String, dynamic>;
          final durationMs = data['duration'] as int?;

          return QuickPick(
            videoId: data['id'] as String,
            title: data['title'] as String,
            artists: data['artist'] as String? ?? 'Unknown Artist',
            thumbnail: data['artUri'] as String? ?? '',
            duration: durationMs != null
                ? _formatDuration(Duration(milliseconds: durationMs))
                : null,
          );
        }).toList();

        return Column(
          children: [
            // Stats bar with theme colors
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.music_note, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${songs.length} songs',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: onSurface.withOpacity(0.6),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _calculateTotalDuration(songs),
                        style: TextStyle(
                          color: onSurface.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Song list
            Expanded(
              child: StreamBuilder<MediaItem?>(
                stream: widget.audioService.mediaItemStream,
                builder: (context, mediaSnapshot) {
                  final currentMedia = mediaSnapshot.data;

                  return StreamBuilder<PlaybackState>(
                    stream: widget.audioService.playbackStateStream,
                    builder: (context, playbackSnapshot) {
                      final playbackState = playbackSnapshot.data;
                      final isPlaying = playbackState?.playing ?? false;

                      return ListView.builder(
                        itemCount: songs.length,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          final isCurrentSong =
                              currentMedia?.id == song.videoId;

                          return _buildSongItem(
                            song: song,
                            isCurrentSong: isCurrentSong,
                            isPlaying: isPlaying,
                            index: index + 1,
                            showDragHandle: false,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // Add helper method for duration formatting
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildQueueTab() {
    final handler = getAudioHandler();

    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;
    final surfaceVariant = themeData.colorScheme.surfaceVariant;

    if (handler == null) {
      return Center(
        child: Text(
          'Audio handler not available',
          style: TextStyle(color: onSurface.withOpacity(0.5), fontSize: 16),
        ),
      );
    }

    return StreamBuilder<List<MediaItem>>(
      stream: handler.queue.stream,
      builder: (context, snapshot) {
        final queue = snapshot.data ?? [];

        final queueSongs = queue.map((mediaItem) {
          return QuickPick(
            videoId: mediaItem.id,
            title: mediaItem.title,
            artists: mediaItem.artist ?? 'Unknown Artist',
            thumbnail: mediaItem.artUri?.toString() ?? '',
            duration: mediaItem.duration != null
                ? _formatDuration(mediaItem.duration!)
                : null,
          );
        }).toList();

        // Empty state
        if (queueSongs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.queue_music,
                  size: 64,
                  color: onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No songs in queue',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.7),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add songs from radio to build your queue',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.4),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Stats bar with theme colors
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isEditMode
                    ? primaryColor.withOpacity(0.1)
                    : surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isEditMode
                      ? primaryColor
                      : onSurface.withOpacity(0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isEditMode ? Icons.edit : Icons.queue_music,
                        color: _isEditMode ? primaryColor : onSurface,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isEditMode
                            ? 'Drag to reorder'
                            : '${queueSongs.length} songs in queue',
                        style: TextStyle(
                          color: _isEditMode ? primaryColor : onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (!_isEditMode)
                    Text(
                      _calculateTotalDuration(queueSongs),
                      style: TextStyle(
                        color: onSurface.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),

            // Queue list
            Expanded(
              child: StreamBuilder<MediaItem?>(
                stream: widget.audioService.mediaItemStream,
                builder: (context, mediaSnapshot) {
                  final currentMedia = mediaSnapshot.data;

                  return StreamBuilder<PlaybackState>(
                    stream: widget.audioService.playbackStateStream,
                    builder: (context, playbackSnapshot) {
                      final playbackState = playbackSnapshot.data;
                      final isPlaying = playbackState?.playing ?? false;

                      return ListView.builder(
                        itemCount: queueSongs.length,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          final song = queueSongs[index];
                          final isCurrentSong =
                              currentMedia?.id == song.videoId;

                          return _buildSongItem(
                            song: song,
                            isCurrentSong: isCurrentSong,
                            isPlaying: isPlaying,
                            index: index + 1,
                            showDragHandle: false,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSongItem({
    Key? key,
    required QuickPick song,
    required bool isCurrentSong,
    required bool isPlaying,
    required int index,
    required bool showDragHandle,
    bool isEditMode = false,
  }) {
    // Get theme colors
    final themeData = Theme.of(context);
    final primaryColor = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;
    final surfaceVariant = themeData.colorScheme.surfaceVariant;
    final cardBg = themeData.colorScheme.surface;

    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentSong
            ? primaryColor.withOpacity(0.15)
            : surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentSong
              ? primaryColor.withOpacity(0.3)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: showDragHandle ? 8 : 16,
          vertical: 8,
        ),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDragHandle)
              Icon(Icons.drag_handle, color: onSurface.withOpacity(0.5)),
            const SizedBox(width: 8),
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: cardBg,
                    child: song.thumbnail.isNotEmpty
                        ? Image.network(
                            song.thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.music_note,
                                color: onSurface.withOpacity(0.3),
                              );
                            },
                          )
                        : Icon(
                            Icons.music_note,
                            color: onSurface.withOpacity(0.3),
                          ),
                  ),
                ),
                // ✅ UPDATED: Custom visualizer with theme color
                if (isCurrentSong && isPlaying)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: _MiniMusicVisualizer(
                        // ✅ NEW - uses custom implementation
                        color:
                            primaryColor, // ✅ Uses theme color instead of white
                        width: 4,
                        height: 15,
                      ),
                    ),
                  ),
                if (isCurrentSong && !isPlaying)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.pause,
                      color: primaryColor, // ✅ Theme-aware color
                      size: 28,
                    ),
                  ),
                if (!isCurrentSong && !showDragHandle)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$index',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        title: Text(
          song.title,
          style: TextStyle(
            color: isCurrentSong ? primaryColor : onSurface,
            fontSize: 15,
            fontWeight: isCurrentSong ? FontWeight.w600 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          song.artists,
          style: TextStyle(
            color: isCurrentSong
                ? primaryColor.withOpacity(0.8)
                : onSurface.withOpacity(0.6),
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isEditMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => _removeFromQueue(song),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (song.duration != null && song.duration!.isNotEmpty)
                    Text(
                      song.duration!,
                      style: TextStyle(
                        color: isCurrentSong
                            ? primaryColor.withOpacity(0.8)
                            : onSurface.withOpacity(0.5),
                        fontSize: 12,
                        fontWeight: isCurrentSong
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (isCurrentSong)
                    Container(
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: themeData.colorScheme.onPrimary,
                          size: 24,
                        ),
                        onPressed: () {
                          widget.audioService.playPause();
                        },
                      ),
                    )
                  else
                    PopupMenuButton(
                      icon: Icon(
                        Icons.more_vert,
                        color: onSurface.withOpacity(0.7),
                      ),
                      color: cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          onTap: () => _playNow(song),
                          child: Row(
                            children: [
                              Icon(Icons.play_arrow, color: onSurface),
                              const SizedBox(width: 12),
                              Text(
                                'Play now',
                                style: TextStyle(color: onSurface),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          onTap: () => _addToQueue(song),
                          child: Row(
                            children: [
                              Icon(Icons.queue_music, color: onSurface),
                              const SizedBox(width: 12),
                              Text(
                                'Add to queue',
                                style: TextStyle(color: onSurface),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
        onTap: isEditMode
            ? null
            : isCurrentSong
            ? () {
                widget.audioService.playPause();
              }
            : () {
                _playNow(song);
              },
      ),
    );
  }
}

class _MiniMusicVisualizer extends StatefulWidget {
  final Color color;
  final double width;
  final double height;

  const _MiniMusicVisualizer({
    required this.color,
    this.width = 4,
    this.height = 15,
  });

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
      width: widget.width,
      height: widget.height * heightFactor,
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
