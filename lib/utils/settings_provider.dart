import 'package:flutter_riverpod/legacy.dart';
import 'package:vibeflow/models/settings_model.dart';
import 'package:vibeflow/utils/lyrics_provider.dart' as lyrics_provider;

class SettingsNotifier extends StateNotifier<SettingsModel> {
  SettingsNotifier() : super(SettingsModel());

  void setLyricsProvider(lyrics_provider.LyricsSource source) {
    state = state.copyWith(lyricsProvider: source);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsModel>(
  (ref) => SettingsNotifier(),
);
