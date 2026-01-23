// lib/services/audio_session_bridge.dart
import 'package:flutter/services.dart';

class AudioSessionBridge {
  static const MethodChannel _channel = MethodChannel('audio_effects');

  static Future<int?> getAudioSessionId() async {
    try {
      final sessionId = await _channel.invokeMethod<int>('getAudioSessionId');
      print('✅ [AudioSession] Got audio session ID: $sessionId');
      return sessionId ?? 0;
    } catch (e) {
      print('❌ [AudioSession] Error getting audio session ID: $e');
      return 0; // Return 0 as fallback (default audio output)
    }
  }
}
