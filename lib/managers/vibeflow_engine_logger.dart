import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vibeflow/models/engine_logs.dart';
import 'package:vibeflow/services/bg_audio_handler.dart';

/// Central logger for VibeFlow Engine operations
class VibeFlowEngineLogger extends ChangeNotifier {
  static final VibeFlowEngineLogger _instance =
      VibeFlowEngineLogger._internal();
  factory VibeFlowEngineLogger() => _instance;
  VibeFlowEngineLogger._internal();

  // Store logs in memory (limit to last 500 entries)
  final List<EngineLogEntry> _logs = [];
  static const int _maxLogs = 500;

  // Engine status
  bool _isEngineInitialized = false;
  bool get isBlocked => !_isEngineInitialized;
  DateTime? _initializationTime;

  // Operation counters
  int _totalFetches = 0;
  int _successfulFetches = 0;
  int _failedFetches = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalEnrichments = 0;

  // Active operations
  final Set<String> _activeOperations = {};
  final Map<String, DateTime> _operationStartTimes = {};

  // Getters
  bool get isEngineInitialized => _isEngineInitialized;
  DateTime? get initializationTime => _initializationTime;
  List<EngineLogEntry> get logs => List.unmodifiable(_logs);
  int get totalFetches => _totalFetches;
  int get successfulFetches => _successfulFetches;
  int get failedFetches => _failedFetches;
  int get cacheHits => _cacheHits;
  int get cacheMisses => _cacheMisses;
  int get totalEnrichments => _totalEnrichments;
  Set<String> get activeOperations => Set.unmodifiable(_activeOperations);

  double get successRate {
    if (_totalFetches == 0) return 0.0;
    return (_successfulFetches / _totalFetches) * 100;
  }

  double get cacheHitRate {
    final total = _cacheHits + _cacheMisses;
    if (total == 0) return 0.0;
    return (_cacheHits / total) * 100;
  }

