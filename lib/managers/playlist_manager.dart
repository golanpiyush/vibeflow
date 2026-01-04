// import 'dart:async';
// import 'package:sqflite/sqflite.dart';
// import 'package:uuid/uuid.dart';
// import 'package:vibeflow/database/database_helper.dart';
// import 'package:vibeflow/models/song_model.dart';

// class PlaylistManager {
//   static final PlaylistManager instance = PlaylistManager._init();
//   final _uuid = const Uuid();

//   PlaylistManager._init();

//   Database get _db => DatabaseManager.instance.database as Database;

//   // ==================== SONG OPERATIONS ====================

//   /// Add or update a song (upsert)
//   Future<void> saveSong(Song song) async {
//     final db = await DatabaseManager.instance.database;
//     await db.insert(
//       'songs',
//       song.toMap(),
//       conflictAlgorithm: ConflictAlgorithm.replace,
//     );
//   }

//   /// Get song by videoId
//   Future<Song?> getSong(String videoId) async {
//     final db = await DatabaseManager.instance.database;
//     final results = await db.query(
//       'songs',
//       where: 'video_id = ?',
//       whereArgs: [videoId],
//       limit: 1,
//     );

//     if (results.isEmpty) return null;
//     return Song.fromMap(results.first);
//   }

//   /// Get all songs (paginated for performance)
//   Future<List<Song>> getAllSongs({int limit = 100, int offset = 0}) async {
//     final db = await DatabaseManager.instance.database;
//     final results = await db.query(
//       'songs',
//       orderBy: 'date_added DESC',
//       limit: limit,
//       offset: offset,
//     );

//     return results.map((map) => Song.fromMap(map)).toList();
//   }

//   // ==================== PLAYLIST OPERATIONS ====================

//   /// Create a new playlist
//   Future<Playlist> createPlaylist({
//     required String name,
//     String? description,
//     String? coverImage,
//     int? color,
//   }) async {
//     final db = await DatabaseManager.instance.database;
//     final now = DateTime.now().millisecondsSinceEpoch;

//     final playlist = Playlist(
//       id: _uuid.v4(),
//       name: name,
//       description: description,
//       coverImage: coverImage,
//       createdAt: now,
//       updatedAt: now,
//       color: color,
//     );

//     await db.insert('playlists', playlist.toMap());
//     return playlist;
//   }

//   /// Get all playlists
//   Future<List<Playlist>> getAllPlaylists() async {
//     final db = await DatabaseManager.instance.database;
//     final results = await db.query('playlists', orderBy: 'updated_at DESC');

//     return results.map((map) => Playlist.fromMap(map)).toList();
//   }

//   /// Get single playlist by ID
//   Future<Playlist?> getPlaylist(String playlistId) async {
//     final db = await DatabaseManager.instance.database;
//     final results = await db.query(
//       'playlists',
//       where: 'id = ?',
//       whereArgs: [playlistId],
//       limit: 1,
//     );

//     if (results.isEmpty) return null;
//     return Playlist.fromMap(results.first);
//   }

//   /// Update playlist metadata
//   Future<void> updatePlaylist(Playlist playlist) async {
//     final db = await DatabaseManager.instance.database;
//     final updatedPlaylist = playlist.copyWith();

//     await db.update(
//       'playlists',
//       updatedPlaylist.toMap(),
//       where: 'id = ?',
//       whereArgs: [playlist.id],
//     );
//   }

//   /// Delete playlist
//   Future<void> deletePlaylist(String playlistId) async {
//     final db = await DatabaseManager.instance.database;

//     // CASCADE delete will handle playlist_songs automatically
//     await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
//   }

//   // ==================== PLAYLIST ↔ SONGS OPERATIONS ====================

//   /// Add song to playlist (transaction-safe)
//   Future<bool> addSongToPlaylist({
//     required String playlistId,
//     required Song song,
//   }) async {
//     final db = await DatabaseManager.instance.database;

//     try {
//       return await db.transaction((txn) async {
//         // 1. Ensure song exists in songs table
//         await txn.insert(
//           'songs',
//           song.toMap(),
//           conflictAlgorithm: ConflictAlgorithm.ignore,
//         );

//         // 2. Check if song already in playlist
//         final existing = await txn.query(
//           'playlist_songs',
//           where: 'playlist_id = ? AND video_id = ?',
//           whereArgs: [playlistId, song.videoId],
//         );

//         if (existing.isNotEmpty) {
//           return false; // Song already in playlist
//         }

//         // 3. Get next position
//         final maxPos = await txn.rawQuery(
//           'SELECT COALESCE(MAX(position), -1) as max_pos FROM playlist_songs WHERE playlist_id = ?',
//           [playlistId],
//         );
//         final nextPosition = (maxPos.first['max_pos'] as int) + 1;

//         // 4. Insert into playlist_songs
//         await txn.insert('playlist_songs', {
//           'playlist_id': playlistId,
//           'video_id': song.videoId,
//           'position': nextPosition,
//           'added_at': DateTime.now().millisecondsSinceEpoch,
//         });

//         // 5. Update playlist metadata
//         await txn.rawUpdate(
//           '''
//           UPDATE playlists 
//           SET song_count = song_count + 1,
//               updated_at = ?
//           WHERE id = ?
//         ''',
//           [DateTime.now().millisecondsSinceEpoch, playlistId],
//         );

//         return true;
//       });
//     } catch (e) {
//       print('Error adding song to playlist: $e');
//       return false;
//     }
//   }

//   /// Remove song from playlist
//   Future<void> removeSongFromPlaylist({
//     required String playlistId,
//     required String videoId,
//   }) async {
//     final db = await DatabaseManager.instance.database;

