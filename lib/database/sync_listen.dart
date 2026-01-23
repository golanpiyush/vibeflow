// lib/services/sync_listening_service.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/models/listening_together.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

// ============================================================================
// SYNC LISTENING SERVICE
// ============================================================================

class SyncListeningService {
  final SupabaseClient _supabase;
  RealtimeChannel? _sessionChannel;
  RealtimeChannel? _presenceChannel;
  String? _currentSessionId;

  SyncListeningService(this._supabase);

  // ========== SESSION MANAGEMENT ==========

  /// Create a new listening session
  // Replace the createSession method in sync_listening_service.dart

  /// Create a new listening session
  Future<String> createSession({String? sessionName}) async {
    print('📻 [SYNC] Creating new session: $sessionName');

    final user = _supabase.auth.currentUser;
    if (user == null) {
      print('❌ [SYNC] Not authenticated');
      throw Exception('Not authenticated');
    }

    print('🔐 [SYNC] Authenticated as user: ${user.id}');

    try {
      // First, verify user has jammer enabled
      print('🔍 [SYNC] Checking user profile...');
      final profileCheck = await _supabase
          .from('profiles')
          .select('is_jammer_on, userid')
          .eq('id', user.id)
          .single();

      print('👤 [SYNC] User: ${profileCheck['userid']}');
      print('🎵 [SYNC] Jammer: ${profileCheck['is_jammer_on']}');

      if (profileCheck['is_jammer_on'] != true) {
        throw Exception(
          'Jammer mode is not enabled. Please enable it in settings.',
        );
      }

      // Create session - using maybeSingle to avoid errors
      print('📝 [SYNC] Inserting session (user: ${user.id})...');

      final insertData = {
        'host_user_id': user.id,
        'session_name': sessionName,
        'status': 'active',
      };

      print('📦 [SYNC] Insert data: $insertData');

      final response = await _supabase
          .from('listening_sessions')
          .insert(insertData)
          .select('id')
          .single();

      final sessionId = response['id'] as String;
      print('✅ [SYNC] Session created with ID: $sessionId');

      // Add host as participant
      print('👥 [SYNC] Adding host as participant...');
      await _supabase.from('session_participants').insert({
        'session_id': sessionId,
        'user_id': user.id,
        'role': 'host',
      });

      print('✅ [SYNC] Host added successfully');
      print('🎉 [SYNC] Session fully created: $sessionId');

      return sessionId;
    } catch (e, stackTrace) {
      print('❌ [SYNC] Error creating session: $e');
      print('❌ [SYNC] Error type: ${e.runtimeType}');
      print('📋 [SYNC] Stack trace:');
      print(stackTrace.toString().split('\n').take(5).join('\n'));
      rethrow;
    }
  }

