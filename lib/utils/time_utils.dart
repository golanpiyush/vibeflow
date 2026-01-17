// utils/time_utils.dart
class TimeUtils {
  static String nowUtcIsoString() {
    return DateTime.now().toUtc().toIso8601String();
  }

  static DateTime parseUtc(String isoString) {
    return DateTime.parse(isoString).toUtc();
  }

  static String formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now().toUtc();
    final difference = now.difference(dateTime);

    switch (true) {
      case true when difference.inSeconds < 60:
        return '${difference.inSeconds} seconds ago';

      case true when difference.inMinutes < 60:
        return '${difference.inMinutes} minutes ago';

      case true when difference.inHours < 24:
        return '${difference.inHours} hours ago';

      case true when difference.inDays < 30:
        return '${difference.inDays} days ago';

      case true when difference.inDays < 365:
        final months = (difference.inDays / 30).floor();
        return '$months month${months > 1 ? 's' : ''} ago';

      default:
        final years = (difference.inDays / 365).floor();
        return '$years year${years > 1 ? 's' : ''} ago';
    }
  }
}
