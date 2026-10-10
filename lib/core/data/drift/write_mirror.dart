import 'package:drift/drift.dart';

import '../remote_write_sink.dart';
import 'database.dart';

/// Re-reads one raw row and mirrors it to the remote store at mutation time.
///
/// Call this inside the same transaction as the local write, after the write,
/// so the queued intent commits atomically with it. The row is read back (not
/// built from the caller's model) so partial writes mirror exactly what is
/// stored, including the freshly stamped `updated_at`.
///
/// [table] and [idColumn] are internal constants at every call site, never
/// user input. A missing row (deleted concurrently) or an uninstalled sink
/// simply skips the mirror; in unconfigured mode the engine no-ops anyway.
Future<void> mirrorUpsert(
  AppDatabase database,
  RemoteWriteSink? sink, {
  required String table,
  required String id,
  String idColumn = 'id',
}) async {
  final target = sink;
  if (target == null) return;
  final row = await database
      .customSelect(
        'SELECT * FROM $table WHERE $idColumn = ?',
        variables: [Variable.withString(id)],
      )
      .getSingleOrNull();
  if (row == null) return;
  await target.recordUpsert(table, Map<String, Object?>.from(row.data));
}
