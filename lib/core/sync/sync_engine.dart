import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/drift/database.dart';
import '../data/remote_write_sink.dart';
import 'pending_write_store.dart';
import 'remote_schema.dart';
import 'turso_client.dart';

/// The outcome of one [SyncEngine.sync] run.
class SyncResult {
  /// Creates a [SyncResult].
  const SyncResult({
    required this.pushed,
    required this.pulled,
    required this.flushedWrites,
    required this.pendingWritesRemaining,
    required this.skewWarning,
  });

  /// Rows written to the remote during this run.
  final int pushed;

  /// Rows written to the local database during this run.
  final int pulled;

  /// Queued writes successfully flushed to the remote during this run.
  final int flushedWrites;

  /// Queued writes that could not be flushed and remain queued.
  final int pendingWritesRemaining;

  /// A human-readable warning when the device clock differs grossly from the
  /// Turso server clock, or `null` when the clocks agree.
  final String? skewWarning;
}

/// Bidirectional last-write-wins sync engine.
///
/// Faithful port of `../personal-os/src/lib/sync.ts`: per-table LWW on the
/// string-compared `updated_at` column, with tag/phase tables insert-only in
/// both directions. The local drift database is the source of truth and the
/// remote Turso database is shared with the desktop and TUI clients, so the
/// merge rules and value formats must match exactly.
///
/// Mobile extensions beyond the desktop:
/// - every local write (creates, updates, deletes, tag replacements, phase
///   upserts) is mirrored to the remote at mutation time through a local-only
///   `pending_writes` outbound queue, so the cloud converges without waiting
///   for a sync (the desktop only mirrors deletes at mutation time);
/// - the queue holds one latest intent per `(table, row)` and is flushed
///   before pulling (the desktop simply loses offline writes);
/// - pulled rows whose id (or parent id) has a queued delete, or whose parent
///   has a queued tag replacement, are suppressed so they cannot resurrect;
/// - a read-only clock-skew check against the Turso server time.
class SyncEngine implements RemoteWriteSink {
  /// Creates an engine over [database] using [client] to reach Turso.
  ///
  /// [client] is a lazily-evaluated factory so configuration can change without
  /// rebuilding the engine; it throws [TursoNotConfiguredException] while sync
  /// is unconfigured.
  SyncEngine(this._database, this._client)
    : _pendingWrites = PendingWriteStore(_database);

  final AppDatabase _database;
  final TursoClient Function() _client;
  final PendingWriteStore _pendingWrites;

  /// Serializes every remote flush (mutation-time mirrors and the sync flush)
  /// so two flushes never interleave and clobber a newer write.
  Future<void> _writeChain = Future<void>.value();

  /// Applies the full remote schema, converging a fresh or existing database.
  ///
  /// Runs on cloud setup and before every [sync].
  Future<void> ensureRemoteSchema() async {
    final client = _client();
    await _applyRemoteSchema(client);
  }

  Future<void> _applyRemoteSchema(TursoClient client) =>
      applyRemoteSchema(client.execute);

  /// Runs one full sync and returns the per-run counts and skew warning.
  ///
  /// Ordering mirrors the reference: ensure schema, flush queued writes before
  /// pulling, then sync `app_settings`, `todos`, `notes`, `links`, `work_logs`,
  /// and `projects`.
  Future<SyncResult> sync() async {
    final client = _client();
    await _applyRemoteSchema(client);

    final skewWarning = await _checkClockSkew(client);
    final counts = _Counts();

    final flushed = await _flushPendingWrites(client);

    try {
      await _syncAppSettings(client, counts);
      await _syncTodos(client, counts);
      await _syncNotes(client, counts);
      await _syncLinks(client, counts);
      await _syncWorkLogs(client, counts);
      await _syncProjects(client, counts);
    } finally {
      // Local writes go through raw SQL, which drift cannot trace back to a
      // table, so refresh every watched stream once the run finishes.
      _database.markTablesUpdated(_database.allTables);
    }

    return SyncResult(
      pushed: counts.pushed,
      pulled: counts.pulled,
      flushedWrites: flushed,
      pendingWritesRemaining: (await _pendingWrites.keys()).total,
      skewWarning: skewWarning,
    );
  }

