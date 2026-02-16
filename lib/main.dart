// lib/main.dart - FIXED VERSION
// Key changes:
// 1. Changed notification icon to use existing 'mipmap/ic_launcher'
// 2. Set androidStopForegroundOnPause to false to keep notification visible

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:vibeflow/database/database_service.dart';
import 'package:vibeflow/installer_services/update_manager_service.dart';
import 'package:vibeflow/managers/download_manager.dart';
import 'package:vibeflow/pages/access_code_management_screen.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/pages/authOnboard/profile_setup_screen.dart';
import 'package:vibeflow/pages/home_page.dart';
import 'package:vibeflow/providers/immersive_mode_provider.dart';
import 'package:vibeflow/services/access_code_wrapper.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';
import 'package:vibeflow/services/sync_services/musicIntelligence.dart';
import 'package:vibeflow/utils/deepLinkService.dart';
import 'package:vibeflow/utils/secure_storage.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/services/supabase_initializer.dart';
import 'package:vibeflow/widgets/ban_wrapper.dart';
import 'package:vibeflow/widgets/global_miniplayer.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<bool> isMiniplayerVisible = ValueNotifier(true);

Future<void> main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('❌ [Flutter Error] ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('❌ [Platform Error] $error');
    debugPrint('Stack: $stack');
    return true;
  };

  WidgetsFlutterBinding.ensureInitialized();

  final dbService = DatabaseService();
  await dbService.database;
  print('✅ Local database initialized');

  await SupabaseInitializer.initialize();
  print('✅ Supabase initialized');

  await AudioServices.init();
  print('✅ Audio service initialized');

  await _initializeAiSystem();
  print('✅ AI system check complete');

  final updateReport = await DownloadService.checkAfterUpdate();
  if (updateReport.wasUpdated) {
    print(
      '🔄 App updated: ${updateReport.oldVersion} -> ${updateReport.newVersion}',
    );
    print(
      '📦 Downloads verified: ${updateReport.validFiles} files intact (${updateReport.formattedStorage})',
    );
  } else if (updateReport.isFirstLaunch) {
    print('🆕 First launch - Welcome to VibeFlow!');
  } else {
    print('✅ Downloads verified (no update)');
  }

  await _initAwesomeNotifications();
  print('✅ Notifications initialized');

  await HapticFeedbackService().initialize();
  print('✅ Haptic feedback initialized');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  _setupNotificationListeners();

  runApp(const ProviderScope(child: VibeFlowApp()));
}

void _setupNotificationListeners() {
  AwesomeNotifications().setListeners(
    onActionReceivedMethod: (ReceivedAction receivedAction) async {
      debugPrint('🔔 Notification action: ${receivedAction.buttonKeyPressed}');
    },
    onNotificationCreatedMethod: (ReceivedNotification notification) async {
      debugPrint('🔔 Notification created: ${notification.title}');
    },
    onNotificationDisplayedMethod: (ReceivedNotification notification) async {
      debugPrint('🔔 Notification displayed: ${notification.title}');
    },
    onDismissActionReceivedMethod: (ReceivedAction receivedAction) async {
      debugPrint('🔔 Notification dismissed: ${receivedAction.title}');
    },
  );
}

Future<void> _initializeAiSystem() async {
  try {
    final secureStorage = SecureStorageService();
    final accessCode = await secureStorage.getAccessCode();

    if (accessCode != null && accessCode.isNotEmpty) {
      await MusicIntelligenceOrchestrator.init();
      print('✅ AI Playlist System initialized');
    } else {
      print('ℹ️ AI system skipped - no access code');
    }
  } catch (e) {
    print('❌ Failed to initialize AI Playlist System: $e');
  }
}

Future<void> _initAwesomeNotifications() async {
  await AwesomeNotifications().initialize(null, [
    NotificationChannel(
      channelKey: 'download_channel',
      channelName: 'Music Playback',
      channelDescription: 'Now playing controls and music notifications',
      defaultColor: const Color(0xFF9C27B0),
      ledColor: Colors.white,
      importance: NotificationImportance.Max,
      channelShowBadge: true,
      playSound: false,
      enableVibration: false,
      criticalAlerts: true,
    ),
    NotificationChannel(
      channelKey: 'audio_error_channel',
      channelName: 'Audio Errors',
      channelDescription: 'Notifications for audio playback errors',
      defaultColor: const Color(0xFFFF4458),
      ledColor: Colors.red,
      importance: NotificationImportance.High,
      channelShowBadge: false,
      playSound: true,
      enableVibration: true,
    ),
    NotificationChannel(
      channelKey: 'social_updates_channel',
      channelName: 'Social Updates',
      channelDescription: 'Notifications for social features',
      defaultColor: const Color(0xFF2196F3),
      ledColor: Colors.blue,
      importance: NotificationImportance.Default,
      channelShowBadge: true,
      playSound: false,
      enableVibration: true,
    ),
  ], debug: false);

  final isAllowed = await AwesomeNotifications().isNotificationAllowed();
  if (!isAllowed) {
    await AwesomeNotifications().requestPermissionToSendNotifications();
  }
}

