// lib/services/db_actions.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:vibeflow/database/access_code_service.dart';
import 'package:vibeflow/database/following_service.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/database/playlist_services.dart';
import 'package:vibeflow/database/profile_service.dart';
import 'package:vibeflow/database/sync_listen.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart';
import 'dart:async';

import 'package:vibeflow/models/listening_together.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

// ============================================================================
// DBActions - UNIFIED SERVICE INTERFACE
// ============================================================================

class DBActions {
  final SupabaseClient _supabase;
  final Connectivity _connectivity;

  // Individual service instances
  late final AccessCodeService _accessCodeService;
  late final ListeningActivityService _listeningActivityService;
  late final RealtimeService _realtimeService;
  late final FollowService _followService;
  late final ProfileService _profileService;
  late final PlaylistService _playlistService;
  late final SyncListeningService _syncListeningService; // ✅ ADD THIS

  DBActions({
    required SupabaseClient supabase,
    required Connectivity connectivity,
  }) : _supabase = supabase,
       _connectivity = connectivity {
    // Initialize all services
    _accessCodeService = AccessCodeService(_supabase);
    _listeningActivityService = ListeningActivityService(
      _supabase,
      _connectivity,
    );
    _realtimeService = RealtimeService(_supabase, _connectivity);
    _followService = FollowService(_supabase);
    _profileService = ProfileService(_supabase);
    _playlistService = PlaylistService(_supabase);
    _syncListeningService = SyncListeningService(_supabase); // ✅ ADD THIS
  }

  // ==========================================================================
  // ACCESS CODE METHODS (from AccessCodeService)
  // ==========================================================================

  Future<AccessCodeValidationResult> validateCode(String code) =>
      _accessCodeService.validateCode(code);

  Future<bool> checkIfUserHasAccessCode(String userId) =>
      _accessCodeService.checkIfUserHasAccessCode(userId);

  // ==========================================================================
  // LISTENING ACTIVITY METHODS (from ListeningActivityService)
  // ==========================================================================

  String generateSongId(String title, List<String> artists) =>
      ListeningActivityService.generateSongId(title, artists);

  Future<void> recordListeningActivity({
    required String userId,
    required String videoId,
    required String title,
    required List<String> artists,
    required String? thumbnail,
    required int durationMs,
    int playedDurationMs = 0,
  }) => _listeningActivityService.recordListeningActivity(
    userId: userId,
    videoId: videoId,
    title: title,
    artists: artists,
    thumbnail: thumbnail,
    durationMs: durationMs,
    playedDurationMs: playedDurationMs,
  );

