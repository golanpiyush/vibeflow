// lib/services/profile_service.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final SupabaseClient _supabase;

  ProfileService(this._supabase);

  Future<Map<String, dynamic>?> getUserProfileByUserId(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('*')
          .eq('userid', userId.toLowerCase())
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ Error getting user profile: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserProfileById(String id) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ Error getting user profile by id: $e');
      return null;
    }
  }

  /// Create a new profile for a user
  Future<bool> createProfile({
    required String id,
    required String userId,
    required String email,
    required String accessCode,
    required bool hasAgreedToRules,
    String? gender,
    String? profilePicUrl,
  }) async {
    try {
      await _supabase.from('profiles').insert({
        'id': id,
        'userid': userId.toLowerCase(),
        'email': email,
        'access_code_used': accessCode,
        'has_agreed_to_rules': hasAgreedToRules,
        if (gender != null) 'gender': gender,
        if (profilePicUrl != null) 'profile_pic_url': profilePicUrl,
      });

      print('✅ Profile created successfully');
      return true;
    } catch (e) {
      print('❌ Error creating profile: $e');
      return false;
    }
  }

  /// Update existing profile
  Future<void> updateProfile({
    required String userId,
    String? gender,
    String? profilePicUrl,
    bool? hasAgreedToRules,
  }) async {
    try {
      final updates = <String, dynamic>{};

      if (gender != null) updates['gender'] = gender;
      if (profilePicUrl != null) updates['profile_pic_url'] = profilePicUrl;
      if (hasAgreedToRules != null) {
        updates['has_agreed_to_rules'] = hasAgreedToRules;
      }

      if (updates.isNotEmpty) {
        await _supabase.from('profiles').update(updates).eq('id', userId);
        print('✅ Profile updated successfully');
      }
    } catch (e) {
      print('❌ Error updating profile: $e');
      rethrow;
    }
  }

  /// Check if user has agreed to rules
  Future<bool> hasUserAgreedToRules(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('has_agreed_to_rules')
          .eq('id', userId)
          .maybeSingle();

      return response?['has_agreed_to_rules'] ?? false;
    } catch (e) {
      print('❌ Error checking rules agreement: $e');
      return false;
    }
  }

  /// Upload profile picture
  Future<String?> uploadProfilePicture(String userId, String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final fileExt = imagePath.split('.').last;

      final fileName = '$userId.$fileExt';

      await _supabase.storage
          .from('profile-pictures')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$fileExt',
              upsert: true,
            ),
          );

      print('✅ Uploaded: $fileName');

      // Return only file name
      return fileName;
    } catch (e) {
      print('❌ Error uploading profile picture: $e');
      return null;
    }
  }

  /// Delete profile picture by userId (tries multiple extensions)
  Future<bool> deleteProfilePicture(String userId) async {
    try {
      final fileExtensions = ['jpeg', 'jpg', 'png', 'webp'];

      for (final ext in fileExtensions) {
        try {
          final fileName = '$userId.$ext';
          await _supabase.storage.from('profile-pictures').remove([fileName]);
          print('✅ Deleted old profile picture: $fileName');
        } catch (e) {
          // File might not exist, continue
        }
      }

      return true;
    } catch (e) {
      print('❌ Error deleting profile picture: $e');
      return false;
    }
  }

  /// Delete profile picture by exact filename
  Future<bool> deleteProfilePictureByFileName(String fileName) async {
    try {
      if (fileName.isEmpty) return false;

      await _supabase.storage.from('profile-pictures').remove([fileName]);
      print('✅ Deleted profile picture: $fileName');
      return true;
    } catch (e) {
      print('❌ Error deleting profile picture by filename: $e');
      return false;
    }
  }

  /// Get profile picture URL for a user
  Future<String?> getProfilePictureUrl(String userId) async {
    try {
      final profile = await getUserProfileById(userId);
      return profile?['profile_pic_url'] as String?;
    } catch (e) {
      print('❌ Error getting profile picture URL: $e');
      return null;
    }
  }

  /// Build public URL for profile image
  String? buildProfileImageUrl(String? fileName) {
    if (fileName == null || fileName.isEmpty) return null;

    return _supabase.storage.from('profile-pictures').getPublicUrl(fileName);
  }
}

// Providers
final profileServiceProvider = Provider<ProfileService>((ref) {
  final supabase = Supabase.instance.client;
  return ProfileService(supabase);
});

final currentUserProfileProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser == null) return null;

  final profileService = ref.watch(profileServiceProvider);
  return await profileService.getUserProfileById(currentUser.id);
});

final userProfileProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
      final profileService = ref.watch(profileServiceProvider);
      return await profileService.getUserProfileById(userId);
    });
