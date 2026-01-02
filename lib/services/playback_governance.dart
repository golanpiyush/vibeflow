// lib/services/playback_governance.dart

/// Navigation source for tracking how playback was initiated
enum NavigationSource {
  USER, // User clicked play
  QUEUE, // From queue
  AUTOPLAY, // Auto-progression from radio
  ERROR_RECOVERY, // Error recovery
  SYSTEM, // System-initiated
}

/// Operation types with priority levels
enum OperationType {
  USER_PLAY, // Priority 1 - User initiated playback
  USER_NAVIGATE, // Priority 1 - User navigation (next/previous)
  ERROR_RECOVERY, // Priority 2 - Error recovery operations
  QUEUE_SYNC, // Priority 2 - Queue synchronization
  AUTOPLAY, // Priority 3 - Automatic progression
  BACKGROUND_FETCH, // Priority 5 - Background operations
}

/// Playback context for tracking state
class PlaybackContext {
  final String videoId;
  final NavigationSource source;
  final OperationType operation;
  final bool isNetworkPlayback;
  final DateTime timestamp;
  final String? parentRadioId; // Track which song's radio this came from

  PlaybackContext({
    required this.videoId,
    required this.source,
    required this.operation,
    this.isNetworkPlayback = true,
    DateTime? timestamp,
    this.parentRadioId,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Get priority level (1 is highest)
  int get priority {
    switch (operation) {
      case OperationType.USER_PLAY:
      case OperationType.USER_NAVIGATE:
        return 1;
      case OperationType.ERROR_RECOVERY:
      case OperationType.QUEUE_SYNC:
        return 2;
      case OperationType.AUTOPLAY:
        return 3;
      case OperationType.BACKGROUND_FETCH:
        return 5;
    }
  }

  /// Check if this is a user-initiated action
  bool get isUserInitiated {
    return source == NavigationSource.USER &&
        (operation == OperationType.USER_PLAY ||
            operation == OperationType.USER_NAVIGATE);
  }
}

/// Governance system to manage playback priorities and radio loading
class PlaybackGovernance {
  PlaybackContext? _currentContext;
  PlaybackContext? _pendingContext;

  // Track loaded radio to prevent duplicate loads
  final Set<String> _loadedRadios = {};
  String? _activeRadioSource; // Which song's radio is currently active

  // Tracks user queue orders
  List<String> _userQueueOrder = [];

  // Sets user-defined queue order
  void setUserQueueOrder(List<String> videoIds) {
    _userQueueOrder = List.from(videoIds);
    print(
      '📋 [Governance] User queue order set: ${_userQueueOrder.length} items',
    );
  }

  // Gets user queue order
  List<String> get userQueueOrder => List.unmodifiable(_userQueueOrder);

  // Clear queue order
  void clearQueueOrder() {
    _userQueueOrder.clear();
    print('🗑️ [Governance] Queue order cleared');
  }

  /// Check if an operation should proceed based on priority
  bool shouldProceed(PlaybackContext newContext) {
    // No current operation - always proceed
    if (_currentContext == null) {
      return true;
    }

    // Check priority
    if (newContext.priority < _currentContext!.priority) {
      // Higher priority (lower number) - interrupt current
      print(
        '⚡ [Governance] Higher priority operation: ${newContext.operation}',
      );
      return true;
    }

    // Same priority - check timestamp (newer wins)
    if (newContext.priority == _currentContext!.priority) {
      final isNewer = newContext.timestamp.isAfter(_currentContext!.timestamp);
      if (isNewer) {
        print('🔄 [Governance] Newer operation of same priority');
      }
      return isNewer;
    }

    // Lower priority - reject
    print(
      '⛔ [Governance] Lower priority operation blocked: ${newContext.operation}',
    );
    return false;
  }

  // Validates if queue matches user orders
  bool validateQueueOrder(List<String> currentQueue) {
    if (_userQueueOrder.isEmpty) return true;

    if (currentQueue.length != _userQueueOrder.length) {
      print('⚠️ [Governance] Queue length mismatch');
      return false;
    }

    for (int i = 0; i < currentQueue.length; i++) {
      if (currentQueue[i] != _userQueueOrder[i]) {
        print('⚠️ [Governance] Queue order mismatch at index $i');
        return false;
      }
    }

    print('✅ [Governance] Queue order validated and is being followed');
    return true;
  }

  /// Start an operation
  void startOperation(PlaybackContext context) {
    _currentContext = context;
    _pendingContext = null;

    // Track radio source for user-initiated plays
    if (context.isUserInitiated) {
      _activeRadioSource = context.videoId;
      print('🎵 [Governance] Active radio source set to: ${context.videoId}');
    }

    print(
      '▶️ [Governance] Operation started: ${context.operation} '
      'from ${context.source} (Priority ${context.priority})',
    );
  }

  /// Complete an operation
  void completeOperation() {
    if (_currentContext != null) {
      print(
        '✅ [Governance] Operation completed: ${_currentContext!.operation}',
      );
      _currentContext = null;
    }

    // Process pending operation if any
    if (_pendingContext != null) {
      startOperation(_pendingContext!);
      _pendingContext = null;
    }
  }

  /// Queue a pending operation
  void queueOperation(PlaybackContext context) {
    _pendingContext = context;
    print('⏳ [Governance] Operation queued: ${context.operation}');
  }

  /// Check if we should load radio for this song
  bool shouldLoadRadio(String videoId) {
    // Don't load if already loaded
    if (_loadedRadios.contains(videoId)) {
      print('⚠️ [Governance] Radio already loaded for: $videoId');
      return false;
    }

    // Only load for user-initiated plays or active radio source
    if (_currentContext == null) return true;

    final isUserPlay = _currentContext!.isUserInitiated;
    final isActiveSource = videoId == _activeRadioSource;

    if (isUserPlay || isActiveSource) {
      _loadedRadios.add(videoId);
      print('✅ [Governance] Radio loading approved for: $videoId');
      return true;
    }

    print('⛔ [Governance] Radio loading blocked for: $videoId');
    return false;
  }

  /// Mark radio as loaded
  void markRadioLoaded(String videoId) {
    _loadedRadios.add(videoId);
  }

  /// Clear radio loaded state when switching sources
  void clearRadioState() {
    _loadedRadios.clear();
    _activeRadioSource = null;
    print('🗑️ [Governance] Radio state cleared');
  }

  /// Get current operation context
  PlaybackContext? get currentContext => _currentContext;

  /// Get active radio source
  String? get activeRadioSource => _activeRadioSource;

  /// Check if currently playing from a specific radio source
  bool isPlayingFromRadio(String? parentRadioId) {
    return parentRadioId != null && parentRadioId == _activeRadioSource;
  }

  /// Reset governance states
  void reset() {
    _currentContext = null;
    _pendingContext = null;
    _loadedRadios.clear();
    _activeRadioSource = null;
    _userQueueOrder.clear();
    print('🔄 [Governance] State reset');
  }
}
