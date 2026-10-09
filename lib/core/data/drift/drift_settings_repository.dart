import 'package:drift/drift.dart';

import '../../models/app_setting.dart';
import '../../utils/clock.dart';
import '../repositories.dart';
import 'database.dart';

/// Drift-backed [SettingsRepository] over the shared `app_settings` table.
///
/// Mirrors `MockSettingsRepository`: `set` upserts and stamps `updated_at` from
/// [nowIso] (never the column's `datetime('now')` default, whose format differs
/// and would corrupt the shared last-write-wins comparison).
class DriftSettingsRepository implements SettingsRepository {
  /// Creates a repository over [database].
  DriftSettingsRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<AppSetting>> watchAll() {
    final query = _database.select(_database.appSettings)
      ..orderBy([(s) => OrderingTerm.asc(CustomExpression<int>('rowid'))]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          AppSetting(key: row.key, value: row.value, updatedAt: row.updatedAt),
      ],
    );
  }

  @override
  Future<String?> get(String key) async {
    final row = await (_database.select(
      _database.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> set(String key, String value) async {
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            key: Value(key),
            value: Value(value),
            updatedAt: Value(nowIso()),
          ),
        );
  }

  @override
  Future<void> delete(String key) async {
    await (_database.delete(
      _database.appSettings,
    )..where((s) => s.key.equals(key))).go();
  }
}