  /// Log engine initialization
  void logInitialization({bool success = true}) {
    _isEngineInitialized = success;
    if (success) {
      _initializationTime = DateTime.now();
    }

    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: success ? 'SUCCESS' : 'ERROR',
        category: 'INIT',
        message: success
            ? 'VibeFlow Engine initialized successfully'
            : 'VibeFlow Engine initialization failed',
      ),
    );
  }

  /// Log audio URL fetch start
  void logFetchStart(String videoId, {String? songTitle}) {
    _totalFetches++;
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        category: 'FETCH',
        message: 'Starting audio URL fetch',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );

    _startOperation('fetch_$videoId');
  }

  /// Log audio URL fetch success
  void logFetchSuccess(String videoId, {String? songTitle, String? source}) {
    _successfulFetches++;
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'SUCCESS',
        category: 'FETCH',
        message: source != null
            ? 'Audio URL fetched successfully from $source'
            : 'Audio URL fetched successfully',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );

    _endOperation('fetch_$videoId');
  }

  /// Log audio URL fetch failure
  void logFetchFailure(String videoId, {String? songTitle, String? error}) {
    _failedFetches++;
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'ERROR',
        category: 'FETCH',
        message: error != null
            ? 'Audio URL fetch failed: $error'
            : 'Audio URL fetch failed',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );

    _endOperation('fetch_$videoId');
  }

  /// Log cache hit
  void logCacheHit(String videoId, {String? songTitle, Duration? age}) {
    _cacheHits++;
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        category: 'CACHE',
        message: age != null
            ? 'Cache hit (age: ${age.inMinutes}m ${age.inSeconds % 60}s)'
            : 'Cache hit',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );
  }

  /// Log cache miss
  void logCacheMiss(String videoId, {String? songTitle}) {
    _cacheMisses++;
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        category: 'CACHE',
        message: 'Cache miss, fetching fresh URL',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );
  }

  /// Log cache expiry
  void logCacheExpiry(String videoId, {String? songTitle, Duration? age}) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'WARNING',
        category: 'CACHE',
        message: age != null
            ? 'Cache expired (age: ${age.inHours}h ${age.inMinutes % 60}m)'
            : 'Cache expired',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );
  }

  /// Log song enrichment start
  void logEnrichmentStart(String videoId, {String? songTitle}) {
    _totalEnrichments++;
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        category: 'ENRICH',
        message: 'Starting song enrichment',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );

    _startOperation('enrich_$videoId');
  }

  /// Log song enrichment success
  void logEnrichmentSuccess(String videoId, {String? songTitle}) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'SUCCESS',
        category: 'ENRICH',
        message: 'Song enrichment completed',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );

    _endOperation('enrich_$videoId');
  }

  /// Log batch operation start
  void logBatchStart(int count, String operation) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        category: 'BATCH',
        message: 'Starting batch $operation for $count songs',
        metadata: {'count': count, 'operation': operation},
      ),
    );

    _startOperation('batch_$operation');
  }

  /// Log batch operation complete
  void logBatchComplete(int successful, int total, String operation) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'SUCCESS',
        category: 'BATCH',
        message: 'Batch $operation completed: $successful/$total successful',
        metadata: {
          'successful': successful,
          'total': total,
          'operation': operation,
        },
      ),
    );

    _endOperation('batch_$operation');
  }

  /// Log retry attempt
  void logRetry(
    String videoId,
    int attempt,
    int maxAttempts, {
    String? songTitle,
  }) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'WARNING',
        category: 'FETCH',
        message: 'Retry attempt $attempt/$maxAttempts',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );
  }

  /// Log force refresh
  void logForceRefresh(String videoId, {String? songTitle}) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        category: 'FETCH',
        message: 'Force refreshing audio URL (bypass cache)',
        videoId: videoId,
        songTitle: songTitle,
      ),
    );
  }

  /// Add a log entry
  void _addLog(EngineLogEntry entry) {
    _logs.add(entry);

    // Keep only last _maxLogs entries
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }

    notifyListeners();
  }

  /// Log an info message
  void logInfo(
    String message, {
    String category = 'INFO',
    Map<String, dynamic>? metadata,
  }) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        category: category,
        message: message,
        metadata: metadata,
      ),
    );
  }

  /// Log a warning message
  void logWarning(
    String message, {
    String category = 'WARNING',
    Map<String, dynamic>? metadata,
  }) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'WARNING',
        category: category,
        message: message,
        metadata: metadata,
      ),
    );
  }

  /// Log an error message
  void logError(
    String message, {
    String? error,
    String category = 'ERROR',
    Map<String, dynamic>? metadata,
  }) {
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'ERROR',
        category: category,
        message: error != null ? '$message: $error' : message,
        metadata: metadata,
      ),
    );
  }

  /// Start tracking an operation
  void _startOperation(String operationId) {
    _activeOperations.add(operationId);
    _operationStartTimes[operationId] = DateTime.now();
    notifyListeners();
  }

  /// End tracking an operation
  void _endOperation(String operationId) {
    _activeOperations.remove(operationId);
    _operationStartTimes.remove(operationId);
    notifyListeners();
  }

  /// Get operation duration
  Duration? getOperationDuration(String operationId) {
    final startTime = _operationStartTimes[operationId];
    if (startTime == null) return null;
    return DateTime.now().difference(startTime);
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Reset all statistics
  void resetStats() {
    _totalFetches = 0;
    _successfulFetches = 0;
    _failedFetches = 0;
    _cacheHits = 0;
    _cacheMisses = 0;
    _totalEnrichments = 0;
    notifyListeners();
  }

  // ADD after resetStats() method:
  void stopEngine() {
    _isEngineInitialized = false;
    _activeOperations.clear();
    _operationStartTimes.clear();
    _addLog(
      EngineLogEntry(
        timestamp: DateTime.now(),
        level: 'WARNING',
        category: 'INIT',
        message: 'VibeFlow Engine manually stopped',
      ),
    );

    // Kill playback
    final handler = getAudioHandler();
    if (handler != null) {
      handler.stopImmediately();
    }
  }

  void restartEngine() {
    stopEngine();
    Future.delayed(const Duration(milliseconds: 500), () {
      logInitialization(success: true);
    });
  }

  /// Get logs by category
  List<EngineLogEntry> getLogsByCategory(String category) {
    return _logs.where((log) => log.category == category).toList();
  }

  /// Get logs by level
  List<EngineLogEntry> getLogsByLevel(String level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// Get recent logs (last n entries)
  List<EngineLogEntry> getRecentLogs(int count) {
    if (_logs.length <= count) return _logs;
    return _logs.sublist(_logs.length - count);
  }
}
