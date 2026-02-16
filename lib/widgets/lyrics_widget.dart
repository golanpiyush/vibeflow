// lib/widgets/centered_lyrics_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/lyrics_service.dart';

class CenteredLyricsWidget extends ConsumerStatefulWidget {
  final String title;
  final String artist;
  final String videoId;
  final int duration;
  final Color? accentColor;
  // ✅ NEW: Loading shimmer builder
  final Widget Function(BuildContext)? loadingBuilder;
  // ✅ NEW: Auto-translate CJK lyrics
  final bool autoTranslate;

  const CenteredLyricsWidget({
    Key? key,
    required this.title,
    required this.artist,
    required this.videoId,
    required this.duration,
    this.accentColor,
    this.loadingBuilder, // ✅ NEW
    this.autoTranslate = false, // ✅ NEW
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
  bool requestTranslation = false;
  // ✅ NEW: Translation state
  bool _isCJKLanguage = false;
  Map<String, dynamic>? _translatedLyricsData;
  bool _showTranslation = false;
  String? _detectedLanguage;
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
      _isCJKLanguage = false;
      _detectedLanguage = null;
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

            // ✅ NEW: Check if lyrics are in CJK language
            if (widget.autoTranslate) {
              final detectedLang = _detectCJKLanguage(_lyricsData!);
              _isCJKLanguage = detectedLang != null;
              _detectedLanguage = detectedLang;

              if (_isCJKLanguage) {
                print('🌐 [Lyrics] $_detectedLanguage language detected');
              }
            }

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

  Widget _buildTranslationLine(String text, Color accentColor) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: 0.7 * value,
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.3,
              letterSpacing: 0.3,
              fontStyle: FontStyle.italic,
              shadows: [
                Shadow(
                  color: accentColor.withOpacity(0.3 * value),
                  blurRadius: 15,
                ),
              ],
            ),
          ),
        );
      },
    );
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

    // ✅ NEW: Show custom loading shimmer if provided
    if (_isLoading) {
      if (widget.loadingBuilder != null) {
        return widget.loadingBuilder!(context);
      }
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return const Center(
        child: Text(
          'No lyrics available',
          style: TextStyle(color: Colors.white),
        ),
      );
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

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// ───────── PREVIOUS ─────────
              SizedBox(
                height: 36,
                child: prev == null
                    ? const SizedBox.shrink()
                    : Text(
                        prev,
                        maxLines: 1,
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

              /// ───────── CURRENT ─────────
              SizedBox(
                height: _isCJKLanguage ? 96 : 72,
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 520),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.35),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          isWordByWord
                              ? _buildWordByWordLine(current, accentColor)
                              : _buildSimpleLine(current, accentColor),
                          // ✅ NEW: Show language indicator for CJK
                          if (_isCJKLanguage) ...[
                            const SizedBox(height: 6),
                            _buildLanguageIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              /// ───────── NEXT ─────────
              SizedBox(
                height: 36,
                child: next == null
                    ? const SizedBox.shrink()
                    : Text(
                        next,
                        maxLines: 1,
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
        ),

        // ✅ NEW: Language indicator badge (top-right)
        if (_isCJKLanguage)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getLanguageName(),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ✅ NEW: Get language display name
  String _getLanguageName() {
    switch (_detectedLanguage) {
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'zh':
        return '中文';
      default:
        return 'Original';
    }
  }

  // ✅ NEW: Generate romanized version of text (basic implementation)
  String _generateRomanization(String text) {
    // This is a placeholder - in production you'd use a proper romanization API
    // For now, just show a helpful message below CJK text

    switch (_detectedLanguage) {
      case 'ja':
        return '[Japanese - Romaji not available]';
      case 'ko':
        return '[Korean - Romanization not available]';
      case 'zh':
        return '[Chinese - Pinyin not available]';
      default:
        return '';
    }
  }

  // ✅ NEW: Detect if lyrics contain CJK characters and return language code
  String? _detectCJKLanguage(Map<String, dynamic> lyricsData) {
    final lines = lyricsData['lines'] as List?;
    if (lines == null || lines.isEmpty) return null;

    // Check first few lines for CJK characters
    final sampleText = lines
        .take(3)
        .map((line) => line['text'] as String? ?? '')
        .join(' ');

    // Japanese: Hiragana, Katakana
    final japaneseRegex = RegExp(r'[\u3040-\u309F\u30A0-\u30FF]');
    if (japaneseRegex.hasMatch(sampleText)) {
      return 'ja'; // Japanese
    }

    // Korean: Hangul
    final koreanRegex = RegExp(r'[\uAC00-\uD7AF]');
    if (koreanRegex.hasMatch(sampleText)) {
      return 'ko'; // Korean
    }

    // Chinese: Kanji/Hanzi (but not if Japanese detected)
    final chineseRegex = RegExp(r'[\u4E00-\u9FFF]');
    if (chineseRegex.hasMatch(sampleText)) {
      return 'zh'; // Chinese
    }

    return null;
  }

  String _getLanguageHint() {
    switch (_detectedLanguage) {
      case 'ja':
        return 'Original Japanese lyrics';
      case 'ko':
        return 'Original Korean lyrics';
      case 'zh':
        return 'Original Chinese lyrics';
      default:
        return '';
    }
  }

  // ✅ NEW: Load translated lyrics
  Future<void> _loadTranslation() async {
    if (!mounted || _lyricsData == null) return;

    try {
      final service = await ref.read(lyricsServiceFutureProvider.future);

      // Fetch romanized/translated version
      final translatedResult = await service.fetchLyrics(
        title: widget.title,
        artist: widget.artist,
        duration: widget.duration,
        requestTranslation: true, // Add this parameter to your lyrics service
      );

      if (mounted && translatedResult['success'] == true) {
        setState(() {
          _translatedLyricsData = translatedResult;
          _showTranslation = true;
        });
        print('✅ [Lyrics] Translation loaded');
      }
    } catch (e) {
      print('⚠️ [Lyrics] Translation failed: $e');
      // Don't set error - just continue showing original lyrics
    }
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

  Widget _buildLanguageIndicator() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: 0.5 * value,
          child: Text(
            _getLanguageHint(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0.2,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    for (var controller in _wordControllers.values) {
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.dispose();
    }

    _wordControllers.clear();
    _scaleAnimations.clear();
    _fadeAnimations.clear();

    super.dispose();
  }
}
// ============================================================================
// COMPLETE FIXED CompactLineByLineLyrics Widget
// Replace the entire class with this version to fix the disposal error
// ============================================================================

class CompactLineByLineLyrics extends ConsumerStatefulWidget {
  final String title;
  final String artist;
  final String videoId;
  final int duration;
  final Color accentColor;

  const CompactLineByLineLyrics({
    Key? key,
    required this.title,
    required this.artist,
    required this.videoId,
    required this.duration,
    required this.accentColor,
  }) : super(key: key);

  @override
  ConsumerState<CompactLineByLineLyrics> createState() =>
      _CompactLineByLineLyricsState();
}

class _CompactLineByLineLyricsState
    extends ConsumerState<CompactLineByLineLyrics> {
  List<Map<String, dynamic>> _lyrics = [];
  bool _isLoading = true;
  int _currentLineIndex = -1;
  StreamSubscription<Duration>? _positionSubscription;
  bool _isDisposed = false; // ✅ Track disposal state

  @override
  void initState() {
    super.initState();
    _fetchLyrics();
    _startPositionListener();
  }

  @override
  void didUpdateWidget(CompactLineByLineLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reload lyrics if song changes
    if (oldWidget.videoId != widget.videoId) {
      _currentLineIndex = -1;
      _fetchLyrics();
    }
  }

  Future<void> _fetchLyrics() async {
    if (_isDisposed || !mounted) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final lyricsServiceAsync = ref.read(lyricsServiceFutureProvider.future);
      final lyricsService = await lyricsServiceAsync;

      if (_isDisposed || !mounted) return;

      final lyricsData = await lyricsService.fetchLyrics(
        title: widget.title,
        artist: widget.artist,
        duration: widget.duration,
      );

      if (_isDisposed || !mounted) return;

      print(
        '🎤 [CompactLyrics] Fetch result: success=${lyricsData['success']}, has lines=${lyricsData['lines'] != null}',
      );

      if (lyricsData['success'] == true) {
        final lines = lyricsData['lines'] as List<dynamic>?;

        if (lines != null && lines.isNotEmpty) {
          if (_isDisposed || !mounted) return;

          setState(() {
            _lyrics = lines
                .map(
                  (line) => {
                    'text': line['text'] as String? ?? '',
                    'time': (line['timestamp'] as int? ?? -1) / 1000.0,
                  },
                )
                .where((line) => (line['text'] as String).isNotEmpty)
                .toList();
            _isLoading = false;

            print('✅ [CompactLyrics] Loaded ${_lyrics.length} lines');
            if (_lyrics.isNotEmpty) {
              print(
                '   First line: "${_lyrics.first['text']}" at ${_lyrics.first['time']}s',
              );
            }
          });
        } else {
          print('⚠️ [CompactLyrics] No lines in lyrics data');
          if (_isDisposed || !mounted) return;
          setState(() {
            _lyrics = [];
            _isLoading = false;
          });
        }
      } else {
        print('❌ [CompactLyrics] Fetch failed: ${lyricsData['error']}');
        if (_isDisposed || !mounted) return;
        setState(() {
          _lyrics = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ [CompactLyrics] Error fetching lyrics: $e');
      if (_isDisposed || !mounted) return;
      if (mounted) {
        setState(() {
          _lyrics = [];
          _isLoading = false;
        });
      }
    }
  }

  void _startPositionListener() {
    // Cancel any existing subscription
    _positionSubscription?.cancel();

    final audioService = AudioServices.instance;

    _positionSubscription = audioService.positionStream.listen(
      (position) {
        if (_isDisposed || !mounted) return;

        final currentSeconds = position.inSeconds.toDouble();
        int newIndex = -1;

        for (int i = 0; i < _lyrics.length; i++) {
          final lineTime = _lyrics[i]['time'] as double;
          if (lineTime < 0) continue;

          if (currentSeconds >= lineTime) {
            newIndex = i;
          } else {
            break;
          }
        }

        if (newIndex != _currentLineIndex && newIndex >= 0) {
          if (_isDisposed || !mounted) return;

          setState(() {
            _currentLineIndex = newIndex;
            print(
              '📍 [CompactLyrics] Line $newIndex: "${_lyrics[newIndex]['text']}"',
            );
          });
        }
      },
      onError: (error) {
        print('⚠️ [CompactLyrics] Position stream error: $error');
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't build if disposed
    if (_isDisposed) return const SizedBox.shrink();

    print(
      '🎤 [CompactLyrics] Building - loading: $_isLoading, lyrics: ${_lyrics.length}, currentLine: $_currentLineIndex',
    );

    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              widget.accentColor.withOpacity(0.5),
            ),
          ),
        ),
      );
    }

    if (_lyrics.isEmpty) {
      return const SizedBox.shrink(); // Just hide if no lyrics
    }

    // Show only current line with slide-up animation
    if (_currentLineIndex < 0 || _currentLineIndex >= _lyrics.length) {
      return const SizedBox.shrink(); // Hide while waiting
    }

    final currentLine = _lyrics[_currentLineIndex];
    final text = currentLine['text'] as String;

    // Calculate dynamic font size based on text length
    final textLength = text.length;
    final fontSize = textLength > 50
        ? 13.0
        : textLength > 30
        ? 14.0
        : 15.0;

    return SizedBox(
      height: 50, // Reduced height
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutQuart,
          switchOutCurve: Curves.easeInQuart,
          transitionBuilder: (child, animation) {
            // Smoother slide up with more gradual fade
            final slideAnimation =
                Tween<Offset>(
                  begin: const Offset(
                    0,
                    0.3,
                  ), // Start closer for smoother effect
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutQuart,
                  ),
                );

            // Separate fade animation for smoother transition
            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
              ),
            );

            return SlideTransition(
              position: slideAnimation,
              child: FadeTransition(opacity: fadeAnimation, child: child),
            );
          },
          child: Container(
            key: ValueKey(_currentLineIndex),
            color: const Color.fromARGB(
              0,
              255,
              10,
              10,
            ), // Transparent background
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: widget.accentColor,
                height: 1.3,
                letterSpacing: 0.1,
                shadows: [
                  Shadow(
                    color: widget.accentColor.withOpacity(0.4),
                    blurRadius: 15,
                  ),
                  Shadow(
                    color: widget.accentColor.withOpacity(0.2),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
