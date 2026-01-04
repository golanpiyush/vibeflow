import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
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
      _accessCode = await _secureStorage.getAccessCode();
      _validatedAt = await _secureStorage.getAccessCodeValidatedAt();
    } catch (_) {}

    setState(() => _isLoading = false);
  }

  Future<void> _clearAccessCodeData() async {
    setState(() => _isClearing = true);

    try {
      await _secureStorage.clearAccessCode();
      await ref.read(dbActionsProvider).supabaseClient.auth.signOut();
      await _secureStorage.clearAllUserData();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Access code cleared')));

      setState(() {
        _accessCode = null;
        _validatedAt = null;
        _showConfirmation = false;
      });

      await Future.delayed(const Duration(milliseconds: 1200));

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const AccessCodeScreen(showSkipButton: true),
        ),
        (_) => false,
      );
    } finally {
      setState(() => _isClearing = false);
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
          style: AppTypography.sectionHeader.copyWith(
            color: colorScheme.onSurface,
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
          style: AppTypography.caption.copyWith(
            color: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        _faqSection(colorScheme),
      ],
    );
  }

  // =======================
  // STATUS CARD
  // =======================

  Widget _statusCard(bool isValid, int remaining, ColorScheme colorScheme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Access Status', style: AppTypography.sectionHeader),
                _pill(
                  text: isValid ? 'ACTIVE' : 'EXPIRED',
                  color: isValid ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
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
                style: AppTypography.caption.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.subtitle.copyWith(
                  color: warning ? Colors.orange : colorScheme.onSurface,
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
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied')));
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            Icon(Icons.lock_open, size: 64, color: scheme.primary),
            const SizedBox(height: AppSpacing.lg),
            Text('No Access Code', style: AppTypography.sectionHeader),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enter an access code to unlock social features.',
              style: AppTypography.subtitle.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                style: AppTypography.subtitle.copyWith(color: textColor),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ElevatedButton.icon(
      icon: const Icon(Icons.delete_outline),
      label: const Text('Clear Access Code'),
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
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        'Clear Access Code',
        style: AppTypography.dialogTitle.copyWith(color: colorScheme.onSurface),
      ),
      content: Text(
        'This action cannot be undone. And you will be logged out.',
        style: AppTypography.subtitle.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _showConfirmation = false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isClearing ? null : _clearAccessCodeData,
          child: _isClearing
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Clear'),
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About Access Codes', style: AppTypography.sectionHeader),
            const SizedBox(height: AppSpacing.lg),
            _faq(
              'What is it?',
              'Unlocks social and shared playlist features.',
              colorScheme,
            ),
            _faq('Validity?', 'Valid for 30 days.', colorScheme),
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
            style: AppTypography.subtitle.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            a,
            style: AppTypography.caption.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
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
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
