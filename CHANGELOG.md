# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-11

Everything since the first release: notes now use lightweight summaries,
todos are ordered per status with drag reorder, new and promoted todos land
on top, and the content gutter is unified across the app.

### Added

- Notes: the list reads lightweight note summaries (title, tags, pin, and
  timestamps, without the body); note bodies load on demand when the editor
  opens, so a list refresh no longer re-reads every note body.
- Todos: drag-to-reorder within a status tab, persisting the new order through
  `updatePositions`.

### Changed

- Todos: a new todo and a status change now land on top of the destination
  status (one below the current minimum position) instead of appending to the
  end, so the newest work is visible first and never collides with a position
  left behind by a reorder.
- Notes: `NoteCard` drops the content snippet and the inline pin toggle, the
  list builds cards lazily with `ListView.builder`, and search matches titles
  and tags only.
- Layout: a single 22px horizontal content gutter is used across pages, sheets,
  and tabs so content lines up with the nested header title inset (12 page
  padding plus 10 title padding).
- Sync settings: the extra padding wrapping the connection fields is removed,
  letting `FTile.raw`'s built-in content padding space them without double
  inset.
- Todo card: the menu button no longer stretches title-only cards; half its
  height is reserved in layout instead.
- Note editor and detail pages now own their own content padding.

## [1.0.0] - 2026-10-10

First release. Mobile client for Personal OS sharing one database with the
desktop and terminal clients.

### Added

- Home: greeting, due/overdue todos, per-feature counts, and recent activity.
- Todo: three status tabs, priorities, due dates, archive, search, and
  "add to work log".
- Notes: markdown editor with preview, autosave, pin, tags, and search.
- Links: favicon list, search, tag filter, external open, and auto-fetched
  page titles.
- Work Log: date-ranged entries grouped by ISO week, filters, and presets.
- Projects: phase-colored week Gantt with drag reorder and dialog editing.
- Sync (optional): cloud mode against a Turso database, with local, desktop,
  and TUI clients converging via last-write-wins on `updated_at`; credentials
  stay device-local.
- Local persistence with drift (SQLite) as the source of truth, so the app
  works fully offline.
- Native splash screen for Android and iOS.

[1.1.0]: https://github.com/im4aLL/personal-os-flutter/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/im4aLL/personal-os-flutter/releases/tag/1.0.0
