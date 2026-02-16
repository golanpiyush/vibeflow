// Add this at the top of your file with other providers
import 'package:flutter_riverpod/legacy.dart';

final engineRateLimitProvider =
    StateNotifierProvider<EngineRateLimitNotifier, EngineRateLimitState>((ref) {
      return EngineRateLimitNotifier();
    });

class EngineRateLimitState {
  final List<DateTime> actionTimestamps;
  final DateTime? blockUntil;

  EngineRateLimitState({required this.actionTimestamps, this.blockUntil});

  EngineRateLimitState copyWith({
    List<DateTime>? actionTimestamps,
    DateTime? blockUntil,
  }) {
    return EngineRateLimitState(
      actionTimestamps: actionTimestamps ?? this.actionTimestamps,
      blockUntil: blockUntil ?? this.blockUntil,
    );
  }
}

class EngineRateLimitNotifier extends StateNotifier<EngineRateLimitState> {
  EngineRateLimitNotifier() : super(EngineRateLimitState(actionTimestamps: []));

  void addAction() {
    final now = DateTime.now();

    // Clean up old timestamps (older than 10 seconds)
    final recentActions = state.actionTimestamps
        .where((timestamp) => now.difference(timestamp).inSeconds < 10)
        .toList();

    // Add new action
    recentActions.add(now);

    // Check if we've hit the limit (4 actions in 10 seconds)
    DateTime? newBlockUntil = state.blockUntil;
    if (recentActions.length >= 4 && state.blockUntil == null) {
      newBlockUntil = now.add(const Duration(minutes: 10));
    }

    state = state.copyWith(
      actionTimestamps: recentActions,
      blockUntil: newBlockUntil,
    );
  }

  void clearBlock() {
    state = state.copyWith(actionTimestamps: [], blockUntil: null);
  }

  bool get isBlocked {
    if (state.blockUntil == null) return false;
    return DateTime.now().isBefore(state.blockUntil!);
  }

  int get remainingBlockSeconds {
    if (state.blockUntil == null) return 0;
    final remaining = state.blockUntil!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }
}
