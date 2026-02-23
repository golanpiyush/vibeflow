import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/database/database_service.dart';
import 'package:vibeflow/pages/appearance_page.dart';
import 'package:vibeflow/pages/subpages/settings/about_page.dart';
import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/other_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:vibeflow/utils/user_preference_tracker.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({Key? key}) : super(key: key);

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  bool _isResettingQuickPicks = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  String? _lastBackupDate;

  @override
  void initState() {
    super.initState();
    _loadLastBackupDate();
  }

  Future<void> _loadLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastBackupDate = prefs.getString('last_backup_date');
      });
    }
  }

  Future<void> _resetQuickPicks() async {
    final colorScheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Reset Quick Picks',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: Text(
          'This will clear your quick picks history and recommendations.\n\n'
          'Your saved songs and playlists will not be affected.',
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.87)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: colorScheme.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isResettingQuickPicks = true);

    try {
      // Clear quick picks cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('quick_picks_cache');
      await prefs.remove('quick_picks_last_update');
      await prefs.remove('recommended_songs');

      // ✅ ADD THIS: Reset user preference tracker data
      final userPrefs = UserPreferenceTracker();
      await userPrefs.resetAllPreferences();

      if (!mounted) return;
      setState(() => _isResettingQuickPicks = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quick picks and taste profile reset'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      print('❌ Error resetting quick picks: $e');
      if (!mounted) return;

      setState(() => _isResettingQuickPicks = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reset quick picks: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _backupDatabase() async {
    setState(() => _isBackingUp = true);

    try {
      // Get the database path
      final db = await DatabaseService().database;
      final dbPath = db.path;

      // Create backup filename with timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupFileName = 'vibeflow_backup_$timestamp.db';

      // Get external storage directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception('Could not access storage directory');
      }

      // Create backups folder
      final backupsDir = Directory(path.join(directory.path, 'backups'));
      if (!await backupsDir.exists()) {
        await backupsDir.create(recursive: true);
      }

      final backupPath = path.join(backupsDir.path, backupFileName);

      // Close database temporarily
      await db.close();

      // Copy database file
      final dbFile = File(dbPath);
      await dbFile.copy(backupPath);
      // Safely reopen
      try {
        await DatabaseService().database;
      } catch (e) {
        throw Exception('Failed to reopen database after backup: $e');
      }
      // Reopen database
      await DatabaseService().database;

      // Save backup metadata
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_backup_date',
        DateTime.now().toIso8601String(),
      );
      await prefs.setString('last_backup_path', backupPath);

      if (!mounted) return;

      setState(() {
        _isBackingUp = false;
        _lastBackupDate = DateTime.now().toIso8601String();
      });

      // Show success dialog with share option
      final shouldShare = await showDialog<bool>(
        context: context,
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;

          return AlertDialog(
            backgroundColor: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Backup Created',
              style: AppTypography.subtitle(context).copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Database backed up successfully!',
                  style: AppTypography.body(
                    context,
                  ).copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 12),

                /// Location Box (cleaner look)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    backupPath,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'OK',
                  style: AppTypography.subtitle(context).copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Share',
                  style: AppTypography.subtitle(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      );

      if (shouldShare == true) {
        await Share.shareXFiles(
          [XFile(backupPath)],
          subject: 'VibeFlow Database Backup',
          text: 'VibeFlow database backup created on ${DateTime.now()}',
        );
      }
    } catch (e) {
      print('❌ Error backing up database: $e');
      if (!mounted) return;

      setState(() => _isBackingUp = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _restoreDatabase() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // Show warning dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface, // UPDATED
        title: Text(
          '⚠️ Warning',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface, // ADD THIS
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Restoring from backup will:\n\n'
          '• Overwrite all existing data\n'
          '• Replace your current library\n'
          '• Cannot be undone\n\n'
          'The app will restart after restoration.\n\n'
          'Are you sure you want to continue?',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.8), // ADD THIS
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.primary, // UPDATED
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(
              'Restore',
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onError, // ADD THIS
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);

    try {
      // Pick backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() => _isRestoring = false);
        return;
      }

      final backupFilePath = result.files.single.path!;
      final backupFile = File(backupFilePath);

      if (!await backupFile.exists()) {
        throw Exception('Backup file not found');
      }

      final isValid = await _verifyDatabaseFile(backupFilePath);
      if (!isValid) {
        throw Exception('Invalid or corrupted backup file');
      }

      final db = await DatabaseService().database;
      final dbPath = db.path;

      await db.close();

      // Create emergency backup
      final currentDbFile = File(dbPath);
      final emergencyBackupPath = '$dbPath.emergency_backup';
      await currentDbFile.copy(emergencyBackupPath);

      try {
        await File(emergencyBackupPath).delete();
      } catch (e) {
        print('Could not delete emergency backup: $e');
      }

      // Restore
      await backupFile.copy(dbPath);

      // Save restore metadata
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_restore_date',
        DateTime.now().toIso8601String(),
      );
      await prefs.setString('restored_from', backupFilePath);

      if (!mounted) return;

      // Show success and restart prompt
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: colorScheme.surface, // UPDATED
          title: Text(
            '✓ Restore Complete',
            style: textTheme.titleMedium?.copyWith(
              color: Colors.green, // Keep green for success
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Database restored successfully!\n\n'
            'The app will now restart to apply changes.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.8), // ADD THIS
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                SystemNavigator.pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, // Keep amber for warning/action
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Text(
                'Close App',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimary, // ADD THIS
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error restoring database: $e');
      if (!mounted) return;

      setState(() => _isRestoring = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restore failed: ${e.toString()}',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onError, // UPDATED
            ),
          ),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<bool> _verifyDatabaseFile(String filePath) async {
    try {
      final db = await openDatabase(filePath, readOnly: true);

      // Check if required tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      final tableNames = tables.map((t) => t['name'] as String).toList();
      final requiredTables = ['songs', 'playlists', 'playlist_songs'];

      for (final table in requiredTables) {
        if (!tableNames.contains(table)) {
          await db.close();
          return false;
        }
      }

      await db.close();
      return true;
    } catch (e) {
      print('Database verification failed: $e');
      return false;
    }
  }

  String _formatBackupDate(String? isoDate) {
    if (isoDate == null) return 'Never';

    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textPrimaryColor = colorScheme.onSurface;
    final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
    final iconActiveColor = colorScheme.primary;
    final warningColor = const Color(0xFFE57373);

    return _SettingsPageTemplate(
      title: 'Database',
      currentIndex: 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CLEANUP SECTION
          Text(
            'CLEANUP',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildActionItem(
            context,
            'Reset quick picks',
            'Clear quick picks cache and recommendations',
            _isResettingQuickPicks ? null : _resetQuickPicks,
            isLoading: _isResettingQuickPicks,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),
          const SizedBox(height: AppSpacing.xl),

          // BACKUP SECTION
          Text(
            'BACKUP',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Personal preferences (i.e. the theme mode) and the cache are excluded.',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondaryColor, height: 1.5),
          ),
          if (_lastBackupDate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Last backup: ${_formatBackupDate(_lastBackupDate)}',
              style: AppTypography.caption(context).copyWith(
                color: textSecondaryColor.withOpacity(0.8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _buildActionItem(
            context,
            'Backup',
            'Export the database to external storage',
            _isBackingUp ? null : _backupDatabase,
            isLoading: _isBackingUp,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),
          const SizedBox(height: AppSpacing.xl),

          // RESTORE SECTION
          Text(
            'RESTORE',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _buildActionItem(
            context,
            'Restore',
            'Import database from external storage',
            _isRestoring ? null : _restoreDatabase,
            isLoading: _isRestoring,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),
          const SizedBox(height: AppSpacing.md),

          Text(
            'Existing data will be overwritten.\nvibeFlow will automatically close itself after restoring the database.',
            style: AppTypography.caption(
              context,
            ).copyWith(color: warningColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context,
    String title,
    String subtitle,
    VoidCallback? onTap, {
    bool isLoading = false,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required Color iconActiveColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.subtitle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor),
                  ),
                ],
              ),
            ),
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(iconActiveColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Template for settings pages
class _SettingsPageTemplate extends ConsumerWidget {
  final String title;
  final int currentIndex;
  final Widget content;

  const _SettingsPageTemplate({
    required this.title,
    required this.currentIndex,
    required this.content,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = colorScheme.background;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xxxl),

            _buildTopBar(context, colorScheme),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(context, colorScheme),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [content, const SizedBox(height: 100)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ColorScheme colorScheme) {
    final textPrimaryColor = colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.chevron_left, color: textPrimaryColor, size: 28),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                title,
                style: AppTypography.pageTitle(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, ColorScheme colorScheme) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = colorScheme.primary;
    final iconInactiveColor = colorScheme.onSurface.withOpacity(0.6);
    final sidebarLabelColor = colorScheme.onSurface;
    final sidebarLabelActiveColor = colorScheme.primary;

    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: sidebarLabelActiveColor);

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              context,
              icon: Icons.edit_square,
              label: '',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: -1,
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              context,
              label: 'Player',
              isActive: currentIndex == 0,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 0
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 0,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Cache',
              isActive: currentIndex == 1,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 1
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 1,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Database',
              isActive: currentIndex == 2,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 2
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 2,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Other',
              isActive: currentIndex == 3,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 3
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 3,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'About',
              isActive: currentIndex == 4,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 4
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 4,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context, {
    IconData? icon,
    required String label,
    bool isActive = false,
    required Color iconActiveColor,
    required Color iconInactiveColor,
    required TextStyle labelStyle,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          _navigateToPage(context, index, currentIndex: currentIndex);
        }
      },
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 28,
                color: isActive ? iconActiveColor : iconInactiveColor,
              ),
              const SizedBox(height: 16),
            ],
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: labelStyle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPage(
    BuildContext context,
    int targetIndex, {
    required int currentIndex,
  }) {
    Widget page;
    switch (targetIndex) {
      case -1:
        page = const AppearancePage();
        break;
      case 0:
        page = const PlayerSettingsPage();
        break;
      case 1:
        page = const CachePage();
        break;
      case 2:
        page = const DatabasePage();
        break;
      case 3:
        page = const OtherPage();
        break;
      case 4:
        page = const AboutPage();
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacementDirectional(
      page,
      currentIndex: currentIndex,
      targetIndex: targetIndex,
    );
  }
}