  Future<List<ListeningActivity>> getUserListeningHistory({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) => _listeningActivityService.getUserListeningHistory(
    userId: userId,
    limit: limit,
    offset: offset,
  );

  Future<List<ListeningActivity>> getFollowingActivities(String userId) =>
      _listeningActivityService.getFollowingActivities(userId);

  Future<Map<String, int>> getListeningStats(String userId) =>
      _listeningActivityService.getListeningStats(userId);

  // ==========================================================================
  // REALTIME METHODS (from RealtimeService)
  // ==========================================================================

  Stream<ListeningActivity> subscribeToFollowingActivity() =>
      _realtimeService.subscribeToFollowingActivity();

  Stream<PlaylistUpdate> subscribeToPlaylist(String playlistId) =>
      _realtimeService.subscribeToPlaylist(playlistId);

  void disposeRealtime() => _realtimeService.dispose();

  // ==========================================================================
  // FOLLOW SYSTEM METHODS (from FollowService)
  // ==========================================================================

  Future<void> followUser(String followerId, String followedId) =>
      _followService.followUser(followerId, followedId);

  Future<void> unfollowUser(String followerId, String followedId) =>
      _followService.unfollowUser(followerId, followedId);

  Future<List<Map<String, dynamic>>> getFollowers(String userId) =>
      _followService.getFollowers(userId);

  Future<List<Map<String, dynamic>>> getFollowing(String userId) =>
      _followService.getFollowing(userId);

  Future<bool> isFollowing(String followerId, String followedId) =>
      _followService.isFollowing(followerId, followedId);

  // ==========================================================================
  // PROFILE METHODS (from ProfileService)
  // ==========================================================================

  Future<Map<String, dynamic>?> getUserProfileByUserId(String userId) =>
      _profileService.getUserProfileByUserId(userId);

  Future<void> updateProfile({
    required String userId,
    String? gender,
    String? profilePicUrl,
  }) => _profileService.updateProfile(
    userId: userId,
    gender: gender,
    profilePicUrl: profilePicUrl,
  );

  Future<String?> uploadProfilePicture(String userId, String imagePath) =>
      _profileService.uploadProfilePicture(userId, imagePath);

  // ==========================================================================
  // PLAYLIST METHODS (from PlaylistService)
  // ==========================================================================

  Future<String> createPlaylist({
    required String name,
    required String userId,
    bool isPublic = false,
  }) => _playlistService.createPlaylist(
    name: name,
    userId: userId,
    isPublic: isPublic,
  );

  Future<void> addSongToPlaylist({
    required String playlistId,
    required String videoId,
    required String title,
    required List<String> artists,
    required String? thumbnail,
    required String userId,
  }) => _playlistService.addSongToPlaylist(
    playlistId: playlistId,
    videoId: videoId,
    title: title,
    artists: artists,
    thumbnail: thumbnail,
    userId: userId,
  );

  Future<String?> joinPlaylistWithToken(String shareToken, String userId) =>
      _playlistService.joinPlaylistWithToken(shareToken, userId);

  // ==========================================================================
  // SYNC LISTENING METHODS (from SyncListeningService)
  // ✅ NEW SECTION
  // ==========================================================================

  Future<String> createListeningSession({String? sessionName}) =>
      _syncListeningService.createSession(sessionName: sessionName);

  Future<List<MutualFollower>> getMutualFollowers() =>
      _syncListeningService.getMutualFollowers();

  Future<void> inviteUserToSession(String sessionId, String userId) =>
      _syncListeningService.inviteUser(sessionId, userId);

  Future<List<SessionInvitation>> getPendingInvitations() =>
      _syncListeningService.getPendingInvitations();

  Future<void> acceptSessionInvitation(String invitationId, String sessionId) =>
      _syncListeningService.acceptInvitation(invitationId, sessionId);

  Future<void> declineSessionInvitation(String invitationId) =>
      _syncListeningService.declineInvitation(invitationId);

  Future<ListeningSession?> getActiveSession() =>
      _syncListeningService.getActiveSession();

  Future<List<SessionParticipant>> getSessionParticipants(String sessionId) =>
      _syncListeningService.getSessionParticipants(sessionId);

  Future<void> leaveSession(String sessionId) =>
      _syncListeningService.leaveSession(sessionId);

  Future<void> endSession(String sessionId) =>
      _syncListeningService.endSession(sessionId);

  Future<void> kickParticipant(String sessionId, String userId) =>
      _syncListeningService.kickParticipant(sessionId, userId);

  Future<void> updateSessionPlaybackState({
    required String sessionId,
    QuickPick? song,
    int? positionMs,
    bool? isPlaying,
  }) => _syncListeningService.updatePlaybackState(
    sessionId: sessionId,
    song: song,
    positionMs: positionMs,
    isPlaying: isPlaying,
  );

  Future<void> broadcastSessionPlaybackEvent(PlaybackEvent event) =>
      _syncListeningService.broadcastPlaybackEvent(event);

  Future<void> updateSessionSyncStatus(String sessionId, bool isSynced) =>
      _syncListeningService.updateSyncStatus(sessionId, isSynced);

  Future<void> connectToSession(String sessionId) =>
      _syncListeningService.connectToSession(sessionId);

  Future<void> disconnectFromSession() =>
      _syncListeningService.disconnectFromSession();

  Stream<PlaybackEvent> listenToSessionPlaybackEvents() =>
      _syncListeningService.listenToPlaybackEvents();

  Stream<ListeningSession> listenToSessionUpdates(String sessionId) =>
      _syncListeningService.listenToSessionUpdates(sessionId);

  // ==========================================================================
  // HELPER METHODS
  // ==========================================================================

  Future<void> initialize() async {
    // Initialize any services that need async setup
    // This can be expanded if needed
  }

  void dispose() {
    _realtimeService.dispose();
    _syncListeningService.dispose(); // ✅ ADD THIS
  }

  SupabaseClient get supabaseClient => _supabase;

  Connectivity get connectivity => _connectivity;

  // Get direct access to individual services if needed
  AccessCodeService get accessCodeService => _accessCodeService;
  ListeningActivityService get listeningActivityService =>
      _listeningActivityService;
  RealtimeService get realtimeService => _realtimeService;
  FollowService get followService => _followService;
  ProfileService get profileService => _profileService;
  PlaylistService get playlistService => _playlistService;
  SyncListeningService get syncListeningService =>
      _syncListeningService; // ✅ ADD THIS
}

// ============================================================================
// PROVIDER SETUP
// ============================================================================

// Provider for DBActions instance
final dbActionsProvider = Provider<DBActions>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final connectivity = ref.watch(connectivityProvider);

