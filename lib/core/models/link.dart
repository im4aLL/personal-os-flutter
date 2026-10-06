import 'sentinel.dart';

/// A saved link, mirroring the remote `links` table column-for-column.
class Link {
  /// Creates a [Link].
  const Link({
    required this.id,
    required this.url,
    required this.title,
    this.faviconUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID primary key.
  final String id;

  /// Unique URL (`url TEXT NOT NULL UNIQUE`).
  final String url;

  /// Display title.
  final String title;

  /// Optional favicon URL (`favicon_url TEXT`, nullable).
  final String? faviconUrl;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// [faviconUrl] uses [unset] so an explicit `null` clears it.
  Link copyWith({
    String? id,
    String? url,
    String? title,
    Object? faviconUrl = unset,
    String? createdAt,
    String? updatedAt,
  }) => Link(
    id: id ?? this.id,
    url: url ?? this.url,
    title: title ?? this.title,
    faviconUrl: faviconUrl == unset ? this.faviconUrl : faviconUrl as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A link tag row, mirroring the remote `link_tags` table.
class LinkTag {
  /// Creates a [LinkTag].
  const LinkTag({
    required this.id,
    required this.linkId,
    required this.name,
    required this.createdAt,
  });

  /// UUID primary key.
  final String id;

  /// Owning link id (`link_id TEXT NOT NULL REFERENCES links(id)`).
  final String linkId;

  /// Tag name.
  final String name;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;
}

/// A link together with its tag names, matching the reference `LinkWithTags`.
class LinkWithTags {
  /// Creates a [LinkWithTags].
  const LinkWithTags({required this.link, this.tags = const []});

  /// The link row.
  final Link link;

  /// Tag names in insertion order.
  final List<String> tags;

  /// The link id.
  String get id => link.id;

  /// The URL.
  String get url => link.url;

  /// The display title.
  String get title => link.title;

  /// The optional favicon URL.
  String? get faviconUrl => link.faviconUrl;

  /// Creation timestamp.
  String get createdAt => link.createdAt;

  /// Last-write timestamp.
  String get updatedAt => link.updatedAt;

  /// Returns a copy with the given fields replaced.
  LinkWithTags copyWith({Link? link, List<String>? tags}) =>
      LinkWithTags(link: link ?? this.link, tags: tags ?? this.tags);
}
