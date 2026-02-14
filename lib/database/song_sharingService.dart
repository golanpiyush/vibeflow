import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/utils/deepLinkService.dart';

final songSharingServiceProvider = Provider<SongSharingService>((ref) {
  return SongSharingService(ref);
});

class SongSharingService {
  final Ref _ref;

  SongSharingService(this._ref);

  /// Share a song with access code validation
  Future<void> shareSong(QuickPick song) async {
    // Check if user has access code
    final hasAccessCode = await _ref.read(hasAccessCodeProvider.future);

    if (!hasAccessCode) {
      throw Exception('You need an access code to share songs');
    }

    await _shareSongInternal(song);
  }

  /// Share a song without access code check
  Future<void> shareSongPublic(QuickPick song) async {
    await _shareSongInternal(song);
  }

  Future<String> _shortenUrl(String longUrl) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://tinyurl.com/api-create.php?url=${Uri.encodeComponent(longUrl)}',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.body.startsWith('https://')) {
        return response.body.trim();
      }
    } catch (e) {
      print('⚠️ URL shortening failed, using original: $e');
    }
    return longUrl;
  }

  /// Internal method to handle actual sharing
  Future<void> _shareSongInternal(QuickPick song) async {
    final deepLinkService = _ref.read(deepLinkServiceProvider);
    final longLink = deepLinkService.generateSongLink(song.videoId, song);

    // Shorten it
    final songLink = await _shortenUrl(longLink);

    final shareText =
        '''
🎵 "${song.title}" by ${song.artists}

$songLink
''';

    await Share.share(shareText, subject: 'Listen on VibeFlow');
  }
}
