import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';
import 'package:vibeflow/utils/secure_storage.dart';

class AuthService {
  final SupabaseClient _supabase;
  final SecureStorageService _secureStorage;

  AuthService(this._supabase, this._secureStorage);

  // Sign in with email and password
  Future<void> signIn({required String email, required String password}) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Login failed');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // Get email by username
  Future<String?> getEmailByUsername(String username) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('email')
          .eq('userid', username)
          .maybeSingle();

      if (response == null) return null;
      return response['email'] as String?;
    } catch (e) {
      print('Error getting email by username: $e');
      return null;
    }
  }

  // ✅ UPDATED: Sign out with audio and tracking cleanup
  Future<void> signOut() async {
    try {
      print('🛑 [AUTH] ========== SIGN OUT STARTED ==========');

      // ✅ Step 1: Stop audio playback and tracking FIRST
      try {
        final audioHandler = await AudioService.init(
          builder: () => BackgroundAudioHandler(),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.vibeflow.audio',
            androidNotificationChannelName: 'VibeFlow Audio',
            androidNotificationOngoing: true,
          ),
        );

        if (audioHandler != null) {
          print('🛑 [AUTH] Stopping audio handler...');
          await audioHandler
              .stop(); // This calls stop() which stops tracking + player
          print('✅ [AUTH] Audio handler stopped');
        }
      } catch (e) {
        print('⚠️ [AUTH] Error stopping audio (continuing): $e');
        // Continue with logout even if audio stop fails
      }

      // ✅ Step 2: Clear secure storage
      print('🗑️ [AUTH] Clearing user data...');
      await _secureStorage.clearAllUserData();
      print('✅ [AUTH] User data cleared');

      // ✅ Step 3: Sign out from Supabase
      print('🔓 [AUTH] Signing out from Supabase...');
      await _supabase.auth.signOut();
      print('✅ [AUTH] Supabase sign out complete');

      print('✅ [AUTH] ========== SIGN OUT COMPLETED ==========');
    } catch (e) {
      print('❌ [AUTH] ========== SIGN OUT ERROR ==========');
      print('   Error: $e');
      rethrow;
    }
  }

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Check if user is logged in
  bool get isLoggedIn => _supabase.auth.currentUser != null;
}

// ✅ UPDATED: Provider with SecureStorageService dependency
final authServiceProvider = Provider<AuthService>((ref) {
  final supabase = Supabase.instance.client;
  final secureStorage = SecureStorageService();
  return AuthService(supabase, secureStorage);
});

// Auth state provider
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});
