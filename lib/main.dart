// lib/main.dart - UPDATED WITH ACCESS CODE SYSTEM
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:vibeflow/database/database_service.dart';
import 'package:vibeflow/pages/access_code_management_screen.dart';
import 'package:vibeflow/pages/authOnboard/access_code_screen.dart';
import 'package:vibeflow/pages/authOnboard/profile_setup_screen.dart';
import 'package:vibeflow/pages/home_page.dart';
import 'package:vibeflow/services/access_code_wrapper.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/services/haptic_feedback_service.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/services/supabase_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🗄️ Initialize Database FIRST
  final dbService = DatabaseService();
  await dbService.database; // This ensures DB is created and ready
  print('✅ Local database initialized');

  // 🔐 Initialize Supabase
  await SupabaseInitializer.initialize();
  print('✅ Supabase initialized');

  // 🎵 Initialize Audio Service
  await AudioServices.init();
  print('✅ Audio service initialized');

  // 🔔 Initialize Awesome Notifications
  await _initAwesomeNotifications();
  print('✅ Notifications initialized');

  // 📱 Initialize haptic feedback
  await HapticFeedbackService().initialize();
  print('✅ Haptic feedback initialized');

  // 🎛 System UI styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: VibeFlowApp()));
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
    debug: false, // Set to false in production
  );

  // Android 13+ permission (handled safely)
  final isAllowed = await AwesomeNotifications().isNotificationAllowed();
  if (!isAllowed) {
    await AwesomeNotifications().requestPermissionToSendNotifications();
  }
}

class VibeFlowApp extends ConsumerWidget {
  const VibeFlowApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch theme providers
    final themeState = ref.watch(themeProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return MaterialApp(
      title: 'VibeFlow',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeNotifier.themeMode,
      home: const AccessCodeWrapper(), // Updated to use AccessCodeWrapper
      // Define your routes here
      routes: {
        '/home': (context) => const HomePage(), // Add this line
        '/access-code': (context) =>
            const AccessCodeScreen(showSkipButton: true),
        '/profile-setup': (context) => ProfileSetupScreen(accessCode: ''),
        '/access-code-management': (context) =>
            const AccessCodeManagementScreen(),
      },
      scaffoldMessengerKey: AudioErrorHandler.scaffoldMessengerKey,
    );
  }
}

// Audio Error Handler (same as before)
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
