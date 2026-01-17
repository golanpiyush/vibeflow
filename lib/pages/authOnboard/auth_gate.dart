import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/pages/authOnboard/login_page.dart';
import 'package:vibeflow/pages/home_page.dart';
import 'package:vibeflow/services/auth_service.dart';
import 'package:vibeflow/utils/secure_storage.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _isChecking = true;
  bool _hasAccessCode = false;

  @override
  void initState() {
    super.initState();
    _checkAccessCode();
  }

  Future<void> _checkAccessCode() async {
    try {
      final secureStorage = SecureStorageService();
      final hasCode = await secureStorage.hasAccessCode();

      if (hasCode) {
        // Check if code was validated recently (within 30 days)
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
      print('Error checking access code: $e');
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
  }

  @override
  Widget build(BuildContext context) {
    // First check if access code check is complete
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If no access code, show access code screen
    if (!_hasAccessCode) {
      return AccessCodeScreen(
        showSkipButton: true,
        onSuccess: _onAccessCodeSuccess,
      );
    }

    // If has access code, check authentication state
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (state) {
        // Check if user is signed in
        if (state.session != null) {
          return const HomePage();
        }
        return const LoginPage();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => const LoginPage(),
    );
  }
}
