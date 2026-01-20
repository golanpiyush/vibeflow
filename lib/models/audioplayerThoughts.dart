/// Data class representing a single thought
class AudioThought {
  final String type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic> context;

  AudioThought({
    required this.type,
    required this.message,
    required this.timestamp,
    required this.context,
  });

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
