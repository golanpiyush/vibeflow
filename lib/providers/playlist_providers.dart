// lib/providers/playlist_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/database/database_service.dart';
import 'package:vibeflow/models/DBSong.dart';
import 'package:vibeflow/models/playlist_model.dart';

// Database provider
final databaseProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

// Playlist repository provider (properly initialized)
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final dbService = ref.watch(databaseProvider);

  // This returns a FutureProvider that waits for DB initialization
  // But we need synchronous access, so we'll use a different approach
  throw UnimplementedError('Use playlistRepositoryFutureProvider instead');
});

// Future-based repository provider (async initialization)
final playlistRepositoryFutureProvider = FutureProvider<PlaylistRepository>((
  ref,
) async {
  final dbService = ref.watch(databaseProvider);
  final db = await dbService.database;
  return PlaylistRepository(db);
});

// Playlists provider (loads all playlists)
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final repo = await ref.watch(playlistRepositoryFutureProvider.future);
  return await repo.getAllPlaylists();
});

// Single playlist provider
final playlistProvider = FutureProvider.family<Playlist?, int>((
  ref,
  playlistId,
) async {
  final repo = await ref.watch(playlistRepositoryFutureProvider.future);
  return await repo.getPlaylistById(playlistId);
});

// Playlist with songs provider
final playlistWithSongsProvider =
    FutureProvider.family<PlaylistWithSongs?, int>((ref, playlistId) async {
      final repo = await ref.watch(playlistRepositoryFutureProvider.future);
      return await repo.getPlaylistWithSongs(playlistId);
    });

// Songs in playlist provider
final playlistSongsProvider = FutureProvider.family<List<DbSong>, int>((
  ref,
  playlistId,
) async {
  final repo = await ref.watch(playlistRepositoryFutureProvider.future);
  return await repo.getPlaylistSongs(playlistId);
});

// Playlists containing a specific song
final playlistsContainingSongProvider =
    FutureProvider.family<List<Playlist>, String>((ref, videoId) async {
      final repo = await ref.watch(playlistRepositoryFutureProvider.future);
      return await repo.getPlaylistsContainingSong(videoId);
    });
