import 'package:intl/intl.dart';

/// Formats [date] as `YYYY-MM-DD`.
String formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Parses a `YYYY-MM-DD` string into a local [DateTime] at midnight.
DateTime parseDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    throw FormatException('Not a YYYY-MM-DD date', value);
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Returns the local date component of [dateTime] at midnight.
DateTime dateOnly(DateTime dateTime) =>
    DateTime(dateTime.year, dateTime.month, dateTime.day);

/// Today's local date as `YYYY-MM-DD`.
///
/// [now] is injectable for deterministic tests.
String todayDate([DateTime? now]) => formatDate(dateOnly(now ?? DateTime.now()));

/// Returns the ISO-8601 week key `YYYY-Www` for a `YYYY-MM-DD` string.
///
/// Weeks start on Monday (ISO 8601); the Thursday of the week determines the
/// year, matching the reference `getWeekKey`.
String weekKey(String dateStr) {
  final date = parseDate(dateStr);
  // Mon=1 .. Sun=7 -> the Thursday of this week.
  final thursday = DateTime.utc(date.year, date.month, date.day + (4 - date.weekday));
  final yearStart = DateTime.utc(thursday.year, 1, 1);
  final weekNum = ((thursday.difference(yearStart).inDays + 1) / 7).ceil();
  return '${thursday.year}-W${weekNum.toString().padLeft(2, '0')}';
}

/// Returns the Monday of the week containing [dateStr].
DateTime mondayOf(String dateStr) {
  final date = parseDate(dateStr);
  return DateTime(date.year, date.month, date.day - (date.weekday - 1));
}

/// Returns a human label for the ISO week containing [dateStr]:
/// `This week`, `Last week`, or `Week of <date>`.
///
/// [now] is injectable for deterministic tests.
String weekLabel(String dateStr, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final key = weekKey(dateStr);
  if (key == weekKey(todayDate(current))) return 'This week';

  final today = parseDate(todayDate(current));
  final lastMonday = DateTime(today.year, today.month, today.day - 7);
  if (key == weekKey(formatDate(lastMonday))) return 'Last week';

  final monday = mondayOf(dateStr);
  final pattern = monday.year == current.year ? 'MMM d' : 'MMM d, y';
  return 'Week of ${DateFormat(pattern).format(monday)}';
}

/// Formats an ISO-8601 timestamp for display, converting to local time.
String formatDateTimeShort(String iso) =>
    DateFormat('MMM d, HH:mm').format(DateTime.parse(iso).toLocal());

/// Formats a `YYYY-MM-DD` date for display, e.g. `Oct 5`.
String formatDateShort(String dateStr) =>
    DateFormat('MMM d').format(parseDate(dateStr));

