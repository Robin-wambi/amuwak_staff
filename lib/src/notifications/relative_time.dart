/// Short, scannable relative-time label for a past instant ("4 min ago").
///
/// Pure: [now] is injected so callers (and tests) stay deterministic.
String relativeTimeLabel(DateTime time, {required DateTime now}) {
  final diff = now.difference(time);
  // A future [time] (clock skew, bad data) has a negative diff. Collapse it to
  // "just now" explicitly rather than relying on `inMinutes < 1` to swallow it.
  if (diff.isNegative) return 'just now';
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  final days = diff.inDays;
  return '$days day${days == 1 ? '' : 's'} ago';
}