  // -- Change detection ------------------------------------------------------

  /// Entity tables carrying `updated_at`, compared by count and max timestamp.
  static const _stampedTables = [
    'app_settings',
    RemoteTables.todos,
    RemoteTables.notes,
    RemoteTables.links,
    RemoteTables.workLogs,
    RemoteTables.projects,
    RemoteTables.workItems,
  ];

  /// Insert-only child tables without `updated_at`, compared by count and
  /// checked by `created_at` for local newness.
  static const _childTables = [
    'note_tags',
    'link_tags',
    'work_log_tags',
    RemoteTables.projectPhases,
  ];

  /// Cheap check gating automatic syncs (timer, resume, background, detach).
  ///
  /// Returns true when a full [sync] could move data either way: never synced,
  /// queued outbound writes exist, any local row is newer than [lastSyncAt]
  /// (covers creates/updates, which are not queued), or any remote aggregate
  /// differs from local. A remote failure with a clean local state returns
  /// false, so an offline device with nothing to push stays quiet instead of
  /// failing every tick. Manual syncs and config changes bypass this and call
  /// [sync] unconditionally.
  Future<bool> hasChanges(String? lastSyncAt) async {
    if (lastSyncAt == null) return true;
    if ((await _pendingWrites.keys()).total > 0) return true;
    if (await _localNewerThan(lastSyncAt)) return true;
    final client = _tryClient();
    if (client == null) return false;
    try {
      return await _remoteDiffers(client);
    } catch (_) {
      return false;
    }
  }

  /// Whether any local row was created/updated after [lastSyncAt].
  ///
  /// Deletes leave no row behind, but deletes, tag replacements, and phase
  /// upserts are always queued, so the queue check above already covers them.
  Future<bool> _localNewerThan(String lastSyncAt) async {
    for (final table in _stampedTables) {
      final hit = await _database
          .customSelect(
            'SELECT 1 AS hit FROM $table WHERE updated_at > ? LIMIT 1',
            variables: [Variable.withString(lastSyncAt)],
          )
          .getSingleOrNull();
      if (hit != null) return true;
    }
    for (final table in _childTables) {
      final hit = await _database
          .customSelect(
            'SELECT 1 AS hit FROM $table WHERE created_at > ? LIMIT 1',
            variables: [Variable.withString(lastSyncAt)],
          )
          .getSingleOrNull();
      if (hit != null) return true;
    }
    return false;
  }

  /// Whether any remote aggregate differs from its local counterpart.
  ///
  /// Counts catch creates/deletes on either side; max timestamps catch newer
  /// edits. Two empty tables compare equal (null max on both sides).
  Future<bool> _remoteDiffers(TursoClient client) async {
    for (final table in _stampedTables) {
      final select = 'SELECT COUNT(*) AS c, MAX(updated_at) AS m FROM $table';
      final local = await _database.customSelect(select).getSingle();
      final remoteRows = await client.select(select);
      if (remoteRows.isEmpty) continue;
      final remote = remoteRows.first;
      if (remote['c'] != local.read<int>('c') ||
          remote['m'] != local.readNullable<String>('m')) {
        return true;
      }
    }
    for (final table in _childTables) {
      final select = 'SELECT COUNT(*) AS c FROM $table';
      final local = await _database.customSelect(select).getSingle();
      final remoteRows = await client.select(select);
      if (remoteRows.isEmpty) continue;
      if (remoteRows.first['c'] != local.read<int>('c')) return true;
    }
    return false;
  }

  // -- Outbound writes -------------------------------------------------------

  @override
  Future<void> recordDelete(String table, String id) => _record(
    PendingWrite.of(
      kind: PendingWriteKind.delete,
      table: table,
      rowId: id,
      statements: _remoteDeleteStatements(table, id),
    ),
  );

  @override
  Future<void> recordTags({
    required String parentTable,
    required String parentId,
    required String childTable,
    required String parentColumn,
    required List<RemoteTagRow> rows,
  }) => _record(
    PendingWrite.of(
      kind: PendingWriteKind.tags,
      table: parentTable,
      rowId: parentId,
      statements: _remoteTagStatements(
        childTable: childTable,
        parentColumn: parentColumn,
        parentId: parentId,
        rows: rows,
      ),
    ),
  );

