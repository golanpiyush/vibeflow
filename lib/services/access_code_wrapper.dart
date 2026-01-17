// lib/services/access_code_wrapper.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/pages/home_page.dart';
import 'package:vibeflow/utils/secure_storage.dart';

class AccessCodeWrapper extends ConsumerStatefulWidget {
  const AccessCodeWrapper({super.key});

  @override
  _AccessCodeWrapperState createState() => _AccessCodeWrapperState();
}

class _AccessCodeWrapperState extends ConsumerState<AccessCodeWrapper> {
  bool _isChecking = true;
  bool _hasAccessCode = false;
  bool _isAuthenticated = false;
  bool _realtimeInitialized = false;
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      _hasInitialized = true;
      _checkAuthAndAccessCode();
    }
  }

  Future<void> _checkAuthAndAccessCode() async {
    try {
      // First, check if user is authenticated
      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;

      _isAuthenticated = session != null && user != null;

      if (_isAuthenticated) {
        // User is logged in, skip access code check and go to HomePage
        debugPrint('✅ User authenticated, going to HomePage');
        setState(() {
          _hasAccessCode = true; // Set to true to show HomePage
          _isChecking = false;
        });
        _initRealtimeIfNeeded();
        return;
      }

      // User not authenticated, check for access code
      final secureStorage = SecureStorageService();
      final hasCode = await secureStorage.hasAccessCode();

      if (hasCode) {
        final validatedAt = await secureStorage.getAccessCodeValidatedAt();
        if (validatedAt != null &&
            DateTime.now().difference(validatedAt).inDays < 30) {
          setState(() {
            _hasAccessCode = true;
            _isChecking = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking auth/access code: $e');
    }

    setState(() {
      _hasAccessCode = false;
      _isChecking = false;
    });
  }

  void _onAccessCodeSuccess() {
    setState(() {
      _hasAccessCode = true;
    });
    _initRealtimeIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hasAccessCode || _isAuthenticated) {
      return const HomePage();
    }

    return AccessCodeScreen(
      showSkipButton: true,
      onSuccess: _onAccessCodeSuccess,
    );
  }

  void _initRealtimeIfNeeded() {
    if (_realtimeInitialized) return;

    // Use a post-frame callback to safely access ref after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) return;

      initializeRealtimeSubscriptions(ref);
      _realtimeInitialized = true;

      debugPrint('✅ Supabase realtime initialized');
    });
  }

  void initializeRealtimeSubscriptions(WidgetRef ref) {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final supabase = ref.read(supabaseClientProvider);

    supabase
        .channel('my_activity_debug_${currentUser.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'listening_activity',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUser.id,
          ),
          callback: (payload) {
            debugPrint('🔔 My activity changed: ${payload.eventType}');
            debugPrint('   New data: ${payload.newRecord}');
          },
        )
        .subscribe();
  }
}
