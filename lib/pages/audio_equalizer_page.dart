// lib/pages/audio_equalizer_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/utils/audio_session_bridge.dart';
import 'package:vibeflow/utils/theme_provider.dart';

class AudioEqualizerPage extends ConsumerStatefulWidget {
  const AudioEqualizerPage({Key? key}) : super(key: key);

  @override
  ConsumerState<AudioEqualizerPage> createState() => _AudioEqualizerPageState();
}

class _AudioEqualizerPageState extends ConsumerState<AudioEqualizerPage> {
  static const MethodChannel _channel = MethodChannel('audio_effects');

  // Audio effects values
  double _bassBoost = 0.0;
  double _loudnessEnhancer = 0.0;
  double _reverbLevel = 0.0;
  double _audioBalance = 0.5;

  // Equalizer bands (5-band)
  List<double> _eqBands = [0.0, 0.0, 0.0, 0.0, 0.0];
  int _eqBandCount = 5;

  // Presets
  String _selectedPreset = 'Normal';
  final List<String> _availablePresets = [
    'Normal',
    'Rock',
    'Pop',
    'Jazz',
    'Classical',
    'Bass Boost',
    'Vocal',
  ];

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeAudioEffects();
  }

  Future<void> _initializeAudioEffects() async {
    try {
      print('🎛️ [EQ] Starting initialization...');

      final sessionId = await AudioSessionBridge.getAudioSessionId();
      print('🎛️ [EQ] Got session ID: $sessionId');

      final initialized = await _channel.invokeMethod<bool>(
        'initializeEffects',
        {'sessionId': sessionId ?? 0},
      );

      print('🎛️ [EQ] Initialize result: $initialized');

      if (initialized == true) {
        // ✅ FIX: Load saved settings FIRST
        await _loadSavedSettings();

        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
        print('✅ [EQ] Audio effects initialized with saved settings');
      } else {
        throw Exception('Initialize returned false');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [EQ] Error initializing audio effects: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        _showErrorSnackbar('Failed to initialize: ${e.toString()}');
      }
    }
  }

  // ✅ NEW: Load settings from SharedPreferences
  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _bassBoost = prefs.getDouble('eq_bass_boost') ?? 0.0;
        _loudnessEnhancer = prefs.getDouble('eq_loudness') ?? 0.0;
        _reverbLevel = prefs.getDouble('eq_reverb') ?? 0.0;
        _audioBalance = prefs.getDouble('eq_balance') ?? 0.5;
        _selectedPreset = prefs.getString('eq_preset') ?? 'Normal';

        // Load EQ bands
        for (int i = 0; i < _eqBandCount; i++) {
          _eqBands[i] = prefs.getDouble('eq_band_$i') ?? 0.0;
        }
      });

      // ✅ FIX: Apply saved settings to native side immediately
      await _applySavedSettingsToNative();

      print('✅ [EQ] Loaded saved settings from storage');
      print(
        '   Bass: $_bassBoost, Loudness: $_loudnessEnhancer, Preset: $_selectedPreset',
      );
    } catch (e) {
      debugPrint('❌ [EQ] Error loading saved settings: $e');
    }
  }

  // ✅ NEW: Apply saved settings to native audio effects
  Future<void> _applySavedSettingsToNative() async {
    try {
      // Apply bass boost
      if (_bassBoost != 0.0) {
        await _channel.invokeMethod('setBassBoost', {
          'strength': _bassBoost.toInt(),
        });
      }

      // Apply loudness enhancer
      if (_loudnessEnhancer != 0.0) {
        await _channel.invokeMethod('setLoudnessEnhancer', {
          'gain': _loudnessEnhancer.toInt(),
        });
      }

      // Apply reverb
      if (_reverbLevel != 0.0) {
        await _channel.invokeMethod('setEnvironmentalReverbLevel', {
          'level': _reverbLevel.toInt(),
        });
      }

      // Apply audio balance
      if (_audioBalance != 0.5) {
        await _channel.invokeMethod('setAudioBalance', {
          'balance': _audioBalance,
        });
      }

      // Apply EQ bands
      for (int i = 0; i < _eqBandCount; i++) {
        if (_eqBands[i] != 0.0) {
          await _channel.invokeMethod('setEqualizerBand', {
            'band': i,
            'level': _eqBands[i].toInt(),
          });
        }
      }

      print('✅ [EQ] Applied all saved settings to native');
    } catch (e) {
      debugPrint('❌ [EQ] Error applying saved settings: $e');
    }
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final settings = await _channel.invokeMethod<Map>('getCurrentSettings');
      if (settings != null && mounted) {
        setState(() {
          _bassBoost = (settings['bassBoost'] ?? 0).toDouble();
          _loudnessEnhancer = (settings['loudnessEnhancer'] ?? 0).toDouble();
          _reverbLevel = (settings['environmentalReverbLevel'] ?? 0).toDouble();
          _audioBalance = (settings['audioBalance'] ?? 0.5).toDouble();
          _eqBandCount = settings['equalizerBandCount'] ?? 5;

          if (_eqBandCount > 0) {
            _eqBands = List.generate(_eqBandCount, (i) => 0.0);
            for (int i = 0; i < _eqBandCount; i++) {
              if (settings.containsKey('eq_band_$i')) {
                _eqBands[i] = (settings['eq_band_$i'] ?? 0).toDouble();
              }
            }
          }
        });
        print(
          '✅ [EQ] Loaded settings - Bass: $_bassBoost, Loudness: $_loudnessEnhancer',
        );
      }
    } catch (e) {
      debugPrint('❌ [EQ] Error loading settings: $e');
    }
  }

  Future<void> _applyPreset(String presetName) async {
    try {
      final success = await _channel.invokeMethod<bool>('applyPreset', {
        'presetName': presetName,
      });

      if (success == true) {
        await _loadCurrentSettings();
        setState(() {
          _selectedPreset = presetName;
        });

        // ✅ FIX: Save preset to storage
        await _savePresetToStorage(presetName);

        _showSuccessSnackbar('Applied $presetName preset');
      }
    } catch (e) {
      debugPrint('Error applying preset: $e');
      _showErrorSnackbar('Failed to apply preset');
    }
  }

  // ✅ NEW: Save preset to storage
  Future<void> _savePresetToStorage(String presetName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('eq_preset', presetName);
    } catch (e) {
      debugPrint('❌ [EQ] Error saving preset: $e');
    }
  }

  Future<void> _setBassBoost(double value) async {
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': value.toInt()});
      setState(() {
        _bassBoost = value;
        _selectedPreset = 'Custom';
      });

      // ✅ FIX: Save to storage
      await _saveSettingToStorage('eq_bass_boost', value);
      await _savePresetToStorage('Custom');
    } catch (e) {
      debugPrint('Error setting bass boost: $e');
    }
  }

  Future<void> _setLoudnessEnhancer(double value) async {
    try {
      await _channel.invokeMethod('setLoudnessEnhancer', {
        'gain': value.toInt(),
      });
      setState(() {
        _loudnessEnhancer = value;
        _selectedPreset = 'Custom';
      });

      // ✅ FIX: Save to storage
      await _saveSettingToStorage('eq_loudness', value);
      await _savePresetToStorage('Custom');
    } catch (e) {
      debugPrint('Error setting loudness enhancer: $e');
    }
  }

  Future<void> _setReverbLevel(double value) async {
    try {
      await _channel.invokeMethod('setEnvironmentalReverbLevel', {
        'level': value.toInt(),
      });
      setState(() {
        _reverbLevel = value;
        _selectedPreset = 'Custom';
      });

      // ✅ FIX: Save to storage
      await _saveSettingToStorage('eq_reverb', value);
      await _savePresetToStorage('Custom');
    } catch (e) {
      debugPrint('Error setting reverb: $e');
    }
  }

  Future<void> _setAudioBalance(double value) async {
    try {
      await _channel.invokeMethod('setAudioBalance', {'balance': value});
      setState(() {
        _audioBalance = value;
      });

      // ✅ FIX: Save to storage
      await _saveSettingToStorage('eq_balance', value);
    } catch (e) {
      debugPrint('Error setting audio balance: $e');
    }
  }

  Future<void> _setEqualizerBand(int band, double value) async {
    try {
      await _channel.invokeMethod('setEqualizerBand', {
        'band': band,
        'level': value.toInt(),
      });
      setState(() {
        _eqBands[band] = value;
        _selectedPreset = 'Custom';
      });

      // ✅ FIX: Save to storage
      await _saveSettingToStorage('eq_band_$band', value);
      await _savePresetToStorage('Custom');
    } catch (e) {
      debugPrint('Error setting EQ band: $e');
    }
  }

  // ✅ NEW: Helper to save individual settings
  Future<void> _saveSettingToStorage(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (e) {
      debugPrint('❌ [EQ] Error saving $key: $e');
    }
  }

  Future<void> _resetAllEffects() async {
    try {
      await _channel.invokeMethod('resetAllEffects');
      await _loadCurrentSettings();
      setState(() {
        _selectedPreset = 'Normal';
      });

      // ✅ FIX: Clear storage
      await _clearStoredSettings();

      _showSuccessSnackbar('All effects reset');
    } catch (e) {
      debugPrint('Error resetting effects: $e');
      _showErrorSnackbar('Failed to reset effects');
    }
  }

  // ✅ NEW: Clear all stored EQ settings
  Future<void> _clearStoredSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('eq_bass_boost');
      await prefs.remove('eq_loudness');
      await prefs.remove('eq_reverb');
      await prefs.remove('eq_balance');
      await prefs.remove('eq_preset');

      for (int i = 0; i < _eqBandCount; i++) {
        await prefs.remove('eq_band_$i');
      }

      print('✅ [EQ] Cleared all stored settings');
    } catch (e) {
      debugPrint('❌ [EQ] Error clearing storage: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Define theme-aware colors
    final backgroundColor = colorScheme.surface;
    final surfaceColor = colorScheme.surfaceContainerHighest;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurface.withOpacity(0.7);
    final textMuted = colorScheme.onSurface.withOpacity(0.5);
    final borderColor = colorScheme.outline.withOpacity(0.2);
    final iconColor = colorScheme.onSurface;

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: Text(
            'Audio Equalizer',
            style: theme.textTheme.titleLarge?.copyWith(color: textPrimary),
          ),
          centerTitle: true,
          backgroundColor: surfaceColor,
          elevation: 0,
        ),
        body: Center(
          child: CircularProgressIndicator(
            color: colorScheme.primary,
            backgroundColor: surfaceColor,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Audio Equalizer',
          style: theme.textTheme.titleLarge?.copyWith(color: textPrimary),
        ),
        centerTitle: true,
        backgroundColor: surfaceColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: iconColor),
            onPressed: _resetAllEffects,
            tooltip: 'Reset All',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPresetsSection(),
          const SizedBox(height: 24),
          _buildKnobsSection(),
          const SizedBox(height: 24),
          _buildEqualizerSection(),
          const SizedBox(height: 24),
          _buildEffectCard(
            title: 'Loudness',
            icon: Icons.volume_up_rounded,
            value: _loudnessEnhancer,
            max: 1000,
            onChanged: _setLoudnessEnhancer,
            color: Colors.orange,
          ),
          const SizedBox(height: 16),
          _buildBalanceCard(),
          const SizedBox(height: AppSpacing.fourxxxl),
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary.withOpacity(0.8), colorScheme.primary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune_rounded, color: colorScheme.onPrimary),
              ),
              const SizedBox(width: 12),
              Text(
                'Presets',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availablePresets.map((preset) {
              final isSelected = _selectedPreset == preset;
              return GestureDetector(
                onTap: () => _applyPreset(preset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onPrimary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : colorScheme.onPrimary.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    preset,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onPrimary,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildKnobsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline.withOpacity(0.2);
    final textPrimary = colorScheme.onSurface; // ADD THIS LINE
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: _buildKnob(
              title: 'Bass',
              value: _bassBoost,
              max: 1000,
              onChanged: _setBassBoost,
              color: Colors.deepPurple, // Keep functional color
              icon: Icons.graphic_eq_rounded,
              textColor: textPrimary, // Add theme-aware text color
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildKnob(
              title: 'Reverb',
              value: _reverbLevel,
              max: 100,
              onChanged: _setReverbLevel,
              color: Colors.teal, // Keep functional color
              icon: Icons.surround_sound_rounded,
              textColor: textPrimary, // Add theme-aware text color
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKnob({
    required String title,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
    required Color color,
    required IconData icon,
    required Color textColor, // Add this parameter
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final percentage = (value / max * 100).toInt();

    return Column(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: textColor, // Use passed textColor
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onPanUpdate: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final center = Offset(box.size.width / 2, box.size.height / 2);
            final angle = math.atan2(
              details.localPosition.dy - center.dy,
              details.localPosition.dx - center.dx,
            );

            var normalizedAngle = (angle + math.pi / 2) % (2 * math.pi);
            if (normalizedAngle < 0) normalizedAngle += 2 * math.pi;

            final range = (3 * math.pi / 2);
            final offset = math.pi / 8;

            var adjustedAngle = normalizedAngle - offset;
            if (adjustedAngle < 0) adjustedAngle += 2 * math.pi;

            final normalized = (adjustedAngle / range).clamp(0.0, 1.0);
            onChanged(normalized * max);
          },
          child: SizedBox(
            width: 140,
            height: 140,
            child: CustomPaint(
              painter: KnobPainter(
                value: value,
                max: max,
                color: color,
                backgroundColor: colorScheme.surfaceContainerHighest,
                trackColor: colorScheme.outline.withOpacity(0.2),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      '$percentage%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: textColor, // Use passed textColor
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEqualizerSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline.withOpacity(0.2);
    final bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.equalizer_rounded, color: Colors.green),
              ),
              const SizedBox(width: 12),
              Text(
                '5-Band Equalizer',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_eqBandCount, (index) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 32,
                                activeTrackColor: Colors.green,
                                inactiveTrackColor: colorScheme.outline
                                    .withOpacity(0.2),
                                thumbColor: Colors.green,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                                overlayColor: Colors.green.withOpacity(0.2),
                              ),
                              child: Slider(
                                value: _eqBands[index],
                                min: -1500,
                                max: 1500,
                                onChanged: (value) =>
                                    _setEqualizerBand(index, value),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          bandLabels[index],
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '${(_eqBands[index] / 100).toStringAsFixed(1)}dB',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectCard({
    required String title,
    required IconData icon,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline.withOpacity(0.2);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${(value / max * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withOpacity(0.2),
              thumbColor: color,
              overlayColor: color.withOpacity(0.2),
              valueIndicatorColor: color,
            ),
            child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline.withOpacity(0.2);
    final balanceColor = Colors.indigo;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: balanceColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.balance_rounded, color: balanceColor),
              ),
              const SizedBox(width: 12),
              Text(
                'Audio Balance',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                _audioBalance == 0.5
                    ? 'Center'
                    : _audioBalance < 0.5
                    ? 'Left ${((0.5 - _audioBalance) * 200).toStringAsFixed(0)}%'
                    : 'Right ${((_audioBalance - 0.5) * 200).toStringAsFixed(0)}%',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: balanceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.volume_up, size: 20, color: balanceColor),
              const SizedBox(width: 8),
              Text(
                'L',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: balanceColor,
                    inactiveTrackColor: balanceColor.withOpacity(0.2),
                    thumbColor: balanceColor,
                    overlayColor: balanceColor.withOpacity(0.2),
                    valueIndicatorColor: balanceColor,
                  ),
                  child: Slider(
                    value: _audioBalance,
                    min: 0.0,
                    max: 1.0,
                    onChanged: _setAudioBalance,
                  ),
                ),
              ),
              Text(
                'R',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.volume_up, size: 20, color: balanceColor),
            ],
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// Custom Painter for Knob
class KnobPainter extends CustomPainter {
  final double value;
  final double max;
  final Color color;
  final Color backgroundColor;
  final Color trackColor;

  KnobPainter({
    required this.value,
    required this.max,
    required this.color,
    required this.backgroundColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Track (full circle)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 5 / 8,
      math.pi * 3 / 2,
      false,
      trackPaint,
    );

    // Active arc
    final activePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (value / max) * (math.pi * 3 / 2);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 5 / 8,
      sweepAngle,
      false,
      activePaint,
    );

    // Knob indicator (pointer)
    final angle = -math.pi * 5 / 8 + sweepAngle;
    final indicatorStart = Offset(
      center.dx + (radius - 20) * math.cos(angle),
      center.dy + (radius - 20) * math.sin(angle),
    );
    final indicatorEnd = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );

    final indicatorPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(indicatorStart, indicatorEnd, indicatorPaint);

    // Center dot
    final centerDotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, centerDotPaint);
  }

  @override
  bool shouldRepaint(KnobPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.max != max ||
      oldDelegate.color != color;
}
