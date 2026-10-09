import 'package:drift/drift.dart';

import '../../models/link.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';

/// Drift-backed [LinkRepository].
///
/// Mirrors `MockLinkRepository`: newest link first, tag replacement deletes and
/// re-inserts without touching the link's `updated_at`, and `urlExists` guards
/// the schema's UNIQUE `links.url` (the UI reports a duplicate instead of
/// letting the insert fail).
class DriftLinkRepository implements LinkRepository {
  /// Creates a repository over [database].
  DriftLinkRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<LinkWithTags>> watchAll() {
    final query =
        _database.select(_database.links).join([
          leftOuterJoin(
            _database.linkTags,
            _database.linkTags.linkId.equalsExp(_database.links.id),
          ),
        ])..orderBy([
          OrderingTerm.desc(_database.links.createdAt),
          OrderingTerm.asc(_database.linkTags.createdAt),
          OrderingTerm.asc(_linkTagsRowId),
        ]);
    return query.watch().map(_group);
  }

  @override
  Future<LinkWithTags?> getById(String id) async {
    final row = await (_database.select(
      _database.links,
    )..where((l) => l.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return LinkWithTags(link: linkFromRow(row), tags: await _tagsFor(id));
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
    await _database.transaction(() async {
      await _database
          .into(_database.links)
          .insert(
            LinksCompanion(
              id: Value(link.id),
              url: Value(link.url),
              title: Value(link.title),
              faviconUrl: Value(link.faviconUrl),
              createdAt: Value(link.createdAt),
              updatedAt: Value(link.updatedAt),
            ),
          );
      await _insertTags(link.id, tags);
    });
    return LinkWithTags(link: link, tags: List.unmodifiable(tags));
  }

  @override
  Future<void> update(Link link) async {
    // `created_at` is intentionally absent so the stored value is preserved.
    await (_database.update(
      _database.links,
    )..where((l) => l.id.equals(link.id))).write(
      LinksCompanion(
        url: Value(link.url),
        title: Value(link.title),
        faviconUrl: Value(link.faviconUrl),
        updatedAt: Value(nowIso()),
      ),
    );
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Touches only link_tags; the link's updated_at is deliberately untouched,
    // matching the reference setTagsForLink (LWW safety).
    await _database.transaction(() async {
      await (_database.delete(
        _database.linkTags,
      )..where((t) => t.linkId.equals(id))).go();
      await _insertTags(id, tags);
    });
  }

  @override
  Future<bool> urlExists(String url) async {
    final row =
        await (_database.select(_database.links)
              ..where((l) => l.url.equals(url))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> delete(String id) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.linkTags,
      )..where((t) => t.linkId.equals(id))).go();
      await (_database.delete(
        _database.links,
      )..where((l) => l.id.equals(id))).go();
    });
  }

  Future<void> _insertTags(String linkId, List<String> tags) async {
    final now = nowIso();
    for (final name in tags) {
      await _database
          .into(_database.linkTags)
          .insert(
            LinkTagsCompanion(
              id: Value(newId()),
              linkId: Value(linkId),
              name: Value(name),
              createdAt: Value(now),
            ),
          );
    }
  }

  Future<List<String>> _tagsFor(String linkId) async {
    final rows =
        await (_database.select(_database.linkTags)
              ..where((t) => t.linkId.equals(linkId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(_linkTagsRowId),
              ]))
            .get();
    return List.unmodifiable([for (final row in rows) row.name]);
  }

  List<LinkWithTags> _group(List<TypedResult> rows) {
    final order = <String>[];
    final links = <String, Link>{};
    final tags = <String, List<String>>{};
    for (final row in rows) {
      final linkRow = row.readTable(_database.links);
      final tagRow = row.readTableOrNull(_database.linkTags);
      if (!links.containsKey(linkRow.id)) {
        links[linkRow.id] = linkFromRow(linkRow);
        tags[linkRow.id] = <String>[];
        order.add(linkRow.id);
      }
      if (tagRow != null) tags[linkRow.id]!.add(tagRow.name);
    }
    return [
      for (final id in order)
        LinkWithTags(link: links[id]!, tags: List.unmodifiable(tags[id]!)),
    ];
  }
}

/// Ordering tiebreaker for `link_tags` rows inserted together.
///
/// Same rationale as the note repository: insertion order is recovered from
/// SQLite's implicit `rowid`. This is an implicit dependency on `link_tags`
/// being a rowid table; the frozen remote schema declares no `WITHOUT ROWID`,
/// so `rowid` is present. It would fail if the schema ever moved to
/// `WITHOUT ROWID`.
final Expression<int> _linkTagsRowId = CustomExpression<int>('link_tags.rowid');
