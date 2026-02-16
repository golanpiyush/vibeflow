// // lib/providers/update_settings_provider.dart
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_riverpod/legacy.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// // Keys for SharedPreferences
// const String _keyUpdateNotifications = 'update_notifications_enabled';
// const String _keyAutoUpdateOnStart = 'auto_update_on_start_enabled';

// // Provider for update notifications setting
// final updateNotificationsProvider =
//     StateNotifierProvider<UpdateNotificationsNotifier, bool>((ref) {
//       return UpdateNotificationsNotifier();
//     });

// class UpdateNotificationsNotifier extends StateNotifier<bool> {
//   UpdateNotificationsNotifier() : super(true) {
//     _loadSetting();
//   }

//   Future<void> _loadSetting() async {
//     final prefs = await SharedPreferences.getInstance();
//     state = prefs.getBool(_keyUpdateNotifications) ?? true;
//   }

//   Future<void> toggle() async {
//     final newValue = !state;
//     state = newValue;
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setBool(_keyUpdateNotifications, newValue);
//   }

//   Future<void> setValue(bool value) async {
//     state = value;
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setBool(_keyUpdateNotifications, value);
//   }
// }

// // Provider for auto-update on start setting
// final autoUpdateOnStartProvider =
//     StateNotifierProvider<AutoUpdateOnStartNotifier, bool>((ref) {
//       return AutoUpdateOnStartNotifier();
//     });

// class AutoUpdateOnStartNotifier extends StateNotifier<bool> {
//   AutoUpdateOnStartNotifier() : super(true) {
//     _loadSetting();
//   }

//   Future<void> _loadSetting() async {
//     final prefs = await SharedPreferences.getInstance();
//     state = prefs.getBool(_keyAutoUpdateOnStart) ?? true;
//   }

//   Future<void> toggle() async {
//     final newValue = !state;
//     state = newValue;
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setBool(_keyAutoUpdateOnStart, newValue);
//   }

//   Future<void> setValue(bool value) async {
//     state = value;
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setBool(_keyAutoUpdateOnStart, value);
//   }
// }
