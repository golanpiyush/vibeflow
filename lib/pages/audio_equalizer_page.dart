// lib/pages/audio_equalizer_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  void _showSuccessSnackbar(String message) {
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
        backgroundColor: const Color(0xFF4CAF50),
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
        backgroundColor: const Color(0xFFFF4458),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: Text('Audio Equalizer', style: TextStyle(color: textColor)),
          centerTitle: true,
          backgroundColor: bgColor,
          iconTheme: IconThemeData(color: textColor),
        ),
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Audio Equalizer', style: TextStyle(color: textColor)),
        centerTitle: true,
        backgroundColor: bgColor,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: textColor),
            onPressed: _resetAllEffects,
            tooltip: 'Reset All',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Presets
          _buildPresetsSection(surfaceColor, textColor),

          const SizedBox(height: 24),

          // Bass and Reverb Knobs
          _buildKnobsSection(surfaceColor, textColor),

          const SizedBox(height: 24),

          // Equalizer Bands
          _buildEqualizerSection(surfaceColor, textColor),

          const SizedBox(height: 24),

          // Loudness Enhancer
          _buildEffectCard(
            title: 'Loudness',
            icon: Icons.volume_up_rounded,
            value: _loudnessEnhancer,
            max: 1000,
            onChanged: _setLoudnessEnhancer,
            color: Colors.orange,
            surfaceColor: surfaceColor,
            textColor: textColor,
          ),

          const SizedBox(height: 16),

          // Audio Balance
          _buildBalanceCard(surfaceColor, textColor),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPresetsSection(Color surfaceColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
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
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'Presets',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
                        ? Colors.white
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : Colors.white.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    preset,
                    style: TextStyle(
                      color: isSelected ? Colors.blue.shade700 : Colors.white,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 14,
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

  Widget _buildKnobsSection(Color surfaceColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.1)),
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
              color: Colors.deepPurple,
              icon: Icons.graphic_eq_rounded,
              textColor: textColor,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildKnob(
              title: 'Reverb',
              value: _reverbLevel,
              max: 100,
              onChanged: _setReverbLevel,
              color: Colors.teal,
              icon: Icons.surround_sound_rounded,
              textColor: textColor,
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
    required Color textColor,
  }) {
    final percentage = (value / max * 100).toInt();

    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
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

            // Convert angle to value (0 to max)
            var normalizedAngle = (angle + math.pi / 2) % (2 * math.pi);
            if (normalizedAngle < 0) normalizedAngle += 2 * math.pi;

            // Map to 0-1 range (270 degrees of rotation)
            final range = (3 * math.pi / 2); // 270 degrees
            final offset = math.pi / 8; // 22.5 degrees offset

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
                textColor: textColor,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
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

  Widget _buildEqualizerSection(Color surfaceColor, Color textColor) {
    final bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.1)),
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
                child: Icon(
                  Icons.equalizer_rounded,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '5-Band Equalizer',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
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
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                              ),
                              child: Slider(
                                value: _eqBands[index],
                                min: -1500,
                                max: 1500,
                                onChanged: (value) =>
                                    _setEqualizerBand(index, value),
                                activeColor: Colors.green,
                                inactiveColor: Colors.grey.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          bandLabels[index],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textColor.withOpacity(0.6),
                          ),
                        ),
                        Text(
                          '${(_eqBands[index] / 100).toStringAsFixed(1)}dB',
                          style: TextStyle(
                            fontSize: 10,
                            color: textColor.withOpacity(0.4),
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
    required Color surfaceColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.1)),
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const Spacer(),
              Text(
                '${(value / max * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
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
            ),
            child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(Color surfaceColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.balance_rounded, color: Colors.indigo),
              ),
              const SizedBox(width: 12),
              Text(
                'Audio Balance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const Spacer(),
              Text(
                _audioBalance == 0.5
                    ? 'Center'
                    : _audioBalance < 0.5
                    ? 'Left ${((0.5 - _audioBalance) * 200).toStringAsFixed(0)}%'
                    : 'Right ${((_audioBalance - 0.5) * 200).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.volume_up, size: 20, color: Colors.indigo),
              const SizedBox(width: 8),
              Text(
                'L',
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: Colors.indigo,
                    inactiveTrackColor: Colors.indigo.withOpacity(0.2),
                    thumbColor: Colors.indigo,
                    overlayColor: Colors.indigo.withOpacity(0.2),
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
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.volume_up, size: 20, color: Colors.indigo),
            ],
          ),
        ],
      ),
    );
  }
}

// Custom Painter for Knob
class KnobPainter extends CustomPainter {
  final double value;
  final double max;
  final Color color;
  final Color textColor;

  KnobPainter({
    required this.value,
    required this.max,
    required this.color,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background circle
    final bgPaint = Paint()
      ..color = textColor.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Track (full circle)
    final trackPaint = Paint()
      ..color = textColor.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 5 / 8, // Start at 225 degrees
      math.pi * 3 / 2, // 270 degrees
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
