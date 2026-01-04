import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseManager {
  static final DatabaseManager instance = DatabaseManager._init();
  static Database? _database;

  DatabaseManager._init();

  // Current schema version - increment on each schema change
  static const int _currentVersion = 1;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vibeflow_music.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _currentVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: (db) async {
        // Enable foreign key constraints
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // Initial database creation
  Future<void> _createDB(Database db, int version) async {
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

    await db.execute('CREATE INDEX idx_songs_video_id ON songs(video_id)');
    await db.execute('CREATE INDEX idx_songs_active ON songs(is_active)');

    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        cover_image_path TEXT,
        cover_type TEXT DEFAULT 'mosaic',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        song_count INTEGER DEFAULT 0,
        total_duration INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_playlists_favorite ON playlists(is_favorite)',
    );

    await db.execute('''
      CREATE TABLE playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        song_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        added_at INTEGER NOT NULL,
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
        UNIQUE(playlist_id, song_id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_playlist_songs_playlist ON playlist_songs(playlist_id, position)',
    );
    await db.execute(
      'CREATE INDEX idx_playlist_songs_song ON playlist_songs(song_id)',
    );

    await db.execute('''
      CREATE TABLE app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.insert('app_metadata', {
      'key': 'schema_version',
      'value': version.toString(),
    });

    await db.insert('app_metadata', {
      'key': 'last_migration',
      'value': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    // Create default "Favorites" playlist
    await db.insert('playlists', {
      'name': 'Favorites',
      'description': 'Your favorite songs',
      'cover_type': 'gradient',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'is_favorite': 1,
      'sort_order': 0,
    });
  }

  // Safe migration system
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    print('🔄 Migrating database from v$oldVersion to v$newVersion');

    // Run migrations sequentially to prevent data loss
    for (int version = oldVersion + 1; version <= newVersion; version++) {
      await _runMigration(db, version);
    }

    // Update metadata
    await db.update(
      'app_metadata',
      {'value': newVersion.toString()},
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );

    await db.update(
      'app_metadata',
      {'value': DateTime.now().millisecondsSinceEpoch.toString()},
      where: 'key = ?',
      whereArgs: ['last_migration'],
    );
  }

  // Migration handlers for each version
  Future<void> _runMigration(Database db, int version) async {
    switch (version) {
      case 2:
        // Example: Add new column without breaking existing data
        await db.execute('ALTER TABLE playlists ADD COLUMN custom_color TEXT');
        break;

      case 3:
        // Example: Add lyrics support
        await db.execute(
          'ALTER TABLE songs ADD COLUMN has_lyrics INTEGER DEFAULT 0',
        );
        break;

      // Add more migrations as app evolves
      default:
        print('⚠️ No migration defined for version $version');
    }
  }

  // Backup before major changes
  Future<void> backupDatabase() async {
    final db = await database;
    final dbPath = await getDatabasesPath();
    final backupPath = join(
      dbPath,
      'vibeflow_music_backup_${DateTime.now().millisecondsSinceEpoch}.db',
    );

    // Simple file copy for safety
    await db.close();
    // Implement file copy here using dart:io
    _database = await _initDB('vibeflow_music.db');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
