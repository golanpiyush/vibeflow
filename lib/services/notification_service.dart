// // lib/services/notification_service.dart
// import 'package:awesome_notifications/awesome_notifications.dart';
// import 'package:flutter/material.dart';
// import 'package:vibeflow/installer_services/update_manager_service.dart';

// class UpdateNotificationService {
//   static const String _updateChannelKey = 'vibeflow_updates';
//   static const String _updateDownloadChannelKey = 'update_downloads';

//   /// Initialize notification service with update channels
//   static Future<void> initialize() async {
//     debugPrint('🔔 Initializing update notification service...');

//     // Create update notification channels
//     await AwesomeNotifications().initialize(
//       null, // Uses app icon
//       [
//         NotificationChannel(
//           channelKey: _updateChannelKey,
//           channelName: 'App Updates',
//           channelDescription: 'Notifications for app updates and new versions',
//           defaultColor: const Color(0xFF9C27B0),
//           ledColor: Colors.purple,
//           importance: NotificationImportance.High,
//           channelShowBadge: true,
//           playSound: true,
//           enableVibration: true,
//           enableLights: true,
//         ),
//         NotificationChannel(
//           channelKey: _updateDownloadChannelKey,
//           channelName: 'Update Downloads',
//           channelDescription: 'Download progress for app updates',
//           defaultColor: const Color(0xFF2196F3),
//           ledColor: Colors.blue,
//           importance: NotificationImportance.Low,
//           channelShowBadge: false,
//           playSound: false,
//           enableVibration: false,
//           onlyAlertOnce: true,
//         ),
//       ],
//       debug: false,
//     );

//     debugPrint('✅ Update notification service initialized');

//     // Request permissions if not already granted
//     await _requestPermissions();
//   }

//   /// Request notification permissions
//   static Future<void> _requestPermissions() async {
//     final isAllowed = await AwesomeNotifications().isNotificationAllowed();

//     if (!isAllowed) {
//       debugPrint('📬 Requesting notification permissions...');
//       final granted = await AwesomeNotifications()
//           .requestPermissionToSendNotifications();
//       debugPrint('📬 Notification permission granted: $granted');
//     } else {
//       debugPrint('✅ Notification permissions already granted');
//     }
//   }

//   /// Show update available notification
//   static Future<void> showUpdateAvailableNotification(
//     UpdateInfo updateInfo,
//   ) async {
//     try {
//       debugPrint('📬 Showing update notification...');

//       await AwesomeNotifications().createNotification(
//         content: NotificationContent(
//           id: 100, // Fixed ID for update notifications
//           channelKey: _updateChannelKey,
//           title: '🎉 Update Available!',
//           body:
//               'VibeFlow v${updateInfo.latestVersion} is ready to install (${updateInfo.fileSizeFormatted})',
//           notificationLayout: NotificationLayout.Default,
//           bigPicture: null,
//           largeIcon: null,
//           payload: {
//             'type': 'update_available',
//             'version': updateInfo.latestVersion,
//             'downloadUrl': updateInfo.downloadUrl,
//             'fileSize': updateInfo.fileSize.toString(),
//           },
//           autoDismissible: true,
//           color: const Color(0xFF9C27B0),
//           backgroundColor: const Color(0xFF9C27B0),
//           category: NotificationCategory.Recommendation,
//           actionType: ActionType.Default,
//         ),
//         actionButtons: [
//           NotificationActionButton(
//             key: 'download_update',
//             label: 'Download Now',
//             color: const Color(0xFF9C27B0),
//             autoDismissible: true,
//             actionType: ActionType.Default,
//           ),
//           NotificationActionButton(
//             key: 'dismiss_update',
//             label: 'Later',
//             autoDismissible: true,
//             actionType: ActionType.DismissAction,
//           ),
//         ],
//       );

//       debugPrint('✅ Update notification shown successfully');
//     } catch (e) {
//       debugPrint('❌ Failed to show update notification: $e');
//     }
//   }

//   /// Show download progress notification
//   static Future<void> showDownloadProgressNotification({
//     required String version,
//     required int progress,
//     required int downloaded,
//     required int total,
//   }) async {
//     try {
//       await AwesomeNotifications().createNotification(
//         content: NotificationContent(
//           id: 101, // Fixed ID for download progress
//           channelKey: _updateDownloadChannelKey,
//           title: 'Downloading v$version',
//           body:
//               'Progress: $progress% (${UpdateManagerService.formatFileSize(downloaded)} / ${UpdateManagerService.formatFileSize(total)})',
//           notificationLayout: NotificationLayout.ProgressBar,
//           progress: progress.toDouble(),
//           payload: {
//             'type': 'update_download_progress',
//             'version': version,
//             'progress': progress.toString(),
//           },
//           locked: true, // Prevent swipe to dismiss
//           autoDismissible: false,
//           color: const Color(0xFF2196F3),
//           backgroundColor: const Color(0xFF2196F3),
//           category: NotificationCategory.Progress,
//         ),
//       );
//     } catch (e) {
//       debugPrint('❌ Failed to show download progress: $e');
//     }
//   }

