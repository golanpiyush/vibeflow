// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'vibeflow.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Songs table (stores all songs without audio URLs)
    await db.execute('''
      CREATE TABLE songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_id TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        artists TEXT NOT NULL,
        thumbnail TEXT NOT NULL,
        duration TEXT,
        added_at INTEGER NOT NULL,
        last_played_at INTEGER,
        play_count INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1
      )
    ''');

    // Playlists table
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        cover_image_path TEXT,
        cover_type TEXT DEFAULT 'mosaic',
        song_count INTEGER DEFAULT 0,
        total_duration INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER DEFAULT 0
      )
    ''');

    // Junction table for playlist-song relationships
    await db.execute('''
      CREATE TABLE playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        song_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        added_at INTEGER NOT NULL,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE,
        UNIQUE(playlist_id, song_id)
      )
    ''');

    // Indexes for better performance
    await db.execute('CREATE INDEX idx_songs_video_id ON songs(video_id)');
    await db.execute('CREATE INDEX idx_songs_is_active ON songs(is_active)');
    await db.execute(
      'CREATE INDEX idx_playlist_songs_playlist_id ON playlist_songs(playlist_id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlist_songs_song_id ON playlist_songs(song_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database migrations here in the future
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
