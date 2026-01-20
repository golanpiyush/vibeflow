// lib/utils/secure_storage.dart - FINAL VERSION
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';
import 'dart:math';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const String _keyStorageKey = 'encryption_master_key';

  static Key? _cachedKey;

  // Keys
  static const String _hasAccessCodeKey = 'hasAccessCode';
  static const String _accessCodeKey = 'accessCode';
  static const String _accessCodeValidatedAtKey = 'accessCodeValidatedAt';
  static const String _accessCodeSkippedKey = 'accessCodeSkipped';
  static const String _accessCodeSkippedAtKey = 'accessCodeSkippedAt';
  static const String _userIdKey = 'userId';
  static const String _emailKey = 'userEmail';

  SecureStorageService._privateConstructor();
  static final SecureStorageService _instance =
      SecureStorageService._privateConstructor();
  factory SecureStorageService() => _instance;

  /// Get or create device-specific encryption key (Update resistant!)
  static Future<Key> _getOrCreateKey() async {
    if (_cachedKey != null) return _cachedKey!;

    // Try to read existing key
    String? keyBase64 = await _storage.read(key: _keyStorageKey);

    if (keyBase64 == null) {
      // Generate new key on first launch
      final secureRandom = Random.secure();
      final keyBytes = Uint8List.fromList(
        List<int>.generate(32, (_) => secureRandom.nextInt(256)),
      );
      final key = Key(keyBytes);

      // Save for future use
      await _storage.write(key: _keyStorageKey, value: key.base64);
      _cachedKey = key;
      print('🔑 Generated new device-specific encryption key');
      return key;
    }

    _cachedKey = Key.fromBase64(keyBase64);
    return _cachedKey!;
  }

  static Future<Encrypter> _getEncrypter() async {
    final key = await _getOrCreateKey();
    return Encrypter(AES(key));
  }

  Future<void> writeSecureData(String key, String value) async {
    try {
      final encrypter = await _getEncrypter();
      final iv = IV.fromSecureRandom(16);
      final encrypted = encrypter.encrypt(value, iv: iv);

      await _storage.write(key: key, value: '${iv.base64}:${encrypted.base64}');
    } catch (e) {
      print('Error writing secure data: $e');
      // Fallback to plain storage if encryption fails
      await _storage.write(key: key, value: value);
    }
  }

  Future<String?> readSecureData(String key) async {
    try {
      final combined = await _storage.read(key: key);
      if (combined == null) return null;

      final parts = combined.split(':');
      if (parts.length != 2) {
        // Legacy data (not encrypted)
        return combined;
      }

      final encrypter = await _getEncrypter();
      final iv = IV.fromBase64(parts[0]);
      final encrypted = Encrypted.fromBase64(parts[1]);

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print('Error reading secure data: $e');
      // Try to read as plain text
      return await _storage.read(key: key);
    }
  }

  Future<void> deleteSecureData(String key) async {
    await _storage.delete(key: key);
  }

  // Access Code Methods
  Future<void> saveAccessCode(String code) async {
    await writeSecureData(_accessCodeKey, code);
    await writeSecureData(_hasAccessCodeKey, 'true');
    await writeSecureData(
      _accessCodeValidatedAtKey,
      DateTime.now().toIso8601String(),
    );
    // Clear skipped status when user enters code
    await deleteSecureData(_accessCodeSkippedKey);
    await deleteSecureData(_accessCodeSkippedAtKey);
  }

  Future<bool> hasAccessCode() async {
    final value = await readSecureData(_hasAccessCodeKey);
    return value == 'true';
  }

  Future<String?> getAccessCode() async {
    return await readSecureData(_accessCodeKey);
  }

  Future<DateTime?> getAccessCodeValidatedAt() async {
    final value = await readSecureData(_accessCodeValidatedAtKey);
    if (value != null) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Mark that user skipped access code entry
  Future<void> markAccessCodeSkipped() async {
    await writeSecureData(_accessCodeSkippedKey, 'true');
    await writeSecureData(
      _accessCodeSkippedAtKey,
      DateTime.now().toIso8601String(),
    );
    // Clear access code data when skipped
    await deleteSecureData(_hasAccessCodeKey);
    await deleteSecureData(_accessCodeKey);
    await deleteSecureData(_accessCodeValidatedAtKey);
  }

  /// Check if user has skipped access code entry
  Future<bool> hasSkippedAccessCode() async {
    final value = await readSecureData(_accessCodeSkippedKey);
    return value == 'true';
  }

  /// Get when user skipped access code
  Future<DateTime?> getAccessCodeSkippedAt() async {
    final value = await readSecureData(_accessCodeSkippedAtKey);
    if (value != null) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // In SecureStorageService class
  Future<bool> isProfileSetupCompleted() async {
    final value = await _storage.read(key: 'profile_setup_completed');
    return value == 'true';
  }

  Future<void> markProfileSetupCompleted() async {
    await _storage.write(key: 'profile_setup_completed', value: 'true');
  }

  /// Clear skip status (useful when user wants to enter code later)
  Future<void> clearSkipStatus() async {
    await deleteSecureData(_accessCodeSkippedKey);
    await deleteSecureData(_accessCodeSkippedAtKey);
  }

  /// Clear all access code related data
  Future<void> clearAccessCode() async {
    await deleteSecureData(_hasAccessCodeKey);
    await deleteSecureData(_accessCodeKey);
    await deleteSecureData(_accessCodeValidatedAtKey);
    await deleteSecureData(_accessCodeSkippedKey);
    await deleteSecureData(_accessCodeSkippedAtKey);
  }

  /// Check access code status
  /// Returns: 'validated', 'skipped', or 'none'
  Future<String> getAccessCodeStatus() async {
    if (await hasAccessCode()) {
      return 'validated';
    } else if (await hasSkippedAccessCode()) {
      return 'skipped';
    } else {
      return 'none';
    }
  }

  // User Data Methods
  Future<void> saveUserId(String userId) async {
    await writeSecureData(_userIdKey, userId);
  }

  Future<String?> getUserId() async {
    return await readSecureData(_userIdKey);
  }

  Future<void> saveUserEmail(String email) async {
    await writeSecureData(_emailKey, email);
  }

  Future<String?> getUserEmail() async {
    return await readSecureData(_emailKey);
  }

  Future<void> clearAllUserData() async {
    await clearAccessCode();
    await deleteSecureData(_userIdKey);
    await deleteSecureData(_emailKey);
  }
}
