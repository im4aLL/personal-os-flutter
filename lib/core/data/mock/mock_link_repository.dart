import '../../models/link.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../in_memory_store.dart';
import '../repositories.dart';

/// In-memory [LinkRepository] seeded with five tagged links.
class MockLinkRepository implements LinkRepository {
  MockLinkRepository._(this._store);

  /// Creates a repository seeded relative to today.
  factory MockLinkRepository.seeded() =>
      MockLinkRepository._(InMemoryStore<LinkWithTags>(_seedLinks()));

  final InMemoryStore<LinkWithTags> _store;

  @override
  Stream<List<LinkWithTags>> watchAll() => _store.watch().map(_sorted);

  @override
  Future<LinkWithTags?> getById(String id) async {
    for (final link in _store.snapshot) {
      if (link.id == id) return link;
    }
    return null;
  }

  @override
  Future<LinkWithTags> create({
    required String url,
    required String title,
    String? faviconUrl,
    List<String> tags = const [],
  }) async {
    final now = nowIso();
    final link = Link(
      id: newId(),
      url: url,
      title: title,
      faviconUrl: faviconUrl,
      createdAt: now,
      updatedAt: now,
    );
    final created = LinkWithTags(
      link: link,
      tags: List<String>.unmodifiable(tags),
    );
    _store.mutate((items) => items.add(created));
    return created;
  }

  @override
  Future<void> update(Link link) async {
    _store.mutate((items) {
      final index = items.indexWhere((l) => l.id == link.id);
      if (index == -1) return;
      final next = link.copyWith(
        createdAt: items[index].createdAt,
        updatedAt: nowIso(),
      );
      items[index] = items[index].copyWith(link: next);
    });
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Tag replacement touches only link_tags; it must NOT advance the link's
    // updated_at, matching the reference setTagsForLink (LWW safety).
    _store.mutate((items) {
      final index = items.indexWhere((l) => l.id == id);
      if (index == -1) return;
      items[index] = items[index].copyWith(
        tags: List<String>.unmodifiable(tags),
      );
    });
  }

  @override
  Future<bool> urlExists(String url) async =>
      _store.snapshot.any((link) => link.url == url);

  @override
  Future<void> delete(String id) async {
    _store.mutate((items) => items.removeWhere((l) => l.id == id));
  }

  static List<LinkWithTags> _sorted(Iterable<LinkWithTags> items) {
    final sorted = List<LinkWithTags>.of(items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }
}

/// Five links with tags and favicon URLs.
List<LinkWithTags> _seedLinks() {
  final now = DateTime.now();
  String ts(int hoursAgo) =>
      isoFromDateTime(now.subtract(Duration(hours: hoursAgo)));

  LinkWithTags link({
    required String id,
    required String url,
    required String title,
    required int createdHoursAgo,
    required int updatedHoursAgo,
    List<String> tags = const [],
  }) => LinkWithTags(
    link: Link(
      id: id,
      url: url,
      title: title,
      faviconUrl:
          'https://www.google.com/s2/favicons?domain=${Uri.parse(url).host}&sz=32',
      createdAt: ts(createdHoursAgo),
      updatedAt: ts(updatedHoursAgo),
    ),
    tags: tags,
  );

  return [
    link(
      id: 'c0000000-0000-4000-8000-000000000001',
      url: 'https://flutter.dev',
      title: 'Flutter documentation',
      createdHoursAgo: 48,
      updatedHoursAgo: 2,
      tags: const ['dev', 'flutter', 'docs'],
    ),
    link(
      id: 'c0000000-0000-4000-8000-000000000002',
      url: 'https://forui.dev',
      title: 'ForUI',
      createdHoursAgo: 72,
      updatedHoursAgo: 24,
      tags: const ['dev', 'ui', 'design'],
    ),
    link(
      id: 'c0000000-0000-4000-8000-000000000003',
      url: 'https://riverpod.dev',
      title: 'Riverpod',
      createdHoursAgo: 96,
      updatedHoursAgo: 48,
      tags: const ['dev', 'flutter', 'state'],
    ),
    link(
      id: 'c0000000-0000-4000-8000-000000000004',
      url: 'https://turso.tech',
      title: 'Turso',
      createdHoursAgo: 120,
      updatedHoursAgo: 96,
      tags: const ['infra', 'db', 'backend'],
    ),
    link(
      id: 'c0000000-0000-4000-8000-000000000005',
      url: 'https://news.ycombinator.com',
      title: 'Hacker News',
      createdHoursAgo: 144,
      updatedHoursAgo: 144,
      tags: const ['reading', 'news'],
    ),
  ];
}