  @override
  Future<void> recordUpsert(String table, Map<String, Object?> row) => _record(
    PendingWrite.of(
      kind: PendingWriteKind.upsert,
      table: table,
      rowId: row['id']! as String,
      statements: _remoteUpsertStatements(table, row),
    ),
  );

  /// Enqueues the mirror for [write] in the same local transaction as the
  /// mutation, then attempts an immediate remote flush.
  ///
  /// In local (unconfigured) mode this is a no-op so the queue never grows. The
  /// enqueue is best-effort: a rare local enqueue failure is logged and the
  /// mirror is skipped while the local mutation still succeeds, so the mirror
  /// is not guaranteed to be queued.
  Future<void> _record(PendingWrite write) async {
    final client = _tryClient();
    if (client == null) return;

    try {
      await _pendingWrites.enqueue(write);
    } catch (error) {
      // The mirror is best-effort: a rare local enqueue failure must not
      // surface as a mutation failure, so it is logged and skipped (the local
      // mutation still commits). Remote failures are handled the same way below.
      debugPrint(
        'Queueing remote write ${write.table}/${write.rowId} failed: $error',
      );
      return;
    }
    // Never block the caller on a flaky connection: the queue entry is removed
    // only on success, otherwise the next sync retries it.
    _scheduleFlush(client, write.table, write.rowId);
  }

  void _scheduleFlush(TursoClient client, String table, String rowId) {
    // `_record` runs inside the repository's drift transaction, whose
    // zone-scoped engine routes raw SQL to the still-open transaction.
    // `Future(...)` is `Timer.run`, and a timer binds its callback to
    // `Zone.current`, so creating it here would run the flush later in that same
    // (by then closed) transaction zone and throw `StateError: A transaction was
    // used after being closed`. Escape to the root zone first so the deferred
    // flush reads the queue through the `AppDatabase` and runs strictly after
    // the transaction commits.
    Zone.root.run(() {
      Future<void>(() {
        final run = _writeChain.then(
          (_) => _flushOneWrite(client, table, rowId),
        );
        _writeChain = run.then((_) {}, onError: (_) {});
      });
    });
  }

  // -- Pending writes --------------------------------------------------------

