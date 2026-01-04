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

  /// Upload profile picture - SIMPLIFIED VERSION
  Future<String?> uploadProfilePicture(String userId, String imagePath) async {
    try {
      print('📤 Starting upload...');
      print('📂 File path: $imagePath');

      final file = File(imagePath);

      // Check if file exists
      if (!await file.exists()) {
        print('❌ File does not exist at path: $imagePath');
        throw Exception('Image file not found');
      }

      // Read file bytes
      final fileBytes = await file.readAsBytes();
      print('📊 File size: ${fileBytes.length} bytes');

      // Determine file extension
      final fileExtension = imagePath.split('.').last.toLowerCase();
      final normalizedExt = fileExtension == 'jpg' ? 'jpeg' : fileExtension;
      final fileName = 'profile_$userId.$normalizedExt';

      print('📝 Uploading as: $fileName');
      print('🎯 Bucket: profile-pictures');

      // Upload directly without bucket check
      await _supabase.storage
          .from('profile-pictures')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$normalizedExt',
            ),
          );

      print('✅ Upload successful!');

      // Get public URL
      final publicUrl = _supabase.storage
          .from('profile-pictures')
          .getPublicUrl(fileName);

      print('🔗 Public URL: $publicUrl');

      return publicUrl;
    } on StorageException catch (e) {
      print('❌ Storage Error: ${e.message}');
      print('❌ Status Code: ${e.statusCode}');

      if (e.statusCode == 404) {
        print('');
        print('🔧 BUCKET NOT FOUND - Please create it:');
        print('1. Go to Supabase Dashboard');
        print('2. Storage → New Bucket');
        print('3. Name: profile-pictures');
        print('4. Make it PUBLIC');
        print('5. Add storage policies');
        print('');
      } else if (e.statusCode == 403) {
        print('');
        print('🔧 PERMISSION DENIED - Check your policies:');
        print('You need INSERT policy for authenticated users');
        print('');
      }

      return null;
    } catch (e) {
      print('❌ Unexpected error: $e');
      print('❌ Error type: ${e.runtimeType}');
      return null;
    }
  }

  /// Delete profile picture
  Future<bool> deleteProfilePicture(String userId) async {
    try {
      final fileExtensions = ['jpeg', 'jpg', 'png', 'webp'];

      for (final ext in fileExtensions) {
        try {
          final fileName = 'profile_$userId.$ext';
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
