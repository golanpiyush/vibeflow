-- Songs table (never deleted, only marked inactive)
CREATE TABLE songs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  video_id TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  artists TEXT NOT NULL,  -- JSON array stored as text
  thumbnail TEXT NOT NULL,
  duration TEXT,
  added_at INTEGER NOT NULL,
  last_played_at INTEGER,
  play_count INTEGER DEFAULT 0,
  is_active INTEGER DEFAULT 1,  -- Soft delete flag
  UNIQUE(video_id)
);

CREATE INDEX idx_songs_video_id ON songs(video_id);
CREATE INDEX idx_songs_active ON songs(is_active);

-- Playlists table
CREATE TABLE playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT,
  cover_image_path TEXT,  -- Local file path for custom images
  cover_type TEXT DEFAULT 'mosaic',  -- 'mosaic', 'custom', 'gradient'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  song_count INTEGER DEFAULT 0,
  total_duration INTEGER DEFAULT 0,  -- Cached in seconds
  is_favorite INTEGER DEFAULT 0,  -- Pin to top
  sort_order INTEGER DEFAULT 0  -- User-defined order
);

CREATE INDEX idx_playlists_favorite ON playlists(is_favorite);

-- Junction table for many-to-many relationship
CREATE TABLE playlist_songs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id INTEGER NOT NULL,
  song_id INTEGER NOT NULL,
  position INTEGER NOT NULL,  -- 0-indexed order in playlist
  added_at INTEGER NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
  FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
  UNIQUE(playlist_id, song_id)  -- Prevent duplicates
);

CREATE INDEX idx_playlist_songs_playlist ON playlist_songs(playlist_id, position);
CREATE INDEX idx_playlist_songs_song ON playlist_songs(song_id);

-- Metadata table for schema versioning
CREATE TABLE app_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO app_metadata (key, value) VALUES ('schema_version', '1');
INSERT INTO app_metadata (key, value) VALUES ('last_migration', '0');