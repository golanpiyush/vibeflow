// lib/utils/cache_manager.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibeflow/api_base/community_playlistScaper.dart';
import 'package:vibeflow/api_base/ytmusic_artists_scraper.dart';
import 'package:vibeflow/models/artist_model.dart';
import 'package:vibeflow/models/song_model.dart';
import 'package:vibeflow/models/album_model.dart';

class CacheManager {
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  static CacheManager get instance => _instance;

  CacheManager._internal();

  static const String _cacheDirectory = 'vibeflow_cache';
  static const Duration _defaultCacheDuration = Duration(days: 7);

  Future<Directory> get _cacheDir async {
    if (kIsWeb) {
      throw UnsupportedError('Cache not supported on web');
    }
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/$_cacheDirectory');
  }

  /// Save data to cache
  Future<void> set<T>(String key, T data) async {
    try {
      if (kIsWeb) return; // Skip caching on web

      final cacheDir = await _cacheDir;
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final file = File('${cacheDir.path}/$key.json');
      final jsonData = _serializeData(data);
      final cacheEntry = {
        'data': jsonData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'expiresAt': DateTime.now()
            .add(_defaultCacheDuration)
            .millisecondsSinceEpoch,
      };

      await file.writeAsString(jsonEncode(cacheEntry));
      print('💾 Saved cache: $key');
    } catch (e) {
      print('⚠️ Cache save error: $e');
    }
  }

  /// Get data from cache
  Future<T?> get<T>(String key) async {
    try {
      if (kIsWeb) return null; // Skip caching on web

      final cacheDir = await _cacheDir;
      final file = File('${cacheDir.path}/$key.json');

      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final cacheEntry = jsonDecode(content) as Map<String, dynamic>;

      // Check if cache is expired
      final expiresAt = cacheEntry['expiresAt'] as int;
      if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
        await file.delete(); // Remove expired cache
        return null;
      }

      final data = cacheEntry['data'];
      return _deserializeData<T>(data);
    } catch (e) {
      print('⚠️ Cache read error: $e');
      return null;
    }
  }

  /// Serialize data for caching
  dynamic _serializeData<T>(T data) {
    if (data is List<Artist>) {
      return data.map((artist) => artist.toJson()).toList();
    } else if (data is ArtistDetails) {
      return data.toJson();
    } else if (data is List<Song>) {
      return data.map((song) => song.toJson()).toList();
    } else if (data is List<Album>) {
      return data.map((album) => album.toJson()).toList();
    } else if (data is List<CommunityPlaylist>) {
      // NEW: Support for playlists
      return data.map((playlist) => playlist.toJson()).toList();
    } else if (data is CommunityPlaylist) {
      // NEW: Single playlist
      return data.toJson();
    }
    return data;
  }

  /// Deserialize data from cache
  T? _deserializeData<T>(dynamic data) {
    if (T == List<Artist>) {
      final list = (data as List).map((item) => Artist.fromJson(item)).toList();
      return list as T;
    } else if (T == ArtistDetails) {
      return ArtistDetails.fromJson(data) as T;
    } else if (T == List<Song>) {
      final list = (data as List).map((item) => Song.fromJson(item)).toList();
      return list as T;
    } else if (T == List<Album>) {
      final list = (data as List).map((item) => Album.fromJson(item)).toList();
      return list as T;
    } else if (T == List<CommunityPlaylist>) {
      // NEW: Support for playlists
      final list = (data as List)
          .map((item) => CommunityPlaylist.fromJson(item))
          .toList();
      return list as T;
    } else if (T == CommunityPlaylist) {
      // NEW: Single playlist
      return CommunityPlaylist.fromJson(data) as T;
    }
    return data as T?;
  }

  /// Cache community playlists
  Future<void> setCommunityPlaylists(
    String query,
    List<CommunityPlaylist> playlists,
  ) async {
    final key = 'community_playlists_${_hashQuery(query)}';
    await set(key, playlists);
  }

  /// Get cached community playlists
  Future<List<CommunityPlaylist>?> getCommunityPlaylists(String query) async {
    final key = 'community_playlists_${_hashQuery(query)}';
    return await get<List<CommunityPlaylist>>(key);
  }

  /// Cache single community playlist details
  Future<void> setCommunityPlaylistDetails(
    String playlistId,
    CommunityPlaylist playlist,
  ) async {
    final key = 'playlist_details_$playlistId';
    await set(key, playlist);
  }

  /// Get cached community playlist details
  Future<CommunityPlaylist?> getCommunityPlaylistDetails(
    String playlistId,
  ) async {
    final key = 'playlist_details_$playlistId';
    return await get<CommunityPlaylist>(key);
  }

  /// Clear community playlists cache
  Future<void> clearCommunityPlaylists() async {
    try {
      if (kIsWeb) return;

      final cacheDir = await _cacheDir;
      if (!await cacheDir.exists()) return;

      final files = await cacheDir.list().toList();
      for (final file in files) {
        if (file is File) {
          final name = file.path.split('/').last;
          if (name.startsWith('community_playlists_') ||
              name.startsWith('playlist_details_')) {
            await file.delete();
          }
        }
      }
      print('🗑️ Cleared community playlists cache');
    } catch (e) {
      print('⚠️ Error clearing community playlists: $e');
    }
  }

  /// Helper to hash query for cache key
  String _hashQuery(String query) {
    return query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  /// Clear specific cache
  Future<void> clear(String key) async {
    try {
      if (kIsWeb) return;

      final cacheDir = await _cacheDir;
      final file = File('${cacheDir.path}/$key.json');
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Cleared cache: $key');
      }
    } catch (e) {
      print('⚠️ Cache clear error: $e');
    }
  }

  /// Clear all caches
  Future<void> clearAll() async {
    try {
      if (kIsWeb) return;

      final cacheDir = await _cacheDir;
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        print('🧹 Cleared all caches');
      }
    } catch (e) {
      print('⚠️ Cache clear all error: $e');
    }
  }
}
