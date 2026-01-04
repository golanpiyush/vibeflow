// lib/services/haptic_feedback_service.dart

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Service for managing haptic feedback and vibrations
class HapticFeedbackService {
  static final HapticFeedbackService _instance =
      HapticFeedbackService._internal();
  factory HapticFeedbackService() => _instance;
  HapticFeedbackService._internal();

  bool _hasVibrator = false;
  bool _isInitialized = false;

  /// Initialize the service and check for vibration support
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _hasVibrator = await Vibration.hasVibrator() ?? false;
      _isInitialized = true;
      print('✅ [HapticFeedback] Initialized - Vibrator: $_hasVibrator');
    } catch (e) {
      print('⚠️ [HapticFeedback] Initialization failed: $e');
      _hasVibrator = false;
      _isInitialized = true;
    }
  }

  // ============================================================================
  // AUDIO ERROR PATTERNS
  // ============================================================================

  /// Double vibration pattern for audio URL errors (na-na)
  /// Pattern: [vibrate, pause, vibrate]
  /// Duration: 100ms, 150ms pause, 100ms
  Future<void> vibrateAudioError() async {
    await _ensureInitialized();

    if (!_hasVibrator) {
      print('⚠️ [HapticFeedback] No vibrator available');
      return;
    }

    try {
      print('📳 [HapticFeedback] Audio error pattern: na-na');

      // Pattern: [wait, vibrate, wait, vibrate]
      // Times in milliseconds
      await Vibration.vibrate(
        pattern: [
          0,
          100,
          150,
          100,
        ], // wait 0ms, vibrate 100ms, wait 150ms, vibrate 100ms
        intensities: [0, 128, 0, 128], // Medium intensity
      );
    } catch (e) {
      print('❌ [HapticFeedback] Vibration failed: $e');
      // Fallback to system haptic
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      HapticFeedback.heavyImpact();
    }
  }

  /// Triple vibration pattern for critical errors (na-na-na)
  /// Pattern: [vibrate, pause, vibrate, pause, vibrate]
  Future<void> vibrateCriticalError() async {
    await _ensureInitialized();

    if (!_hasVibrator) return;

    try {
      print('📳 [HapticFeedback] Critical error: na-na-na (pause) na-na');

      await Vibration.vibrate(
        pattern: [
          0, // start immediately
          100, // na
          120,
          100, // na
          120,
          100, // na
          1000, // 🔕 1 second pause
          100, // na
          120,
          100, // na
        ],
        intensities: [0, 200, 0, 200, 0, 200, 0, 500, 0, 500],
      );
    } catch (e) {
      print('❌ [HapticFeedback] Vibration failed: $e');

      // Fallback: approximate pattern
      for (int i = 0; i < 3; i++) {
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 120));
      }

      await Future.delayed(const Duration(seconds: 1));

      for (int i = 0; i < 2; i++) {
        HapticFeedback.heavyImpact();
        if (i < 1) {
          await Future.delayed(const Duration(milliseconds: 120));
        }
      }
    }
  }

  /// Network error pattern (quick double tap)
  Future<void> vibrateNetworkError() async {
    await _ensureInitialized();

    if (!_hasVibrator) return;

    try {
      print('📳 [HapticFeedback] Network error pattern');

      await Vibration.vibrate(
        pattern: [0, 80, 100, 80],
        intensities: [0, 150, 0, 150],
      );
    } catch (e) {
      print('❌ [HapticFeedback] Vibration failed: $e');
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.mediumImpact();
    }
  }

  // ============================================================================
  // SUCCESS PATTERNS
  // ============================================================================

  /// Success pattern (single strong vibration)
  Future<void> vibrateSuccess() async {
    await _ensureInitialized();

    if (!_hasVibrator) return;

    try {
      print('📳 [HapticFeedback] Success pattern');

      await Vibration.vibrate(duration: 200, amplitude: 180);
    } catch (e) {
      print('❌ [HapticFeedback] Vibration failed: $e');
      HapticFeedback.mediumImpact();
    }
  }

  /// Download complete pattern (ascending vibrations)
  Future<void> vibrateDownloadComplete() async {
    await _ensureInitialized();

    if (!_hasVibrator) return;

    try {
      print('📳 [HapticFeedback] Download complete pattern');

      await Vibration.vibrate(
        pattern: [0, 50, 50, 100, 50, 150],
        intensities: [0, 100, 0, 150, 0, 200],
      );
    } catch (e) {
      print('❌ [HapticFeedback] Vibration failed: $e');
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.heavyImpact();
    }
  }

  // ============================================================================
  // UI FEEDBACK PATTERNS
  // ============================================================================

  /// Light tap for button presses
  Future<void> lightTap() async {
    HapticFeedback.lightImpact();
  }

  /// Medium impact for selections
  Future<void> mediumTap() async {
    HapticFeedback.mediumImpact();
  }

  /// Heavy impact for important actions
  Future<void> heavyTap() async {
    HapticFeedback.heavyImpact();
  }

  /// Selection changed (subtle feedback)
  Future<void> selectionClick() async {
    HapticFeedback.selectionClick();
  }

  /// Long press detected
  Future<void> longPress() async {
    await _ensureInitialized();

    if (!_hasVibrator) {
      HapticFeedback.heavyImpact();
      return;
    }

    try {
      await Vibration.vibrate(duration: 50, amplitude: 150);
    } catch (e) {
      HapticFeedback.heavyImpact();
    }
  }

  // ============================================================================
  // PLAYBACK PATTERNS
  // ============================================================================

  /// Song change pattern (quick pulse)
  Future<void> vibrateSongChange() async {
    await _ensureInitialized();

    if (!_hasVibrator) return;

    try {
      await Vibration.vibrate(duration: 50, amplitude: 100);
    } catch (e) {
      HapticFeedback.lightImpact();
    }
  }

  /// Skip pattern (double quick tap)
  Future<void> vibrateSkip() async {
    await _ensureInitialized();

    if (!_hasVibrator) return;

    try {
      await Vibration.vibrate(
        pattern: [0, 40, 60, 40],
        intensities: [0, 100, 0, 100],
      );
    } catch (e) {
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 60));
      HapticFeedback.lightImpact();
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Custom vibration pattern
  ///
  /// Example:
  /// ```dart
  /// vibrateCustomPattern(
  ///   pattern: [0, 100, 50, 200], // wait, vibrate, wait, vibrate
  ///   intensities: [0, 128, 0, 255], // low, high
  /// );
  ///
  /// ```
  // Future<void> vibrateCustomPattern({
  //   required List<int> pattern,
  //   List<int>? intensities,
  // }) async {
  //   await _ensureInitialized();

  //   if (!_hasVibrator) return;

  //   try {
  //     await Vibration.vibrate(pattern: pattern, intensities: intensities);
  //   } catch (e) {
  //     print('❌ [HapticFeedback] Custom pattern failed: $e');
  //     HapticFeedback.mediumImpact();
  //   }
  // }

  /// Cancel any ongoing vibration
  Future<void> cancel() async {
    try {
      await Vibration.cancel();
    } catch (e) {
      print('⚠️ [HapticFeedback] Cancel failed: $e');
    }
  }

  /// Check if device has vibrator
  bool get hasVibrator => _hasVibrator;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  // ============================================================================
  // PRIVATE METHODS
  // ============================================================================

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
}

// ============================================================================
// EXAMPLES
// ============================================================================


/// Example 2: Download Complete
/// 
/// ```dart
/// if (result.success) {
///   await HapticFeedbackService().vibrateDownloadComplete();
///   _showNotification(title: 'Download Complete');
/// }
/// ```

/// Example 3: Button Taps
/// 
/// ```dart
/// IconButton(
///   icon: Icon(Icons.favorite),
///   onPressed: () {
///     HapticFeedbackService().lightTap();
///     // Handle favorite...
///   },
/// )
/// ```

/// Example 4: Initialize in main.dart
/// 
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   
///   // Initialize haptic feedback
///   await HapticFeedbackService().initialize();
///   
///   runApp(MyApp());
/// }
/// ```