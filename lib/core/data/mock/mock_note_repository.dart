import '../../models/note.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../in_memory_store.dart';
import '../repositories.dart';

/// In-memory [NoteRepository] seeded with pinned, tagged, and untitled notes.
class MockNoteRepository implements NoteRepository {
  MockNoteRepository._(this._store);

  /// Creates a repository seeded relative to today.
  factory MockNoteRepository.seeded() =>
      MockNoteRepository._(InMemoryStore<NoteWithTags>(_seedNotes()));

  final InMemoryStore<NoteWithTags> _store;

  @override
  Stream<List<NoteWithTags>> watchAll() =>
      _store.watch().map(_sorted);

  @override
  Future<NoteWithTags?> getById(String id) async {
    for (final note in _store.snapshot) {
      if (note.id == id) return note;
    }
    return null;
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
    _store.mutate((items) => items.add(NoteWithTags(note: note)));
    return note;
  }

  @override
  Future<void> update(Note note) async {
    _store.mutate((items) {
      final index = items.indexWhere((n) => n.id == note.id);
      if (index == -1) return;
      final next = note.copyWith(
        createdAt: items[index].createdAt,
        updatedAt: nowIso(),
      );
      items[index] = items[index].copyWith(note: next);
    });
  }

  @override
  Future<void> setPinned(String id, bool pinned) async {
    _mutate(id, (note) => note.copyWith(note: note.note.copyWith(pinned: pinned)));
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Tag replacement touches only note_tags; it must NOT advance the note's
    // updated_at, matching the reference setTagsForNote (LWW safety).
    _store.mutate((items) {
      final index = items.indexWhere((n) => n.id == id);
      if (index == -1) return;
      items[index] = items[index].copyWith(
        tags: List<String>.unmodifiable(tags),
      );
    });
  }

  @override
  Future<void> delete(String id) async {
    _store.mutate((items) => items.removeWhere((n) => n.id == id));
  }

  void _mutate(String id, NoteWithTags Function(NoteWithTags note) change) {
    _store.mutate((items) {
      final index = items.indexWhere((n) => n.id == id);
      if (index == -1) return;
      final next = change(items[index]);
      items[index] = next.copyWith(
        note: next.note.copyWith(updatedAt: nowIso()),
      );
    });
  }

  static List<NoteWithTags> _sorted(Iterable<NoteWithTags> items) {
    final sorted = List<NoteWithTags>.of(items)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return sorted;
  }
}

/// Three notes: one pinned with tags, one untitled (title null), one plain.
List<NoteWithTags> _seedNotes() {
  final now = DateTime.now();
  String ts(int hoursAgo) =>
      isoFromDateTime(now.subtract(Duration(hours: hoursAgo)));

  return [
    NoteWithTags(
      note: Note(
        id: 'b0000000-0000-4000-8000-000000000001',
        title: 'Sprint planning',
        content: '# Sprint planning\n\n- [ ] Scope the sync engine\n- [ ] Mock repositories\n- [ ] Home dashboard',
        pinned: true,
        createdAt: ts(72),
        updatedAt: ts(1),
      ),
      tags: const ['work', 'planning'],
    ),
    NoteWithTags(
      note: Note(
        id: 'b0000000-0000-4000-8000-000000000002',
        title: null,
        content: 'Journal entry: shipped the mock layer today and the dashboard wiring finally clicks.',
        createdAt: ts(120),
        updatedAt: ts(48),
      ),
      tags: const ['journal'],
    ),
    NoteWithTags(
      note: Note(
        id: 'b0000000-0000-4000-8000-000000000003',
        title: 'Reading list',
        content: '1. Designing Data-Intensive Applications\n2. Refactoring UI\n3. The Pragmatic Programmer',
        createdAt: ts(168),
        updatedAt: ts(96),
      ),
    ),
  ];
}
