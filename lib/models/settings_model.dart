import 'package:vibeflow/utils/lyrics_provider.dart' as lyrics_provider;

class SettingsModel {
  final lyrics_provider.LyricsSource lyricsProvider;

  SettingsModel({this.lyricsProvider = lyrics_provider.LyricsSource.kugou});

  SettingsModel copyWith({lyrics_provider.LyricsSource? lyricsProvider}) {
    return SettingsModel(lyricsProvider: lyricsProvider ?? this.lyricsProvider);
  }
}
