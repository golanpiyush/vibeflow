import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/quick_picks_model.dart';
import 'package:vibeflow/services/audio_service.dart';
import 'package:vibeflow/utils/deepLinkService.dart';

final songSharingServiceProvider = Provider<SongSharingService>((ref) {
  return SongSharingService(ref);
});

class SongSharingService {
  final Ref _ref;

  SongSharingService(this._ref);

  /// Share currently playing song with access code validation
  Future<void> shareSong() async {
    // Check if user has access code
    final hasAccessCode = await _ref.read(hasAccessCodeProvider.future);

    if (!hasAccessCode) {
      throw Exception('You need an access code to share songs');
    }

    await _shareSongInternal();
  }

  /// Share currently playing song without access code check
  Future<void> shareSongPublic() async {
    await _shareSongInternal();
  }

  // Future<String> _shortenUrl(String longUrl) async {
  //   try {
  //     final response = await http
  //         .get(
  //           Uri.parse(
  //             'https://tinyurl.com/api-create.php?url=${Uri.encodeComponent(longUrl)}',
  //           ),
  //         )
  //         .timeout(const Duration(seconds: 5));

  //     if (response.statusCode == 200 && response.body.startsWith('https://')) {
  //       return response.body.trim();
  //     }
  //   } catch (e) {
  //     print('⚠️ URL shortening failed, using original: $e');
  //   }
  //   return longUrl;
  // }

  /// Internal method to handle actual sharing - uses CURRENT media item
  Future<void> _shareSongInternal() async {
    final audioService = AudioServices.instance;
    final currentMedia = audioService.currentMediaItem;

    if (currentMedia == null) {
      throw Exception('No song is currently playing');
    }

    final currentSong = QuickPick(
      videoId: currentMedia.id,
      title: currentMedia.title,
      artists: currentMedia.artist ?? 'Unknown Artist',
      thumbnail: currentMedia.artUri?.toString() ?? '',
      duration: currentMedia.duration?.inSeconds.toString(),
    );

    print('🎵 [Share] Sharing: ${currentSong.title}');

    final deepLinkService = _ref.read(deepLinkServiceProvider);
    final songLink = deepLinkService.generateSongLink(
      currentSong.videoId,
      currentSong,
    );

    print('🔗 [Share] Link: $songLink');

    final shareText =
        '''
🎵 "${currentSong.title}" by ${currentSong.artists}

$songLink
''';

    await Share.share(shareText, subject: 'Listen on VibeFlow');
    print('✅ [Share] Share dialog opened');
  }
}