  Future<int> _flushPendingWrites(TursoClient client) {
    // Drain any in-flight mutation mirrors first, then flush everything that
    // remains, all through the same chain so nothing interleaves.
    final run = _writeChain.then((_) => _flushAllQueuedWrites(client));
    _writeChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<int> _flushAllQueuedWrites(TursoClient client) async {
    final entries = await _pendingWrites.allEntries();
    var flushed = 0;

    for (final entry in entries) {
      try {
        await _executeRemote(client, entry.statements);
        await _pendingWrites.removeIfUnchanged(
          entry.table,
          entry.rowId,
          entry.statementsJson,
        );
        flushed++;
      } catch (error) {
        debugPrint(
          'Flushing queued write ${entry.table}/${entry.rowId} failed: $error',
        );
      }
    }

    return flushed;
  }

  Future<void> _flushOneWrite(
    TursoClient client,
    String table,
    String rowId,
  ) async {
    try {
      final entry = await _pendingWrites.entry(table, rowId);
      if (entry == null) return;
      await _executeRemote(client, entry.statements);
      await _pendingWrites.removeIfUnchanged(
        table,
        rowId,
        entry.statementsJson,
      );
    } catch (error) {
      debugPrint(
        'Remote write of $table/$rowId failed; queued for next sync: $error',
      );
    }
  }

  Future<void> _executeRemote(
    TursoClient client,
    List<QueuedStatement> statements,
  ) async {
    for (final statement in statements) {
      await client.execute(statement.sql, statement.args);
    }
  }

  // -- Clock skew ------------------------------------------------------------

  Future<String?> _checkClockSkew(TursoClient client) async {
    try {
      final rows = await client.select(
        "SELECT strftime('%Y-%m-%dT%H:%M:%fZ','now') AS now",
      );
      final serverNow = rows.isEmpty ? null : rows.first['now'];
      if (serverNow is! String) return null;

      final serverTime = DateTime.tryParse(serverNow);
      if (serverTime == null) return null;

      final skewSeconds = DateTime.now()
          .toUtc()
          .difference(serverTime)
          .inSeconds;
      if (skewSeconds.abs() <= 60) return null;

      return 'Device clock differs from the sync server by about '
          '${skewSeconds.abs()}s. Edits may sync incorrectly until the clock '
          'is corrected.';
    } catch (_) {
      return null;
    }
  }

  // -- app_settings ----------------------------------------------------------

  Future<void> _syncAppSettings(TursoClient client, _Counts counts) async {
    final remoteRows = await client.select('SELECT * FROM app_settings');
    final localRows = await _selectLocal('app_settings');
    final remoteMap = {for (final row in remoteRows) row['key'] as String: row};
    final localMap = {for (final row in localRows) row['key'] as String: row};

    for (final remote in remoteRows) {
      final key = remote['key'];
      final local = localMap[key];
      if (local == null) {
        await _insertLocal('app_settings', _appSettingsInsert, remote);
        counts.pulled++;
      } else if (_isNewer(remote, local)) {
        await _database.customStatement(
          'UPDATE app_settings SET value = ?, updated_at = ? WHERE key = ?',
          [remote['value'], remote['updated_at'], key],
        );
        counts.pulled++;
      }
    }

    for (final local in localRows) {
      final key = local['key'];
      final remote = remoteMap[key];
      if (remote == null) {
        await client.execute(
          _insertSql('app_settings', _appSettingsInsert),
          _values(_appSettingsInsert, local),
        );
        counts.pushed++;
      } else if (_isNewer(local, remote)) {
        await client.execute(
          'UPDATE app_settings SET value = ?, updated_at = ? WHERE key = ?',
          [local['value'], local['updated_at'], key],
        );
        counts.pushed++;
      }
    }
  }

  // -- todos -----------------------------------------------------------------

  Future<void> _syncTodos(TursoClient client, _Counts counts) =>
      _syncEntityTable(
        client,
        table: RemoteTables.todos,
        insertColumns: _todosInsert,
        updateColumns: _todosUpdate,
        counts: counts,
        suppress: (pending, row) =>
            pending.suppressesEntity(RemoteTables.todos, row['id']),
      );

  // -- notes -----------------------------------------------------------------

  Future<void> _syncNotes(TursoClient client, _Counts counts) async {
    final maps = await _syncEntityTable(
      client,
      table: RemoteTables.notes,
      insertColumns: _notesInsert,
      updateColumns: _notesUpdate,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesEntity(RemoteTables.notes, row['id']),
    );

    await _syncInsertOnlyChildren(
      client,
      table: 'note_tags',
      parentColumn: 'note_id',
      columns: _noteTagsInsert,
      localParents: maps.local,
      remoteParents: maps.remote,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesChildren(RemoteTables.notes, row['note_id']),
    );
  }

  // -- links -----------------------------------------------------------------

  Future<void> _syncLinks(TursoClient client, _Counts counts) async {
    final maps = await _syncEntityTable(
      client,
      table: RemoteTables.links,
      insertColumns: _linksInsert,
      updateColumns: _linksUpdate,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesEntity(RemoteTables.links, row['id']),
    );

    await _syncInsertOnlyChildren(
      client,
      table: 'link_tags',
      parentColumn: 'link_id',
      columns: _linkTagsInsert,
      localParents: maps.local,
      remoteParents: maps.remote,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesChildren(RemoteTables.links, row['link_id']),
    );
  }

  // -- work logs -------------------------------------------------------------

  Future<void> _syncWorkLogs(TursoClient client, _Counts counts) async {
    final maps = await _syncEntityTable(
      client,
      table: RemoteTables.workLogs,
      insertColumns: _workLogsInsert,
      updateColumns: _workLogsUpdate,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesEntity(RemoteTables.workLogs, row['id']),
    );

    await _syncInsertOnlyChildren(
      client,
      table: 'work_log_tags',
      parentColumn: 'work_log_id',
      columns: _workLogTagsInsert,
      localParents: maps.local,
      remoteParents: maps.remote,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesChildren(RemoteTables.workLogs, row['work_log_id']),
    );
  }

  // -- projects --------------------------------------------------------------

  Future<void> _syncProjects(TursoClient client, _Counts counts) async {
    final maps = await _syncEntityTable(
      client,
      table: RemoteTables.projects,
      insertColumns: _projectsInsert,
      updateColumns: _projectsUpdate,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesEntity(RemoteTables.projects, row['id']),
    );

    await _syncInsertOnlyChildren(
      client,
      table: 'project_phases',
      parentColumn: 'project_id',
      columns: _projectPhasesInsert,
      localParents: maps.local,
      remoteParents: maps.remote,
      counts: counts,
      suppress: (pending, row) =>
          pending.suppressesEntity(RemoteTables.projects, row['project_id']) ||
          pending.suppressesEntity(RemoteTables.projectPhases, row['id']),
    );

    await _syncWorkItems(
      client,
      localProjects: maps.local,
      remoteProjects: maps.remote,
      counts: counts,
    );
  }

  Future<void> _syncWorkItems(
    TursoClient client, {
    required Map<String, Map<String, Object?>> localProjects,
    required Map<String, Map<String, Object?>> remoteProjects,
    required _Counts counts,
  }) async {
    final remoteRows = await client.select('SELECT * FROM work_items');
    final localRows = await _selectLocal('work_items');
    final remoteMap = {for (final row in remoteRows) row['id'] as String: row};
    final localMap = {for (final row in localRows) row['id'] as String: row};

    // Fresh keys for this step, for the same reason as [_syncEntityTable].
    final pending = await _pendingWrites.keys();

    // A work item may reference a phase the desktop deleted without clearing
    // the reference (the frozen schema has no cascade on that FK). Local
    // SQLite enforces foreign keys, so a dangling reference is coalesced to
    // `null` at pull time, which is exactly how the desktop UI resolves it.
    final localPhaseIds = {
      for (final row in await _selectLocal('project_phases')) row['id'],
    };

    for (final remote in remoteRows) {
      final id = remote['id'];
      if (pending.suppressesEntity(
            RemoteTables.projects,
            remote['project_id'],
          ) ||
          pending.suppressesEntity(RemoteTables.workItems, id)) {
        continue;
      }
      final local = localMap[id];
      if (local == null) {
        if (!localProjects.containsKey(remote['project_id'])) continue;
        await _insertLocal(
          'work_items',
          _workItemsInsert,
          _dropDanglingPhase(remote, localPhaseIds),
        );
        counts.pulled++;
      } else if (_isNewer(remote, local)) {
        await _updateLocal(
          'work_items',
          _workItemsUpdate,
          _dropDanglingPhase(remote, localPhaseIds),
          id,
        );
        counts.pulled++;
      }
    }

    for (final local in localRows) {
      final id = local['id'];
      // Push-side guard: skip a work item whose project or the item itself has
      // a queued delete, matching the pull-side suppression above so a
      // mutation-time delete cannot be undone by a stale local push.
      if (pending.suppressesEntity(
            RemoteTables.projects,
            local['project_id'],
          ) ||
          pending.suppressesEntity(RemoteTables.workItems, id)) {
        continue;
      }
      final remote = remoteMap[id];
      if (remote == null) {
        if (!remoteProjects.containsKey(local['project_id'])) continue;
        await client.execute(
          _insertSql('work_items', _workItemsInsert),
          _values(_workItemsInsert, local),
        );
        counts.pushed++;
      } else if (_isNewer(local, remote)) {
        await client.execute(_updateSql('work_items', _workItemsUpdate), [
          ..._values(_workItemsUpdate, local),
          id,
        ]);
        counts.pushed++;
      }
    }
  }

  Map<String, Object?> _dropDanglingPhase(
    Map<String, Object?> row,
    Set<Object?> localPhaseIds,
  ) {
    final phaseId = row['phase_id'];
    if (phaseId is String && !localPhaseIds.contains(phaseId)) {
      return {...row, 'phase_id': null};
    }
    return row;
  }

  // -- Generic table sync ----------------------------------------------------

  Future<_EntityMaps> _syncEntityTable(
    TursoClient client, {
    required String table,
    required List<String> insertColumns,
    required List<String> updateColumns,
    required _Counts counts,
    bool Function(PendingWriteKeys pending, Map<String, Object?> row)? suppress,
  }) async {
    final remoteRows = await client.select('SELECT * FROM $table');
    final localRows = await _selectLocal(table);
    final remoteMap = {for (final row in remoteRows) row['id'] as String: row};
    final localMap = {for (final row in localRows) row['id'] as String: row};

    // Read the queued keys fresh for this step rather than once per sync
    // run: a mutation queued while an earlier step was in flight must still
    // suppress its row, otherwise the pull can resurrect it. The mirror enqueue
    // commits in the same transaction as the local mutation, so if the local
    // change is visible here its queued intent is too; if it is not yet visible
    // the row still looks locally present and the pull skips it.
    final pending = await _pendingWrites.keys();

    // Pull: remote -> local.
    for (final remote in remoteRows) {
      if (suppress?.call(pending, remote) ?? false) continue;
      final id = remote['id'];
      final local = localMap[id];
      if (local == null) {
        await _insertLocal(table, insertColumns, remote);
        counts.pulled++;
      } else if (_isNewer(remote, local)) {
        await _updateLocal(table, updateColumns, remote, id);
        counts.pulled++;
      }
    }

    // Push: local -> remote.
    for (final local in localRows) {
      // Push-side guard: a row whose entity has a queued delete must not be
      // pushed. Otherwise a mutation-time flush that already removed it remotely
      // could let this stale local row (captured at step start) resurrect it.
      if (suppress?.call(pending, local) ?? false) continue;
      final id = local['id'];
      final remote = remoteMap[id];
      if (remote == null) {
        await client.execute(
          _insertSql(table, insertColumns),
          _values(insertColumns, local),
        );
        counts.pushed++;
      } else if (_isNewer(local, remote)) {
        await client.execute(_updateSql(table, updateColumns), [
          ..._values(updateColumns, local),
          id,
        ]);
        counts.pushed++;
      }
    }

    return _EntityMaps(remote: remoteMap, local: localMap);
  }

  Future<void> _syncInsertOnlyChildren(
    TursoClient client, {
    required String table,
    required String parentColumn,
    required List<String> columns,
    required Map<String, Map<String, Object?>> localParents,
    required Map<String, Map<String, Object?>> remoteParents,
    required _Counts counts,
    bool Function(PendingWriteKeys pending, Map<String, Object?> row)? suppress,
  }) async {
    final remoteRows = await client.select('SELECT * FROM $table');
    final localRows = await _selectLocal(table);
    final remoteIds = {for (final row in remoteRows) row['id']};
    final localIds = {for (final row in localRows) row['id']};

    // Fresh keys for this step, for the same reason as [_syncEntityTable].
    final pending = await _pendingWrites.keys();

    for (final row in remoteRows) {
      final id = row['id'];
      final parent = row[parentColumn];
      if (localIds.contains(id)) continue;
      if (parent is! String || !localParents.containsKey(parent)) continue;
      if (suppress?.call(pending, row) ?? false) continue;

      await _insertLocal(table, columns, row);
      counts.pulled++;
    }

    for (final row in localRows) {
      final id = row['id'];
      final parent = row[parentColumn];
      if (remoteIds.contains(id)) continue;
      if (parent is! String || !remoteParents.containsKey(parent)) continue;
      // Push-side guard: a child whose parent has a queued delete (or tag
      // replacement) must not be pushed, mirroring the pull-side suppression.
      if (suppress?.call(pending, row) ?? false) continue;

      await client.execute(_insertSql(table, columns), _values(columns, row));
      counts.pushed++;
    }
  }

  // -- Local SQL helpers -----------------------------------------------------

  Future<List<Map<String, Object?>>> _selectLocal(String table) async {
    final rows = await _database.customSelect('SELECT * FROM $table').get();
    return [for (final row in rows) Map<String, Object?>.from(row.data)];
  }

  Future<void> _insertLocal(
    String table,
    List<String> columns,
    Map<String, Object?> row,
  ) => _database.customStatement(
    _insertSql(table, columns),
    _values(columns, row),
  );

  Future<void> _updateLocal(
    String table,
    List<String> updateColumns,
    Map<String, Object?> row,
    Object? id,
  ) => _database.customStatement(_updateSql(table, updateColumns), [
    ..._values(updateColumns, row),
    id,
  ]);

  static String _insertSql(String table, List<String> columns) =>
      'INSERT OR IGNORE INTO $table (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})';

  static String _updateSql(String table, List<String> updateColumns) =>
      'UPDATE $table SET ${[for (final column in updateColumns) '$column = ?'].join(', ')} '
      'WHERE id = ?';

  static List<Object?> _values(
    List<String> columns,
    Map<String, Object?> row,
  ) => [for (final column in columns) row[column]];

  /// Whether [a]'s `updated_at` is strictly newer than [b]'s (string compare).
  static bool _isNewer(Map<String, Object?> a, Map<String, Object?> b) =>
      _updatedAt(a).compareTo(_updatedAt(b)) > 0;

  static String _updatedAt(Map<String, Object?> row) =>
      (row['updated_at'] as String?) ?? '';

  TursoClient? _tryClient() {
    try {
      return _client();
    } on TursoNotConfiguredException {
      return null;
    }
  }
}

/// Mutable per-run counters shared by the table sync helpers.
class _Counts {
  int pushed = 0;
  int pulled = 0;
}

/// The remote and pre-sync local rows of one table, keyed by id.
class _EntityMaps {
  const _EntityMaps({required this.remote, required this.local});

