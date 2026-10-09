import 'package:drift/drift.dart';

import '../../models/note.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';

/// Drift-backed [NoteRepository].
///
/// Mirrors `MockNoteRepository`: pinned first then most recently updated, tag
/// replacement is delete-all plus re-insert, and tag-only edits never advance
/// the note's `updated_at` (LWW safety). Watches join `notes` with `note_tags`
/// so either table changing re-emits.
class DriftNoteRepository implements NoteRepository {
  /// Creates a repository over [database].
  DriftNoteRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<NoteWithTags>> watchAll() {
    final query =
        _database.select(_database.notes).join([
          leftOuterJoin(
            _database.noteTags,
            _database.noteTags.noteId.equalsExp(_database.notes.id),
          ),
        ])..orderBy([
          OrderingTerm.desc(_database.notes.pinned),
          OrderingTerm.desc(_database.notes.updatedAt),
          OrderingTerm.asc(_database.noteTags.createdAt),
          OrderingTerm.asc(_noteTagsRowId),
        ]);
    return query.watch().map(_group);
  }

  @override
  Future<NoteWithTags?> getById(String id) async {
    final row = await (_database.select(
      _database.notes,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return NoteWithTags(note: noteFromRow(row), tags: await _tagsFor(id));
  }

  @override
  Future<Note> create({String? title, String content = ''}) async {
    final now = nowIso();
    final note = Note(
      id: newId(),
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
    await _database
        .into(_database.notes)
        .insert(
          NotesCompanion(
            id: Value(note.id),
            title: Value(note.title),
            content: Value(note.content),
            pinned: const Value(0),
            createdAt: Value(note.createdAt),
            updatedAt: Value(note.updatedAt),
          ),
        );
    return note;
  }

  @override
  Future<void> update(Note note) async {
    // `created_at` is intentionally absent so the stored value is preserved.
    await (_database.update(
      _database.notes,
    )..where((n) => n.id.equals(note.id))).write(
      NotesCompanion(
        title: Value(note.title),
        content: Value(note.content),
        pinned: Value(flagToInt(note.pinned)),
        updatedAt: Value(nowIso()),
      ),
    );
  }

  @override
  Future<void> updateContent(
    String id, {
    String? title,
    required String content,
  }) async {
    // Writes only title/content: `pinned` and tags are owned elsewhere, so a
    // queued autosave can never re-assert a pin that setPinned failed to
    // persist. `created_at` is likewise preserved.
    await (_database.update(
      _database.notes,
    )..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: Value(title),
        content: Value(content),
        updatedAt: Value(nowIso()),
      ),
    );
  }

  @override
  Future<void> setPinned(String id, bool pinned) async {
    await (_database.update(
      _database.notes,
    )..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        pinned: Value(flagToInt(pinned)),
        updatedAt: Value(nowIso()),
      ),
    );
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Touches only note_tags; the note's updated_at is deliberately untouched,
    // matching the reference setTagsForNote (LWW safety).
    await _database.transaction(() async {
      await (_database.delete(
        _database.noteTags,
      )..where((t) => t.noteId.equals(id))).go();
      final now = nowIso();
      for (final name in tags) {
        await _database
            .into(_database.noteTags)
            .insert(
              NoteTagsCompanion(
                id: Value(newId()),
                noteId: Value(id),
                name: Value(name),
                createdAt: Value(now),
              ),
            );
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.noteTags,
      )..where((t) => t.noteId.equals(id))).go();
      await (_database.delete(
        _database.notes,
      )..where((n) => n.id.equals(id))).go();
    });
  }

  Future<List<String>> _tagsFor(String noteId) async {
    final rows =
        await (_database.select(_database.noteTags)
              ..where((t) => t.noteId.equals(noteId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(_noteTagsRowId),
              ]))
            .get();
    return List.unmodifiable([for (final row in rows) row.name]);
  }

  List<NoteWithTags> _group(List<TypedResult> rows) {
    final order = <String>[];
    final notes = <String, Note>{};
    final tags = <String, List<String>>{};
    for (final row in rows) {
      final noteRow = row.readTable(_database.notes);
      final tagRow = row.readTableOrNull(_database.noteTags);
      if (!notes.containsKey(noteRow.id)) {
        notes[noteRow.id] = noteFromRow(noteRow);
        tags[noteRow.id] = <String>[];
        order.add(noteRow.id);
      }
      if (tagRow != null) tags[noteRow.id]!.add(tagRow.name);
    }
    return [
      for (final id in order)
        NoteWithTags(note: notes[id]!, tags: List.unmodifiable(tags[id]!)),
    ];
  }
}

/// Ordering tiebreaker for `note_tags` rows inserted together.
///
/// Tag replacement stamps every row with the same `created_at`, so insertion
/// order is recovered from SQLite's implicit `rowid`. Drift does not expose a
/// typed getter for it, hence the raw expression.
///
/// This is an implicit dependency on `note_tags` being a rowid table: the
/// frozen remote schema declares no `WITHOUT ROWID`, so `rowid` is always
/// present here. If the schema ever moved to `WITHOUT ROWID`, this tiebreaker
/// would fail.
final Expression<int> _noteTagsRowId = CustomExpression<int>('note_tags.rowid');
