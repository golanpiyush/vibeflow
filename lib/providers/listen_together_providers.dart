// lib/providers/listen_together_providers.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/database/sync_listen.dart';
import 'package:vibeflow/models/listening_together.dart';

// ============================================================================
// BASIC DATA PROVIDERS
// ============================================================================

/// Active session provider - checks if user has an active session
final activeSessionProvider = FutureProvider<ListeningSession?>((ref) async {
  final db = ref.watch(dbActionsProvider);

  try {
    final session = await db.syncListeningService.getActiveSession();
    return session;
  } catch (e) {
    print('❌ [PROVIDER] Error getting active session: $e');
    return null;
  }
});

/// Pending invitations provider - gets invitations sent to current user
final pendingInvitationsProvider = FutureProvider<List<SessionInvitation>>((
  ref,
) async {
  final db = ref.watch(dbActionsProvider);

  try {
    final invitations = await db.syncListeningService.getPendingInvitations();
    return invitations;
  } catch (e) {
    print('❌ [PROVIDER] Error getting invitations: $e');
    return [];
  }
});

/// Mutual followers provider - gets users who can be invited to session
final mutualFollowersProvider = FutureProvider<List<MutualFollower>>((
  ref,
) async {
  final db = ref.watch(dbActionsProvider);

  try {
    final followers = await db.syncListeningService.getMutualFollowers();
    return followers;
  } catch (e) {
    print('❌ [PROVIDER] Error getting mutual followers: $e');
    return [];
  }
});

/// Session participants provider - gets participants for a specific session
final sessionParticipantsProvider =
    FutureProvider.family<List<SessionParticipant>, String>((
      ref,
      sessionId,
    ) async {
      final db = ref.watch(dbActionsProvider);

      try {
        final participants = await db.syncListeningService
            .getSessionParticipants(sessionId);
        return participants;
      } catch (e) {
        print('❌ [PROVIDER] Error getting participants: $e');
        return [];
      }
    });

// ============================================================================
// REAL-TIME STREAM PROVIDERS
// ============================================================================

