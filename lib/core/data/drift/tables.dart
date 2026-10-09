import 'package:drift/drift.dart';

/// Drift table definitions mirroring `../personal-os/src/lib/schema.ts`
/// (the frozen remote Turso schema) column-for-column.
///
/// Every table, column, SQLite type, nullability, default, CHECK/UNIQUE
/// constraint, foreign key (including `ON DELETE CASCADE`), and index here must
/// match `REMOTE_SCHEMAS`. `tool/schema_conformance.js` diffs this file against
/// the reference and fails on any drift, so treat the reference as the source
/// of truth and never change a definition to suit local code.
///
/// Notes:
/// - Value semantics match the reference clients exactly: 0/1 integers for
///   boolean-ish flags (`archived`, `pinned`, `is_separator`), `''` rather than
///   `NULL` where the reference uses an empty-string default, and a nullable
///   `notes.title` (`NULL` means "display the formatted `created_at`").
/// - The `ALTER TABLE ... ADD COLUMN` statements in `REMOTE_SCHEMAS` are
///   additive migrations for pre-existing remote databases. A fresh local drift
///   database already contains those columns in the `CREATE TABLE` body below,
///   so no migration runs here.
/// - Drift's `@TableIndex` emits ascending index columns. The reference
///   declares some indexes `DESC`; SQLite can reverse-scan an ascending index,
///   so the two are semantically equivalent. The conformance script normalizes
///   the sort direction away and documents this equivalence.

/// `todos` table. `archived` is stored as 0/1.
@DataClassName('TodoRow')
@TableIndex(name: 'idx_todos_status', columns: {#status})
@TableIndex(name: 'idx_todos_due_date', columns: {#dueDate})
class Todos extends Table {
  @override
  String get tableName => 'todos';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('todo'))();
  TextColumn get priority => text().nullable()();
  TextColumn get dueDate => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  IntColumn get archived => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (status IN ('todo','in_progress','completed'))",
    "CHECK (priority IN ('low','medium','high'))",
  ];
}

/// `app_settings` table. Shared state across the desktop, TUI, and mobile
/// clients; namespace mobile-only keys with `mobile.`.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  @override
  String get tableName => 'app_settings';

  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get updatedAt =>
      text().withDefault(CustomExpression("(datetime('now'))"))();

  @override
  Set<Column> get primaryKey => {key};
}

/// `notes` table. `title` is nullable on purpose.
@DataClassName('NoteRow')
@TableIndex(name: 'idx_notes_updated_at', columns: {#updatedAt})
class Notes extends Table {
  @override
  String get tableName => 'notes';

  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get content => text().withDefault(const Constant(''))();
  IntColumn get pinned => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `note_tags` table. Insert-only; on edit the rows are deleted and re-inserted.
@DataClassName('NoteTagRow')
@TableIndex(name: 'idx_note_tags_note_id', columns: {#noteId})
@TableIndex(name: 'idx_note_tags_name', columns: {#name})
class NoteTags extends Table {
  @override
  String get tableName => 'note_tags';

  TextColumn get id => text()();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `links` table. `url` is UNIQUE (`uq_links_url`).
@DataClassName('LinkRow')
@TableIndex(name: 'idx_links_created_at', columns: {#createdAt})
class Links extends Table {
  @override
  String get tableName => 'links';

  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get faviconUrl => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {url},
  ];
}

/// `link_tags` table. Insert-only; cascade-deleted with the link.
@DataClassName('LinkTagRow')
@TableIndex(name: 'idx_link_tags_link_id', columns: {#linkId})
@TableIndex(name: 'idx_link_tags_name', columns: {#name})
class LinkTags extends Table {
  @override
  String get tableName => 'link_tags';

  TextColumn get id => text()();
  TextColumn get linkId =>
      text().references(Links, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `work_logs` table.
@DataClassName('WorkLogRow')
@TableIndex(name: 'idx_work_logs_start_date', columns: {#startDate})
class WorkLogs extends Table {
  @override
  String get tableName => 'work_logs';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `work_log_tags` table. Insert-only; cascade-deleted with the work log.
@DataClassName('WorkLogTagRow')
@TableIndex(name: 'idx_work_log_tags_work_log_id', columns: {#workLogId})
@TableIndex(name: 'idx_work_log_tags_name', columns: {#name})
class WorkLogTags extends Table {
  @override
  String get tableName => 'work_log_tags';

  TextColumn get id => text()();
  TextColumn get workLogId =>
      text().references(WorkLogs, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `projects` table.
@DataClassName('ProjectRow')
class Projects extends Table {
  @override
  String get tableName => 'projects';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get startDate => text()();
  IntColumn get weekCount => integer().withDefault(const Constant(12))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `project_phases` table. No `updated_at` column in the frozen schema.
@DataClassName('ProjectPhaseRow')
@TableIndex(
  name: 'idx_project_phases_project',
  columns: {#projectId, #position},
)
class ProjectPhases extends Table {
  @override
  String get tableName => 'project_phases';

  TextColumn get id => text()();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get color => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `work_items` table.
///
/// `phase_id` references `project_phases(id)` with NO cascade (nullable). The
/// repository clears referencing rows before deleting a phase so items survive
/// unphased; see `DriftProjectRepository.deletePhase`.
@DataClassName('WorkItemRow')
@TableIndex(name: 'idx_work_items_project', columns: {#projectId, #position})
class WorkItems extends Table {
  @override
  String get tableName => 'work_items';

  TextColumn get id => text()();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get phaseId => text().nullable().references(ProjectPhases, #id)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get person => text().nullable()();
  TextColumn get comment => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get startWeek => integer().withDefault(const Constant(1))();
  IntColumn get endWeek => integer().withDefault(const Constant(1))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  IntColumn get isSeparator => integer().withDefault(const Constant(0))();
  TextColumn get jiraTicket => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (status IN ('pending','in_progress','done'))",
  ];
}