  return DBActions(supabase: supabase, connectivity: connectivity);
});

// Required providers (these should be defined elsewhere in your app)
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final connectivityProvider = Provider<Connectivity>((ref) {
  return Connectivity();
});

// ============================================================================
// SHORTHAND METHODS FOR COMMON OPERATIONS
// ============================================================================

extension DBActionsExtensions on DBActions {
  // Check if current user has access code
  Future<bool> getCurrentUserHasAccessCode() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    return await checkIfUserHasAccessCode(user.id);
  }

  // Get current user's listening history
  Future<List<ListeningActivity>> getCurrentUserListeningHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];
    return await getUserListeningHistory(
      userId: user.id,
      limit: limit,
      offset: offset,
    );
  }

  // Get current user's following activities
  Future<List<ListeningActivity>> getCurrentUserFollowingActivities() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];
    return await getFollowingActivities(user.id);
  }

  // Get current user's profile
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error getting current user profile: $e');
      return null;
    }
  }

  // Follow/unfollow with current user
  Future<void> followWithCurrentUser(String followedUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await followUser(user.id, followedUserId);
  }

  Future<void> unfollowWithCurrentUser(String followedUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await unfollowUser(user.id, followedUserId);
  }

  // Check if current user is following someone
  Future<bool> isCurrentUserFollowing(String followedUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    return await isFollowing(user.id, followedUserId);
  }

  // Update current user's profile
  Future<void> updateCurrentUserProfile({
    String? gender,
    String? profilePicUrl,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await updateProfile(
      userId: user.id,
      gender: gender,
      profilePicUrl: profilePicUrl,
    );
  }

  // Create playlist with current user as owner
  Future<String> createPlaylistWithCurrentUser({
    required String name,
    bool isPublic = false,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return await createPlaylist(
      name: name,
      userId: user.id,
      isPublic: isPublic,
    );
  }

  // Add song to playlist with current user
  Future<void> addSongToPlaylistWithCurrentUser({
    required String playlistId,
    required String videoId,
    required String title,
    required List<String> artists,
    required String? thumbnail,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await addSongToPlaylist(
      playlistId: playlistId,
      videoId: videoId,
      title: title,
      artists: artists,
      thumbnail: thumbnail,
      userId: user.id,
    );
  }

  // Join playlist with current user
  Future<String?> joinPlaylistWithCurrentUser(String shareToken) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return await joinPlaylistWithToken(shareToken, user.id);
  }

  // ✅ NEW: Sync Listening Shorthand Methods

  /// Create a listening session with current user as host
  Future<String> createListenTogetherSession({String? name}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Check access code
    final hasCode = await checkIfUserHasAccessCode(user.id);
    if (!hasCode) throw Exception('Access code required');

    return await createListeningSession(sessionName: name);
  }

  /// Get mutual followers for current user (for inviting to sessions)
  Future<List<MutualFollower>> getMutualFollowersForSession() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    return await getMutualFollowers();
  }

  /// Get active session for current user
  Future<ListeningSession?> getActiveListeningSession() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    return await getActiveSession();
  }

  /// Leave current user's active session
  Future<void> leaveActiveSession() async {
    final session = await getActiveSession();
    if (session == null) return;

    await leaveSession(session.id);
  }

  /// End current user's session (if host)
  Future<void> endActiveSession() async {
    final session = await getActiveSession();
    if (session == null) return;

    if (session.isHost) {
      await endSession(session.id);
    } else {
      throw Exception('Only host can end session');
    }
  }
}