Future<Widget> _determineInitialRoute() async {
  final hasOrphan = await AccessCodeScreen.hasOrphanAccessCode();
  if (hasOrphan) {
    final secureStorage = SecureStorageService();
    final accessCode = await secureStorage.getAccessCode();
    return ProfileSetupScreen(accessCode: accessCode ?? '');
  }

  return const AccessCodeWrapper();
}

class AudioErrorHandler {
  static final AudioErrorHandler _instance = AudioErrorHandler._internal();
  factory AudioErrorHandler() => _instance;
  AudioErrorHandler._internal();

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void showAudioUrlError(BuildContext? context, String songTitle) {
    final message = 'Unable to play "$songTitle". Audio source unavailable.';

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFFF4458),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } else {
      _showErrorNotification(songTitle);
    }
  }

  static void showNetworkError(BuildContext? context) {
    final message = 'Network error. Please check your connection.';
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFFF6B35),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  static void showRetryError(
    BuildContext? context,
    String songTitle,
    VoidCallback onRetry,
  ) {
    final message = 'Failed to load "$songTitle"';
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFFF9500),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: onRetry,
          ),
        ),
      );
    }
  }

  static void showSuccess(BuildContext? context, String message) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static Future<void> _showErrorNotification(String songTitle) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'audio_error_channel',
        title: 'Playback Error',
        body: 'Unable to play "$songTitle". Please try again.',
        notificationLayout: NotificationLayout.Default,
        autoDismissible: true,
        color: const Color(0xFFFF4458),
      ),
    );
  }
}

class VibeFlowApp extends ConsumerStatefulWidget {
  const VibeFlowApp({Key? key}) : super(key: key);

  @override
  ConsumerState<VibeFlowApp> createState() => _VibeFlowAppState();
}

class _VibeFlowAppState extends ConsumerState<VibeFlowApp> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final deepLinkService = ref.read(deepLinkServiceProvider);
      deepLinkService.initDeepLinks(context);
      print('✅ Deep linking initialized');
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'VibeFlow',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeNotifier.themeMode,
      // ✅ builder wraps EVERY route — miniplayer persists across all pages
      builder: (context, child) {
        final isImmersive = ref.watch(immersiveModeProvider);
        final bottomInset = MediaQuery.of(context).padding.bottom;

        if (isImmersive) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }

        return ValueListenableBuilder<bool>(
          valueListenable: isMiniplayerVisible,
          builder: (context, isVisible, _) {
            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    // ✅ Remove bottom padding when miniplayer is hidden
                    bottom: (!isVisible || isImmersive)
                        ? 0
                        : kMiniplayerHeight + bottomInset,
                  ),
                  child: child!,
                ),
                // ✅ Only render miniplayer when visible
                if (isVisible) const GlobalMiniplayer(),
              ],
            );
          },
        );
      },
      home: BanWrapper(
        child: FutureBuilder<Widget>(
          future: _determineInitialRoute(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final initialScreen = snapshot.data ?? const AccessCodeWrapper();

            _hasValidAccessCode().then((hasAccess) {
              if (hasAccess) {
                initializeAiPlaylistSystem();
              }
            });

            return initialScreen;
          },
        ),
      ),
      routes: {
        '/home': (context) => const BanWrapper(child: HomePage()),
        '/access-code': (context) =>
            const BanWrapper(child: AccessCodeScreen(showSkipButton: true)),
        '/profile-setup': (context) =>
            BanWrapper(child: ProfileSetupScreen(accessCode: '')),
        '/access-code-management': (context) =>
            const BanWrapper(child: AccessCodeManagementScreen()),
      },
      scaffoldMessengerKey: AudioErrorHandler.scaffoldMessengerKey,
    );
  }
}

Future<void> initializeAiPlaylistSystem() async {
  try {
    await MusicIntelligenceOrchestrator.init();
    print('✅ AI Playlist System initialized');
  } catch (e) {
    print('❌ Failed to initialize AI Playlist System: $e');
  }
}

Future<bool> _hasValidAccessCode() async {
  final secureStorage = SecureStorageService();
  final accessCode = await secureStorage.getAccessCode();
  return accessCode != null && accessCode.isNotEmpty;
}