  final Map<String, Map<String, Object?>> remote;
  final Map<String, Map<String, Object?>> local;
}

/// The delete statements the desktop runs at mutation time (and on flush).
List<QueuedStatement> _remoteDeleteStatements(String table, String id) {
  switch (table) {
    case RemoteTables.todos:
      return [
        QueuedStatement('DELETE FROM todos WHERE id = ?', [id]),
      ];
    case RemoteTables.notes:
      return [
        QueuedStatement('DELETE FROM notes WHERE id = ?', [id]),
        QueuedStatement('DELETE FROM note_tags WHERE note_id = ?', [id]),
      ];
    case RemoteTables.links:
      return [
        QueuedStatement('DELETE FROM links WHERE id = ?', [id]),
        QueuedStatement('DELETE FROM link_tags WHERE link_id = ?', [id]),
      ];
    case RemoteTables.workLogs:
      return [
        QueuedStatement('DELETE FROM work_logs WHERE id = ?', [id]),
        QueuedStatement('DELETE FROM work_log_tags WHERE work_log_id = ?', [
          id,
        ]),
      ];
    case RemoteTables.projects:
      // The remote `ON DELETE CASCADE` clears project_phases and work_items.
      return [
        QueuedStatement('DELETE FROM projects WHERE id = ?', [id]),
      ];
    case RemoteTables.projectPhases:
      return [
        QueuedStatement('DELETE FROM project_phases WHERE id = ?', [id]),
      ];
    case RemoteTables.workItems:
      return [
        QueuedStatement('DELETE FROM work_items WHERE id = ?', [id]),
      ];
    default:
      throw ArgumentError.value(table, 'table', 'Unknown sync table');
  }
}

/// The tag replacement the desktop runs at mutation time: delete the parent's
/// tag rows, then insert the replacement rows with the same local ids.
List<QueuedStatement> _remoteTagStatements({
  required String childTable,
  required String parentColumn,
  required String parentId,
  required List<RemoteTagRow> rows,
}) => [
  QueuedStatement('DELETE FROM $childTable WHERE $parentColumn = ?', [
    parentId,
  ]),
  for (final row in rows)
    QueuedStatement(
      'INSERT OR IGNORE INTO $childTable (id, $parentColumn, name, created_at) '
      'VALUES (?, ?, ?, ?)',
      [row.id, parentId, row.name, row.createdAt],
    ),
];

/// The upsert the remote runs at mutation time.
///
/// For `project_phases` (no `updated_at`, insert-only in sync) this inserts
/// the row if missing, then updates its mutable columns. For every other
/// entity table this replays the sync's own insert/update column lists, so a
/// mutation-time mirror converges to exactly what the next sync would write.
List<QueuedStatement> _remoteUpsertStatements(
  String table,
  Map<String, Object?> row,
) {
  switch (table) {
    case RemoteTables.projectPhases:
      return [
        QueuedStatement(
          'INSERT OR IGNORE INTO project_phases '
          '(id, project_id, name, color, position, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            row['id'],
            row['project_id'],
            row['name'],
            row['color'],
            row['position'],
            row['created_at'],
          ],
        ),
        QueuedStatement(
          'UPDATE project_phases SET name = ?, color = ?, position = ? '
          'WHERE id = ?',
          [row['name'], row['color'], row['position'], row['id']],
        ),
      ];
    case RemoteTables.todos:
      return _entityUpsert(table, _todosInsert, _todosUpdate, row);
    case RemoteTables.notes:
      return _entityUpsert(table, _notesInsert, _notesUpdate, row);
    case RemoteTables.links:
      return _entityUpsert(table, _linksInsert, _linksUpdate, row);
    case RemoteTables.workLogs:
      return _entityUpsert(table, _workLogsInsert, _workLogsUpdate, row);
    case RemoteTables.projects:
      return _entityUpsert(table, _projectsInsert, _projectsUpdate, row);
    case RemoteTables.workItems:
      return _entityUpsert(table, _workItemsInsert, _workItemsUpdate, row);
    default:
      throw ArgumentError.value(table, 'table', 'Unknown upsert table');
  }
}

