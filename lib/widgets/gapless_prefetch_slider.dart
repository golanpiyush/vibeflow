// lib/widgets/gapless_prefetch_slider.dart
// Drop this widget into your PlayerSettingsPage under the PLAYBACK section

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';

/// Gapless Playback Prefetch Slider
/// Controls how many seconds before a song ends the next URL is pre-fetched.
/// Range: 10s – 20s
class GaplessPrefetchSlider extends StatefulWidget {
  const GaplessPrefetchSlider({Key? key}) : super(key: key);

  @override
  State<GaplessPrefetchSlider> createState() => _GaplessPrefetchSliderState();
}

class _GaplessPrefetchSliderState extends State<GaplessPrefetchSlider>
    with SingleTickerProviderStateMixin {
  static const String _prefKey = 'gapless_prefetch_seconds';
  static const double _min = 10;
  static const double _max = 20;

  double _seconds = 15; // default 15s
  bool _loaded = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadPref();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefKey);
    if (mounted) {
      setState(() {
        _seconds = (saved ?? 15).clamp(_min, _max);
        _loaded = true;
      });
    }
    // Push to handler on load
    // getAudioHandler()?.setPreFetchWindow(Duration(seconds: _seconds.toInt()));
  }

  Future<void> _onChanged(double val) async {
    setState(() => _seconds = val);

    // Pulse the badge
    _pulseController.forward().then((_) => _pulseController.reverse());

    // Update handler live
    // getAudioHandler()?.setPreFetchWindow(Duration(seconds: val.toInt()));
  }

  Future<void> _onChangeEnd(double val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, val);
    print('💾 [GaplessSlider] Saved prefetch: ${val.toInt()}s');
  }

  /// Label shown inside the track at each stop
  String _qualityLabel(double s) {
    if (s <= 11) return 'Fast\nNetwork';
    if (s <= 14) return 'Good\nNetwork';
    if (s <= 17) return 'Average\nNetwork';
    return 'Slow\nNetwork';
  }

  Color _accentColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final accent = _accentColor(context);
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
        // ── Header row ───────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gapless playback',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Pre-fetch next song URL before current ends',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: textSecondary),
                  ),
                ],
              ),
            ),

            // ── Animated seconds badge ────────────────────────────────────
            ScaleTransition(
              scale: _pulseAnim,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withOpacity(0.35), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 13, color: accent),
                    const SizedBox(width: 3),
                    Text(
                      '${_seconds.toInt()}s',
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Slider ───────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
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
                  valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
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
                  divisions: 10, // steps of 1s
                  label: '${_seconds.toInt()}s before end',
                  onChanged: _onChanged,
                  onChangeEnd: _onChangeEnd,
                ),
              ),

              // ── Min / Max labels ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '10s',
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '20s',
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

        const SizedBox(height: 10),

        // ── Context hint ─────────────────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _HintChip(
            key: ValueKey(_seconds.toInt()),
            label: _qualityLabel(_seconds),
            icon: _seconds <= 12
                ? Icons.network_wifi
                : _seconds <= 15
                ? Icons.network_wifi_3_bar
                : Icons.network_wifi_2_bar,
            color: accent,
          ),
        ),
      ],
    );
  }
}

// ── Small hint chip ───────────────────────────────────────────────────────────
class _HintChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _HintChip({
    Key? key,
    required this.label,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Convert newline label to single-line
    final flat = label.replaceAll('\n', ' ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color.withOpacity(0.75)),
        const SizedBox(width: 5),
        Text(
          'Recommended for $flat',
          style: TextStyle(
            fontSize: 11.5,
            color: color.withOpacity(0.75),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
