// Services
import 'package:supabase_flutter/supabase_flutter.dart';

class AccessCodeService {
  final SupabaseClient _supabase;

  AccessCodeService(this._supabase);

  Future<AccessCodeValidationResult> validateCode(String code) async {
    try {
      final normalizedCode = code.trim().toLowerCase();

      final response = await _supabase
          .from('access_codes')
          .select('*')
          .eq('code', normalizedCode)
          .single();

      if (response['is_active'] != true) {
        return AccessCodeValidationResult.invalid('Access code is disabled');
      }

      final expiresAt = response['expires_at'];
      if (expiresAt != null &&
          DateTime.parse(expiresAt).isBefore(DateTime.now())) {
        return AccessCodeValidationResult.invalid('Access code has expired');
      }

      final maxUses = response['max_uses'];
      final usedCount = response['used_count'];
      if (maxUses != null && usedCount >= maxUses) {
        return AccessCodeValidationResult.invalid(
          'Access code usage limit reached',
        );
      }

      return AccessCodeValidationResult.valid();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        return AccessCodeValidationResult.invalid('Invalid access code');
      }
      return AccessCodeValidationResult.invalid(
        'Validation failed: ${e.message}',
      );
    } catch (e) {
      return AccessCodeValidationResult.invalid(
        'Connection error. Please try again.',
      );
    }
  }

  Future<bool> checkIfUserHasAccessCode(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('access_code_used')
          .eq('id', userId)
          .maybeSingle();

      return response != null && response['access_code_used'] != null;
    } catch (e) {
      return false;
    }
  }
}

class AccessCodeValidationResult {
  final bool isValid;
  final String? errorMessage;

  const AccessCodeValidationResult._({
    required this.isValid,
    this.errorMessage,
  });

  factory AccessCodeValidationResult.valid() {
    return const AccessCodeValidationResult._(isValid: true);
  }

  factory AccessCodeValidationResult.invalid(String error) {
    return AccessCodeValidationResult._(isValid: false, errorMessage: error);
  }
}