/// Builds the insert-if-missing plus update-columns statements for one entity
/// row, reusing the sync merge's own column lists (same library, so the
/// engine's private builders are visible here).
List<QueuedStatement> _entityUpsert(
  String table,
  List<String> insertColumns,
  List<String> updateColumns,
  Map<String, Object?> row,
) => [
  QueuedStatement(
    SyncEngine._insertSql(table, insertColumns),
    SyncEngine._values(insertColumns, row),
  ),
  QueuedStatement(
    SyncEngine._updateSql(table, updateColumns),
    [...SyncEngine._values(updateColumns, row), row['id']],
  ),
];

// Column lists, in the reference schema's order. `*Insert` covers every column
// for an INSERT; `*Update` is the subset the desktop updates on a newer write
// (always ending in `updated_at`).

const List<String> _appSettingsInsert = ['key', 'value', 'updated_at'];

const List<String> _todosInsert = [
  'id',
  'title',
  'description',
  'status',
  'priority',
  'due_date',
  'position',
  'archived',
  'created_at',
  'updated_at',
];
const List<String> _todosUpdate = [
  'title',
  'description',
  'status',
  'priority',
  'due_date',
  'position',
  'archived',
  'updated_at',
];

const List<String> _notesInsert = [
  'id',
  'title',
  'content',
  'pinned',
  'created_at',
  'updated_at',
];
const List<String> _notesUpdate = ['title', 'content', 'pinned', 'updated_at'];

