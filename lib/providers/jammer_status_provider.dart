// ============================================================================
// FILE: lib/providers/jammer_status_provider.dart
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/database/access_code_service.dart';
import 'package:vibeflow/database/profile_service.dart';

// StateNotifier for managing jammer status
class JammerStatusNotifier extends StateNotifier<AsyncValue<bool>> {
  JammerStatusNotifier() : super(const AsyncValue.loading()) {
    _loadJammerStatus();
  }

  Future<void> _loadJammerStatus() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        state = const AsyncValue.data(false);
        return;
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select('is_jammer_on')
          .eq('id', user.id)
          .single();

      final isJammerOn = response['is_jammer_on'] ?? false;
      state = AsyncValue.data(isJammerOn);
      print('✅ [JAMMER] Status loaded: $isJammerOn');
    } catch (e) {
      print('❌ [JAMMER] Error loading status: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  // Method to refresh the jammer status
  Future<void> refresh() async {
    print('🔄 [JAMMER] Refreshing status...');
    state = const AsyncValue.loading();
    await _loadJammerStatus();
  }

  // Method to update jammer status locally (optimistic update)
  void updateStatus(bool isEnabled) {
    print('🎵 [JAMMER] Updating status to: $isEnabled');
    state = AsyncValue.data(isEnabled);
  }
}

// Provider - THIS IS THE CORRECT ONE TO USE
final jammerStatusProvider =
    StateNotifierProvider<JammerStatusNotifier, AsyncValue<bool>>((ref) {
      return JammerStatusNotifier();
    });

// ========================================================================================================================
// ========================================================================================================================
// ========================================================================================================================

// Add this to your providers file or create a new one
final shouldShowJammerProvider = FutureProvider<bool>((ref) async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser == null) return false;

  final profileService = ref.read(profileServiceProvider);
  final accessCodeService = ref.read(accessCodeServiceProvider);

  // Check both conditions
  final hasAccessCode = await accessCodeService.checkIfUserHasAccessCode(
    currentUser.id,
  );
  if (!hasAccessCode) return false;

  final profile = await profileService.getUserProfileById(currentUser.id);
  if (profile == null) return false;

  final isBetaTester = profile['is_beta_tester'] == true;

  return hasAccessCode && isBetaTester;
});

// Also create the access code service provider
final accessCodeServiceProvider = Provider<AccessCodeService>((ref) {
  final supabase = Supabase.instance.client;
  return AccessCodeService(supabase);
});
