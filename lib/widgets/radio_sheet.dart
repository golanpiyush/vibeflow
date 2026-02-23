import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:vibeflow/api_base/yt_radio.dart';
import 'package:vibeflow/api_base/ytradionew.dart';
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
  // final RadioService _radioService = RadioService();
  final NewYTRadio _newradioService = NewYTRadio();
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
    final handler = getAudioHandler();
    final cs = handler?.customState.value as Map<String, dynamic>? ?? {};
    final isPlaylistMode = cs['is_playlist_mode'] == true;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: isPlaylistMode ? 1 : 0,
    );
    // ✅ REMOVED: _loadQueue() — queue tab now reads from customState stream directly
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
    // This is now handled directly in the ReorderableListView via handler
  }

  Future<void> _saveQueueOrder() async {
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

  void _applyReorder(List<QuickPick> currentSongs, int oldIndex, int newIndex) {
    final handler = getAudioHandler();
    if (handler == null) return;

    if (newIndex > oldIndex) newIndex -= 1;

    // Reorder in the handler's radio queue via customState
    final customState =
        handler.customState.value as Map<String, dynamic>? ?? {};
    final radioQueueData = List<dynamic>.from(
      customState['radio_queue'] as List<dynamic>? ?? [],
    );

    if (oldIndex >= radioQueueData.length || newIndex >= radioQueueData.length)
      return;

    final item = radioQueueData.removeAt(oldIndex);
    radioQueueData.insert(newIndex, item);

    // Push back to handler — use the public updateCustomState equivalent
    // Since _updateCustomState is private, we update via a workaround:
    // rebuild the state map and add it
    final updated = Map<String, dynamic>.from(customState);
    updated['radio_queue'] = radioQueueData;
    updated['radio_queue_count'] = radioQueueData.length;
    handler.customState.add(updated);

    print('✅ [Queue] Reordered: $oldIndex → $newIndex');
  }

  Future<void> _playNow(QuickPick song) async {
    try {
      final handler = getAudioHandler();
      if (handler == null) return;

      Navigator.pop(context);

      // Find song in the audio_service queue by videoId
      final queue = handler.queue.value;
      final queueIndex = queue.indexWhere((item) => item.id == song.videoId);

      if (queueIndex != -1) {
        // Song exists in queue — jump directly, no re-fetch
        await handler.skipToQueueItem(queueIndex);
      } else {
        // Not in queue — find in radio queue and play via radio path
        await handler.playSongFromRadio(song);
      }
    } catch (e) {
      print('❌ [PlayNow] Error: $e');
    }
  }

  Future<void> _addToQueue(QuickPick song) async {
    try {
      await widget.audioService.addToQueue(song);
      // ✅ REMOVED: await _loadQueue() — UI updates via customState stream

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
    // _radioService.dispose();
    _newradioService.dispose();
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
                Builder(
                  builder: (context) {
                    final handler = getAudioHandler();
                    final cs =
                        handler?.customState.value as Map<String, dynamic>? ??
                        {};
                    final isPlaylist = cs['is_playlist_mode'] == true;
                    final count = isPlaylist
                        ? (cs['playlist_songs_count'] as int? ?? 0)
                        : (cs['explicit_queue_count'] as int? ?? 0);
                    return Text('Queue ($count)');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioTab() {
    final handler = getAudioHandler();
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

        // ✅ NEW: Get playlist mode and source info
        final isPlaylistMode = customState['is_playlist_mode'] == true;
        final radioSource = customState['radio_source'] as String?;
        final playlistQueueCount =
            customState['playlist_queue_count'] as int? ?? 0;
        final playlistCurrentIndex =
            customState['playlist_current_index'] as int? ?? -1;

        // EMPTY STATE with detailed reasons
        if (radioQueueData.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // === SCENARIO 1: PLAYLIST MODE ===
                    if (isPlaylistMode) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.playlist_play,
                          size: 56,
                          color: primaryColor.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Radio Paused',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You\'re playing from a playlist',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: onSurface.withOpacity(0.65),
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Playlist progress indicator
                      if (playlistQueueCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: onSurface.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.playlist_play,
                                size: 18,
                                color: onSurface.withOpacity(0.7),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Song ${playlistCurrentIndex + 1} of $playlistQueueCount',
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Info box explaining why
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: onSurface.withOpacity(0.1),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.info_outline,
                                    color: primaryColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Why no radio?',
                                    style: TextStyle(
                                      color: onSurface.withOpacity(0.9),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Radio is automatically paused during playlist playback to preserve your listening order.',
                              style: TextStyle(
                                color: onSurface.withOpacity(0.65),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: primaryColor.withOpacity(0.7),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Radio will resume automatically when the playlist ends',
                                    style: TextStyle(
                                      color: primaryColor.withOpacity(0.8),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: primaryColor,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Playlist mode active',
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]
                    // === SCENARIO 2: LOADING RADIO ===
                    else ...[
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Icon(
                        Icons.radio,
                        size: 64,
                        color: onSurface.withOpacity(0.25),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Loading Radio Queue',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Discovering similar songs based on\nwhat you\'re listening to',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: onSurface.withOpacity(0.55),
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Loading process info box
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: onSurface.withOpacity(0.1),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.psychology_outlined,
                                  color: primaryColor,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Smart Radio Loading',
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.9),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildLoadingStep(
                              context,
                              '1',
                              'Analyzing current song',
                              onSurface,
                              primaryColor,
                            ),
                            const SizedBox(height: 10),
                            _buildLoadingStep(
                              context,
                              '2',
                              'Finding similar tracks',
                              onSurface,
                              primaryColor,
                            ),
                            const SizedBox(height: 10),
                            _buildLoadingStep(
                              context,
                              '3',
                              'Building personalized queue',
                              onSurface,
                              primaryColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        onPressed: _forceRefreshRadio,
                        icon: const Icon(Icons.refresh, size: 20),
                        label: const Text(
                          'Refresh Radio',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: themeData.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        }

        // RADIO LOADED - convert to QuickPick and show songs
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
            // Stats bar with radio source info
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
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

                  // ✅ NEW: Radio source indicator
                  if (radioSource != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: primaryColor.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getRadioSourceIcon(radioSource),
                            color: primaryColor,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _getRadioSourceText(radioSource),
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Song list (existing code)
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

  // ✅ NEW HELPER METHODS

  Widget _buildLoadingStep(
    BuildContext context,
    String number,
    String text,
    Color textColor,
    Color accentColor,
  ) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: accentColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: textColor.withOpacity(0.7),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  IconData _getRadioSourceIcon(String? source) {
    if (source == null) return Icons.radio;
    switch (source) {
      case 'playlist_continuation':
        return Icons.playlist_play;
      case 'search':
        return Icons.search;
      case 'quickPick':
        return Icons.bolt;
      case 'savedSongs':
        return Icons.favorite;
      case 'communityPlaylist':
        return Icons.people;
      default:
        return Icons.radio;
    }
  }

  String _getRadioSourceText(String? source) {
    if (source == null) return 'Smart radio queue';
    switch (source) {
      case 'playlist_continuation':
        return 'Radio from playlist continuation';
      case 'search':
        return 'Radio based on search result';
      case 'quickPick':
        return 'Radio based on quick pick';
      case 'savedSongs':
        return 'Radio based on saved song';
      case 'communityPlaylist':
        return 'Radio from community playlist';
      default:
        return 'Smart radio queue';
    }
  }

  // Add helper method for duration formatting
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildQueueTab() {
    final handler = getAudioHandler();
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
        final isPlaylistMode = customState['is_playlist_mode'] == true;

        // ── PLAYLIST MODE: show playlist songs ──────────────────────────
        if (isPlaylistMode) {
          final playlistData =
              customState['playlist_songs'] as List<dynamic>? ?? [];
          final currentIndex =
              customState['playlist_current_index'] as int? ?? -1;

          if (playlistData.isEmpty) {
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
                    'Loading playlist...',
                    style: TextStyle(
                      color: onSurface.withOpacity(0.7),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }

          final songs = playlistData.map((data) {
            final d = data as Map<String, dynamic>;
            final durationMs = d['duration'] as int?;
            return QuickPick(
              videoId: d['id'] as String,
              title: d['title'] as String,
              artists: d['artist'] as String? ?? 'Unknown Artist',
              thumbnail: d['artUri'] as String? ?? '',
              duration: durationMs != null
                  ? _formatDuration(Duration(milliseconds: durationMs))
                  : null,
            );
          }).toList();

          return Column(
            children: [
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
                        Icon(
                          Icons.playlist_play,
                          color: primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${songs.length} songs in playlist',
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      currentIndex >= 0
                          ? 'Playing ${currentIndex + 1} of ${songs.length}'
                          : '',
                      style: TextStyle(
                        color: onSurface.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<MediaItem?>(
                  stream: widget.audioService.mediaItemStream,
                  builder: (context, mediaSnapshot) {
                    final currentMedia = mediaSnapshot.data;
                    return StreamBuilder<PlaybackState>(
                      stream: widget.audioService.playbackStateStream,
                      builder: (context, playbackSnapshot) {
                        final isPlaying =
                            playbackSnapshot.data?.playing ?? false;
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
        }

        // ── RADIO MODE: show explicit queue ─────────────────────────────
        final explicitData =
            customState['explicit_queue'] as List<dynamic>? ?? [];

        if (explicitData.isEmpty) {
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
                  'Queue is empty',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.7),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add songs from radio to play next',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.4),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        final queueSongs = explicitData.map((data) {
          final d = data as Map<String, dynamic>;
          final durationMs = d['duration'] as int?;
          return QuickPick(
            videoId: d['id'] as String,
            title: d['title'] as String,
            artists: d['artist'] as String? ?? 'Unknown Artist',
            thumbnail: d['artUri'] as String? ?? '',
            duration: durationMs != null
                ? _formatDuration(Duration(milliseconds: durationMs))
                : null,
          );
        }).toList();

        return Column(
          children: [
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
                      Icon(Icons.queue_music, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${queueSongs.length} songs up next',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
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
            Expanded(
              child: StreamBuilder<MediaItem?>(
                stream: widget.audioService.mediaItemStream,
                builder: (context, mediaSnapshot) {
                  final currentMedia = mediaSnapshot.data;
                  return StreamBuilder<PlaybackState>(
                    stream: widget.audioService.playbackStateStream,
                    builder: (context, playbackSnapshot) {
                      final isPlaying = playbackSnapshot.data?.playing ?? false;
                      return ListView.builder(
                        itemCount: queueSongs.length,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          final song = queueSongs[index];
                          final isCurrentSong =
                              currentMedia?.id == song.videoId;
                          return _buildSongItem(
                            key: ValueKey(song.videoId),
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
