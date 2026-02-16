// lib/providers/immersive_provider.dart
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final immersiveModeProvider =
    StateNotifierProvider<ImmersiveModeNotifier, bool>((ref) {
      return ImmersiveModeNotifier();
    });

class ImmersiveModeNotifier extends StateNotifier<bool> {
  ImmersiveModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('immersive_mode') ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('immersive_mode', state);
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('immersive_mode', value);
  }
}
