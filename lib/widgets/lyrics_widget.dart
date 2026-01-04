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

  // Stream subscription
  StreamSubscription<Duration>? _positionSubscription;

  // Animation controllers for each word
  final Map<int, AnimationController> _wordControllers = {};
  final Map<int, Animation<double>> _scaleAnimations = {};
  final Map<int, Animation<double>> _fadeAnimations = {};

  @override
  void initState() {
    super.initState();
    _loadLyrics();
    _listenToPosition();
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
          } else {
            _error = result['error'] ?? 'Failed to load lyrics';
            _isLoading = false;
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.75),
            Colors.black.withOpacity(0.85),
            Colors.black.withOpacity(0.75),
          ],
        ),
      ),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: widget.accentColor ?? AppColors.iconActive,
          strokeWidth: 2,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              color: Colors.white.withOpacity(0.3),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'No lyrics available',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final isWordByWord = _lyricsData!['type'] == 'word_by_word';
    final lines = _lyricsData!['lines'] as List;

    if (_currentLineIndex == -1 || _currentLineIndex >= lines.length) {
      return Center(
        child: Text(
          'Waiting for lyrics...',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
        ),
      );
    }

    final currentLine = lines[_currentLineIndex];
    final currentText = currentLine['text'] as String;

    final previousLine = _currentLineIndex > 0
        ? lines[_currentLineIndex - 1]['text'] as String
        : null;
    final nextLine = _currentLineIndex < lines.length - 1
        ? lines[_currentLineIndex + 1]['text'] as String
        : null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (previousLine != null)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: 1.0,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  previousLine,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey(_currentLineIndex),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: isWordByWord
                  ? _buildWordByWordLine(
                      currentText,
                      widget.accentColor ?? AppColors.iconActive,
                    )
                  : _buildSimpleLine(currentText, true),
            ),
          ),

          if (nextLine != null)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: 1.0,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  nextLine,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSimpleLine(String text, bool isActive) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * value),
          child: Opacity(
            opacity: value,
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.6,
                shadows: [
                  Shadow(
                    color: (widget.accentColor ?? Colors.white).withOpacity(
                      0.4 * value,
                    ),
                    blurRadius: 16,
                  ),
                  Shadow(
                    color: (widget.accentColor ?? Colors.white).withOpacity(
                      0.2 * value,
                    ),
                    blurRadius: 24,
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

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: List.generate(words.length, (wordIndex) {
        final word = words[wordIndex];
        final isHighlighted = wordIndex <= _currentWordIndex;
        final isPast = wordIndex < _currentWordIndex;

        return AnimatedBuilder(
          animation:
              _wordControllers[wordIndex] ?? const AlwaysStoppedAnimation(0),
          builder: (context, child) {
            final scaleValue = _scaleAnimations[wordIndex]?.value ?? 1.0;
            final fadeValue = _fadeAnimations[wordIndex]?.value ?? 0.0;

            final baseOpacity = isPast ? 0.6 : (isHighlighted ? 1.0 : 0.35);
            final finalOpacity = isHighlighted ? baseOpacity : baseOpacity;

            return Transform.scale(
              scale: isHighlighted && wordIndex == _currentWordIndex
                  ? scaleValue
                  : (isPast ? 1.0 : 0.95),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: Text(
                  word,
                  style: TextStyle(
                    color: Colors.white.withOpacity(finalOpacity),
                    fontSize: 22,
                    fontWeight: isHighlighted
                        ? FontWeight.w700
                        : FontWeight.w400,
                    height: 1.6,
                    letterSpacing: isHighlighted ? 0.5 : 0,
                    shadows: isHighlighted && wordIndex == _currentWordIndex
                        ? [
                            Shadow(
                              color: accentColor.withOpacity(0.8 * fadeValue),
                              blurRadius: 20,
                              offset: const Offset(0, 0),
                            ),
                            Shadow(
                              color: accentColor.withOpacity(0.5 * fadeValue),
                              blurRadius: 30,
                              offset: const Offset(0, 0),
                            ),
                            Shadow(
                              color: accentColor.withOpacity(0.3 * fadeValue),
                              blurRadius: 40,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : isPast
                        ? [
                            Shadow(
                              color: accentColor.withOpacity(0.2),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          },
        );
      }),
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
