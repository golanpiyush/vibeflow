// lib/main.dart - WITH UPDATE CHECK ADDED
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
import 'package:vibeflow/services/access_code_wrapper.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';
import 'package:vibeflow/services/sync_services/musicIntelligence.dart';
import 'package:vibeflow/utils/secure_storage.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/services/supabase_initializer.dart';
import 'package:vibeflow/widgets/ban_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🗄️ Initialize Database FIRST
  final dbService = DatabaseService();
  await dbService.database;
  print('✅ Local database initialized');

  // 🔐 Initialize Supabase
  await SupabaseInitializer.initialize();
  print('✅ Supabase initialized');

  // 🎵 Initialize Audio Service
  await AudioServices.init();
  print('✅ Audio service initialized');

  // 🤖 Initialize AI Playlist System (if access code exists)
  await _initializeAiSystem();
  print('✅ AI system check complete');

  // 📥 Check downloads after app update (INTEGRATED)
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

  // 🔔 Initialize Awesome Notifications
  await _initAwesomeNotifications();
  print('✅ Notifications initialized');

  // 📱 Initialize haptic feedback
  await HapticFeedbackService().initialize();
  print('✅ Haptic feedback initialized');

  // // 🔄 CHECK FOR UPDATES FROM GITHUB - ADD THIS SECTION
  // print('🔍 Checking for app updates from GitHub...');
  // try {
  //   final updateResult = await UpdateManagerService.checkForUpdate();

  //   switch (updateResult.status) {
  //     case UpdateStatus.available:
  //       print('🎉 ${updateResult.message}');
  //       if (updateResult.updateInfo != null) {
  //         print('   Current: v${updateResult.updateInfo!.currentVersion}');
  //         print('   Latest: v${updateResult.updateInfo!.latestVersion}');
  //         print('   Size: ${updateResult.updateInfo!.fileSizeFormatted}');
  //       }
  //       break;
  //     case UpdateStatus.upToDate:
  //       print('✅ ${updateResult.message}');
  //       break;
  //     case UpdateStatus.error:
  //       print('⚠️ ${updateResult.message}');
  //       break;
  //   }
  // } catch (e) {
  //   print('⚠️ Update check failed: $e');
  // }

  // 🎛 System UI styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: VibeFlowApp()));
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
    // App can still work without AI features
  }
}

/// 🔔 Awesome Notifications setup
Future<void> _initAwesomeNotifications() async {
  await AwesomeNotifications().initialize(
    null, // Uses app icon
    [
      NotificationChannel(
        channelKey: 'download_channel',
        channelName: 'Downloads',
        channelDescription: 'Download progress notifications',
        defaultColor: const Color(0xFF9C27B0),
        ledColor: Colors.white,
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: false,
        enableVibration: false,
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
    ],
    debug: false,
  );

  final isAllowed = await AwesomeNotifications().isNotificationAllowed();
  if (!isAllowed) {
    await AwesomeNotifications().requestPermissionToSendNotifications();
  }
}

Future<Widget> _determineInitialRoute() async {
  // Check for orphan access code first
  final hasOrphan = await AccessCodeScreen.hasOrphanAccessCode();
  if (hasOrphan) {
    final secureStorage = SecureStorageService();
    final accessCode = await secureStorage.getAccessCode();
    return ProfileSetupScreen(accessCode: accessCode ?? '');
  }

  // Default route - AccessCodeWrapper will handle the rest
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

class VibeFlowApp extends ConsumerWidget {
  const VibeFlowApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return MaterialApp(
      // ❌ DON'T wrap MaterialApp with BanWrapper
      title: 'VibeFlow',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeNotifier.themeMode,

      // ✅ Wrap the home widget instead
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

            // 🔐 Gate AI initialization behind access code
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

  Future<void> initializeAiPlaylistSystem() async {
    try {
      // Initialize the orchestrator (loads .env, validates API key)
      await MusicIntelligenceOrchestrator.init();
      print('✅ AI Playlist System initialized');
    } catch (e) {
      print('❌ Failed to initialize AI Playlist System: $e');
      // App can still work without AI features
    }
  }

  Future<bool> _hasValidAccessCode() async {
    final secureStorage = SecureStorageService();
    final accessCode = await secureStorage.getAccessCode();
    return accessCode != null && accessCode.isNotEmpty;
  }
}
