import 'package:intl/intl.dart';

import 'sentinel.dart';

/// A note, mirroring the remote `notes` table column-for-column.
class Note {
  /// Creates a [Note].
  const Note({
    required this.id,
    this.title,
    this.content = '',
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID primary key.
  final String id;

  /// Optional title (`title TEXT`, nullable).
  ///
  /// `null` means "display the formatted [createdAt]" (see [noteDisplayTitle]);
  /// the reference client writes `null` on create and never coerces it to `''`.
  final String? title;

  /// Markdown content (`content TEXT NOT NULL DEFAULT ''`).
  final String content;

  /// Pinned flag, stored as 0/1 at the data boundary.
  final bool pinned;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// [title] uses [unset] so an explicit `null` clears it.
  Note copyWith({
    String? id,
    Object? title = unset,
    String? content,
    bool? pinned,
    String? createdAt,
    String? updatedAt,
  }) => Note(
    id: id ?? this.id,
    title: title == unset ? this.title : title as String?,
    content: content ?? this.content,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          id == other.id &&
          title == other.title &&
          content == other.content &&
          pinned == other.pinned &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(id, title, content, pinned, createdAt, updatedAt);
}

/// A note tag row, mirroring the remote `note_tags` table.
class NoteTag {
  /// Creates a [NoteTag].
  const NoteTag({
    required this.id,
    required this.noteId,
    required this.name,
    required this.createdAt,
  });

  /// UUID primary key.
  final String id;

  /// Owning note id (`note_id TEXT NOT NULL REFERENCES notes(id)`).
  final String noteId;

  /// Tag name.
  final String name;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;
}

/// A note together with its tag names, matching the reference `NoteWithTags`.
class NoteWithTags {
  /// Creates a [NoteWithTags].
  const NoteWithTags({required this.note, this.tags = const []});

  /// The note row.
  final Note note;

  /// Tag names in insertion order.
  final List<String> tags;

  /// The note id.
  String get id => note.id;

  /// The optional note title.
  String? get title => note.title;

  /// The markdown content.
  String get content => note.content;

  /// Whether the note is pinned.
  bool get pinned => note.pinned;

  /// Creation timestamp.
  String get createdAt => note.createdAt;

  /// Last-write timestamp.
  String get updatedAt => note.updatedAt;

  /// Returns a copy with the given fields replaced.
  NoteWithTags copyWith({Note? note, List<String>? tags}) =>
      NoteWithTags(note: note ?? this.note, tags: tags ?? this.tags);
}

/// Returns the display title for a note.
///
/// Falls back to the formatted creation timestamp when [title] is null or
/// blank, matching the reference `noteDisplayTitle`.
String noteDisplayTitle(Note note) {
  final title = note.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final created = DateTime.parse(note.createdAt).toLocal();
  return DateFormat.yMMMd().add_jm().format(created);
}
