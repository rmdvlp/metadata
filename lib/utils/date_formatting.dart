const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _weekdayNames = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String formatShortDate(DateTime date) {
  return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
}

String formatTime(DateTime date) {
  final hour24 = date.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${_twoDigits(date.minute)} $period';
}

/// "2 min ago" / "3 hr ago" / "5 days ago" / falls back to a short date.
String formatTimeAgo(DateTime date, {required DateTime now}) {
  final diff = now.difference(date);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  return formatShortDate(date);
}

/// A call's talk time as a clock reading: "0:42" / "4:07" / "1:05:30".
///
/// Hours are only shown once there are any, so the common case stays as short
/// as the timer on the live call screen. Negative input (a clock that moved
/// backwards mid-call) reads as zero rather than as a nonsense duration.
String formatCallDuration(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;
  if (hours > 0) {
    return '$hours:${_twoDigits(minutes)}:${_twoDigits(secs)}';
  }
  return '$minutes:${_twoDigits(secs)}';
}

/// "Today, 4:30 PM" / "Yesterday, 7:45 PM" / "Mon, 11:20 AM" / "May 14, 2026"
String formatRelativeDateTime(DateTime date, {required DateTime now}) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diffDays = today.difference(target).inDays;

  if (diffDays == 0) return 'Today, ${formatTime(date)}';
  if (diffDays == 1) return 'Yesterday, ${formatTime(date)}';
  if (diffDays > 1 && diffDays < 7) {
    return '${_weekdayNames[date.weekday - 1]}, ${formatTime(date)}';
  }
  return formatShortDate(date);
}
