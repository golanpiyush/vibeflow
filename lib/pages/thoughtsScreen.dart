import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:vibeflow/services/audioGoverner.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'dart:async';

/// Full screen to display audio player thoughts with 24hr persistence
class AudioThoughtsScreen extends StatefulWidget {
  const AudioThoughtsScreen({Key? key}) : super(key: key);

  @override
  State<AudioThoughtsScreen> createState() => _AudioThoughtsScreenState();
}

class _AudioThoughtsScreenState extends State<AudioThoughtsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final AudioGovernor _governor = AudioGovernor.instance;
  List<AudioThought> _thoughts = [];
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();
  bool _isAudioPlaying = false;

  // Stream subscriptions that need to be cancelled
  StreamSubscription? _playbackStateSubscription;
  StreamSubscription? _thoughtStreamSubscription;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    // Load existing thoughts
    _thoughts = _governor.allThoughts;

    // Listen to audio playback state - STORE THE SUBSCRIPTION
    _playbackStateSubscription = AudioServices.instance.playbackStateStream
        .listen((state) {
          if (mounted) {
            setState(() {
              _isAudioPlaying = state.playing;
            });
          }
        });

    // Listen to new thoughts - STORE THE SUBSCRIPTION
    _thoughtStreamSubscription = _governor.thoughtStream.listen((thought) {
      if (mounted) {
        setState(() {
          _thoughts = _governor.allThoughts;
        });

        _animationController.forward(from: 0.0);

        // Auto scroll to top when new thought arrives
        if (_autoScroll && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });

    // Listen to scroll events to disable auto-scroll when user scrolls
    _scrollController.addListener(() {
      if (!mounted) return;

      if (_scrollController.position.pixels > 100) {
        if (_autoScroll) {
          setState(() => _autoScroll = false);
        }
      } else {
        if (!_autoScroll) {
          setState(() => _autoScroll = true);
        }
      }
    });
  }

  @override
  void dispose() {
    // Cancel all stream subscriptions
    _playbackStateSubscription?.cancel();
    _thoughtStreamSubscription?.cancel();

    // Dispose controllers
    _animationController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Engine Observations',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface, // ADD THIS
              ),
            ),
            Text(
              '${_thoughts.length} thoughts • Auto-clears after 24hrs',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6), // ADD THIS
              ),
            ),
          ],
        ),
        actions: [
          if (_thoughts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: colorScheme.error, // UPDATED
              tooltip: 'Clear all thoughts',
              onPressed: _confirmClearThoughts,
            ),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.arrow_downward : Icons.arrow_upward,
              color: _autoScroll
                  ? Colors.green
                  : colorScheme.onSurface.withOpacity(0.6), // UPDATED
            ),
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
              if (_autoScroll && _scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _thoughts.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildCurrentThought(),
                    Divider(
                      color: colorScheme.outline.withOpacity(0.2),
                      height: 1,
                    ),
                    Expanded(child: _buildThoughtsList()),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _isAudioPlaying
              ? Lottie.asset(
                  'assets/animations/pepe_listen.json',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  repeat: true,
                )
              : Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.psychology_rounded,
                    size: 80,
                    color: colorScheme.onSurface.withOpacity(0.3), // UPDATED
                  ),
                ),
          const SizedBox(height: 24),
          Text(
            _isAudioPlaying ? 'Vibing...' : 'No Thoughts Yet',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface, // ADD THIS
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isAudioPlaying
                ? 'Music is playing but no new thoughts\nKeep listening! 🎵'
                : 'Start playing music to see what\nthe audio player is thinking',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6), // ADD THIS
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentThought() {
    if (_thoughts.isEmpty) return const SizedBox.shrink();

    final current = _thoughts.first;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer.withOpacity(0.3),
                colorScheme.secondaryContainer.withOpacity(0.3),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: colorScheme.primary.withOpacity(0.3),
                width: 2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Colors.green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'THINKING NOW',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${current.formattedTime} • ${current.timeAgo}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(
                              0.5,
                            ), // UPDATED
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildThoughtTypeChip(current.type),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Text(
                  current.message,
                  style: textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                    color: colorScheme.onSurface, // ADD THIS
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThoughtCard(AudioThought thought, bool isRecent, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Opacity(
      opacity: isRecent ? 1.0 : 0.85,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isRecent
              ? colorScheme.primaryContainer.withOpacity(0.3)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecent
                ? colorScheme.primary.withOpacity(0.3)
                : colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showThoughtDetails(thought),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getColorForType(thought.type).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getIconForType(thought.type),
                      color: _getColorForType(thought.type),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              thought.formattedTime,
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface, // ADD THIS
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(
                                  0.3,
                                ), // UPDATED
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              thought.timeAgo,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(
                                  0.5,
                                ), // UPDATED
                              ),
                            ),
                            const Spacer(),
                            _buildThoughtTypeChip(thought.type),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          thought.message,
                          style: textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                            color: isRecent
                                ? colorScheme.onSurface
                                : colorScheme.onSurface.withOpacity(
                                    0.9,
                                  ), // UPDATED
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurface.withOpacity(0.3), // UPDATED
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearThoughts() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Clear All Thoughts?',
          style: TextStyle(color: colorScheme.onSurface), // ADD THIS
        ),
        content: Text(
          'This will permanently delete all audio player thoughts from the last 24 hours. This action cannot be undone.',
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
          ), // ADD THIS
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
              ), // ADD THIS
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _governor.clearAllThoughts();
      if (mounted) {
        setState(() {
          _thoughts = _governor.allThoughts;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('All thoughts cleared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showThoughtDetails(AudioThought thought) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getColorForType(thought.type).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getIconForType(thought.type),
                    color: _getColorForType(thought.type),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTypeLabel(thought.type),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface, // ADD THIS
                        ),
                      ),
                      Text(
                        '${thought.formattedTime} • ${thought.timeAgo}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(
                            0.5,
                          ), // ADD THIS
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
              ),
              child: Text(
                thought.message,
                style: textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                  color: colorScheme.onSurface, // ADD THIS
                ),
              ),
            ),
            if (thought.context.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Context Data:',
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface, // ADD THIS
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  thought.context.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n'),
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface.withOpacity(0.8), // ADD THIS
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Close',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimary, // ADD THIS
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThoughtsList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: _thoughts.length,
      itemBuilder: (context, index) {
        final thought = _thoughts[index];
        final isRecent = index == 0;

        return _buildThoughtCard(thought, isRecent, index);
      },
    );
  }

  Widget _buildThoughtTypeChip(String type) {
    final color = _getColorForType(type);
    final label = _formatTypeLabel(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color, // Keep functional color
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _formatTypeLabel(String type) {
    return type
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Color _getColorForType(String type) {
    if (type.contains('skip') || type.contains('seek')) return Colors.orange;
    if (type.contains('pause') || type.contains('stop')) return Colors.red;
    if (type.contains('play') || type.contains('resum')) return Colors.green;
    if (type.contains('buffer') || type.contains('loading'))
      return Colors.yellow;
    if (type.contains('url') || type.contains('cache')) return Colors.cyan;
    if (type.contains('shuffle') || type.contains('loop')) return Colors.purple;
    if (type.contains('queue')) return Colors.pink;
    if (type.contains('headphone') || type.contains('bluetooth'))
      return Colors.teal;
    if (type.contains('connection') || type.contains('error'))
      return Colors.deepOrange;
    if (type.contains('radio')) return Colors.indigo;
    return Colors.blue;
  }

  IconData _getIconForType(String type) {
    if (type.contains('skip_forward')) return Icons.skip_next;
    if (type.contains('skip_backward')) return Icons.skip_previous;
    if (type.contains('pause')) return Icons.pause;
    if (type.contains('play') || type.contains('resum'))
      return Icons.play_arrow;
    if (type.contains('stop')) return Icons.stop;
    if (type.contains('buffer')) return Icons.hourglass_empty;
    if (type.contains('url')) return Icons.link;
    if (type.contains('shuffle')) return Icons.shuffle;
    if (type.contains('loop')) return Icons.repeat;
    if (type.contains('queue')) return Icons.queue_music;
    if (type.contains('headphone')) return Icons.headphones;
    if (type.contains('bluetooth')) return Icons.bluetooth;
    if (type.contains('connection')) return Icons.wifi;
    if (type.contains('radio')) return Icons.radio;
    if (type.contains('cache')) return Icons.bolt;
    if (type.contains('seek')) return Icons.fast_forward;
    if (type.contains('volume')) return Icons.volume_up;
    if (type.contains('error')) return Icons.error_outline;
    return Icons.music_note;
  }
}
