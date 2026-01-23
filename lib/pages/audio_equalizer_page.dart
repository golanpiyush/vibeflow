// lib/pages/audio_equalizer_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibeflow/utils/audio_session_bridge.dart';

class AudioEqualizerPage extends StatefulWidget {
  const AudioEqualizerPage({Key? key}) : super(key: key);

  @override
  State<AudioEqualizerPage> createState() => _AudioEqualizerPageState();
}

class _AudioEqualizerPageState extends State<AudioEqualizerPage> {
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

  // Replace _initializeAudioEffects with this improved version:
  Future<void> _initializeAudioEffects() async {
    try {
      print('🎛️ [EQ] Starting initialization...');

      // Get audio session ID
      final sessionId = await AudioSessionBridge.getAudioSessionId();
      print('🎛️ [EQ] Got session ID: $sessionId');

      // Initialize effects
      final initialized = await _channel.invokeMethod<bool>(
        'initializeEffects',
        {'sessionId': sessionId ?? 0},
      );

      print('🎛️ [EQ] Initialize result: $initialized');

      if (initialized == true) {
        // Load current settings (which includes saved settings from SharedPreferences)
        await _loadCurrentSettings();

        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
        print('✅ [EQ] Audio effects initialized and loaded saved settings');
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

  // Update _loadCurrentSettings to handle null values:
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

          // Load EQ bands
          if (_eqBandCount > 0) {
            _eqBands = List.generate(_eqBandCount, (i) => 0.0);
            // Try to load individual band values if available
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
        _showSuccessSnackbar('Applied $presetName preset');
      }
    } catch (e) {
      debugPrint('Error applying preset: $e');
      _showErrorSnackbar('Failed to apply preset');
    }
  }

  Future<void> _setBassBoost(double value) async {
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': value.toInt()});
      setState(() {
        _bassBoost = value;
        _selectedPreset = 'Custom';
      });
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
    } catch (e) {
      debugPrint('Error setting EQ band: $e');
    }
  }

  Future<void> _resetAllEffects() async {
    try {
      await _channel.invokeMethod('resetAllEffects');
      await _loadCurrentSettings();
      setState(() {
        _selectedPreset = 'Normal';
      });
      _showSuccessSnackbar('All effects reset');
    } catch (e) {
      debugPrint('Error resetting effects: $e');
      _showErrorSnackbar('Failed to reset effects');
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio Equalizer'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Equalizer'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _resetAllEffects,
            tooltip: 'Reset All',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Presets
          _buildPresetsSection(),

          const SizedBox(height: 24),

          // Equalizer Bands
          _buildEqualizerSection(),

          const SizedBox(height: 24),

          // Bass Boost
          _buildEffectCard(
            title: 'Bass Boost',
            icon: Icons.graphic_eq_rounded,
            value: _bassBoost,
            max: 1000,
            onChanged: _setBassBoost,
            color: Colors.deepPurple,
          ),

          const SizedBox(height: 16),

          // Loudness Enhancer
          _buildEffectCard(
            title: 'Loudness',
            icon: Icons.volume_up_rounded,
            value: _loudnessEnhancer,
            max: 1000,
            onChanged: _setLoudnessEnhancer,
            color: Colors.orange,
          ),

          const SizedBox(height: 16),

          // Reverb
          _buildEffectCard(
            title: 'Reverb',
            icon: Icons.surround_sound_rounded,
            value: _reverbLevel,
            max: 100,
            onChanged: _setReverbLevel,
            color: Colors.teal,
          ),

          const SizedBox(height: 16),

          // Audio Balance
          _buildBalanceCard(),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
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

  Widget _buildEqualizerSection() {
    final bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
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
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.equalizer_rounded,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '5-Band Equalizer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        Text(
                          '${(_eqBands[index] / 100).toStringAsFixed(1)}dB',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
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
              const Text(
                'Audio Balance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              const Text('L', style: TextStyle(fontWeight: FontWeight.bold)),
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
              const Text('R', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              const Icon(Icons.volume_up, size: 20, color: Colors.indigo),
            ],
          ),
        ],
      ),
    );
  }
}