  /// Subscribe to invitation changes using real-time callbacks
  void subscribeToInvitationChanges({required Function() onInvitationChange}) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      print('❌ [REALTIME] Cannot subscribe: User not authenticated');
      return;
    }

    print('👂 [REALTIME] Subscribing to invitation changes for user: $userId');

    final channel = _supabase.channel('invitations_$userId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'session_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'invited_user_id',
            value: userId,
          ),
          callback: (payload) {
            print('🔔 [REALTIME] New invitation created!');
            print('   Data: ${payload.newRecord}');
            onInvitationChange();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'session_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'invited_user_id',
            value: userId,
          ),
          callback: (payload) {
            print('🔔 [REALTIME] Invitation updated!');
            onInvitationChange();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'session_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'invited_user_id',
            value: userId,
          ),
          callback: (payload) {
            print('🔔 [REALTIME] Invitation deleted!');
            onInvitationChange();
          },
        )
        .subscribe();

    print('✅ [REALTIME] Subscribed to invitation changes');
  }

  /// Unsubscribe from invitation changes
  void unsubscribeFromInvitationChanges() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      _supabase.removeChannel(_supabase.channel('invitations_$userId'));
      print('🔌 [REALTIME] Unsubscribed from invitation changes');
    }
  }

  /// Get mutual followers who can be invited
  Future<List<MutualFollower>> getMutualFollowers() async {
    print('👥 [SYNC] Getting mutual followers');

    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    try {
      final response = await _supabase.rpc(
        'get_mutual_followers',
        params: {'p_user_id': user.id},
      );

      final followers = (response as List)
          .map((e) => MutualFollower.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      print('✅ [SYNC] Found ${followers.length} mutual followers');
      return followers;
    } catch (e) {
      print('❌ [SYNC] Error getting mutual followers: $e');
      return [];
    }
  }

  /// Invite a user to session
  Future<void> inviteUser(String sessionId, String userId) async {
    print('📬 [SYNC] Inviting user $userId to session $sessionId');

    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    try {
      await _supabase.from('session_invitations').insert({
        'session_id': sessionId,
        'invited_user_id': userId,
        'invited_by_user_id': user.id,
        'status': 'pending',
      });

      print('✅ [SYNC] Invitation sent');
    } catch (e) {
      print('❌ [SYNC] Error inviting user: $e');
      rethrow;
    }
  }

  /// Get pending invitations for current user
  Future<List<SessionInvitation>> getPendingInvitations() async {
    print('📥 [SYNC] Getting pending invitations');

    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await _supabase.rpc(
        'get_pending_invitations',
        params: {'p_user_id': user.id},
      );

      final invitations = (response as List)
          .map((e) => SessionInvitation.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      print('✅ [SYNC] Found ${invitations.length} pending invitations');
      return invitations;
    } catch (e) {
      print('❌ [SYNC] Error getting invitations: $e');
      return [];
    }
  }

  /// Accept an invitation
  Future<void> acceptInvitation(String invitationId, String sessionId) async {
    print('✅ [SYNC] Accepting invitation $invitationId');

    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    try {
      // Update invitation status
      await _supabase
          .from('session_invitations')
          .update({'status': 'accepted'})
          .eq('id', invitationId);

      // Add user as participant
      await _supabase.from('session_participants').insert({
        'session_id': sessionId,
        'user_id': user.id,
        'role': 'guest',
      });

      print('✅ [SYNC] Invitation accepted, joined session');
    } catch (e) {
      print('❌ [SYNC] Error accepting invitation: $e');
      rethrow;
    }
  }

  /// Decline an invitation
  Future<void> declineInvitation(String invitationId) async {
    print('❌ [SYNC] Declining invitation $invitationId');

    try {
      await _supabase
          .from('session_invitations')
          .update({'status': 'declined'})
          .eq('id', invitationId);

      print('✅ [SYNC] Invitation declined');
    } catch (e) {
      print('❌ [SYNC] Error declining invitation: $e');
      rethrow;
    }
  }

  /// Get active session for current user
  Future<ListeningSession?> getActiveSession() async {
    print('🔍 [SYNC] Getting active session');

    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase.rpc(
        'get_user_active_session',
        params: {'p_user_id': user.id},
      );

      if (response == null || (response as List).isEmpty) {
        print('ℹ️ [SYNC] No active session');
        return null;
      }

      final session = ListeningSession.fromMap(
        Map<String, dynamic>.from((response as List).first),
      );

      print('✅ [SYNC] Found active session: ${session.id}');
      return session;
    } catch (e) {
      print('❌ [SYNC] Error getting active session: $e');
      return null;
    }
  }

  /// Get participants in a session
  Future<List<SessionParticipant>> getSessionParticipants(
    String sessionId,
  ) async {
    print('👥 [SYNC] Getting participants for session $sessionId');

    try {
      final response = await _supabase
          .from('session_participants')
          .select('''
          id,
          user_id,
          role,
          joined_at,
          is_synced,
          profiles!inner(userid, profile_pic_url)
        ''')
          .eq('session_id', sessionId);

      final participants = (response as List).map((e) {
        final data = Map<String, dynamic>.from(e);
        final profile = data['profiles'] as Map<String, dynamic>;

        return SessionParticipant(
          id: data['id'] as String,
          userId: data['user_id'] as String,
          username: profile['userid'] as String,
          profilePic: profile['profile_pic_url'] as String?,
          role: data['role'] as String,
          joinedAt: DateTime.parse(data['joined_at'] as String),
          isSynced: data['is_synced'] as bool? ?? true,
        );
      }).toList();

      print('✅ [SYNC] Found ${participants.length} participants');
      return participants;
    } catch (e) {
      print('❌ [SYNC] Error getting participants: $e');
      return [];
    }
  }

  /// Leave a session
  Future<void> leaveSession(String sessionId) async {
    print('🚪 [SYNC] Leaving session $sessionId');

    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    try {
      await _supabase
          .from('session_participants')
          .delete()
          .eq('session_id', sessionId)
          .eq('user_id', user.id);

      // Disconnect from realtime
      await disconnectFromSession();

      print('✅ [SYNC] Left session');
    } catch (e) {
      print('❌ [SYNC] Error leaving session: $e');
      rethrow;
    }
  }

  /// End a session (host only)
  Future<void> endSession(String sessionId) async {
    print('🛑 [SYNC] Ending session $sessionId');

    try {
      // Update session status
      await _supabase
          .from('listening_sessions')
          .update({'status': 'ended'})
          .eq('id', sessionId);

      // Broadcast end event to all participants
      if (_sessionChannel != null) {
        await _sessionChannel!.sendBroadcastMessage(
          event: 'playback_event',
          payload: PlaybackEvent(
            type: PlaybackEventType.endSession,
            timestamp: DateTime.now().toUtc(),
          ).toJson(),
        );
      }

      // Disconnect from realtime
      await disconnectFromSession();

      print('✅ [SYNC] Session ended');
    } catch (e) {
      print('❌ [SYNC] Error ending session: $e');
      rethrow;
    }
  }

  /// Kick a participant (host only)
  Future<void> kickParticipant(String sessionId, String userId) async {
    print('👢 [SYNC] Kicking participant $userId from session $sessionId');

    try {
      await _supabase
          .from('session_participants')
          .delete()
          .eq('session_id', sessionId)
          .eq('user_id', userId);

      print('✅ [SYNC] Participant kicked');
    } catch (e) {
      print('❌ [SYNC] Error kicking participant: $e');
      rethrow;
    }
  }

  // ========== PLAYBACK SYNCHRONIZATION ==========

  /// Update session playback state (host only)
  Future<void> updatePlaybackState({
    required String sessionId,
    QuickPick? song,
    int? positionMs,
    bool? isPlaying,
  }) async {
    print('🎵 [SYNC] Updating playback state for session $sessionId');

    try {
      final updateData = <String, dynamic>{};

      if (song != null) {
        updateData['current_song_video_id'] = song.videoId;
        updateData['current_song_title'] = song.title;
        updateData['current_song_artists'] = song.artists
            .split(',')
            .map((e) => e.trim())
            .toList();
        updateData['current_song_thumbnail'] = song.thumbnail;
      }

      if (positionMs != null) {
        updateData['current_position_ms'] = positionMs;
      }

      if (isPlaying != null) {
        updateData['is_playing'] = isPlaying;
      }

      if (updateData.isNotEmpty) {
        await _supabase
            .from('listening_sessions')
            .update(updateData)
            .eq('id', sessionId);

        print('✅ [SYNC] Playback state updated');
      }
    } catch (e) {
      print('❌ [SYNC] Error updating playback state: $e');
      rethrow;
    }
  }

  /// Broadcast playback event to session (host only)
  Future<void> broadcastPlaybackEvent(PlaybackEvent event) async {
    if (_sessionChannel == null) {
      print('⚠️ [SYNC] No session channel to broadcast to');
      return;
    }

    print('📡 [SYNC] Broadcasting playback event: ${event.type.name}');

    try {
      await _sessionChannel!.sendBroadcastMessage(
        event: 'playback_event',
        payload: event.toJson(),
      );

      print('✅ [SYNC] Event broadcasted');
    } catch (e) {
      print('❌ [SYNC] Error broadcasting event: $e');
    }
  }

  /// Update sync status for current participant
  Future<void> updateSyncStatus(String sessionId, bool isSynced) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase
          .from('session_participants')
          .update({'is_synced': isSynced})
          .eq('session_id', sessionId)
          .eq('user_id', user.id);
    } catch (e) {
      print('❌ [SYNC] Error updating sync status: $e');
    }
  }

  // ========== REAL-TIME CONNECTION ==========

  /// Connect to session real-time channels
  Future<void> connectToSession(String sessionId) async {
    print('🔌 [SYNC] Connecting to session $sessionId');

    await disconnectFromSession();
    _currentSessionId = sessionId;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      // Playback events channel
      _sessionChannel = _supabase.channel('listening_session:$sessionId');

      // Presence channel (NO config needed)
      _presenceChannel = _supabase.channel(
        'listening_session_presence:$sessionId',
      );

      // Subscribe to playback channel
      _sessionChannel!.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          print('✅ [SYNC] Subscribed to playback channel');
        } else if (error != null) {
          print('❌ [SYNC] Playback subscribe error: $error');
        }
      });

      // Subscribe to presence channel
      _presenceChannel!.subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          print('✅ [SYNC] Subscribed to presence channel');

          // Track presence
          await _presenceChannel!.track({
            'user_id': user.id,
            'online_at': DateTime.now().toUtc().toIso8601String(),
          });
        } else if (error != null) {
          print('❌ [SYNC] Presence subscribe error: $error');
        }
      });

      print('✅ [SYNC] Connected to session channels');
    } catch (e) {
      print('❌ [SYNC] Error connecting to session: $e');
      rethrow;
    }
  }

  /// Disconnect from current session
  Future<void> disconnectFromSession() async {
    if (_sessionChannel != null) {
      print('🔌 [SYNC] Disconnecting from session');

      try {
        await _sessionChannel!.unsubscribe();
      } catch (e) {
        print('⚠️ [SYNC] Error unsubscribing from session channel: $e');
      }
      _sessionChannel = null;
    }

    if (_presenceChannel != null) {
      try {
        await _presenceChannel!.untrack();
        await _presenceChannel!.unsubscribe();
      } catch (e) {
        print('⚠️ [SYNC] Error unsubscribing from presence channel: $e');
      }
      _presenceChannel = null;
    }

    _currentSessionId = null;
  }

  /// Listen to playback events
  Stream<PlaybackEvent> listenToPlaybackEvents() {
    if (_sessionChannel == null) {
      print('⚠️ [SYNC] No session channel to listen to');
      return const Stream.empty();
    }

    print('👂 [SYNC] Listening to playback events');

    final controller = StreamController<PlaybackEvent>.broadcast();

    _sessionChannel!.onBroadcast(
      event: 'playback_event',
      callback: (payload) {
        try {
          final event = PlaybackEvent.fromJson(
            Map<String, dynamic>.from(payload),
          );
          controller.add(event);
        } catch (e) {
          print('⚠️ [SYNC] Error parsing playback event: $e');
        }
      },
    );

    return controller.stream;
  }

  /// Listen to session updates (database changes)
  Stream<ListeningSession> listenToSessionUpdates(String sessionId) {
    print('👂 [SYNC] Listening to session updates for $sessionId');

    return _supabase
        .from('listening_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .asyncMap((data) async {
          if (data.isEmpty) {
            throw Exception('Session not found');
          }

          final sessionData = data.first;

          // Get participant count
          final participantResponse = await _supabase
              .from('session_participants')
              .select('id')
              .eq('session_id', sessionId);

          final participantCount = (participantResponse as List).length;

          // Get host info
          final hostResponse = await _supabase
              .from('profiles')
              .select('userid, profile_pic_url')
              .eq('id', sessionData['host_user_id'])
              .single();

          final user = _supabase.auth.currentUser;
          final userRole = user?.id == sessionData['host_user_id']
              ? 'host'
              : 'guest';

          return ListeningSession(
            id: sessionData['id'] as String,
            hostUserId: sessionData['host_user_id'] as String,
            hostUsername: hostResponse['userid'] as String,
            hostProfilePic: hostResponse['profile_pic_url'] as String?,
            sessionName: sessionData['session_name'] as String?,
            currentSongVideoId: sessionData['current_song_video_id'] as String?,
            currentSongTitle: sessionData['current_song_title'] as String?,
            currentSongArtists: sessionData['current_song_artists'] != null
                ? List<String>.from(sessionData['current_song_artists'])
                : null,
            currentSongThumbnail:
                sessionData['current_song_thumbnail'] as String?,
            currentPositionMs: sessionData['current_position_ms'] as int? ?? 0,
            isPlaying: sessionData['is_playing'] as bool? ?? false,
            userRole: userRole,
            participantCount: participantCount,
            createdAt: DateTime.parse(sessionData['created_at'] as String),
          );
        });
  }

  /// Dispose and cleanup
  void dispose() {
    print('🗑️ [SYNC] Disposing sync listening service');
    disconnectFromSession();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

final syncListeningServiceProvider = Provider<SyncListeningService>((ref) {
  final supabase = Supabase.instance.client;
  return SyncListeningService(supabase);
});
