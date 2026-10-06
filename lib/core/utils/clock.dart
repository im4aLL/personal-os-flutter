/// Millisecond-precision UTC ISO-8601 timestamp helpers.
///
/// This file is the single source of timestamps for syncable data. Dart's
/// `DateTime.toIso8601String()` emits microseconds (`.789123Z`), which breaks
/// the lexicographic `updated_at` comparison the shared Turso database relies
/// on: `'1' < 'Z'`, so a newer Flutter write would look older and lose
/// last-write-wins. Never call `toIso8601String()` directly on syncable data.
library;

/// Returns [dateTime] as a UTC ISO-8601 string truncated to milliseconds, e.g.
/// `2026-10-05T12:34:56.789Z`.
String isoFromDateTime(DateTime dateTime) {
  final milliseconds = dateTime.toUtc().millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
      .toIso8601String();
}

/// Returns the current time as a millisecond-precision UTC ISO-8601 string.
String nowIso() => isoFromDateTime(DateTime.now());
