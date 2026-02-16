// lib/widgets/update_dialog.dart - WITH AUTO-DOWNLOAD AND AUTO-INSTALL SUPPORT
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:vibeflow/installer_services/apk_installer_service.dart';
import 'package:vibeflow/installer_services/update_manager_service.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final bool autoDownload;
  final bool autoInstall;

  const UpdateDialog({
    Key? key,
    required this.updateInfo,
    this.autoDownload = false,
    this.autoInstall = false,
  }) : super(key: key);

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();

  /// Show the update dialog (normal)
  static Future<void> show(BuildContext context, UpdateInfo updateInfo) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  /// Show the update dialog with auto-download triggered
  static Future<void> showWithAutoDownload(
    BuildContext context,
    UpdateInfo updateInfo,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          UpdateDialog(updateInfo: updateInfo, autoDownload: true),
    );
  }

  /// Show the update dialog with auto-install triggered (if already downloaded)
  static Future<void> showWithAutoInstall(
    BuildContext context,
    UpdateInfo updateInfo,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          UpdateDialog(updateInfo: updateInfo, autoInstall: true),
    );
  }
}

class _UpdateDialogState extends State<UpdateDialog>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  String? _errorMessage;
  String _downloadSpeed = '';
  bool _showDownloadDetails = false;
  bool _hasCachedDownload = false;
  int _cachedBytes = 0;
  late AnimationController _animationController;
  late final _AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    // Call after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForCachedDownload().then((_) {
        // Auto-trigger download or install based on flags
        if (widget.autoDownload && !_isDownloading) {
          _downloadAndInstall();
        } else if (widget.autoInstall &&
            _hasCachedDownload &&
            _cachedBytes >= widget.updateInfo.fileSize) {
          _downloadAndInstall(); // Will auto-install if already downloaded
        }
      });
    });

    // Listen for permission granted callback
    ApkInstallerService.setMethodCallHandler(_handleMethodCall);

    // Listen for app lifecycle changes
    _lifecycleObserver = _AppLifecycleObserver(onResumed: _onAppResumed);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  Future<void> _onAppResumed() async {
    // Check if we're waiting for permission
    if (_errorMessage != null &&
        _errorMessage!.contains('Installation permission required')) {
      // Check if permission is now granted
      final canInstall = await ApkInstallerService.canInstallPackages();
      if (canInstall && mounted) {
        setState(() {
          _errorMessage = null;
        });
        // Auto-retry installation
        await _downloadAndInstall();
      }
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'permissionGranted':
      case 'permissionGrantedInstallStarted':
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
          // Auto-retry installation
          await _downloadAndInstall();
        }
        break;
      case 'permissionWaiting':
        debugPrint('⏳ Waiting for permission: ${call.arguments}');
        break;
      case 'permissionTimeout':
        if (mounted) {
          setState(() {
            _errorMessage = 'Permission request timed out. Please try again.';
          });
        }
        break;
      case 'installFailed':
        if (mounted) {
          setState(() {
            _errorMessage = 'Installation failed: ${call.arguments}';
          });
        }
        break;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  String _parseReleaseNotes(String notes) {
    return notes
        .replaceAll(
          RegExp(r'^#{1,6}\s+', multiLine: true),
          '',
        ) // Remove markdown headers
        .replaceAll(
          RegExp(r'\*{1,2}([^*]+)\*{1,2}'),
          r'$1',
        ) // Remove bold/italic
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1') // Remove code blocks
        .replaceAll(RegExp(r'~~([^~]+)~~'), r'$1') // Remove strikethrough
        .replaceAll(
          RegExp(r'\$(\d+)'),
          r'[\$1]',
        ) // Fix $1 issue by wrapping in brackets
        .replaceAll(
          RegExp(r'- '),
          '• ',
        ) // Convert markdown bullets to proper bullets
        .replaceAll(RegExp(r'\n\n+'), '\n\n') // Normalize multiple newlines
        .replaceAll('  ', '\n') // Double space to newline
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDownloading, // Prevent back button during download
      onPopInvoked: (didPop) {
        if (!didPop && _isDownloading) {
          unawaited(HapticFeedbackService().vibratingForNotAllowed());

          // Show warning if user tries to go back during download
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please wait for download to complete'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: ScaleTransition(
        scale: CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeOutBack,
        ),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF0A1929), const Color(0xFF05090F)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: const Color(0xFF2196F3).withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2196F3).withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with animated Lottie icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2196F3).withOpacity(0.15),
                        const Color(0xFF1976D2).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF2196F3).withOpacity(0.2),
                              const Color(0xFF1976D2).withOpacity(0.1),
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2196F3).withOpacity(0.4),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Lottie.asset(
                          'assets/animations/pepe_listen.json',
                          fit: BoxFit.contain,
                          repeat: true,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isDownloading ? 'Updating to...' : 'Update Available',
                        style: GoogleFonts.inter(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF2196F3).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'v${widget.updateInfo.latestVersion}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFBBDEFB),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Show info cards only when not downloading
                          if (!_showDownloadDetails) ...[
                            // Version Info Cards - HORIZONTAL GRID
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoCard(
                                    icon: Icons.info_outline_rounded,
                                    label: 'Current',
                                    value: widget.updateInfo.currentVersion,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildInfoCard(
                                    icon: Icons.new_releases_outlined,
                                    label: 'Latest',
                                    value: widget.updateInfo.latestVersion,
                                    color: const Color(0xFF4CAF50),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildInfoCard(
                              icon: Icons.cloud_download_outlined,
                              label: 'Download Size',
                              value: widget.updateInfo.fileSizeFormatted,
                              color: const Color(0xFF2196F3),
                            ),

                            // Cache indicator
                            if (_hasCachedDownload) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF4CAF50,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF4CAF50,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF4CAF50,
                                        ).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.cached_rounded,
                                        size: 16,
                                        color: Color(0xFF4CAF50),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _cachedBytes >=
                                                    widget.updateInfo.fileSize
                                                ? 'Ready to Install'
                                                : 'Download in Progress',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: const Color(0xFF4CAF50),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _cachedBytes >=
                                                    widget.updateInfo.fileSize
                                                ? 'App already downloaded'
                                                : '${UpdateManagerService.formatFileSize(_cachedBytes)} downloaded',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: Colors.white.withOpacity(
                                                0.5,
                                              ),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _clearCache,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'Clear',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: const Color(0xFF4CAF50),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Release Notes
                            if (widget.updateInfo.releaseNotes.isNotEmpty &&
                                !_isDownloading &&
                                _errorMessage == null) ...[
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          const Color(0xFF2196F3),
                                          const Color(0xFF1976D2),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'What\'s New',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 160,
                                ),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    _parseReleaseNotes(
                                      widget.updateInfo.releaseNotes,
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: Colors.white.withOpacity(0.8),
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],

                          // Download Progress - shown when downloading
                          if (_showDownloadDetails) ...[
                            const SizedBox(height: 8),
                            Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor: _downloadProgress,
                                        child: Container(
                                          height: 12,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                const Color(0xFF2196F3),
                                                const Color(0xFF1976D2),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF2196F3,
                                                ).withOpacity(0.5),
                                                blurRadius: 8,
                                                spreadRadius: 0,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 32,
                                        color: const Color(0xFF2196F3),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (_downloadSpeed.isNotEmpty)
                                      Text(
                                        _downloadSpeed,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 16,
                                          color: Colors.white.withOpacity(0.7),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _downloadStatus,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ],

                          // Error Message
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4458).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFF4458,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: const Color(0xFFFF4458),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _errorMessage!,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: const Color(0xFFFF4458),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (_errorMessage!.contains(
                                          'Installation permission required',
                                        ))
                                          TextButton.icon(
                                            onPressed: () async {
                                              try {
                                                await ApkInstallerService.openInstallPermissionSettings();
                                              } catch (e) {
                                                debugPrint(
                                                  '⚠️ Could not open settings: $e',
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.settings,
                                              size: 16,
                                            ),
                                            label: Text(
                                              'Tap To Go to Settings',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFFF4458,
                                              ),
                                              padding: EdgeInsets.zero,
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          )
                                        else
                                          Text(
                                            'Tap "Retry" to try again',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: const Color(
                                                0xFFFF4458,
                                              ).withOpacity(0.7),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: Row(
                    children: [
                      if (!_isDownloading) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white.withOpacity(0.8),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.2),
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Later',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: _isDownloading ? 1 : 2,
                        child: ElevatedButton(
                          onPressed: _isDownloading
                              ? null
                              : (_errorMessage != null &&
                                    _errorMessage!.contains(
                                      'Installation permission required',
                                    ))
                              ? () async {
                                  try {
                                    // Clear error to show we're waiting
                                    setState(() {
                                      _errorMessage = null;
                                    });

                                    await ApkInstallerService.openInstallPermissionSettings();

                                    // Show waiting message
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                            'Waiting for permission... App will continue automatically',
                                          ),
                                          backgroundColor: Colors.orange,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          margin: const EdgeInsets.all(16),
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      '⚠️ Could not open settings: $e',
                                    );
                                  }
                                }
                              : _downloadAndInstall,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(
                              0xFF2196F3,
                            ).withOpacity(0.4),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                            shadowColor: const Color(
                              0xFF2196F3,
                            ).withOpacity(0.5),
                          ),
                          child: _isDownloading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white.withOpacity(0.9),
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        'Downloading...',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      (_errorMessage != null &&
                                              _errorMessage!.contains(
                                                'Installation permission required',
                                              ))
                                          ? Icons.settings_rounded
                                          : _errorMessage != null
                                          ? Icons.refresh_rounded
                                          : (_hasCachedDownload &&
                                                _cachedBytes >=
                                                    widget.updateInfo.fileSize)
                                          ? Icons.install_mobile_rounded
                                          : Icons.download_rounded,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        (_errorMessage != null &&
                                                _errorMessage!.contains(
                                                  'Installation permission required',
                                                ))
                                            ? 'Open Settings'
                                            : _errorMessage != null
                                            ? 'Retry'
                                            : (_hasCachedDownload &&
                                                  _cachedBytes >=
                                                      widget
                                                          .updateInfo
                                                          .fileSize)
                                            ? 'Install Now'
                                            : 'Update Now',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall() async {
    // If cache is complete, check permission first before showing download UI
    if (_hasCachedDownload && _cachedBytes >= widget.updateInfo.fileSize) {
      final canInstall = await ApkInstallerService.canInstallPackages();

      if (!canInstall) {
        setState(() {
          _errorMessage =
              'Installation permission required. Go to Settings > Apps > VibeFlow > Install unknown apps and enable it, then retry.';
        });
        return;
      }

      // Permission granted, install directly
      try {
        final tempDir = await getTemporaryDirectory();
        final fileName =
            'vibeflow_${widget.updateInfo.latestVersion}_${widget.updateInfo.architecture}.apk';
        final apkPath = '${tempDir.path}/$fileName';

        await ApkInstallerService.installApk(apkPath);

        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        debugPrint('❌ Install failed: $e');
        if (mounted) {
          setState(() {
            _errorMessage = 'Installation failed. Please try again.';
          });
        }
      }
      return;
    }

    // Normal download flow
    setState(() {
      _isDownloading = true;
      _showDownloadDetails = true;
      _errorMessage = null;
    });

    try {
      DateTime lastUpdate = DateTime.now();
      int lastDownloaded = 0;

      final apkPath = await UpdateManagerService.downloadUpdateWithResume(
        widget.updateInfo,
        (progress, downloaded, total) {
          if (mounted) {
            final now = DateTime.now();
            final timeDiff = now.difference(lastUpdate).inMilliseconds;

            if (timeDiff > 500) {
              final bytesDiff = downloaded - lastDownloaded;
              final speed = (bytesDiff / timeDiff) * 1000;

              setState(() {
                _downloadProgress = progress;
                _downloadStatus =
                    '${UpdateManagerService.formatFileSize(downloaded)} / ${UpdateManagerService.formatFileSize(total)}';
                _downloadSpeed =
                    '${UpdateManagerService.formatFileSize(speed.toInt())}/s';
              });

              lastUpdate = now;
              lastDownloaded = downloaded;
            }
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadStatus = 'Installing...';
          _downloadSpeed = '';
        });
      }

      final canInstall = await ApkInstallerService.canInstallPackages();

      if (!canInstall) {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Installation permission required. Go to Settings > Apps > VibeFlow > Install unknown apps and enable it, then retry.';
            _isDownloading = false;
            _showDownloadDetails = false;
          });
        }
        return;
      }

      await ApkInstallerService.installApk(apkPath);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Update failed: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Download failed. Network error or interrupted.';
          _isDownloading = false;
          _showDownloadDetails = false;
          _downloadProgress = 0.0;
          _downloadSpeed = '';
        });
      }
    }
  }

  Future<void> _checkForCachedDownload() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'vibeflow_${widget.updateInfo.latestVersion}_${widget.updateInfo.architecture}.apk';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        final size = await file.length();
        if (size > 0) {
          setState(() {
            _hasCachedDownload = true;
            _cachedBytes = size;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking cache: $e');
    }
  }

  Future<void> _clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'vibeflow_${widget.updateInfo.latestVersion}_${widget.updateInfo.architecture}.apk';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        setState(() {
          _hasCachedDownload = false;
          _cachedBytes = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Download cache cleared'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Future<void> Function() onResumed;

  _AppLifecycleObserver({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