/// Session playback events stream - listens to real-time playback events
final sessionPlaybackEventsProvider =
    StreamProvider.family<PlaybackEvent, String>((ref, sessionId) {
      final db = ref.watch(dbActionsProvider);
      final service = db.syncListeningService;

      final controller = StreamController<PlaybackEvent>();
      StreamSubscription? subscription;
      bool isConnected = false;

      Future<void> connectAndListen() async {
        if (isConnected) return;

        try {
          print('🔌 [PROVIDER] Connecting to session $sessionId');
          await service.connectToSession(sessionId);
          isConnected = true;

          // Start listening to events
          subscription = service.listenToPlaybackEvents().listen(
            (event) {
              if (!controller.isClosed) {
                controller.add(event);
              }
            },
            onError: (error) {
              print('❌ [PROVIDER] Playback event error: $error');
              if (!controller.isClosed) {
                controller.addError(error);
              }
            },
          );

          print('✅ [PROVIDER] Connected and listening to playback events');
        } catch (e) {
          print('❌ [PROVIDER] Error connecting to session: $e');
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      }

      // Connect immediately
      connectAndListen();

      ref.onDispose(() {
        print('🗑️ [PROVIDER] Disposing playback events provider');
        subscription?.cancel();
        if (isConnected) {
          service.disconnectFromSession();
        }
        if (!controller.isClosed) {
          controller.close();
        }
      });

      return controller.stream;
    });

/// Session updates stream - listens to database changes for session
final sessionUpdatesProvider = StreamProvider.family<ListeningSession, String>((
  ref,
  sessionId,
) {
  final db = ref.watch(dbActionsProvider);
  final service = db.syncListeningService;

  print('👂 [PROVIDER] Creating session updates stream for $sessionId');

  return service.listenToSessionUpdates(sessionId);
});

// ============================================================================
// STATE NOTIFIER PROVIDERS
// ============================================================================

/// Session controller - manages session state and actions
class SessionController extends StateNotifier<AsyncValue<ListeningSession?>> {
  final SyncListeningService _service;
  StreamSubscription? _sessionSubscription;
  StreamSubscription? _playbackSubscription;
  String? _currentSessionId;

  SessionController(this._service) : super(const AsyncValue.loading());

  /// Load active session
  Future<void> loadActiveSession() async {
    state = const AsyncValue.loading();

    try {
      final session = await _service.getActiveSession();
      state = AsyncValue.data(session);

      // If session exists, start listening to updates
      if (session != null) {
        _startListeningToSession(session.id);
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Create new session
  Future<String?> createSession({String? name}) async {
    try {
      final sessionId = await _service.createSession(sessionName: name);
      await loadActiveSession();
      return sessionId;
    } catch (e) {
      print('❌ [CONTROLLER] Error creating session: $e');
      return null;
    }
  }

  /// Accept invitation and join session
  Future<bool> acceptInvitation(String invitationId, String sessionId) async {
    try {
      await _service.acceptInvitation(invitationId, sessionId);
      await loadActiveSession();
      return true;
    } catch (e) {
      print('❌ [CONTROLLER] Error accepting invitation: $e');
      return false;
    }
  }

  /// Leave current session
  Future<void> leaveSession() async {
    final session = state.value;
    if (session == null) return;

    try {
      await _service.leaveSession(session.id);
      _stopListeningToSession();
      state = const AsyncValue.data(null);
    } catch (e) {
      print('❌ [CONTROLLER] Error leaving session: $e');
    }
  }

  /// End session (host only)
  Future<void> endSession() async {
    final session = state.value;
    if (session == null || !session.isHost) return;

    try {
      await _service.endSession(session.id);
      _stopListeningToSession();
      state = const AsyncValue.data(null);
    } catch (e) {
      print('❌ [CONTROLLER] Error ending session: $e');
    }
  }

  /// Start listening to session updates
  void _startListeningToSession(String sessionId) {
    if (_currentSessionId == sessionId) return;

    _stopListeningToSession();
    _currentSessionId = sessionId;

    // Listen to session database updates
    _sessionSubscription = _service
        .listenToSessionUpdates(sessionId)
        .listen(
          (session) {
            state = AsyncValue.data(session);
          },
          onError: (error) {
            print('❌ [CONTROLLER] Session update error: $error');
            state = AsyncValue.error(error, StackTrace.current);
          },
        );
  }

  /// Stop listening to session updates
  void _stopListeningToSession() {
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _playbackSubscription?.cancel();
    _playbackSubscription = null;
    _currentSessionId = null;
  }

  @override
  void dispose() {
    _stopListeningToSession();
    super.dispose();
  }
}

/// Session controller provider
final sessionControllerProvider =
    StateNotifierProvider<SessionController, AsyncValue<ListeningSession?>>((
      ref,
    ) {
      final db = ref.watch(dbActionsProvider);
      final controller = SessionController(db.syncListeningService);

      // Load active session on init
      controller.loadActiveSession();

      return controller;
    });

// ============================================================================
// INVITATION CONTROLLER
// ============================================================================
/// Invitation controller - manages invitations with real-time updates
// Replace the entire InvitationController class in listen_together_providers.dart

/// Invitation controller - manages invitations with real-time updates
class InvitationController extends StateNotifier<List<SessionInvitation>> {
  final SyncListeningService _service;
  Timer? _refreshTimer;
  bool _isSubscribed = false;

  InvitationController(this._service) : super([]) {
    _loadInvitations();
    _startRealtimeListener();
    _startAutoRefresh();
  }

  Future<void> _loadInvitations() async {
    try {
      final invitations = await _service.getPendingInvitations();
      print('📨 [INVITATION] Loaded ${invitations.length} invitations');

      // Update state
      state = invitations;

      // Log invitation details
      if (invitations.isNotEmpty) {
        print(
          '🎵 [INVITATION] You have ${invitations.length} pending invitation(s):',
        );
        for (var inv in invitations) {
          print('   - From: ${inv.hostUsername}, Session: ${inv.sessionId}');
        }
      }
    } catch (e) {
      print('❌ [INVITATION] Error loading invitations: $e');
    }
  }

  void _startRealtimeListener() {
    if (_isSubscribed) return;

    print('👂 [INVITATION] Starting real-time listener for invitations');

    try {
      // Subscribe to real-time changes using callback
      _service.subscribeToInvitationChanges(
        onInvitationChange: () {
          print('🔔 [INVITATION] Real-time change detected, refreshing...');
          _loadInvitations();
        },
      );
      _isSubscribed = true;
      print('✅ [INVITATION] Real-time subscription active');
    } catch (e) {
      print('❌ [INVITATION] Failed to start real-time listener: $e');
    }
  }

  void _startAutoRefresh() {
    // Backup polling every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      print('🔄 [INVITATION] Auto-refresh (backup polling)');
      _loadInvitations();
    });
  }

  Future<void> refresh() async {
    print('🔄 [INVITATION] Manual refresh requested');
    await _loadInvitations();
  }

  Future<bool> acceptInvitation(String invitationId, String sessionId) async {
    try {
      print('✅ [INVITATION] Accepting invitation: $invitationId');
      await _service.acceptInvitation(invitationId, sessionId);
      await _loadInvitations();
      return true;
    } catch (e) {
      print('❌ [INVITATION] Error accepting: $e');
      return false;
    }
  }

  Future<bool> declineInvitation(String invitationId) async {
    try {
      print('❌ [INVITATION] Declining invitation: $invitationId');
      await _service.declineInvitation(invitationId);
      await _loadInvitations();
      return true;
    } catch (e) {
      print('❌ [INVITATION] Error declining: $e');
      return false;
    }
  }

  @override
  void dispose() {
    print('🗑️ [INVITATION] Disposing invitation controller');
    _refreshTimer?.cancel();
    if (_isSubscribed) {
      _service.unsubscribeFromInvitationChanges();
      _isSubscribed = false;
    }
    super.dispose();
  }
}

/// Invitation controller provider
final invitationControllerProvider =
    StateNotifierProvider<InvitationController, List<SessionInvitation>>((ref) {
      final db = ref.watch(dbActionsProvider);
      return InvitationController(db.syncListeningService);
    });

// ============================================================================
// HELPER PROVIDERS
// ============================================================================

/// Check if user is in an active session
final isInActiveSessionProvider = Provider<bool>((ref) {
  final session = ref.watch(activeSessionProvider);
  return session.value != null;
});

/// Check if user is host of current session
final isSessionHostProvider = Provider<bool>((ref) {
  final session = ref.watch(activeSessionProvider);
  return session.value?.isHost ?? false;
});

/// Count of pending invitations
final invitationCountProvider = Provider<int>((ref) {
  final invitations = ref.watch(invitationControllerProvider);
  return invitations.length;
});
