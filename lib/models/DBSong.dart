import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:vibeflow/api_base/vibeflowcore.dart';
import 'package:vibeflow/models/playable_song.dart';
import 'package:vibeflow/models/playlist_model.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

// ============================================================================
// SONG MODEL FOR DATABASE (NO AUDIO URL - PERSISTENT DATA ONLY)
// ============================================================================

/// Database-only song model without ephemeral data
/// Used for: Playlists, Favorites, History, Download queue
class DbSong {
  final int? id; // Database ID (null for new songs)
  final String videoId; // Permanent YouTube video ID
  final String title;
  final List<String> artists;
  final String thumbnail;
  final String? duration; // Duration string like "3:45"
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final int playCount;
  final bool isActive;

  DbSong({
    this.id,
    required this.videoId,
    required this.title,
    required this.artists,
    required this.thumbnail,
    this.duration,
    DateTime? addedAt,
    this.lastPlayedAt,
    this.playCount = 0,
    this.isActive = true,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Convert to database map (SQLite)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'video_id': videoId,
      'title': title,
      'artists': jsonEncode(artists),
      'thumbnail': thumbnail,
      'duration': duration,
      'added_at': addedAt.millisecondsSinceEpoch,
      'last_played_at': lastPlayedAt?.millisecondsSinceEpoch,
      'play_count': playCount,
      'is_active': isActive ? 1 : 0,
    };
  }

