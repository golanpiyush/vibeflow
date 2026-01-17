import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart'
    hide supabaseClientProvider;

final realtimeActivityStreamProvider = StreamProvider<ListeningActivity>((ref) {
  final dbActions = ref.watch(dbActionsProvider);
  final hasAccessCode = ref.watch(hasAccessCodeProvider);

  if (!(hasAccessCode.value ?? false)) return Stream.empty();

  return dbActions.subscribeToFollowingActivity();
});

final followingActivitiesProvider = StreamProvider<List<ListeningActivity>>((
  ref,
) {
  final currentUser = ref.watch(currentUserProvider);
  final hasAccessCode = ref.watch(hasAccessCodeProvider);
  final supabase = ref.watch(supabaseClientProvider);

  if (currentUser == null || !(hasAccessCode.value ?? false)) {
    return Stream.value([]);
  }

  final controller = StreamController<List<ListeningActivity>>();
  List<ListeningActivity> activities = [];

  Timer? autoRefreshTimer;
  Timer? uiRefreshTimer; // ✅ NEW: For UI updates
  RealtimeChannel? realtimeChannel;
  bool isDisposed = false;
  bool mounted = true;

  void safeAdd(List<ListeningActivity> newActivities) {
    if (!isDisposed && !controller.isClosed && mounted) {
      try {
        activities = newActivities;
        controller.add(activities);
      } catch (e) {
        print('⚠️ Safe add error: $e');
      }
    }
  }

  Future<void> loadActivities() async {
    if (isDisposed || controller.isClosed || !mounted) return;

    try {
      print('🔄 Loading following activities for: ${currentUser.id}');

      final response = await supabase.rpc(
        'get_following_activities',
        params: {'p_user_id': currentUser.id},
      );

      if (response is List) {
        final newActivities = <ListeningActivity>[];

        for (final item in response) {
          try {
            final jsonData = Map<String, dynamic>.from(item);

            if (jsonData['played_at'] is String) {
              jsonData['played_at'] = DateTime.parse(
                jsonData['played_at'] as String,
              ).toUtc().toIso8601String();
            }

            jsonData['current_position_ms'] =
                jsonData['current_position_ms'] ?? 0;
            jsonData['is_currently_playing'] =
                jsonData['is_currently_playing'] ?? false;
            jsonData['duration_ms'] = jsonData['duration_ms'] ?? 0;
            jsonData['status'] = jsonData['status'] ?? 'unknown';

            final activity = ListeningActivity.fromMap(jsonData);
            newActivities.add(activity);
          } catch (e) {
            print('⚠️ Error parsing activity: $e');
          }
        }

        safeAdd(newActivities);
        print('✅ Loaded ${newActivities.length} activities');
      }
    } catch (e) {
      print('❌ Error loading activities: $e');
      if (!isDisposed && !controller.isClosed && mounted) {
        try {
          controller.addError(e);
        } catch (_) {}
      }
    }
  }

  // Initial load
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isDisposed && mounted) {
      loadActivities();
    }
  });

  // Set up real-time subscription
  if (!isDisposed) {
    try {
      realtimeChannel = supabase
          .channel('following_activities_${currentUser.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'listening_activity',
            callback: (payload) async {
              if (isDisposed) return;

              print('🔔 Real-time activity change: ${payload.eventType}');

              if (!isDisposed && mounted) {
                await loadActivities();
              }
            },
          )
          .subscribe();

      print('📡 Subscribed to real-time activity changes');
    } catch (e) {
      print('❌ Error setting up realtime: $e');
    }
  }

  // ✅ NEW: UI refresh every second for smooth position updates
  uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (!isDisposed && mounted && activities.isNotEmpty) {
      // Check if any activity is currently playing
      final hasPlaying = activities.any((a) => a.isCurrentlyPlaying);

      if (hasPlaying) {
        // Re-emit the same list to trigger UI rebuild
        // The UI will recalculate real-time positions
        safeAdd(List.from(activities));
      }
    } else {
      timer.cancel();
    }
  });

  // Auto-refresh from database every 10 seconds
  autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
    if (!isDisposed && mounted) {
      print('🔄 Auto-refreshing activities (10s interval)...');
      loadActivities();
    } else {
      timer.cancel();
    }
  });

  ref.onDispose(() {
    print('🗑️ Disposing activities provider');
    isDisposed = true;
    mounted = false;

    autoRefreshTimer?.cancel();
    autoRefreshTimer = null;

    // ✅ Cancel UI refresh timer
    uiRefreshTimer?.cancel();
    uiRefreshTimer = null;

    try {
      realtimeChannel?.unsubscribe();
    } catch (e) {
      print('⚠️ Error unsubscribing realtime: $e');
    }
    realtimeChannel = null;

    if (!controller.isClosed) {
      try {
        controller.close();
      } catch (e) {
        print('⚠️ Error closing controller: $e');
      }
    }
  });

  return controller.stream;
});
