import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/services/auth_service.dart';
import 'package:vibeflow/utils/secure_storage.dart';

import '../constants/app_typography.dart';
import '../constants/app_spacing.dart';

class AccessCodeManagementScreen extends ConsumerStatefulWidget {
  const AccessCodeManagementScreen({super.key});

  @override
  ConsumerState<AccessCodeManagementScreen> createState() =>
      _AccessCodeManagementScreenState();
}

class _AccessCodeManagementScreenState
    extends ConsumerState<AccessCodeManagementScreen> {
  final SecureStorageService _secureStorage = SecureStorageService();
  String? _accessCode;
  DateTime? _validatedAt;
  bool _isLoading = true;
  bool _isClearing = false;
  bool _showConfirmation = false;

  @override
  void initState() {
    super.initState();
    _loadAccessCodeData();
  }

  Future<void> _loadAccessCodeData() async {
    setState(() => _isLoading = true);

    try {
      // Check if user is authenticated first
      final currentUser = ref.read(currentUserProvider);

      if (currentUser != null) {
        // User is authenticated - they have access
        // Set a default access code indicator
        _accessCode = 'authenticated';
        _validatedAt = DateTime.now(); // Or fetch from user metadata if stored

        print('✅ User is authenticated, showing access granted');
      } else {
        // Not authenticated - check for access code in storage
        _accessCode = await _secureStorage.getAccessCode();
        _validatedAt = await _secureStorage.getAccessCodeValidatedAt();

        print('🔍 No authentication, checking stored access code');
      }
    } catch (e) {
      print('❌ Error loading access code data: $e');
    }

    setState(() => _isLoading = false);
  }

  // ============================================
  // UPDATED: _clearAccessCodeData method
  // ============================================

  Future<void> _clearAccessCodeData() async {
    setState(() => _isClearing = true);

    try {
      // ✅ Use authService.signOut() - it handles everything:
      // - Stops audio and tracking
      // - Clears secure storage
      // - Signs out from Supabase
      await ref.read(authServiceProvider).signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access code cleared and signed out')),
        );

        setState(() {
          _accessCode = null;
          _validatedAt = null;
          _showConfirmation = false;
        });

        // Small delay for UX
        await Future.delayed(const Duration(milliseconds: 500));

        // Navigate to access code screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const AccessCodeScreen(showSkipButton: true),
          ),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  String _maskAccessCode(String code) {
    if (code.length <= 3) return code;
    return code.substring(0, 3) + '*' * (code.length - 3);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Access Code',
          style: AppTypography.sectionHeader(context).copyWith(
            color: colorScheme.onSurface, // ADD THIS
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _buildContent(colorScheme),
          ),

          if (_showConfirmation)
            ModalBarrier(color: Colors.black54, dismissible: !_isClearing),

          if (_showConfirmation) Center(child: _buildConfirmationDialog()),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    if (_accessCode == null) return _buildNoAccessCard(colorScheme);

    final daysUsed = _validatedAt == null
        ? 30
        : DateTime.now().difference(_validatedAt!).inDays;
    final remaining = 30 - daysUsed;
    final isValid = remaining > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusCard(isValid, remaining, colorScheme),
        const SizedBox(height: AppSpacing.xl),
        _warningCard(isValid, colorScheme),
        const SizedBox(height: AppSpacing.xxxl),
        _clearButton(),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Clearing your access code disables all social features.',
          textAlign: TextAlign.center,
          style: AppTypography.caption(
            context,
          ).copyWith(color: colorScheme.onSurface.withOpacity(0.6)),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        _faqSection(colorScheme),
        const SizedBox(height: AppSpacing.fourxxxl),
      ],
    );
  }

  // =======================
  // STATUS CARD
  // =======================

  Widget _statusCard(bool isValid, int remaining, ColorScheme colorScheme) {
    final currentUser = ref.watch(currentUserProvider);
    final isAuthenticated = currentUser != null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      color: colorScheme.surface, // ADD THIS
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Access Status',
                  style: AppTypography.sectionHeader(context).copyWith(
                    color: colorScheme.onSurface, // ADD THIS
                  ),
                ),
                _pill(
                  text: isAuthenticated
                      ? 'AUTHENTICATED'
                      : (isValid ? 'ACTIVE' : 'EXPIRED'),
                  color: isAuthenticated
                      ? const Color.fromARGB(255, 33, 243, 79)
                      : (isValid ? Colors.green : Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            if (isAuthenticated) ...[
              _infoRow(
                Icons.verified_user,
                'Authentication',
                'Logged in as ${currentUser.email ?? 'User'}',
                colorScheme,
              ),
              _divider(),
              _infoRow(
                Icons.check_circle,
                'Access Level',
                'Full Access (Authenticated)',
                colorScheme,
              ),
            ] else ...[
              _infoRow(
                Icons.code,
                'Access Code Used',
                _maskAccessCode(_accessCode!),
                colorScheme,
              ),
              _divider(),
              _infoRow(
                Icons.calendar_today,
                'Validated On',
                _validatedAt == null
                    ? '-'
                    : '${_validatedAt!.toLocal()}'.split('.')[0],
                colorScheme,
              ),
              _divider(),
              _infoRow(
                Icons.timer,
                'Days Remaining',
                '$remaining days',
                colorScheme,
                warning: remaining <= 7,
              ),
            ],

            _divider(),
            _infoRow(
              Icons.check_circle,
              'Unlocked Features',
              'Social\nListening Activity\nShared Playlists',
              colorScheme,
            ),
          ],
        ),
      ),
    );
  }
  // =======================
  // INFO ROW
  // =======================

  Widget _infoRow(
    IconData icon,
    String title,
    String value,
    ColorScheme colorScheme, {
    bool copy = false,
    bool warning = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: warning
              ? Colors.orange
              : colorScheme.onSurface.withOpacity(0.7),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.caption(context).copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6), // ADD THIS
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.subtitle(context).copyWith(
                  color: warning
                      ? Colors.orange
                      : colorScheme.onSurface, // ADD THIS
                ),
              ),
            ],
          ),
        ),
        if (copy)
          IconButton(
            icon: Icon(
              Icons.copy,
              size: 18,
              color: colorScheme.onSurface.withOpacity(0.7), // ADD THIS
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Copied',
                    style: TextStyle(color: colorScheme.onPrimary), // ADD THIS
                  ),
                  backgroundColor: colorScheme.primary, // ADD THIS
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _divider() =>
      const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md));

  // =======================
  // NO ACCESS CARD
  // =======================

  Widget _buildNoAccessCard(ColorScheme scheme) {
    return Card(
      color: scheme.surface, // ADD THIS
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            Icon(Icons.lock_open, size: 64, color: scheme.primary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No Access Code',
              style: AppTypography.sectionHeader(context).copyWith(
                color: scheme.onSurface, // ADD THIS
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enter an access code to unlock social features.',
              style: AppTypography.subtitle(context).copyWith(
                color: scheme.onSurface.withOpacity(0.7), // ADD THIS
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              icon: const Icon(Icons.code),
              label: const Text('Enter Code'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const AccessCodeScreen(showSkipButton: false),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  // =======================
  // WARNING CARD
  // =======================

  Widget _warningCard(bool isValid, ColorScheme colorScheme) {
    final currentUser = ref.watch(currentUserProvider);
    final isAuthenticated = currentUser != null;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // For authenticated users, show different warning
    if (isAuthenticated) {
      final bgColor = isDark
          ? Colors.blue.shade900.withOpacity(0.3)
          : Colors.blue.shade50;
      final iconColor = Colors.blue;
      final textColor = isDark ? colorScheme.onSurface : Colors.blue.shade900;

      return Card(
        color: bgColor,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.info, color: iconColor),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'You are logged in. Logging out will remove social features.',
                  style: AppTypography.subtitle(context).copyWith(
                    color: textColor, // Keep functional color
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Original warning for access code users
    final bgColor = isValid
        ? (isDark
              ? Colors.orange.shade900.withOpacity(0.3)
              : Colors.orange.shade50)
        : (isDark
              ? Colors.blue.shade900.withOpacity(0.3)
              : Colors.blue.shade50);

    final iconColor = isValid ? Colors.orange : Colors.blue;
    final textColor = isDark
        ? colorScheme.onSurface
        : (isValid ? Colors.orange.shade900 : Colors.blue.shade900);

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(isValid ? Icons.warning_amber : Icons.info, color: iconColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                isValid
                    ? 'Clearing the access code will remove social features and sign you out.'
                    : 'Your access code has expired.',
                style: AppTypography.subtitle(context).copyWith(
                  color: textColor, // Keep functional color
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // =======================
  // CLEAR BUTTON
  // =======================

  Widget _clearButton() {
    final currentUser = ref.watch(currentUserProvider);
    final isAuthenticated = currentUser != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ElevatedButton.icon(
      icon: Icon(isAuthenticated ? Icons.logout : Icons.delete_outline),
      label: Text(isAuthenticated ? 'Sign Out' : 'Clear Access Code'),
      style: ElevatedButton.styleFrom(
        backgroundColor: isDark
            ? Colors.red.shade900.withOpacity(0.3)
            : Colors.red.shade50,
        foregroundColor: isDark ? Colors.red.shade300 : Colors.red.shade700,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      ),
      onPressed: () => setState(() => _showConfirmation = true),
    );
  }

  // =======================
  // CONFIRM DIALOG
  // =======================

  Widget _buildConfirmationDialog() {
    final currentUser = ref.watch(currentUserProvider);
    final isAuthenticated = currentUser != null;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surface, // ADD THIS
      title: Text(
        isAuthenticated ? 'Sign Out' : 'Clear Access Code',
        style: AppTypography.dialogTitle(context).copyWith(
          color: colorScheme.onSurface, // ADD THIS
        ),
      ),
      content: Text(
        isAuthenticated
            ? 'You will be logged out and lose access to social features.'
            : 'This action cannot be undone. And you will be logged out.',
        style: AppTypography.subtitle(context).copyWith(
          color: colorScheme.onSurface.withOpacity(0.7), // ADD THIS
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _showConfirmation = false),
          child: Text(
            'Cancel',
            style: TextStyle(color: colorScheme.primary), // ADD THIS
          ),
        ),
        ElevatedButton(
          onPressed: _isClearing ? null : _clearAccessCodeData,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.error, // ADD THIS
            foregroundColor: colorScheme.onError, // ADD THIS
          ),
          child: _isClearing
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  isAuthenticated ? 'Sign Out' : 'Clear',
                  style: TextStyle(color: colorScheme.onError), // ADD THIS
                ),
        ),
      ],
    );
  }

  // =======================
  // FAQ
  // =======================
  Widget _faqSection(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface, // ADD THIS
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About Access Codes',
              style: AppTypography.sectionHeader(context).copyWith(
                color: colorScheme.onSurface, // ADD THIS
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _faq(
              'What is it?',
              'Unlocks social and shared playlist features.',
              colorScheme,
            ),
            // _faq('Validity?', 'Valid for 30 days.', colorScheme),
            _faq('Multiple codes?', 'Only one at a time.', colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _faq(String q, String a, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q,
            style: AppTypography.subtitle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface, // ADD THIS
            ),
          ),
          const SizedBox(height: 4),
          Text(
            a,
            style: AppTypography.caption(context).copyWith(
              color: colorScheme.onSurface.withOpacity(0.7), // ADD THIS
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppTypography.caption(context).copyWith(
          color: color, // Keep functional color for status
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
