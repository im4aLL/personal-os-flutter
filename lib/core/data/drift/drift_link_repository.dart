import 'package:drift/drift.dart';

import '../../models/link.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../remote_write_sink.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';
import 'write_mirror.dart';

/// Drift-backed [LinkRepository].
///
/// Mirrors `MockLinkRepository`: newest link first, tag replacement deletes and
/// re-inserts without touching the link's `updated_at`, and `urlExists` guards
/// the schema's UNIQUE `links.url` (the UI reports a duplicate instead of
/// letting the insert fail).
class DriftLinkRepository implements LinkRepository {
  /// Creates a repository over [database].
  ///
  /// [writeSink] mirrors every write to the remote store; it is always
  /// installed at runtime and no-ops while sync is unconfigured.
  DriftLinkRepository(this._database, {this.writeSink});

  final AppDatabase _database;

  /// Mirrors writes to the remote store; always installed at runtime, no-op
  /// while sync is unconfigured.
  final RemoteWriteSink? writeSink;

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
    final tagRows = [
      for (final name in tags)
        RemoteTagRow(id: newId(), name: name, createdAt: now),
    ];
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
      await _insertTags(link.id, tagRows);
      // Mirror the create (entity + tags) at mutation time so it reaches the
      // cloud without waiting for a sync. Enqueued in the same transaction so
      // the queued intents commit atomically with the local insert.
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.links,
        id: link.id,
      );
      await writeSink?.recordTags(
        parentTable: RemoteTables.links,
        parentId: link.id,
        childTable: 'link_tags',
        parentColumn: 'link_id',
        rows: tagRows,
      );
    });
    return LinkWithTags(link: link, tags: List.unmodifiable(tags));
  }

  @override
  Future<void> update(Link link) async {
    // `created_at` is intentionally absent so the stored value is preserved.
    await _database.transaction(() async {
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
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.links,
        id: link.id,
      );
    });
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Touches only link_tags; the link's updated_at is deliberately untouched,
    // matching the reference setTagsForLink (LWW safety).
    final now = nowIso();
    final rows = [
      for (final name in tags)
        RemoteTagRow(id: newId(), name: name, createdAt: now),
    ];
    await _database.transaction(() async {
      await (_database.delete(
        _database.linkTags,
      )..where((t) => t.linkId.equals(id))).go();
      await _insertTags(id, rows);
      // Mirror the replacement to the remote so a removed tag is removed
      // remotely too, instead of being pulled straight back by the insert-only
      // sync. Enqueued in the same transaction so the queued intent commits
      // atomically with the local replacement.
      await writeSink?.recordTags(
        parentTable: RemoteTables.links,
        parentId: id,
        childTable: 'link_tags',
        parentColumn: 'link_id',
        rows: rows,
      );
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
      // Enqueue inside the transaction so the queued delete commits atomically
      // with the local delete (see the todo repository).
      await writeSink?.recordDelete(RemoteTables.links, id);
    });
  }

  Future<void> _insertTags(String linkId, List<RemoteTagRow> rows) async {
    for (final row in rows) {
      await _database
          .into(_database.linkTags)
          .insert(
            LinkTagsCompanion(
              id: Value(row.id),
              linkId: Value(linkId),
              name: Value(row.name),
              createdAt: Value(row.createdAt),
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