//     await db.transaction((txn) async {
//       // 1. Get position of song to remove
//       final result = await txn.query(
//         'playlist_songs',
//         columns: ['position'],
//         where: 'playlist_id = ? AND video_id = ?',
//         whereArgs: [playlistId, videoId],
//       );

//       if (result.isEmpty) return;
//       final removedPosition = result.first['position'] as int;

//       // 2. Delete the song
//       await txn.delete(
//         'playlist_songs',
//         where: 'playlist_id = ? AND video_id = ?',
//         whereArgs: [playlistId, videoId],
//       );

//       // 3. Reorder remaining songs (fill the gap)
//       await txn.rawUpdate(
//         '''
//         UPDATE playlist_songs 
//         SET position = position - 1
//         WHERE playlist_id = ? AND position > ?
//       ''',
//         [playlistId, removedPosition],
//       );

//       // 4. Update playlist metadata
//       await txn.rawUpdate(
//         '''
//         UPDATE playlists 
//         SET song_count = song_count - 1,
//             updated_at = ?
//         WHERE id = ?
//       ''',
//         [DateTime.now().millisecondsSinceEpoch, playlistId],
//       );
//     });
//   }

//   /// Reorder songs in playlist (drag & drop)
//   Future<void> reorderPlaylistSong({
//     required String playlistId,
//     required int oldIndex,
//     required int newIndex,
//   }) async {
//     final db = await DatabaseManager.instance.database;

//     await db.transaction((txn) async {
//       if (oldIndex < newIndex) {
//         // Moving down: shift up items between old and new
//         await txn.rawUpdate(
//           '''
//           UPDATE playlist_songs 
//           SET position = position - 1
//           WHERE playlist_id = ? AND position > ? AND position <= ?
//         ''',
//           [playlistId, oldIndex, newIndex],
//         );
//       } else {
//         // Moving up: shift down items between new and old
//         await txn.rawUpdate(
//           '''
//           UPDATE playlist_songs 
//           SET position = position + 1
//           WHERE playlist_id = ? AND position >= ? AND position < ?
//         ''',
//           [playlistId, newIndex, oldIndex],
//         );
//       }

//       // Update the moved item's position
//       await txn.rawUpdate(
//         '''
//         UPDATE playlist_songs 
//         SET position = ?
//         WHERE playlist_id = ? AND position = ?
//       ''',
//         [
//           newIndex,
//           playlistId,
//           oldIndex == newIndex
//               ? oldIndex
//               : (oldIndex < newIndex ? newIndex : oldIndex),
//         ],
//       );

//       // Update playlist timestamp
//       await txn.rawUpdate(
//         '''
//         UPDATE playlists 
//         SET updated_at = ?
//         WHERE id = ?
//       ''',
//         [DateTime.now().millisecondsSinceEpoch, playlistId],
//       );
//     });
//   }

//   /// Get all songs in a playlist (ordered)
//   Future<List<PlaylistSong>> getPlaylistSongs(String playlistId) async {
//     final db = await DatabaseManager.instance.database;

//     final results = await db.rawQuery(
//       '''
//       SELECT ps.*, s.*
//       FROM playlist_songs ps
//       INNER JOIN songs s ON ps.video_id = s.video_id
//       WHERE ps.playlist_id = ?
//       ORDER BY ps.position ASC
//     ''',
//       [playlistId],
//     );

//     return results.map((map) {
//       return PlaylistSong(
//         playlistId: map['playlist_id'] as String,
//         videoId: map['video_id'] as String,
//         position: map['position'] as int,
//         addedAt: map['added_at'] as int,
//         song: Song.fromMap(map),
//       );
//     }).toList();
//   }

//   /// Check which playlists contain a song
//   Future<List<Playlist>> getPlaylistsContainingSong(String videoId) async {
//     final db = await DatabaseManager.instance.database;

//     final results = await db.rawQuery(
//       '''
//       SELECT p.*
//       FROM playlists p
//       INNER JOIN playlist_songs ps ON p.id = ps.playlist_id
//       WHERE ps.video_id = ?
//       ORDER BY p.updated_at DESC
//     ''',
//       [videoId],
//     );

//     return results.map((map) => Playlist.fromMap(map)).toList();
//   }

//   /// Get playlist count efficiently
//   Future<int> getPlaylistCount() async {
//     final db = await DatabaseManager.instance.database;
//     final result = await db.rawQuery('SELECT COUNT(*) as count FROM playlists');
//     return result.first['count'] as int;
//   }

//   // ==================== SEARCH & UTILITIES ====================

//   /// Search playlists by name
//   Future<List<Playlist>> searchPlaylists(String query) async {
//     final db = await DatabaseManager.instance.database;
//     final results = await db.query(
//       'playlists',
//       where: 'name LIKE ?',
//       whereArgs: ['%$query%'],
//       orderBy: 'updated_at DESC',
//     );

//     return results.map((map) => Playlist.fromMap(map)).toList();
//   }

//   /// Search songs by title or artist
//   Future<List<Song>> searchSongs(String query) async {
//     final db = await DatabaseManager.instance.database;
//     final results = await db.query(
//       'songs',
//       where: 'title LIKE ? OR artists LIKE ?',
//       whereArgs: ['%$query%', '%$query%'],
//       orderBy: 'date_added DESC',
//       limit: 50,
//     );

//     return results.map((map) => Song.fromMap(map)).toList();
//   }

//   /// Clear all data (for testing/debugging)
//   Future<void> clearAllData() async {
//     final db = await DatabaseManager.instance.database;
//     await db.delete('playlist_songs');
//     await db.delete('playlists');
//     await db.delete('songs');
//     await db.delete('play_history');
//   }
// }
