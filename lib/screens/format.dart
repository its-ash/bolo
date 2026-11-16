const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 1:05 or 0:09.
String formatDuration(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "16 Nov, 4:05 pm"; the year is added when it is not [now]'s year.
String formatWhen(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final ap = t.hour < 12 ? 'am' : 'pm';
  final year = t.year == n.year ? '' : ' ${t.year}';
  return '${t.day} ${_months[t.month - 1]}$year, $h:$m $ap';
}
