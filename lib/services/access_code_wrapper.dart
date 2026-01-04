// lib/screens/access_code_wrapper.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hasAccessCode) {
      return const HomePage();
    }

    return AccessCodeScreen(
      showSkipButton: true,
      onSuccess: _onAccessCodeSuccess,
    );
  }
}
