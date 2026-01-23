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

  Future<void> _confirmClearThoughts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text(
          'Clear All Thoughts?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently delete all audio player thoughts from the last 24 hours. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
          const SnackBar(
            content: Text('All thoughts cleared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a1a),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Engine Oberservations',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_thoughts.length} thoughts • Auto-clears after 24hrs',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_thoughts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Clear all thoughts',
              onPressed: _confirmClearThoughts,
            ),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.arrow_downward : Icons.arrow_upward,
              color: _autoScroll ? Colors.green : Colors.white54,
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
          // Main content
          _thoughts.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildCurrentThought(),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(child: _buildThoughtsList()),
                  ],
                ),

          // Lottie animation overlay when audio is playing but has thoughts
          // if (_isAudioPlaying && _thoughts.isNotEmpty)
          //   Positioned(
          //     top: 30,
          //     right: 140,
          //     child: Container(
          //       width: 150,
          //       height: 150,
          //       decoration: BoxDecoration(
          //         color: Colors.black.withOpacity(0.7),
          //         borderRadius: BorderRadius.circular(50),
          //         border: Border.all(
          //           color: Colors.green.withOpacity(0.6),
          //           width: 3,
          //         ),
          //         boxShadow: [
          //           BoxShadow(
          //             color: Colors.green.withOpacity(0.4),
          //             blurRadius: 15,
          //             spreadRadius: 3,
          //           ),
          //         ],
          //       ),
          //       child: ClipRRect(
          //         borderRadius: BorderRadius.circular(50),
          //         child: Lottie.asset(
          //           'assets/animations/pepe_listen.json',
          //           width: 100,
          //           height: 100,
          //           fit: BoxFit.cover,
          //           repeat: true,
          //         ),
          //       ),
          //     ),
          //   ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lottie animation when audio is playing, static icon when not
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
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    size: 80,
                    color: Colors.white24,
                  ),
                ),
          const SizedBox(height: 24),
          Text(
            _isAudioPlaying ? 'Vibing...' : 'No Thoughts Yet',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isAudioPlaying
                ? 'Music is playing but no new thoughts\nKeep listening! 🎵'
                : 'Start playing music to see what\nthe audio player is thinking',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentThought() {
    if (_thoughts.isEmpty) return const SizedBox.shrink();

    final current = _thoughts.first;

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
                Colors.blue.withOpacity(0.15),
                Colors.purple.withOpacity(0.15),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.blue.withOpacity(0.3), width: 2),
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
                            const Text(
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
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
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
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  current.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
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

  Widget _buildThoughtCard(AudioThought thought, bool isRecent, int index) {
    return Opacity(
      opacity: isRecent ? 1.0 : 0.85,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isRecent
              ? Colors.blue.withOpacity(0.1)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecent
                ? Colors.blue.withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
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
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              thought.timeAgo,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            _buildThoughtTypeChip(thought.type),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          thought.message,
                          style: TextStyle(
                            color: isRecent
                                ? Colors.white
                                : Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
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
                    color: Colors.white.withOpacity(0.3),
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
          color: color,
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

  void _showThoughtDetails(AudioThought thought) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a1a),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${thought.formattedTime} • ${thought.timeAgo}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
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
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Text(
                thought.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
            if (thought.context.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Context Data:',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  thought.context.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontFamily: 'monospace',
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
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
