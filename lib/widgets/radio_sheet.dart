import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/services/audio_service.dart';

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
    _loadRadio();
    _loadQueue();
  }

  Future<void> _loadRadio() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final songs = await _radioService.getRadioForSong(
        videoId: widget.currentVideoId,
        title: widget.currentTitle,
        artist: widget.currentArtist,
        limit: 25,
      );

      if (mounted) {
        setState(() {
          radioSongs = songs;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading radio: $e');
      if (mounted) {
        setState(() {
          errorMessage = 'Failed to load similar songs';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loadQueue() async {
    // TODO: Load actual queue from audio manager
    setState(() {
      queueSongs = [];
    });
  }

  String _calculateTotalDuration(List<QuickPick> songs) {
    int totalSeconds = 0;

    for (final song in songs) {
      final duration = song.duration;
      if (duration == null || duration.isEmpty) continue;

      final parts = duration
          .split(':')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      if (parts.length == 3) {
        // hh:mm:ss
        totalSeconds += parts[0] * 3600 + parts[1] * 60 + parts[2];
      } else if (parts.length == 2) {
        // mm:ss
        totalSeconds += parts[0] * 60 + parts[1];
      }
    }

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
    // TODO: Save queue order to audio manager and governance
    final videoIds = queueSongs.map((s) => s.videoId).toList();
    print('💾 Saving queue order: $videoIds');

    setState(() {
      _isEditMode = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Queue order saved'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.iconActive,
        ),
      );
    }
  }

  Future<void> _playNow(QuickPick song) async {
    try {
      await widget.audioService.playSong(song);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      print('Error playing song: $e');
    }
  }

  Future<void> _addToQueue(QuickPick song) async {
    try {
      await widget.audioService.addToQueue(song);
      setState(() {
        queueSongs.add(song);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${song.title}" to queue'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.iconActive,
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1A1A1A), Colors.black],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
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
                          color: AppColors.iconActive.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.radio,
                          color: AppColors.iconActive,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Now Playing',
                        style: TextStyle(
                          color: Colors.white,
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
                        color: _isEditMode
                            ? AppColors.iconActive
                            : Colors.white,
                      ),
                      onPressed: _isEditMode
                          ? _saveQueueOrder
                          : _toggleEditMode,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.iconActive,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.black,
        unselectedLabelColor: Colors.white.withOpacity(0.7),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.radio, size: 18),
                const SizedBox(width: 8),
                Text('Radio (${radioSongs.length})'),
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
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.iconActive),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRadio,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.iconActive,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (radioSongs.isEmpty) {
      return const Center(
        child: Text(
          'No similar songs found',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    return Column(
      children: [
        // Stats bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.iconActive.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.music_note, color: AppColors.iconActive, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${radioSongs.length} songs',
                    style: const TextStyle(
                      color: Colors.white,
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
                    color: Colors.white.withOpacity(0.6),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _calculateTotalDuration(radioSongs),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
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
                    itemCount: radioSongs.length,
                    padding: const EdgeInsets.only(bottom: 20),
                    itemBuilder: (context, index) {
                      final song = radioSongs[index];
                      final isCurrentSong = currentMedia?.id == song.videoId;

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
  }

  Widget _buildQueueTab() {
    if (queueSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.queue_music,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No songs in queue',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add songs from radio to build your queue',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Stats and edit bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isEditMode
                ? AppColors.iconActive.withOpacity(0.1)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isEditMode
                  ? AppColors.iconActive
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isEditMode ? Icons.edit : Icons.queue_music,
                    color: _isEditMode ? AppColors.iconActive : Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isEditMode
                        ? 'Drag to reorder'
                        : '${queueSongs.length} songs in queue',
                    style: TextStyle(
                      color: _isEditMode ? AppColors.iconActive : Colors.white,
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
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),

        // Queue list
        Expanded(
          child: _isEditMode
              ? ReorderableListView.builder(
                  itemCount: queueSongs.length,
                  onReorder: _reorderQueue,
                  padding: const EdgeInsets.only(bottom: 20),
                  itemBuilder: (context, index) {
                    final song = queueSongs[index];
                    return _buildSongItem(
                      key: ValueKey(song.videoId),
                      song: song,
                      isCurrentSong: false,
                      isPlaying: false,
                      index: index + 1,
                      showDragHandle: true,
                      isEditMode: true,
                    );
                  },
                )
              : StreamBuilder<MediaItem?>(
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
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentSong
            ? AppColors.iconActive.withOpacity(0.15)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentSong
              ? AppColors.iconActive.withOpacity(0.3)
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
              Icon(Icons.drag_handle, color: Colors.white.withOpacity(0.5)),
            const SizedBox(width: 8),
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: AppColors.cardBackground,
                    child: song.thumbnail.isNotEmpty
                        ? Image.network(
                            song.thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.music_note,
                                color: AppColors.iconInactive,
                              );
                            },
                          )
                        : const Icon(
                            Icons.music_note,
                            color: AppColors.iconInactive,
                          ),
                  ),
                ),
                if (isCurrentSong && isPlaying)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: MiniMusicVisualizer(
                        color: Colors.white,
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
                    child: const Icon(
                      Icons.pause,
                      color: Colors.white,
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
            color: isCurrentSong ? AppColors.iconActive : Colors.white,
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
                ? AppColors.iconActive.withOpacity(0.8)
                : Colors.white.withOpacity(0.6),
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
                            ? AppColors.iconActive.withOpacity(0.8)
                            : Colors.white.withOpacity(0.5),
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
                        color: AppColors.iconActive,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.black,
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
                        color: Colors.white.withOpacity(0.7),
                      ),
                      color: const Color(0xFF2A2A2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          onTap: () => _playNow(song),
                          child: const Row(
                            children: [
                              Icon(Icons.play_arrow, color: Colors.white),
                              SizedBox(width: 12),
                              Text(
                                'Play now',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          onTap: () => _addToQueue(song),
                          child: const Row(
                            children: [
                              Icon(Icons.queue_music, color: Colors.white),
                              SizedBox(width: 12),
                              Text(
                                'Add to queue',
                                style: TextStyle(color: Colors.white),
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
