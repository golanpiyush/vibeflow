import 'package:vibeflow/models/quick_picks_model.dart';

// ============================================================================
// MODELS
// ============================================================================

class ListeningSession {
  final String id;
  final String hostUserId;
  final String hostUsername;
  final String? hostProfilePic;
  final String? sessionName;
  final String? currentSongVideoId;
  final String? currentSongTitle;
  final List<String>? currentSongArtists;
  final String? currentSongThumbnail;
  final int currentPositionMs;
  final bool isPlaying;
  final String userRole; // 'host' or 'guest'
  final int participantCount;
  final DateTime createdAt;

  ListeningSession({
    required this.id,
    required this.hostUserId,
    required this.hostUsername,
    this.hostProfilePic,
    this.sessionName,
    this.currentSongVideoId,
    this.currentSongTitle,
    this.currentSongArtists,
    this.currentSongThumbnail,
    required this.currentPositionMs,
    required this.isPlaying,
    required this.userRole,
    required this.participantCount,
    required this.createdAt,
  });

  factory ListeningSession.fromMap(Map<String, dynamic> map) {
    return ListeningSession(
      id: map['session_id'] as String,
      hostUserId: map['host_user_id'] as String,
      hostUsername: map['host_username'] as String,
      hostProfilePic: map['host_profile_pic'] as String?,
      sessionName: map['session_name'] as String?,
      currentSongVideoId: map['current_song_video_id'] as String?,
      currentSongTitle: map['current_song_title'] as String?,
      currentSongArtists: map['current_song_artists'] != null
          ? List<String>.from(map['current_song_artists'])
          : null,
      currentSongThumbnail: map['current_song_thumbnail'] as String?,
      currentPositionMs: map['current_position_ms'] as int? ?? 0,
      isPlaying: map['is_playing'] as bool? ?? false,
      userRole: map['user_role'] as String,
      participantCount: map['participant_count'] as int? ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  bool get isHost => userRole == 'host';

  QuickPick? get currentSong {
    if (currentSongVideoId == null || currentSongTitle == null) return null;
    return QuickPick(
      videoId: currentSongVideoId!,
      title: currentSongTitle!,
      artists: currentSongArtists?.join(', ') ?? '',
      thumbnail: currentSongThumbnail ?? '',
      duration: null,
    );
  }
}

class SessionParticipant {
  final String id;
  final String userId;
  final String username;
  final String? profilePic;
  final String role;
  final DateTime joinedAt;
  final bool isSynced;

  SessionParticipant({
    required this.id,
    required this.userId,
    required this.username,
    this.profilePic,
    required this.role,
    required this.joinedAt,
    required this.isSynced,
  });

  factory SessionParticipant.fromMap(Map<String, dynamic> map) {
    return SessionParticipant(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      username: map['username'] as String,
      profilePic: map['profile_pic'] as String?,
      role: map['role'] as String,
      joinedAt: DateTime.parse(map['joined_at'] as String),
      isSynced: map['is_synced'] as bool? ?? true,
    );
  }
}

class SessionInvitation {
  final String id;
  final String sessionId;
  final String hostUserId;
  final String hostUsername;
  final String? hostProfilePic;
  final String? currentSongTitle;
  final List<String>? currentSongArtists;
  final int participantCount;
  final DateTime createdAt;

  SessionInvitation({
    required this.id,
    required this.sessionId,
    required this.hostUserId,
    required this.hostUsername,
    this.hostProfilePic,
    this.currentSongTitle,
    this.currentSongArtists,
    required this.participantCount,
    required this.createdAt,
  });

  factory SessionInvitation.fromMap(Map<String, dynamic> map) {
    return SessionInvitation(
      id: map['invitation_id'] as String,
      sessionId: map['session_id'] as String,
      hostUserId: map['host_user_id'] as String,
      hostUsername: map['host_username'] as String,
      hostProfilePic: map['host_profile_pic'] as String?,
      currentSongTitle: map['current_song_title'] as String?,
      currentSongArtists: map['current_song_artists'] != null
          ? List<String>.from(map['current_song_artists'])
          : null,
      participantCount: map['participant_count'] as int? ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class MutualFollower {
  final String userId;
  final String username;
  final String? profilePic;
  final bool isOnline;

  MutualFollower({
    required this.userId,
    required this.username,
    this.profilePic,
    required this.isOnline,
  });

  factory MutualFollower.fromMap(Map<String, dynamic> map) {
    return MutualFollower(
      userId: map['user_id'] as String,
      username: map['userid'] as String,
      profilePic: map['profile_pic_url'] as String?,
      isOnline: map['is_online'] as bool? ?? false,
    );
  }
}

// Playback event types
enum PlaybackEventType { play, pause, seek, skip, songChange, endSession }

class PlaybackEvent {
  final PlaybackEventType type;
  final QuickPick? song;
  final int? positionMs;
  final DateTime timestamp;

  PlaybackEvent({
    required this.type,
    this.song,
    this.positionMs,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'song': song != null
          ? {
              'videoId': song!.videoId,
              'title': song!.title,
              'artists': song!.artists,
              'thumbnail': song!.thumbnail,
              'duration': song!.duration,
            }
          : null,
      'position_ms': positionMs,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PlaybackEvent.fromJson(Map<String, dynamic> json) {
    return PlaybackEvent(
      type: PlaybackEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PlaybackEventType.play,
      ),
      song: json['song'] != null
          ? QuickPick(
              videoId: json['song']['videoId'] as String,
              title: json['song']['title'] as String,
              artists: json['song']['artists'] as String,
              thumbnail: json['song']['thumbnail'] as String,
              duration: json['song']['duration'] as String?,
            )
          : null,
      positionMs: json['position_ms'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
