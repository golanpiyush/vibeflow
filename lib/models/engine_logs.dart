/// Log entry for VibeFlow Engine operations
class EngineLogEntry {
  final DateTime timestamp;
  final String level; // INFO, SUCCESS, WARNING, ERROR
  final String category; // INIT, FETCH, CACHE, ENRICH, BATCH
  final String message;
  final String? videoId;
  final String? songTitle;
  final Map<String, dynamic>? metadata;

  EngineLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.videoId,
    this.songTitle,
    this.metadata,
  });

  String get formattedTime {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$hour:$minute:$second.$ms';
  }

  String get formattedMessage {
    final buffer = StringBuffer();
    buffer.write('[$formattedTime] ');
    buffer.write('[$level] ');
    buffer.write('[$category] ');

    if (videoId != null) {
      buffer.write('[ID: ${videoId!.substring(0, 8)}...] ');
    }

    if (songTitle != null) {
      buffer.write('"$songTitle" - ');
    }

    buffer.write(message);

    return buffer.toString();
  }
}
