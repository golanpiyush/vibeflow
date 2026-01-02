import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

class LastPlayedService {
  static const String _keyVideoId = 'last_played_video_id';
  static const String _keyTitle = 'last_played_title';
  static const String _keyArtists = 'last_played_artists';
  static const String _keyThumbnail = 'last_played_thumbnail';
  static const String _keyDuration = 'last_played_duration';

  static Future<void> saveLastPlayed(QuickPick song) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVideoId, song.videoId);
    await prefs.setString(_keyTitle, song.title);
    await prefs.setString(_keyArtists, song.artists);
    await prefs.setString(_keyThumbnail, song.thumbnail);
    if (song.duration != null) {
      await prefs.setString(_keyDuration, song.duration!);
    }
  }

  static Future<QuickPick?> getLastPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final videoId = prefs.getString(_keyVideoId);

    if (videoId == null) return null;

    return QuickPick(
      videoId: videoId,
      title: prefs.getString(_keyTitle) ?? '',
      artists: prefs.getString(_keyArtists) ?? '',
      thumbnail: prefs.getString(_keyThumbnail) ?? '',
      duration: prefs.getString(_keyDuration),
    );
  }

  static Future<void> clearLastPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyVideoId);
    await prefs.remove(_keyTitle);
    await prefs.remove(_keyArtists);
    await prefs.remove(_keyThumbnail);
    await prefs.remove(_keyDuration);
  }
}