//   /// Show download complete notification
//   static Future<void> showDownloadCompleteNotification(String version) async {
//     try {
//       // Cancel progress notification first
//       await AwesomeNotifications().cancel(101);

//       await AwesomeNotifications().createNotification(
//         content: NotificationContent(
//           id: 102, // Different ID for completion
//           channelKey: _updateChannelKey,
//           title: '✅ Download Complete',
//           body: 'v$version is ready to install. Tap to install now.',
//           notificationLayout: NotificationLayout.Default,
//           payload: {'type': 'update_download_complete', 'version': version},
//           autoDismissible: true,
//           color: const Color(0xFF4CAF50),
//           backgroundColor: const Color(0xFF4CAF50),
//           category: NotificationCategory.Status,
//           actionType: ActionType.Default,
//         ),
//         actionButtons: [
//           NotificationActionButton(
//             key: 'install_update',
//             label: 'Install Now',
//             color: const Color(0xFF4CAF50),
//             autoDismissible: true,
//             actionType: ActionType.Default,
//           ),
//           NotificationActionButton(
//             key: 'dismiss_install',
//             label: 'Later',
//             autoDismissible: true,
//             actionType: ActionType.DismissAction,
//           ),
//         ],
//       );

//       debugPrint('✅ Download complete notification shown');
//     } catch (e) {
//       debugPrint('❌ Failed to show download complete notification: $e');
//     }
//   }

//   /// Show update check failed notification
//   static Future<void> showUpdateCheckFailedNotification(String error) async {
//     try {
//       await AwesomeNotifications().createNotification(
//         content: NotificationContent(
//           id: 103,
//           channelKey: _updateChannelKey,
//           title: '⚠️ Update Check Failed',
//           body: 'Failed to check for updates: $error',
//           notificationLayout: NotificationLayout.Default,
//           payload: {'type': 'update_check_failed', 'error': error},
//           autoDismissible: true,
//           color: const Color(0xFFFF9800),
//           backgroundColor: const Color(0xFFFF9800),
//           category: NotificationCategory.Error,
//         ),
//       );

//       debugPrint('⚠️ Update check failed notification shown');
//     } catch (e) {
//       debugPrint('❌ Failed to show error notification: $e');
//     }
//   }

//   /// Show download failed notification
//   static Future<void> showDownloadFailedNotification(String version) async {
//     try {
//       // Cancel progress notification
//       await AwesomeNotifications().cancel(101);

//       await AwesomeNotifications().createNotification(
//         content: NotificationContent(
//           id: 104,
//           channelKey: _updateChannelKey,
//           title: '❌ Download Failed',
//           body: 'Failed to download v$version. Please try again.',
//           notificationLayout: NotificationLayout.Default,
//           payload: {'type': 'update_download_failed', 'version': version},
//           autoDismissible: true,
//           color: const Color(0xFFFF4458),
//           backgroundColor: const Color(0xFFFF4458),
//           category: NotificationCategory.Error,
//         ),
//         actionButtons: [
//           NotificationActionButton(
//             key: 'retry_download',
//             label: 'Retry',
//             color: const Color(0xFFFF4458),
//             autoDismissible: true,
//             actionType: ActionType.Default,
//           ),
//           NotificationActionButton(
//             key: 'dismiss_error',
//             label: 'Dismiss',
//             autoDismissible: true,
//             actionType: ActionType.DismissAction,
//           ),
//         ],
//       );

//       debugPrint('❌ Download failed notification shown');
//     } catch (e) {
//       debugPrint('❌ Failed to show download failed notification: $e');
//     }
//   }

//   /// Cancel all update notifications
//   static Future<void> cancelAllNotifications() async {
//     try {
//       await AwesomeNotifications().cancelAll();
//       debugPrint('🗑️ All update notifications cancelled');
//     } catch (e) {
//       debugPrint('❌ Failed to cancel notifications: $e');
//     }
//   }

//   /// Cancel specific notification
//   static Future<void> cancelNotification(int id) async {
//     try {
//       await AwesomeNotifications().cancel(id);
//       debugPrint('🗑️ Notification $id cancelled');
//     } catch (e) {
//       debugPrint('❌ Failed to cancel notification $id: $e');
//     }
//   }

//   /// Check if notifications are enabled
//   static Future<bool> areNotificationsEnabled() async {
//     try {
//       return await AwesomeNotifications().isNotificationAllowed();
//     } catch (e) {
//       debugPrint('❌ Failed to check notification status: $e');
//       return false;
//     }
//   }

//   /// Open notification settings
//   static Future<void> openNotificationSettings() async {
//     try {
//       await AwesomeNotifications().showNotificationConfigPage();
//     } catch (e) {
//       debugPrint('❌ Failed to open notification settings: $e');
//     }
//   }
// }
