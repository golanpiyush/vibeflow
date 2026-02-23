// lib/services/changelog_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangelogEntry {
  final String id;
  final String version;
  final String title;
  final DateTime releaseDate;
  final String content;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChangelogEntry({
    required this.id,
    required this.version,
    required this.title,
    required this.releaseDate,
    required this.content,
    required this.isPublished,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) {
    return ChangelogEntry(
      id: json['id'] as String,
      version: json['version'] as String,
      title: json['title'] as String,
      releaseDate: DateTime.parse(json['release_date'] as String),
      content: json['content'] as String,
      isPublished: json['is_published'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(releaseDate);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }
}

class ChangelogService {
  static const String _tableName = 'changelog';
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ChangelogEntry>> getChangelog() async {
    try {
      final response = await _client
          .from(_tableName)
          .select()
          .eq('is_published', true)
          .order('release_date', ascending: false);

      return (response as List)
          .map((json) => ChangelogEntry.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching changelog: $e');
      return [];
    }
  }

  Future<ChangelogEntry?> getLatestVersion() async {
    try {
      final response = await _client
          .from(_tableName)
          .select()
          .eq('is_published', true)
          .order('release_date', ascending: false)
          .limit(1)
          .single();

      return ChangelogEntry.fromJson(response);
    } catch (e) {
      print('Error fetching latest version: $e');
      return null;
    }
  }
}

// Provider for Riverpod
final changelogProvider = FutureProvider<List<ChangelogEntry>>((ref) {
  return ChangelogService().getChangelog();
});