  /// Create from database map
  factory DbSong.fromMap(Map<String, dynamic> map) {
    return DbSong(
      id: map['id'] as int?,
      videoId: map['video_id'] as String,
      title: map['title'] as String,
      artists: List<String>.from(jsonDecode(map['artists'] as String)),
      thumbnail: map['thumbnail'] as String,
      duration: map['duration'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
      lastPlayedAt: map['last_played_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_played_at'] as int)
          : null,
      playCount: map['play_count'] as int? ?? 0,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  DbSong copyWith({
    int? id,
    String? videoId,
    String? title,
    List<String>? artists,
    String? thumbnail,
    String? duration,
    DateTime? addedAt,
    DateTime? lastPlayedAt,
    int? playCount,
    bool? isActive,
  }) {
    return DbSong(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      thumbnail: thumbnail ?? this.thumbnail,
      duration: duration ?? this.duration,
      addedAt: addedAt ?? this.addedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      playCount: playCount ?? this.playCount,
      isActive: isActive ?? this.isActive,
    );
  }

  String get artistsString => artists.join(', ');

  @override
  String toString() => 'DbSong(videoId: $videoId, title: $title)';
}

// ============================================================================
// CONVERSION UTILITIES
// ============================================================================

class SongConverter {
  /// Convert QuickPick (your UI model) to DbSong (database)
  static DbSong quickPickToDb(QuickPick quickPick) {
    return DbSong(
      videoId: quickPick.videoId,
      title: quickPick.title,
      artists: quickPick.artists.split(',').map((a) => a.trim()).toList(),
      thumbnail: quickPick.thumbnail,
      duration: quickPick.duration,
    );
  }

  /// Convert DbSong (database) to QuickPick (your UI model)
  static QuickPick dbToQuickPick(DbSong dbSong) {
    return QuickPick(
      videoId: dbSong.videoId,
      title: dbSong.title,
      artists: dbSong.artistsString,
      thumbnail: dbSong.thumbnail,
      duration: dbSong.duration,
    );
  }

  /// Fetch fresh audio URL and create PlayableSong
  static Future<PlayableSong?> makePlayable(
    DbSong dbSong,
    VibeFlowCore core,
  ) async {
    try {
      // Fetch fresh audio URL
      final audioUrl = await core.getAudioUrlWithRetry(
        dbSong.videoId,
        maxRetries: 3,
      );

      if (audioUrl == null || audioUrl.isEmpty) {
        return null;
      }

      return PlayableSong(
        videoId: dbSong.videoId,
        title: dbSong.title,
        artists: dbSong.artists,
        thumbnail: dbSong.thumbnail,
        duration: dbSong.duration,
        audioUrl: audioUrl,
      );
    } catch (e) {
      print('❌ Failed to fetch audio URL for ${dbSong.videoId}: $e');
      return null;
    }
  }

  /// Batch convert DbSongs to PlayableSongs
  static Future<List<PlayableSong>> makePlayableList(
    List<DbSong> dbSongs,
    VibeFlowCore core, {
    int maxConcurrent = 3, // Limit concurrent API calls
  }) async {
    final results = <PlayableSong>[];

    // Process in chunks to avoid rate limiting
    for (var i = 0; i < dbSongs.length; i += maxConcurrent) {
      final chunk = dbSongs.skip(i).take(maxConcurrent);

      final futures = chunk.map((dbSong) => makePlayable(dbSong, core));
      final chunkResults = await Future.wait(futures);

      // Filter out nulls (failed fetches)
      results.addAll(chunkResults.whereType<PlayableSong>());
    }

    return results;
  }
}

// ============================================================================
// UPDATED PLAYLIST REPOSITORY (USES DbSong)
// ============================================================================

class PlaylistRepository {
  final Database db;

  PlaylistRepository(this.db);

  // === SONG OPERATIONS (Updated for DbSong) ===

  /// Add or update song (idempotent - safe to call multiple times)
  Future<DbSong> upsertSong(DbSong song) async {
    final existing = await getSongByVideoId(song.videoId);

    if (existing != null) {
      // Update existing song
      await db.update(
        'songs',
        song.copyWith(id: existing.id).toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return song.copyWith(id: existing.id);
    } else {
      // Insert new song
      final id = await db.insert('songs', song.toMap());
      return song.copyWith(id: id);
    }
  }

  Future<DbSong?> getSongByVideoId(String videoId) async {
    final maps = await db.query(
      'songs',
      where: 'video_id = ? AND is_active = 1',
      whereArgs: [videoId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return DbSong.fromMap(maps.first);
  }

  Future<DbSong?> getSongById(int id) async {
    final maps = await db.query(
      'songs',
      where: 'id = ? AND is_active = 1',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return DbSong.fromMap(maps.first);
  }

  Future<List<DbSong>> getAllSongs() async {
    final maps = await db.query(
      'songs',
      where: 'is_active = 1',
      orderBy: 'added_at DESC',
    );

    return maps.map((map) => DbSong.fromMap(map)).toList();
  }

  /// Increment play count and update last played timestamp
  Future<void> markSongPlayed(String videoId) async {
    final song = await getSongByVideoId(videoId);
    if (song != null) {
      await db.update(
        'songs',
        {
          'play_count': song.playCount + 1,
          'last_played_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [song.id],
      );
    }
  }

  // === PLAYLIST OPERATIONS (Same as before) ===

  Future<Playlist> createPlaylist({
    required String name,
    String? description,
    String? coverImagePath,
    String coverType = 'mosaic',
  }) async {
    final now = DateTime.now();
    final maxOrder = await _getMaxPlaylistOrder();

    final playlist = Playlist(
      name: name,
      description: description,
      coverImagePath: coverImagePath,
      coverType: coverType,
      createdAt: now,
      updatedAt: now,
      sortOrder: maxOrder + 1,
    );

    final id = await db.insert('playlists', playlist.toMap());
    return playlist.copyWith(id: id);
  }

  Future<int> _getMaxPlaylistOrder() async {
    final result = await db.rawQuery(
      'SELECT MAX(sort_order) as max_order FROM playlists',
    );
    return (result.first['max_order'] as int?) ?? 0;
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    await db.update(
      'playlists',
      playlist.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
  }

  Future<void> deletePlaylist(int playlistId) async {
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  Future<Playlist?> getPlaylistById(int id) async {
    final maps = await db.query(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Playlist.fromMap(maps.first);
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final maps = await db.query(
      'playlists',
      orderBy: 'is_favorite DESC, sort_order ASC, created_at DESC',
    );

    return maps.map((map) => Playlist.fromMap(map)).toList();
  }

  // === PLAYLIST-SONG OPERATIONS (Updated for DbSong) ===

  Future<bool> addSongToPlaylist({
    required int playlistId,
    required DbSong song,
  }) async {
    try {
      final savedSong = await upsertSong(song);
      final maxPosition = await _getMaxPositionInPlaylist(playlistId);

      await db.insert('playlist_songs', {
        'playlist_id': playlistId,
        'song_id': savedSong.id,
        'position': maxPosition + 1,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });

      await _updatePlaylistStats(playlistId);
      return true;
    } catch (e) {
      if (e.toString().contains('UNIQUE constraint failed')) {
        return false;
      }
      rethrow;
    }
  }

  Future<int> _getMaxPositionInPlaylist(int playlistId) async {
    final result = await db.rawQuery(
      'SELECT MAX(position) as max_pos FROM playlist_songs WHERE playlist_id = ?',
      [playlistId],
    );
    return (result.first['max_pos'] as int?) ?? -1;
  }

  Future<void> removeSongFromPlaylist({
    required int playlistId,
    required int songId,
  }) async {
    final maps = await db.query(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
      limit: 1,
    );

    if (maps.isEmpty) return;
    final removedPosition = maps.first['position'] as int;

    await db.delete(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );

    await db.rawUpdate(
      'UPDATE playlist_songs SET position = position - 1 '
      'WHERE playlist_id = ? AND position > ?',
      [playlistId, removedPosition],
    );

    await _updatePlaylistStats(playlistId);
  }

  Future<void> reorderSongInPlaylist({
    required int playlistId,
    required int songId,
    required int newPosition,
  }) async {
    final maps = await db.query(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
      limit: 1,
    );

    if (maps.isEmpty) return;
    final oldPosition = maps.first['position'] as int;

    if (oldPosition == newPosition) return;

    if (oldPosition < newPosition) {
      await db.rawUpdate(
        'UPDATE playlist_songs SET position = position - 1 '
        'WHERE playlist_id = ? AND position > ? AND position <= ?',
        [playlistId, oldPosition, newPosition],
      );
    } else {
      await db.rawUpdate(
        'UPDATE playlist_songs SET position = position + 1 '
        'WHERE playlist_id = ? AND position >= ? AND position < ?',
        [playlistId, newPosition, oldPosition],
      );
    }

    await db.update(
      'playlist_songs',
      {'position': newPosition},
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
  }

  /// Get all songs in a playlist (returns DbSong - no audio URLs)
  Future<List<DbSong>> getPlaylistSongs(int playlistId) async {
    final maps = await db.rawQuery(
      '''
      SELECT s.* FROM songs s
      INNER JOIN playlist_songs ps ON s.id = ps.song_id
      WHERE ps.playlist_id = ? AND s.is_active = 1
      ORDER BY ps.position ASC
    ''',
      [playlistId],
    );

    return maps.map((map) => DbSong.fromMap(map)).toList();
  }

  Future<PlaylistWithSongs?> getPlaylistWithSongs(int playlistId) async {
    final playlist = await getPlaylistById(playlistId);
    if (playlist == null) return null;

    final songs = await getPlaylistSongs(playlistId);
    return PlaylistWithSongs(playlist: playlist, songs: songs);
  }

  Future<List<Playlist>> getPlaylistsContainingSong(String videoId) async {
    final song = await getSongByVideoId(videoId);
    if (song?.id == null) return [];

    final maps = await db.rawQuery(
      '''
      SELECT p.* FROM playlists p
      INNER JOIN playlist_songs ps ON p.id = ps.playlist_id
      WHERE ps.song_id = ?
      ORDER BY p.is_favorite DESC, p.sort_order ASC
    ''',
      [song!.id],
    );

    return maps.map((map) => Playlist.fromMap(map)).toList();
  }

  Future<void> _updatePlaylistStats(int playlistId) async {
    final stats = await db.rawQuery(
      '''
      SELECT 
        COUNT(ps.song_id) as song_count,
        COALESCE(SUM(
          CASE 
            WHEN s.duration IS NOT NULL AND s.duration != '' 
            THEN CAST(s.duration AS INTEGER)
            ELSE 0 
          END
        ), 0) as total_duration
      FROM playlist_songs ps
      LEFT JOIN songs s ON ps.song_id = s.id
      WHERE ps.playlist_id = ?
    ''',
      [playlistId],
    );

    final songCount = stats.first['song_count'] as int;
    final totalDuration = stats.first['total_duration'] as int;

    await db.update(
      'playlists',
      {
        'song_count': songCount,
        'total_duration': totalDuration,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> addSongsToPlaylistBatch({
    required int playlistId,
    required List<DbSong> songs,
  }) async {
    if (songs.isEmpty) return;

    final batch = db.batch();
    int position = await _getMaxPositionInPlaylist(playlistId) + 1;

    for (final song in songs) {
      final savedSong = await upsertSong(song);

      batch.insert('playlist_songs', {
        'playlist_id': playlistId,
        'song_id': savedSong.id,
        'position': position++,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
    await _updatePlaylistStats(playlistId);
  }
}

// ============================================================================
// UPDATED MODELS (PlaylistWithSongs uses DbSong now)
// ============================================================================

class PlaylistWithSongs {
  final Playlist playlist;
  final List<DbSong> songs; // Changed from Song to DbSong

  PlaylistWithSongs({required this.playlist, required this.songs});
}
