// lib/widgets/centered_lyrics_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/lyrics_service.dart';

class CenteredLyricsWidget extends ConsumerStatefulWidget {
  final String title;
  final String artist;
  final String videoId;
  final int duration;
  final Color? accentColor;

  const CenteredLyricsWidget({
    Key? key,
    required this.title,
    required this.artist,
    required this.videoId,
    required this.duration,
    this.accentColor,
  }) : super(key: key);

  @override
  ConsumerState<CenteredLyricsWidget> createState() =>
      _CenteredLyricsWidgetState();
}

class _CenteredLyricsWidgetState extends ConsumerState<CenteredLyricsWidget>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _lyricsData;
  bool _isLoading = true;
  String? _error;
  int _currentLineIndex = -1;
  int _currentWordIndex = -1;
  String _lastVideoId = '';

  // Stream subscription
  StreamSubscription<Duration>? _positionSubscription;

  // Animation controllers for each word
  final Map<int, AnimationController> _wordControllers = {};
  final Map<int, Animation<double>> _scaleAnimations = {};
  final Map<int, Animation<double>> _fadeAnimations = {};

  @override
  void initState() {
    super.initState();
    _lastVideoId = widget.videoId;
    _loadLyrics();
    _listenToPosition();
  }

  @override
  void didUpdateWidget(CenteredLyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reload lyrics when song changes
    if (oldWidget.videoId != widget.videoId) {
      print('🔄 [Lyrics] Song changed, reloading lyrics...');
      _lastVideoId = widget.videoId;
      _currentLineIndex = -1;
      _currentWordIndex = -1;
      _resetWordAnimations();
      _loadLyrics();
    }
  }

  Future<void> _loadLyrics() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = await ref.read(lyricsServiceFutureProvider.future);
      final result = await service.fetchLyrics(
        title: widget.title,
        artist: widget.artist,
        duration: widget.duration,
      );

      if (mounted) {
        setState(() {
          if (result['success'] == true) {
            _lyricsData = result;
            _isLoading = false;
            print('✅ [Lyrics] Loaded successfully for ${widget.title}');
          } else {
            _error = result['error'] ?? 'Failed to load lyrics';
            _isLoading = false;
            print('❌ [Lyrics] Failed: $_error');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _listenToPosition() {
    final audioService = AudioServices.instance;

    // Cancel existing subscription if any
    _positionSubscription?.cancel();

    // Create new subscription
    _positionSubscription = audioService.positionStream.listen(
      (position) {
        // Check if widget is still mounted before updating state
        if (!mounted) return;

        if (_lyricsData == null || _lyricsData!['lines'] == null) return;

        final lines = _lyricsData!['lines'] as List;
        final currentMs = position.inMilliseconds;

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final timestamp = line['timestamp'] as int?;

          if (timestamp != null) {
            final nextTimestamp = i + 1 < lines.length
                ? lines[i + 1]['timestamp'] as int?
                : null;

            if (currentMs >= timestamp &&
                (nextTimestamp == null || currentMs < nextTimestamp)) {
              if (_currentLineIndex != i) {
                if (mounted) {
                  setState(() {
                    _currentLineIndex = i;
                    _currentWordIndex = -1;
                    _resetWordAnimations();
                  });
                }
              }

              if (_lyricsData!['type'] == 'word_by_word') {
                _updateWordHighlight(i, currentMs, timestamp);
              }
              break;
            }
          }
        }
      },
      onError: (error) {
        // Handle stream errors gracefully
        debugPrint('Position stream error: $error');
      },
    );
  }

  void _resetWordAnimations() {
    for (var controller in _wordControllers.values) {
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.reset();
    }
  }

  void _updateWordHighlight(int lineIndex, int currentMs, int lineStartMs) {
    if (!mounted) return;

    final line = (_lyricsData!['lines'] as List)[lineIndex];
    final text = line['text'] as String;
    final words = text.split(' ');

    if (words.isEmpty) return;

    final nextLine = lineIndex + 1 < (_lyricsData!['lines'] as List).length
        ? (_lyricsData!['lines'] as List)[lineIndex + 1]
        : null;
    final nextTimestamp = nextLine != null
        ? nextLine['timestamp'] as int?
        : null;
    final lineDuration = nextTimestamp != null
        ? nextTimestamp - lineStartMs
        : 3000;

    final msPerWord = lineDuration / words.length;
    final elapsed = currentMs - lineStartMs;
    final wordIndex = (elapsed / msPerWord).floor().clamp(0, words.length - 1);

    if (_currentWordIndex != wordIndex && wordIndex >= 0) {
      if (mounted) {
        setState(() {
          _currentWordIndex = wordIndex;
        });
        _animateWord(wordIndex);
      }
    }
  }

  void _animateWord(int wordIndex) {
    if (!mounted) return;

    if (!_wordControllers.containsKey(wordIndex)) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
      );

      _wordControllers[wordIndex] = controller;
      _scaleAnimations[wordIndex] = Tween<double>(
        begin: 0.85,
        end: 1.15,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.elasticOut));

      _fadeAnimations[wordIndex] = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: controller,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
        ),
      );
    }

    _wordControllers[wordIndex]?.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    // COMPLETELY TRANSPARENT BACKGROUND
    return Container(color: Colors.transparent, child: _buildContent());
  }

  Widget _buildContent() {
    final accentColor = widget.accentColor ?? AppColors.iconActive;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return const Center(child: Text('No lyrics available'));
    }

    final lines = _lyricsData!['lines'] as List;
    final isWordByWord = _lyricsData!['type'] == 'word_by_word';

    if (_currentLineIndex < 0 || _currentLineIndex >= lines.length) {
      return const SizedBox.shrink();
    }

    final current = lines[_currentLineIndex]['text'] as String;
    final prev = _currentLineIndex > 0
        ? lines[_currentLineIndex - 1]['text'] as String
        : null;
    final next = _currentLineIndex < lines.length - 1
        ? lines[_currentLineIndex + 1]['text'] as String
        : null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          /// ───────── PREVIOUS (STATIC, NO ANIMATION) ─────────
          SizedBox(
            height: 36,
            child: prev == null
                ? const SizedBox.shrink()
                : Text(
                    prev,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          /// ───────── CURRENT (ONLY THIS SCROLLS) ─────────
          SizedBox(
            height: 72,
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 520),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, 0.35), // looks like scroll
                    end: Offset.zero,
                  ).animate(animation);

                  return SlideTransition(
                    position: slide,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Container(
                  key: ValueKey(_currentLineIndex),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: isWordByWord
                      ? _buildWordByWordLine(current, accentColor)
                      : _buildSimpleLine(current, accentColor),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          /// ───────── NEXT (STATIC, INSTANT CHANGE) ─────────
          SizedBox(
            height: 36,
            child: next == null
                ? const SizedBox.shrink()
                : Text(
                    next,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleLine(String text, Color accentColor) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.92 + (0.08 * value),
          child: Opacity(
            opacity: value,
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.4,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color: accentColor.withOpacity(0.9 * value),
                    blurRadius: 30,
                    offset: const Offset(0, 0),
                  ),
                  Shadow(
                    color: accentColor.withOpacity(0.6 * value),
                    blurRadius: 50,
                    offset: const Offset(0, 0),
                  ),
                  Shadow(
                    color: accentColor.withOpacity(0.4 * value),
                    blurRadius: 70,
                    offset: const Offset(0, 2),
                  ),
                  Shadow(
                    color: Colors.white.withOpacity(0.3 * value),
                    blurRadius: 15,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWordByWordLine(String text, Color accentColor) {
    final words = text.split(' ');

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: List.generate(words.length, (i) {
          final isPast = i < _currentWordIndex;
          final isCurrent = i == _currentWordIndex;

          final opacity = isPast
              ? 0.6
              : isCurrent
              ? 1.0
              : 0.35;

          return TextSpan(
            text: '${words[i]} ',
            style: TextStyle(
              fontSize: 20,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
              color: Colors.white.withOpacity(opacity),
              height: 1.4,
              shadows: isCurrent
                  ? [
                      Shadow(
                        color: accentColor.withOpacity(0.9),
                        blurRadius: 28,
                      ),
                      Shadow(
                        color: accentColor.withOpacity(0.6),
                        blurRadius: 48,
                      ),
                    ]
                  : [
                      Shadow(
                        color: accentColor.withOpacity(0.15),
                        blurRadius: 8,
                      ),
                    ],
            ),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    // Cancel the stream subscription first
    _positionSubscription?.cancel();
    _positionSubscription = null;

    // Stop and dispose all animation controllers
    for (var controller in _wordControllers.values) {
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.dispose();
    }

    // Clear all maps
    _wordControllers.clear();
    _scaleAnimations.clear();
    _fadeAnimations.clear();

    super.dispose();
  }
}
