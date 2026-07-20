/// Formats a past [time] as a short Thai relative-time label, e.g.
/// "5 นาทีที่แล้ว" — used to show "xx ago" next to the subject someone
/// most recently worked on.
String relativeTimeLabel(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'เมื่อสักครู่';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
  if (diff.inDays < 30) return '${diff.inDays} วันที่แล้ว';
  return '${(diff.inDays / 30).floor()} เดือนที่แล้ว';
}
