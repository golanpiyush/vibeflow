import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/pages/authOnboard/login_page.dart';
import 'package:vibeflow/pages/authOnboard/profile_setup_screen.dart';
import 'package:vibeflow/utils/secure_storage.dart';

class AccessCodeScreen extends ConsumerStatefulWidget {
  final bool showSkipButton;
  final VoidCallback? onSuccess;
  final bool isFromDialog; // NEW: Track if opened from dialog

  const AccessCodeScreen({
    super.key,
    this.showSkipButton = true,
    this.onSuccess,
    this.isFromDialog = false, // NEW
  });

  @override
  _AccessCodeScreenState createState() => _AccessCodeScreenState();

  // Add this static method to check for orphan access codes
  static Future<bool> hasOrphanAccessCode() async {
    final secureStorage = SecureStorageService();
    final status = await secureStorage.getAccessCodeStatus();

    if (status == 'validated') {
      final validatedAt = await secureStorage.getAccessCodeValidatedAt();
      if (validatedAt != null &&
          DateTime.now().difference(validatedAt).inDays < 30) {
        // Check if profile setup was completed
        // You'll need to add this method to SecureStorageService
        final profileCompleted = await secureStorage.isProfileSetupCompleted();
        return !profileCompleted; // Returns true if access code validated but profile not completed
      }
    }
    return false;
  }
}

class _AccessCodeScreenState extends ConsumerState<AccessCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _showValidationMessage = false;

  @override
  void initState() {
    super.initState();
    // Don't check existing code if opened from dialog
    if (!widget.isFromDialog && widget.onSuccess != null) {
      _checkExistingAccessCodeForCallback();
    }
  }

  Future<void> _checkExistingAccessCodeForCallback() async {
    final secureStorage = SecureStorageService();
    final status = await secureStorage.getAccessCodeStatus();

    if (status == 'validated') {
      final validatedAt = await secureStorage.getAccessCodeValidatedAt();
      if (validatedAt != null &&
          DateTime.now().difference(validatedAt).inDays < 30) {
        widget.onSuccess?.call();
      }
    }
  }

  Future<void> _validateCode() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showValidationMessage = false;
    });

    try {
      final db = ref.read(dbActionsProvider);
      final result = await db.validateCode(_codeController.text.trim());

      if (result.isValid) {
        final secureStorage = SecureStorageService();
        await secureStorage.saveAccessCode(_codeController.text.trim());

        setState(() {
          _showValidationMessage = true;
        });

        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) {
          // If opened from dialog, just pop back
          if (widget.isFromDialog) {
            Navigator.of(context).pop(true); // Just pop with success result
          } else {
            // Otherwise navigate to profile setup
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    ProfileSetupScreen(accessCode: _codeController.text.trim()),
              ),
            );
          }
        }
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'Invalid access code';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _continueWithoutCode() async {
    final secureStorage = SecureStorageService();
    await secureStorage.markAccessCodeSkipped();

    print('✅ User skipped access code - saved to secure storage');

    if (mounted) {
      if (widget.isFromDialog) {
        Navigator.of(context).pop(false); // Return skipped
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  void _navigateToLogin() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      appBar: widget.isFromDialog
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: _showValidationMessage
            ? _buildSuccessMessage(isDark)
            : _buildAccessCodeForm(isDark),
      ),
    );
  }

  Widget _buildSuccessMessage(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
              size: 60,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Access Code Verified',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isFromDialog
                ? 'Returning to app...'
                : 'Setting up your account...',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessCodeForm(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Access Code',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter your code to unlock social features',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _codeController,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Access Code',
                            labelStyle: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            hintText: 'Enter your code',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 14,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            prefixIcon: Icon(
                              Icons.key_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withOpacity(0.03)
                                : Colors.black.withOpacity(0.02),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter an access code';
                            }
                            return null;
                          },
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _validateCode(),
                        ),
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.error.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _validateCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            'Verify Code',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  if (!widget.isFromDialog) ...[
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _navigateToLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.login_rounded, size: 20),
                      label: Text(
                        'Already Have an Account? Login',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.showSkipButton)
                      OutlinedButton(
                        onPressed: _continueWithoutCode,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          side: BorderSide(
                            color: isDark ? Colors.white12 : Colors.black12,
                            width: 1.5,
                          ),
                          foregroundColor: isDark
                              ? Colors.white70
                              : Colors.black87,
                        ),
                        child: Text(
                          'Continue Without Code',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.blue.withOpacity(0.08)
                            : Colors.blue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.blue.shade400,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You can use the app without an access code. Social features will be limited.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
