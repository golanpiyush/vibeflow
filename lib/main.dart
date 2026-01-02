// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

import 'package:vibeflow/constants/app_theme.dart';
import 'package:vibeflow/pages/home_page.dart';
import 'package:vibeflow/services/audio_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔊 Initialize Background Audio Service
  await AudioServices.init();

  // 🔔 Initialize Awesome Notifications
  await _initAwesomeNotifications();

  // 🎛 System UI styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const VibeFlowApp());
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
        defaultColor: Color(0xFF9C27B0),
        ledColor: Colors.white,
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: false,
        enableVibration: false,
      ),
    ],
    debug: true,
  );

  // Android 13+ permission (handled safely)
  final isAllowed = await AwesomeNotifications().isNotificationAllowed();
  if (!isAllowed) {
    await AwesomeNotifications().requestPermissionToSendNotifications();
  }
}

class VibeFlowApp extends StatelessWidget {
  const VibeFlowApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomePage(),
    );
  }
}
