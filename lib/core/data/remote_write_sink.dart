import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One tag row mirrored to the remote as part of a full parent tag replacement.
///
/// The [id] is generated locally so the remote row shares the local row's uuid;
/// differing ids would let the sync pull re-insert a removed tag as a new row.
class RemoteTagRow {
  /// Creates a [RemoteTagRow].
  const RemoteTagRow({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// The tag row's primary key (uuid v4, shared with the local row).
  final String id;

  /// The tag name.
  final String name;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;
}

/// Receives write notifications for aggregates so they can be mirrored to the
/// remote Turso database at mutation time.
///
/// The drift repositories depend only on this data-layer abstraction (not on
/// the sync layer); the sync layer implements it. At runtime `main()` always
/// installs a sink, which itself no-ops while sync is unconfigured, so the
/// repositories call it unconditionally through their nullable field.
abstract interface class RemoteWriteSink {
  /// Records that [id] was deleted from [table].
  ///
  /// Implementations enqueue the mirror in the same local transaction as the
  /// mutation so it survives being offline, then attempt an immediate remote
  /// delete when configured. A rare local enqueue failure is logged and the
  /// mirror is skipped (the local mutation still succeeds). The delete is a
  /// no-op in local (unconfigured) mode so the outbound queue never grows for a
  /// device that will never sync.
  Future<void> recordDelete(String table, String id);

  /// Records a full tag replacement for the row [parentId] of [parentTable].
  ///
  /// The remote rows in [childTable] whose [parentColumn] equals [parentId] are
  /// deleted and [rows] are inserted. This mirrors the reference
  /// `setTagsForNote`/`setTagsForLink`/`setTagsForWorkLog`, which delete then
  /// `INSERT OR IGNORE` the replacement at mutation time.
  Future<void> recordTags({
    required String parentTable,
    required String parentId,
    required String childTable,
    required String parentColumn,
    required List<RemoteTagRow> rows,
  });

  /// Records an upsert of [row] into [table].
  ///
  /// [row] is the full raw row (as read back from the local database), keyed
  /// by column name. The remote row is inserted if missing, then its mutable
  /// columns are updated to match [row], replaying the sync merge's own column
  /// lists. Used for `project_phases` (which has no `updated_at` and is
  /// insert-only in sync) and for every other entity table so creates and
  /// updates reach the remote at mutation time instead of waiting for a sync.
  Future<void> recordUpsert(String table, Map<String, Object?> row);
}

/// The remote table names a [RemoteWriteSink] understands.
///
/// These match the SQL table names in the frozen remote schema, so they are
/// safe to use as `pending_writes.table_name` values and in remote SQL.
abstract final class RemoteTables {
  /// The `todos` table.
  static const String todos = 'todos';

  /// The `notes` table.
  static const String notes = 'notes';

  /// The `links` table.
  static const String links = 'links';

  /// The `work_logs` table.
  static const String workLogs = 'work_logs';

  /// The `projects` table.
  static const String projects = 'projects';

  /// The `project_phases` table.
  static const String projectPhases = 'project_phases';

  /// The `work_items` table.
  static const String workItems = 'work_items';
}

/// The optional sink the drift repositories use to mirror writes.
///
/// Defaults to `null` and is overridden in `main()` with the sync layer's
/// stable sink, so at runtime the sink is always installed and no-ops while
/// sync is unconfigured. The override is stable, so changing sync configuration
/// never recreates the repositories or restarts their watch streams.
final remoteWriteSinkProvider = Provider<RemoteWriteSink?>((ref) => null);
