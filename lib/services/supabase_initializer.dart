// lib/services/supabase_initializer.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseInitializer {
  static Future<void> initialize() async {
    try {
      // Try to load .env file
      await dotenv.load(fileName: '.env');

      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

      if (supabaseUrl == null || supabaseAnonKey == null) {
        throw Exception('Supabase credentials not found in .env file');
      }

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
      );

      print('✅ Supabase initialized successfully');
    } on FileNotFoundError catch (e) {
      print('⚠️ .env file not found: $e');
      print('ℹ️ App will continue without Supabase features');
      print(
        'ℹ️ To fix: Create a .env file in project root with SUPABASE_URL and SUPABASE_ANON_KEY',
      );
      // Don't rethrow - allow app to continue
    } catch (e) {
      print('⚠️ Supabase initialization failed: $e');
      print('ℹ️ App will continue without Supabase features');
      // Don't rethrow - allow app to continue
    }
  }

  /// Check if Supabase is initialized and ready
  static bool get isInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Safe getter for Supabase client
  static SupabaseClient? get client {
    try {
      return isInitialized ? Supabase.instance.client : null;
    } catch (e) {
      return null;
    }
  }
}
