// lib/widgets/crossfade_slider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';

/// Crossfade Duration Slider
/// Controls how many seconds the crossfade transition lasts (1s – 8s)
/// Also has an enable/disable toggle
class CrossfadeSlider extends StatefulWidget {
  const CrossfadeSlider({Key? key}) : super(key: key);

  @override
  State<CrossfadeSlider> createState() => _CrossfadeSliderState();
}

class _CrossfadeSliderState extends State<CrossfadeSlider>
    with SingleTickerProviderStateMixin {
  static const String _enabledKey = 'crossfade_enabled';
  static const String _durationKey = 'crossfade_duration_seconds';
  static const double _min = 1;
  static const double _max = 8;

  bool _enabled = false;
  double _seconds = 3; // default 3s
  bool _loaded = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadPrefs();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final seconds = prefs.getDouble(_durationKey) ?? 3.0;

    if (mounted) {
      setState(() {
        _enabled = enabled;
        _seconds = seconds.clamp(_min, _max);
        _loaded = true;
      });
    }

    final handler = getAudioHandler();
    handler?.setCrossfadeEnabled(enabled);
    handler?.setCrossfadeDuration(Duration(seconds: seconds.toInt()));
  }

  Future<void> _toggleEnabled() async {
    final newVal = !_enabled;
    setState(() => _enabled = newVal);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, newVal);

    getAudioHandler()?.setCrossfadeEnabled(newVal);
    print('🎚️ [CrossfadeSlider] ${newVal ? "Enabled" : "Disabled"}');
  }

  Future<void> _onChanged(double val) async {
    setState(() => _seconds = val);
    _pulseController.forward().then((_) => _pulseController.reverse());
    getAudioHandler()?.setCrossfadeDuration(Duration(seconds: val.toInt()));
  }

  Future<void> _onChangeEnd(double val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_durationKey, val);
    print('💾 [CrossfadeSlider] Saved: ${val.toInt()}s');
  }

  String _describe(double s) {
    if (s <= 2) return 'Subtle';
    if (s <= 4) return 'Smooth';
    if (s <= 6) return 'Long';
    return 'Very long';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final accent = Theme.of(context).colorScheme.primary;
    final textPrimary = Theme.of(context).colorScheme.onSurface;
    final textSecondary = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.55);
    final surfaceVariant = Theme.of(
      context,
    ).colorScheme.surfaceVariant.withOpacity(0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row with toggle ────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crossfade',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Blend between songs with a fade transition',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: _enabled,
              onChanged: (_) => _toggleEnabled(),
              activeColor: accent,
            ),
          ],
        ),

        // ── Slider (only visible when enabled) ───────────────────────────
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _enabled
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    // ── Duration badge ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ScaleTransition(
                          scale: _pulseAnim,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: accent.withOpacity(0.35),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 13,
                                  color: accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_seconds.toInt()}s  ·  ${_describe(_seconds)}',
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 5,
                        activeTrackColor: accent,
                        inactiveTrackColor: accent.withOpacity(0.18),
                        thumbColor: accent,
                        overlayColor: accent.withOpacity(0.12),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 9,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 20,
                        ),
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                        valueIndicatorShape:
                            const PaddleSliderValueIndicatorShape(),
                        valueIndicatorColor: accent,
                        valueIndicatorTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      child: Slider(
                        value: _seconds,
                        min: _min,
                        max: _max,
                        divisions: 7, // 1s steps
                        label: '${_seconds.toInt()}s fade',
                        onChanged: _onChanged,
                        onChangeEnd: _onChangeEnd,
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '1s',
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '8s',
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Visual crossfade preview ────────────────────────────
              _CrossfadePreview(
                seconds: _seconds,
                accent: accent,
                textSecondary: textSecondary,
              ),
            ],
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Visual preview of the fade curve ─────────────────────────────────────────
class _CrossfadePreview extends StatelessWidget {
  final double seconds;
  final Color accent;
  final Color textSecondary;

  const _CrossfadePreview({
    required this.seconds,
    required this.accent,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.music_note, size: 12, color: textSecondary),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: 20,
            child: CustomPaint(painter: _FadeCurvePainter(accent: accent)),
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.music_note, size: 12, color: accent),
        const SizedBox(width: 6),
        Text(
          '${seconds.toInt()}s overlap',
          style: TextStyle(
            fontSize: 11,
            color: textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FadeCurvePainter extends CustomPainter {
  final Color accent;
  const _FadeCurvePainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final fadeOutPaint = Paint()
      ..color = accent.withOpacity(0.4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fadeInPaint = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Fade out curve (top-left → bottom-right)
    final outPath = Path();
    outPath.moveTo(0, 2);
    outPath.cubicTo(
      size.width * 0.3,
      2,
      size.width * 0.7,
      size.height - 2,
      size.width,
      size.height - 2,
    );
    canvas.drawPath(outPath, fadeOutPaint);

    // Fade in curve (bottom-left → top-right)
    final inPath = Path();
    inPath.moveTo(0, size.height - 2);
    inPath.cubicTo(
      size.width * 0.3,
      size.height - 2,
      size.width * 0.7,
      2,
      size.width,
      2,
    );
    canvas.drawPath(inPath, fadeInPaint);
  }

  @override
  bool shouldRepaint(_FadeCurvePainter old) => old.accent != accent;
}
