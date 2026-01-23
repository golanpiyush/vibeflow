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

  // Add a mounted check variable
  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
  }

  @override
  void dispose() {
    _isMounted = false;
    super.dispose();
  }

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
        // Use safe setState
        _safeSetState(() {
          _hasAccessCode = true;
          _isChecking = false;
        });
        _initRealtimeIfNeeded();
        return;
      }

      // User not authenticated, check for access code OR skip status
      final secureStorage = SecureStorageService();
      final status = await secureStorage.getAccessCodeStatus();

      debugPrint('🔍 Access code status: $status');

      // Allow user to proceed if they have validated code OR skipped
      if (status == 'validated') {
        final validatedAt = await secureStorage.getAccessCodeValidatedAt();
        if (validatedAt != null &&
            DateTime.now().difference(validatedAt).inDays < 30) {
          debugPrint('✅ Valid access code found');
          _safeSetState(() {
            _hasAccessCode = true;
            _isChecking = false;
          });
          return;
        }
      } else if (status == 'skipped') {
        // User previously skipped - let them through
        debugPrint('✅ User previously skipped access code');
        _safeSetState(() {
          _hasAccessCode = true; // Allow access
          _isChecking = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error checking auth/access code: $e');
    }

    // No valid code and no skip - show access code screen
    _safeSetState(() {
      _hasAccessCode = false;
      _isChecking = false;
    });
  }

  // Helper method to safely call setState
  void _safeSetState(VoidCallback callback) {
    if (_isMounted) {
      setState(callback);
    } else {
      debugPrint('⚠️ setState() called after dispose - ignoring');
    }
  }

  void _onAccessCodeSuccess() {
    _safeSetState(() {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted) return;

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
