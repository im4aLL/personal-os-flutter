import '../../models/work_log.dart';
import '../../utils/clock.dart';
import '../../utils/dates.dart';
import '../../utils/id.dart';
import '../in_memory_store.dart';
import '../repositories.dart';

/// In-memory [WorkLogRepository] seeded with entries spanning three ISO weeks.
class MockWorkLogRepository implements WorkLogRepository {
  MockWorkLogRepository._(this._store);

  /// Creates a repository seeded relative to today.
  factory MockWorkLogRepository.seeded() =>
      MockWorkLogRepository._(InMemoryStore<WorkLogWithTags>(_seedWorkLogs()));

  final InMemoryStore<WorkLogWithTags> _store;

  @override
  Stream<List<WorkLogWithTags>> watchAll() => _store.watch().map(_sorted);

  @override
  Future<WorkLogWithTags?> getById(String id) async {
    for (final log in _store.snapshot) {
      if (log.id == id) return log;
    }
    return null;
  }

  @override
  Future<WorkLogWithTags> create({
    required String title,
    String? description,
    required String startDate,
    required String endDate,
    List<String> tags = const [],
  }) async {
    final now = nowIso();
    final log = WorkLog(
      id: newId(),
      title: title,
      description: description,
      startDate: startDate,
      endDate: endDate,
      createdAt: now,
      updatedAt: now,
    );
    final created = WorkLogWithTags(
      workLog: log,
      tags: List<String>.unmodifiable(tags),
    );
    _store.mutate((items) => items.add(created));
    return created;
  }

  @override
  Future<void> update(WorkLog workLog) async {
    _store.mutate((items) {
      final index = items.indexWhere((l) => l.id == workLog.id);
      if (index == -1) return;
      final next = workLog.copyWith(
        createdAt: items[index].createdAt,
        updatedAt: nowIso(),
      );
      items[index] = items[index].copyWith(workLog: next);
    });
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Tag replacement touches only work_log_tags; it must NOT advance the work
    // log's updated_at, matching the reference setTagsForWorkLog (LWW safety).
    _store.mutate((items) {
      final index = items.indexWhere((l) => l.id == id);
      if (index == -1) return;
      items[index] = items[index].copyWith(
        tags: List<String>.unmodifiable(tags),
      );
    });
  }

  @override
  Future<void> delete(String id) async {
    _store.mutate((items) => items.removeWhere((l) => l.id == id));
  }

  static List<WorkLogWithTags> _sorted(Iterable<WorkLogWithTags> items) {
    final sorted = List<WorkLogWithTags>.of(items)
      ..sort((a, b) {
        final byStart = b.startDate.compareTo(a.startDate);
        return byStart != 0 ? byStart : b.createdAt.compareTo(a.createdAt);
      });
    return sorted;
  }
}

/// Six work logs across this ISO week, last week, and two weeks ago.
List<WorkLogWithTags> _seedWorkLogs() {
  final now = DateTime.now();
  final today = dateOnly(now);
  final thisMonday = mondayOf(formatDate(today));
  String day(int offset) =>
      formatDate(DateTime(thisMonday.year, thisMonday.month, thisMonday.day + offset));
  String ts(int hoursAgo) =>
      isoFromDateTime(now.subtract(Duration(hours: hoursAgo)));

  WorkLogWithTags log({
    required String id,
    required String title,
    required String start,
    required String end,
    required int createdHoursAgo,
    required int updatedHoursAgo,
    String? description,
    List<String> tags = const [],
  }) => WorkLogWithTags(
    workLog: WorkLog(
      id: id,
      title: title,
      description: description,
      startDate: start,
      endDate: end,
      createdAt: ts(createdHoursAgo),
      updatedAt: ts(updatedHoursAgo),
    ),
    tags: tags,
  );

  return [
    log(
      id: 'd0000000-0000-4000-8000-000000000001',
      title: 'Sprint kickoff',
      start: day(0),
      end: day(1),
      description: 'Scoped the phase 2 work and split the mock repositories.',
      createdHoursAgo: 8,
      updatedHoursAgo: 4,
      tags: const ['planning'],
    ),
    log(
      id: 'd0000000-0000-4000-8000-000000000002',
      title: 'API integration',
      start: day(2),
      end: day(3),
      description: 'Wired the repository interfaces to the Riverpod providers.',
      createdHoursAgo: 10,
      updatedHoursAgo: 6,
      tags: const ['dev'],
    ),
    log(
      id: 'd0000000-0000-4000-8000-000000000003',
      title: 'Design review',
      start: day(-7),
      end: day(-6),
      createdHoursAgo: 40,
      updatedHoursAgo: 30,
      tags: const ['design'],
    ),
    log(
      id: 'd0000000-0000-4000-8000-000000000004',
      title: 'Bug triage',
      start: day(-5),
      end: day(-4),
      createdHoursAgo: 60,
      updatedHoursAgo: 50,
      tags: const ['dev'],
    ),
    log(
      id: 'd0000000-0000-4000-8000-000000000005',
      title: 'Quarterly planning',
      start: day(-14),
      end: day(-11),
      createdHoursAgo: 96,
      updatedHoursAgo: 80,
      tags: const ['planning', 'strategy'],
    ),
    log(
      id: 'd0000000-0000-4000-8000-000000000006',
      title: 'Customer interviews',
      start: day(-10),
      end: day(-9),
      createdHoursAgo: 120,
      updatedHoursAgo: 100,
      tags: const ['research'],
    ),
  ];
}