const List<String> _noteTagsInsert = ['id', 'note_id', 'name', 'created_at'];

const List<String> _linksInsert = [
  'id',
  'url',
  'title',
  'favicon_url',
  'created_at',
  'updated_at',
];
const List<String> _linksUpdate = ['title', 'favicon_url', 'updated_at'];

const List<String> _linkTagsInsert = ['id', 'link_id', 'name', 'created_at'];

const List<String> _workLogsInsert = [
  'id',
  'title',
  'description',
  'start_date',
  'end_date',
  'created_at',
  'updated_at',
];
const List<String> _workLogsUpdate = [
  'title',
  'description',
  'start_date',
  'end_date',
  'updated_at',
];

const List<String> _workLogTagsInsert = [
  'id',
  'work_log_id',
  'name',
  'created_at',
];

const List<String> _projectsInsert = [
  'id',
  'name',
  'start_date',
  'week_count',
  'position',
  'created_at',
  'updated_at',
];
const List<String> _projectsUpdate = [
  'name',
  'start_date',
  'week_count',
  'position',
  'updated_at',
];

const List<String> _projectPhasesInsert = [
  'id',
  'project_id',
  'name',
  'color',
  'position',
  'created_at',
];

const List<String> _workItemsInsert = [
  'id',
  'project_id',
  'phase_id',
  'title',
  'person',
  'comment',
  'jira_ticket',
  'status',
  'start_week',
  'end_week',
  'position',
  'is_separator',
  'created_at',
  'updated_at',
];
const List<String> _workItemsUpdate = [
  'phase_id',
  'title',
  'person',
  'comment',
  'jira_ticket',
  'status',
  'start_week',
  'end_week',
  'position',
  'updated_at',
];
