// Playlist Services
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/database/listening_activity_service.dart';

class PlaylistService {
  final SupabaseClient _supabase;

  PlaylistService(this._supabase);

  Future<String> createPlaylist({
    required String name,
    required String userId,
    bool isPublic = false,
  }) async {
    try {
      final response = await _supabase
          .from('playlists')
          .insert({'name': name, 'owner_id': userId, 'is_public': isPublic})
          .select('id')
          .single();

      // Add creator as owner
      await _supabase.from('playlist_members').insert({
        'playlist_id': response['id'],
        'user_id': userId,
        'role': 'owner',
      });

      return response['id'];
    } catch (e) {
      print('Error creating playlist: $e');
      rethrow;
    }
  }

  Future<void> addSongToPlaylist({
    required String playlistId,
    required String videoId,
    required String title,
    required List<String> artists,
    required String? thumbnail,
    required String userId,
  }) async {
    try {
      final songId = ListeningActivityService.generateSongId(title, artists);

      await _supabase.from('playlist_songs').insert({
        'playlist_id': playlistId,
        'song_id': songId,
        'source_video_id': videoId,
        'song_title': title,
        'song_artists': artists,
        'song_thumbnail': thumbnail,
        'added_by': userId,
        'position': await _getNextPosition(playlistId),
      });
    } catch (e) {
      print('Error adding song to playlist: $e');
      rethrow;
    }
  }

  Future<double> _getNextPosition(String playlistId) async {
    try {
      final response = await _supabase
          .from('playlist_songs')
          .select('position')
          .eq('playlist_id', playlistId)
          .order('position', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return 0.0;

      return (response['position'] as num).toDouble() + 1.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<String?> joinPlaylistWithToken(
    String shareToken,
    String userId,
  ) async {
    try {
      // Get playlist info
      final playlist = await _supabase
          .from('playlists')
          .select('id, name')
          .eq('share_token', shareToken)
          .maybeSingle();

      if (playlist == null) {
        return null;
      }

      // Check if already a member
      final existing = await _supabase
          .from('playlist_members')
          .select('user_id')
          .eq('playlist_id', playlist['id'])
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        return playlist['id'];
      }

      // Add as viewer
      await _supabase.from('playlist_members').insert({
        'playlist_id': playlist['id'],
        'user_id': userId,
        'role': 'viewer',
      });

      return playlist['id'];
    } catch (e) {
      print('Error joining playlist: $e');
      return null;
    }
  }
}
