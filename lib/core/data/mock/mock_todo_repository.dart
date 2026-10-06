import '../../models/todo.dart';
import '../../utils/clock.dart';
import '../../utils/dates.dart';
import '../../utils/id.dart';
import '../in_memory_store.dart';
import '../repositories.dart';

/// In-memory [TodoRepository] seeded with a week of realistic todos.
class MockTodoRepository implements TodoRepository {
  MockTodoRepository._(this._store);

  /// Creates a repository seeded relative to today.
  factory MockTodoRepository.seeded() =>
      MockTodoRepository._(InMemoryStore<Todo>(_seedTodos()));

  final InMemoryStore<Todo> _store;

  @override
  Stream<List<Todo>> watchAll() =>
      _store.watch().map((items) => _sorted(items.where((t) => !t.archived)));

  @override
  Stream<List<Todo>> watchByStatus(TodoStatus status) => _store.watch().map(
    (items) => _sorted(items.where((t) => !t.archived && t.status == status)),
  );

  @override
  Stream<List<Todo>> watchArchived() => _store.watch().map(
    (items) => _sorted(items.where((t) => t.archived)),
  );

  @override
  Future<Todo?> getById(String id) async {
    for (final todo in _store.snapshot) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  @override
  Future<Todo> create({
    required String title,
    String? description,
    TodoStatus status = TodoStatus.todo,
    TodoPriority? priority,
    String? dueDate,
    int position = 0,
  }) async {
    final now = nowIso();
    final todo = Todo(
      id: newId(),
      title: title,
      description: description,
      status: status,
      priority: priority,
      dueDate: dueDate,
      position: position,
      createdAt: now,
      updatedAt: now,
    );
    _store.mutate((items) => items.add(todo));
    return todo;
  }

  @override
  Future<void> update(Todo todo) async {
    _store.mutate((items) {
      final index = items.indexWhere((t) => t.id == todo.id);
      if (index == -1) return;
      items[index] = todo.copyWith(
        createdAt: items[index].createdAt,
        updatedAt: nowIso(),
      );
    });
  }

  @override
  Future<void> setStatus(String id, TodoStatus status) async {
    _mutate(id, (todo) => todo.copyWith(status: status));
  }

  @override
  Future<void> archive(String id) async {
    _mutate(id, (todo) => todo.copyWith(archived: true));
  }

  @override
  Future<void> restore(String id) async {
    _mutate(id, (todo) => todo.copyWith(archived: false));
  }

  @override
  Future<void> delete(String id) async {
    _store.mutate((items) => items.removeWhere((t) => t.id == id));
  }

  @override
  Future<void> updatePositions(
    List<({String id, int position})> updates,
  ) async {
    _store.mutate((items) {
      final byId = {for (final update in updates) update.id: update.position};
      final now = nowIso();
      for (var i = 0; i < items.length; i++) {
        final position = byId[items[i].id];
        if (position != null) {
          items[i] = items[i].copyWith(position: position, updatedAt: now);
        }
      }
    });
  }

  void _mutate(String id, Todo Function(Todo todo) change) {
    _store.mutate((items) {
      final index = items.indexWhere((t) => t.id == id);
      if (index == -1) return;
      items[index] = change(items[index]).copyWith(updatedAt: nowIso());
    });
  }

  static List<Todo> _sorted(Iterable<Todo> items) {
    final sorted = List<Todo>.of(items)
      ..sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.createdAt.compareTo(b.createdAt);
      });
    return sorted;
  }
}

/// A week of todos across all three statuses, plus due-today, overdue, and
/// archived examples. Dates are relative to today so Home sections always
/// render.
List<Todo> _seedTodos() {
  final now = DateTime.now();
  final today = dateOnly(now);
  String due(int days) =>
      formatDate(DateTime(today.year, today.month, today.day + days));
  String ts(int hoursAgo) =>
      isoFromDateTime(now.subtract(Duration(hours: hoursAgo)));

  return [
    Todo(
      id: 'a0000000-0000-4000-8000-000000000001',
      title: 'Review pull requests',
      status: TodoStatus.todo,
      priority: TodoPriority.high,
      dueDate: due(0),
      position: 0,
      createdAt: ts(72),
      updatedAt: ts(3),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000002',
      title: 'Write weekly update',
      status: TodoStatus.inProgress,
      priority: TodoPriority.medium,
      dueDate: due(0),
      position: 1,
      createdAt: ts(70),
      updatedAt: ts(5),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000003',
      title: 'Submit expense report',
      description: 'Attach the receipts from the Berlin trip.',
      status: TodoStatus.todo,
      priority: TodoPriority.high,
      dueDate: due(-2),
      position: 2,
      createdAt: ts(120),
      updatedAt: ts(10),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000004',
      title: 'Renew domain name',
      status: TodoStatus.todo,
      priority: TodoPriority.low,
      dueDate: due(-1),
      position: 3,
      createdAt: ts(200),
      updatedAt: ts(20),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000005',
      title: 'Prepare demo script',
      status: TodoStatus.todo,
      priority: TodoPriority.medium,
      dueDate: due(1),
      position: 4,
      createdAt: ts(48),
      updatedAt: ts(6),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000006',
      title: 'Refactor sync engine',
      status: TodoStatus.inProgress,
      priority: TodoPriority.high,
      dueDate: due(2),
      position: 5,
      createdAt: ts(96),
      updatedAt: ts(2),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000007',
      title: 'Update onboarding docs',
      status: TodoStatus.todo,
      dueDate: due(4),
      position: 6,
      createdAt: ts(150),
      updatedAt: ts(30),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000008',
      title: 'Ship v0.1.0',
      status: TodoStatus.completed,
      priority: TodoPriority.high,
      dueDate: due(-3),
      position: 7,
      createdAt: ts(240),
      updatedAt: ts(26),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000009',
      title: 'Fix login bug',
      status: TodoStatus.completed,
      priority: TodoPriority.medium,
      dueDate: due(-1),
      position: 8,
      createdAt: ts(180),
      updatedAt: ts(12),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000010',
      title: 'Buy groceries',
      status: TodoStatus.todo,
      priority: TodoPriority.low,
      dueDate: due(0),
      position: 9,
      createdAt: ts(60),
      updatedAt: ts(8),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000011',
      title: 'Old backlog item',
      status: TodoStatus.todo,
      priority: TodoPriority.low,
      dueDate: due(-10),
      position: 10,
      archived: true,
      createdAt: ts(500),
      updatedAt: ts(400),
    ),
    Todo(
      id: 'a0000000-0000-4000-8000-000000000012',
      title: 'Archived idea',
      status: TodoStatus.inProgress,
      dueDate: due(3),
      position: 11,
      archived: true,
      createdAt: ts(480),
      updatedAt: ts(380),
    ),
  ];
}
