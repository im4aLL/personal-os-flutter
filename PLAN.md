# Personal OS Flutter - Implementation Plan

Mobile port of the Personal OS desktop app (Tauri/React, reference at ../personal-os). UI-first against in-memory mock repositories; drift (SQLite) persistence and Turso sync land in later phases without UI rewrites. Target: Android APK sideloaded to the owner's phone; code stays platform-agnostic so iOS is not broken.

## Key decisions

| Decision | Choice |
|---|---|
| UI kit | ForUI (FTheme.neutral light/dark .touch); Material only as host shell |
| State | flutter_riverpod, handwritten providers (no riverpod_generator); repository interfaces behind providers; one Notifier/AsyncNotifier per feature screen |
| Navigation | 5 bottom tabs: Home, Todo, Notes, More, Settings. More hosts Links / Work Log / Projects as entries pushing onto the shell's inner Navigator (nested `Navigator` + `NavigatorPopHandler`) so the bottom bar stays visible |
| Persistence (Phase 9) | drift, schema mirrors ../personal-os/src/lib/schema.ts (the remote Turso schema) column-for-column |
| Sync (Phase 10) | Turso via libSQL HTTP API; bidirectional last-write-wins on updated_at; local DB is source of truth |
| Tests | No broad suite. Targeted high-value tests only: clock/timestamp format, schema conformance vs schema.ts (node script), sync merge (LWW + pending_deletes), plus the Phase 2 Home stream-wiring widget test and the stream-combination test. Otherwise verification = flutter run / release APK + manual inspection; flutter analyze must stay clean |
| Theme | Follow system by default; manual System/Light/Dark toggle in Settings (in-memory until Phase 8) |

## Architecture

Layers and rules:

- UI (lib/features/<name>/ui/): ForUI widgets only; never touches data implementations; reads/writes through Riverpod providers.
- State (lib/features/<name>/providers/): Notifier/AsyncNotifier per screen holding list + filter state; calls repository interfaces only.
- Repository interfaces (lib/core/data/repositories.dart): one abstract interface per aggregate (TodoRepository, NoteRepository, LinkRepository, WorkLogRepository, ProjectRepository, SettingsRepository). Watch methods return Stream so drift's .watch() queries drop in unchanged.
- Data impls: mock (lib/core/data/mock/) now, drift (lib/core/data/drift/) later. The swap happens in exactly one place: the provider body. UI and state code never change.
- Domain models (lib/core/models/): plain immutable Dart classes mirroring the reference tables; shared by mock and drift impls.

Mock to real swap:

```dart
final todoRepositoryProvider = Provider<TodoRepository>(
  // Phase 9: replace with DriftTodoRepository(ref.watch(appDatabaseProvider))
  (ref) => MockTodoRepository.seeded(),
);
```

Mock impls share a tiny InMemoryStore<T> (List + broadcast StreamController) so watch streams re-emit on mutation; screens behave identically before and after drift.

Sync strategy (high level, Phase 10):

- Local SQLite is the source of truth; all UI writes go local first; the app works fully offline.
- Per-table merge: pull remote rows, INSERT OR IGNORE for missing rows and UPDATE only where remote.updated_at > local.updated_at; push local rows where local.updated_at > remote.updated_at (last write wins, row granularity - same as the desktop app).
- Deletes push immediately at mutation time when online; when offline, record (table, id) in a pending_deletes table. On sync: flush pending_deletes to the remote first, then pull; pulled rows that have a pending delete entry are suppressed so they cannot resurrect (INSERT OR IGNORE alone would re-insert them).
- app_settings syncs with the same LWW rule.
- Clock skew: keep client-stamped timestamps (port fidelity) but on sync compare against Turso server time and warn the user on gross skew (see Risks and notes). This check is read-only: it never rewrites updated_at or any value written to the remote, so the remote data format is unchanged.
- Known limitation: a delete made on another device while this one is offline can still resurrect the row (pending_deletes covers only this device going offline, not the reverse direction). The desktop app loses all offline deletes; this app improves on that but does not fully solve two-device offline convergence.

## Folder structure

```
lib/
  main.dart                      # ProviderScope + MaterialApp + FTheme + FToaster + FTooltipGroup
  app/
    app_shell.dart               # FScaffold + FBottomNavigationBar (5 tabs) + IndexedStack
    router.dart                  # named routes for More-tab feature pages (plain Navigator)
    theme.dart                   # FTheme light/dark selection + toApproximateMaterialTheme()
  core/
    models/                      # todo.dart, note.dart, link.dart, work_log.dart, project.dart
    data/
      repositories.dart          # abstract repository interfaces
      in_memory_store.dart       # shared mock backing store (broadcast streams)
      mock/                      # mock_todo_repository.dart, ... with seeded fake data
      drift/                     # (Phase 9) database.dart, tables.dart, drift_*_repository.dart
    sync/                        # (Phase 10) turso_client.dart, sync_engine.dart
    utils/                       # dates.dart (ISO week keys, YYYY-MM-DD), id.dart (uuid), clock.dart (ms-precision ISO timestamps), streams.dart (stream combination)
    widgets/                     # shared UI helpers (empty state, centered message, delete dialog, padded card)
  features/
    home/       ui/home_page.dart + dashboard widget files   providers/
    todo/       ui/todo_page.dart, todo_edit_sheet.dart      providers/
    notes/      ui/notes_page.dart, note_editor_page.dart    providers/
    links/      ui/links_page.dart, link_edit_sheet.dart     providers/
    worklog/    ui/work_log_page.dart, work_log_edit_sheet.dart  providers/
    projects/   ui/projects_page.dart, project_gantt.dart, work_item_dialog.dart  providers/
    more/       ui/more_page.dart
    settings/   ui/settings_page.dart    providers/
test/                             # targeted tests: clock/timestamp, Home stream wiring, stream combination, project repository, tag-timestamp semantics (sync merge in Phase 10)
tool/                             # schema_conformance.js (diffs schema.ts vs drift schema + remote-DDL port)
```

Feature-first: each feature owns ui/ + providers/; shared code lives in core/. test/ holds only the targeted high-value tests (clock/timestamp, the Phase 2 Home stream-wiring and stream-combination tests, and the Phase 10 sync merge tests); tool/schema_conformance.js is the automated schema-drift guard.

## Data model (mirrors ../personal-os/src/lib/schema.ts)

| Table | Key fields |
|---|---|
| todos | id, title, description, status(todo/in_progress/completed), priority(low/medium/high), due_date, position, archived, created_at, updated_at |
| notes | id, title, content, pinned, created_at, updated_at |
| note_tags | id, note_id, name, created_at |
| links | id, url(unique), title, favicon_url, created_at, updated_at |
| link_tags | id, link_id, name, created_at |
| work_logs | id, title, description, start_date, end_date, created_at, updated_at |
| work_log_tags | id, work_log_id, name, created_at |
| projects | id, name, start_date, week_count, position, created_at, updated_at |
| project_phases | id, project_id, name, color(hex), position, created_at |
| work_items | id, project_id, phase_id, title, person, comment, status(pending/in_progress/done), start_week, end_week, position, is_separator, jira_ticket, created_at, updated_at |
| app_settings | key, value, updated_at |

Conventions: UUID string PKs; ISO-8601 datetimes; YYYY-MM-DD dates; updated_at on all syncable tables; tag tables are insert-only (on edit: delete all tags, re-insert).

## Turso compatibility contract (shared DB with desktop + TUI)

The desktop app (personal-os) and terminal app (personal-os-tui) share one Turso database; this app becomes a third client. A schema or data-format deviation from this app breaks the other clients, so the rules in this section are BINDING, not conventions.

**Schema freeze:**

- The schema is owned by the desktop app (../personal-os/src/lib/schema.ts) and is FROZEN from this app's perspective: never add, rename, drop, or retype a column or table from Flutter. Schema evolution, when needed, is coordinated across all three clients and always additive (nullable column or column with a default, added via the ALTER TABLE ADD COLUMN pattern).
- Local drift tables are column-for-column identical to the remote schema (same names, types, nullability, CHECK and UNIQUE constraints, foreign keys with ON DELETE CASCADE, and indexes) so sync is a straight copy with no mapping layer. Local-only helper tables (e.g. pending_deletes) are allowed but MUST be clearly marked local-only and MUST never be created on the remote.
- Respect remote constraints in app code before writing: CHECK value domains (todos.status in todo/in_progress/completed, todos.priority in low/medium/high, work_items.status in pending/in_progress/done), NOT NULL columns always populated, links.url UNIQUE (handle the duplicate-URL rejection gracefully).
- Value semantics must match the other clients exactly: YYYY-MM-DD calendar dates, integers for 0/1 flags (archived, pinned, is_separator), week-based integers for Gantt ranges, empty string rather than null where the other clients use '' defaults (e.g. notes.content), and a nullable notes.title where null means "display formatted created_at" (the desktop writes title: null on create; never coerce null to '').
- No mitigation may change the remote data format. Clock-skew detection is read-only, pending_deletes is local-only (never created on the remote), and the schema conformance check only verifies - none of them may alter the remote schema or rewrite any value written to the remote. The remote DB is the shared contract with the desktop and TUI clients, and it is off-limits to change from this app.

**Client behavior:**

- **Timestamps**: every client writes `new Date().toISOString()` - UTC, millisecond precision, Z suffix (e.g. 2026-10-05T12:34:56.789Z). Sync compares updated_at as plain strings. Dart's DateTime.toIso8601String() emits MICROseconds (.789123Z) which breaks lexicographic comparison ('1' < 'Z', so a newer Flutter write would look older and lose LWW). Rule: all timestamps come from one core/utils/clock.dart helper that truncates to milliseconds, e.g. DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch, isUtc: true).toIso8601String(). Never call toIso8601String() directly on syncable data.
- **Explicit timestamps on every write**: never rely on DB column defaults (the reference app_settings has DEFAULT (datetime('now')) which produces a different space-separated format; letting defaults fire anywhere corrupts string comparison).
- **IDs**: UUID v4, lowercase, hyphenated (uuid package matches crypto.randomUUID()).
- **Remote DDL**: the app ships a verbatim Dart port of REMOTE_SCHEMAS from ../personal-os/src/lib/schema.ts - every CREATE TABLE IF NOT EXISTS (columns, nullability, defaults, CHECK and UNIQUE constraints), every CREATE INDEX IF NOT EXISTS, and the additive ALTER TABLE ADD COLUMN statements. Execution mirrors applyRemoteSchema: statements run one by one and "duplicate column" errors are ignored, so the same list works against a fresh empty DB and an existing one. Running it against a fresh empty Turso DB MUST produce the same tables, columns, and indexes the desktop app would create - the mobile app can bootstrap a new remote database with no other client involved. When schema.ts changes upstream, the Dart port is updated in the same commit.
- **Sync semantics**: port of ../personal-os/src/lib/sync.ts - per-table LWW via string-compared updated_at, tag tables INSERT OR IGNORE both ways (no tombstones), deletes pushed at mutation time when online. One deliberate extension beyond the desktop: a local-only pending_deletes table queues offline deletes (the desktop simply loses them); see the sync strategy above for flush and pull-suppression ordering.
- **app_settings is shared state across clients**: any key this app writes propagates to desktop/TUI and vice versa. Namespace mobile-local keys (e.g. mobile.*) and reuse existing keys only when sharing is intended. Turso credentials and theme mode are NOT stored here - they are device-local on every client (see Phases 8 and 10).

## Dependencies

| Phase | Packages |
|---|---|
| 0 | forui, flutter_riverpod, material_ui |
| 2 | uuid, intl |
| 4 | flutter_markdown |
| 5 | url_launcher |
| 8 | http, shared_preferences |
| 9 | drift, sqlite3_flutter_libs, path_provider, path; dev: drift_dev, build_runner |
| 10 | (reuses http) |

## Status

- [x] Phase 0 - Bootstrap ForUI + Riverpod
- [x] Phase 1 - App shell: tabs, navigation, theme toggle
- [x] Phase 2 - Core models, mock repositories, Home dashboard
- [x] Phase 3 - Todo
- [x] Phase 4 - Notes
- [ ] Phase 5 - Links (core)
- [ ] Phase 6 - Work Log
- [ ] Phase 7 - Projects (week Gantt)
- [ ] Phase 8 - Enrichment: link metadata + persisted settings + empty states
- [ ] Phase 9 - Drift persistence
- [ ] Phase 10 - Turso sync
- [ ] Phase 11 - Polish + APK

## Phases

### Phase 0 - Bootstrap ForUI + Riverpod

Goal: clean slate, ForUI app skeleton runs.

Scope:
- Verify `flutter --version` is 3.44+ (ForUI 0.22+ requirement); upgrade Flutter first if not.
- Delete lib/theme/ and lib/pages/; rewrite lib/main.dart.
- `flutter pub add forui flutter_riverpod material_ui`.
- main.dart: ProviderScope -> MaterialApp (supportedLocales + localizationsDelegates per ForUI docs) -> builder wrapping FTheme (FTheme.neutral.light.touch / dark.touch) -> FToaster -> FTooltipGroup; Material theme via toApproximateMaterialTheme(); home is a placeholder FScaffold with one FButton.
- material_ui is a required direct companion of ForUI, not a transitive detail: ForUI 0.27.x targets the standalone `material_ui` package, so `toApproximateMaterialTheme()` returns `material_ui.ThemeData`. main.dart must import `package:material_ui/material_ui.dart` (importing `package:flutter/material.dart` does not type-check), and relying on the transitive dependency would trip the `depend_on_referenced_packages` lint. Declaring it directly keeps `flutter analyze` clean.

Key files: pubspec.yaml, lib/main.dart.

Done when: `flutter run` shows a ForUI-styled screen that follows system dark mode; `flutter analyze` is clean.

Deferred: navigation, tabs, theme toggle, all features.

### Phase 1 - App shell: tabs, navigation, theme toggle

Goal: full app skeleton; every destination reachable.

Scope:
- app_shell.dart: FScaffold + FBottomNavigationBar with 5 tabs in order Home, Todo, Notes, More, Settings; IndexedStack preserves per-tab state.
- Placeholder page per tab (FHeader title + one descriptive FCard).
- More tab: FTileGroup entries for Links, Work Log, Projects pushing placeholder routes on the root Navigator.
- Settings tab: System/Light/Dark selector backed by themeModeProvider (StateProvider<ThemeMode>, in-memory).

Key files: lib/app/*, placeholder lib/features/*/ui pages.

Done when: `flutter run`; all 5 tabs switch; More entries open pages with working back navigation; theme toggle flips light/dark immediately.

Deferred: real content, persisting the theme choice.

### Phase 2 - Core models, mock repositories, Home dashboard

Goal: repository pattern established; first real screen with seeded data.

Scope:
- core/models: immutable classes for all tables above; status/priority fields as Dart enums whose serialized values exactly match the remote CHECK constraint domains (todo/in_progress/completed, low/medium/high, pending/in_progress/done).
- core/data/repositories.dart: interfaces, Stream-based watch methods + CRUD futures.
- core/data/in_memory_store.dart + core/data/mock/*: mock repositories seeded with realistic data (a week of todos across all 3 statuses, 3 notes, 5 links, 6 work log entries across 3 ISO weeks, 1 project with 3 phases and 8 work items).
- Providers per repository (todoRepositoryProvider etc.).
- utils/dates.dart: ISO week key + label helpers (reused by Work Log); utils/id.dart: uuid v4; utils/clock.dart: millisecond-precision ISO timestamp helper (see Turso compatibility contract).
- Targeted test: clock.dart emits millisecond-precision UTC ISO strings with a Z suffix (no microseconds), so timestamp string comparison stays lexicographically correct.
- Home dashboard: time-of-day greeting; Due today and Overdue todo sections; count cards per feature (tap jumps to the tab); Recent activity list (latest notes/links/work logs by updated_at); completing a todo from the dashboard allowed via checkbox.

Done when: Home shows live counts and lists from mock data; toggling a todo on Home updates counts instantly (proves stream wiring); clock timestamp test passes; analyze clean.

Deferred: feature screens, dashboard editing beyond the complete toggle.

### Phase 3 - Todo

Goal: full todo workflow on mobile.

Scope:
- todo_page.dart: FTabs with 3 status lists (Todo / In Progress / Done) - not a 3-column board; each item a card with title, priority FBadge, due date with overdue highlight.
- Per-status add (button opens edit sheet preset to that status); edit via FSheet: FTextFormField title + description, priority select, FDateField due date.
- Item menu actions: move status, archive (soft delete), delete (confirm FDialog), Add to work log (creates entry via WorkLogRepository with today as start/end and the todo title; toast confirms).
- Search FTextField filtering all tabs; Archived view behind a header action.
- TodoNotifier (Notifier) holding query + filters.

Done when: create/edit/complete/archive/delete/search all work against mock data and survive tab switches; Add to work log shows a confirmation toast; analyze clean.

Deferred: drag reorder (position unused for now), reminders/notifications.

### Phase 4 - Notes

Goal: markdown notes with preview and autosave.

Scope:
- notes_page.dart: list sorted pinned-first then updated_at desc; pin toggle; tag badges; search across title/content/tags; new-note FAB; delete with confirm.
- note_editor_page.dart: title field + markdown editor; edit/preview toggle rendering flutter_markdown MarkdownBody inside a small MarkdownPreview wrapper widget (keeps the package swappable); autosave with ~500 ms debounce through NoteRepository; tag chip editing.

Done when: create/edit/pin/tag/search work; preview toggle renders markdown; leaving and reopening a note keeps edits (in-memory); analyze clean.

Deferred: formatting toolbar, tag autocomplete from existing tags, attachments.

### Phase 5 - Links (core)

Goal: save and organize links.

Scope:
- links_page.dart (pushed from More): list rows with favicon, title, domain, tag badges; search; tag filter (select one tag to narrow the list).
- Add/edit sheet: url + title + tags (manual title entry in this phase); delete with confirm.
- Favicon: Image.network on https://www.google.com/s2/favicons?domain={domain}&sz=32 with a letter fallback; store favicon_url on the model.
- Tap a link to open externally via url_launcher.

Done when: add/edit/delete/search/tag-filter links; tapping opens the URL in the external browser; favicons render with graceful fallback; analyze clean.

Deferred: fetching page title over HTTP (Phase 8), duplicate-URL handling beyond a toast.

### Phase 6 - Work Log

Goal: date-ranged work log grouped by ISO week.

Scope:
- work_log_page.dart (from More): entries grouped under headers This week / Last week / Week of <date> via utils/dates.dart ISO week keys; row shows title, date range, tags.
- Add/edit sheet: title, description, start/end FDateField pair (validate start <= end), tags.
- Filters: search text, date range, presets This week / Last week / This month (FTabs or segmented control).

Done when: seeded entries group correctly by ISO week (items span 3 weeks); add/edit/delete/search/presets work; entries created from todos (Phase 3) appear in This week; analyze clean.

Deferred: export, statistics.

### Phase 7 - Projects (week Gantt)

Goal: week-based Gantt planner.

Scope:
- projects_page.dart (from More): project list (name, start_date, week_count); add/edit/delete project; phase management (name + hex color from preset swatches).
- project_gantt.dart: horizontally scrollable grid - rows are work items grouped under phase headers (phase color), columns are weeks 1..week_count mapped to real dates from start_date, current week column highlighted; bar per item spanning start_week..end_week, colored by status.
- Dialog/sheet-based interactions only (no drag): tap item to edit (title, person, jira_ticket, status, start/end week, comment); separator rows via is_separator; move up/down actions drive position.
- Keep ProjectGantt a dumb widget (items + phases in); ProjectNotifier provides data.

Done when: seeded project renders a scrollable Gantt with the current week highlighted; items and phases are addable/editable via dialogs; layout stays usable on a small phone screen; analyze clean.

Deferred: drag-resize, pinch zoom, export.

### Phase 8 - Enrichment: link metadata + persisted settings + empty states

Goal: quality-of-life pass now that all features exist.

Scope:
- Link add flow: fetch the page <title> over HTTP (http package, ~5 s timeout, silent fallback to manual entry); title stays editable.
- Add INTERNET permission to android/app/src/main/AndroidManifest.xml (debug builds have it, release builds do not - required here and for Turso sync).
- Persist theme mode via shared_preferences (key theme_mode). Theme is device-local and intentionally NOT stored in app_settings, so it does not sync across clients.
- Empty states and error toasts across all feature pages.

Done when: adding a link auto-fills its title when reachable; theme choice survives an app restart; every list has an empty state; analyze clean.

Deferred: real DB, sync.

### Phase 9 - Drift persistence

Goal: mock data replaced by real local SQLite; UI untouched.

Scope:
- Add drift stack; core/data/drift/tables.dart mirrors ../personal-os/src/lib/schema.ts column-for-column (names, types, nullability, CHECK and UNIQUE constraints, foreign keys with ON DELETE CASCADE, defaults, indexes - see Turso compatibility contract: schema freeze). Diff tables.dart against schema.ts as a review step before proceeding (including FKs, cascade, indexes, and constraints, not just columns).
- Schema conformance guard: a node script (tool/schema_conformance.js) parses REMOTE_SCHEMAS from ../personal-os/src/lib/schema.ts and diffs it against tables.dart and the remote-DDL Dart port (columns, types, nullability, defaults, CHECK/UNIQUE constraints, FKs/cascade, indexes). Run before every commit/merge; any drift fails the build.
- database.dart (AppDatabase, schema version 1 - fresh app, no legacy migrations).
- DriftTodoRepository etc. implementing the same interfaces with drift queries and .watch() streams.
- Swap provider bodies to drift impls (single localized diff); keep mock impls available for ProviderScope overrides (demos, widget previews).
- Commit generated .g.dart files so checkouts build without running build_runner.
- Harden the note editor's async failure/rollback semantics: the Phase 4 single-flight write queue assumes success, so once the repository can fail (drift constraint/lock/IO) a failed optimistic pin/tag write can diverge from the store; add convergence/rollback handling at that point.

Done when: fresh install creates the DB; every feature behaves identically against SQLite; data persists across app kill/restart; schema conformance script passes; analyze clean.

Deferred: sync, settings table sync, backup.

### Phase 10 - Turso sync

Goal: optional cloud sync sharing one Turso DB with the desktop and TUI apps (see Turso compatibility contract - it is binding for this phase).

Scope:
- Settings: app mode local vs cloud; Turso URL + auth token fields (entered per device and stored device-locally, never in app_settings - the desktop keeps these in localStorage, so they do NOT propagate across clients; secure token storage is deferred to a later phase).
- core/sync/turso_client.dart: minimal libSQL HTTP API client (execute + select).
- core/sync/sync_engine.dart: per-table bidirectional LWW merge on updated_at (port of ../personal-os/src/lib/sync.ts), ensure-remote-schema step (verbatim Dart port of REMOTE_SCHEMAS from ../personal-os/src/lib/schema.ts, runs on cloud-mode setup and before every sync), pending_deletes queue for offline deletes (mobile extension beyond the desktop), clock-skew check against Turso server time with a user warning, manual Sync now button + sync on app resume.
- Cross-client verification pass: create/edit/delete the same rows from Flutter, desktop, and TUI; confirm convergence and identical timestamp formats in the remote rows.
- Fresh-DB bootstrap verification: point the app at a new empty Turso database, enable cloud mode, and confirm ensure-remote-schema creates every table, column, and index exactly as the desktop app would (diff sqlite_master / PRAGMA table_info output against a desktop-created DB).
- Targeted sync merge tests: LWW ordering on updated_at, pending_deletes flush-before-pull + pull suppression, and timestamp-string comparison edge cases (microsecond vs millisecond).

Done when: a fresh empty Turso DB bootstrapped by the mobile app has the complete schema (tables, columns, indexes) identical to a desktop-created one; with cloud mode enabled, changes made on any client (Flutter, desktop, TUI) appear on the others after sync and vice versa; deletes propagate while online; app fully functional with sync disabled; targeted sync merge tests pass; analyze clean.

Deferred: background isolate sync, incremental cursors, secure token storage.

### Phase 11 - Polish + APK

Goal: distributable build on the owner's phone.

Scope:
- App name/icon, Android applicationId, minSdk sanity check against forui/drift requirements.
- Release signing via a local keystore (not committed) or debug-signed release for personal sideload.
- `flutter build apk --release`; install via adb; manual smoke pass over all 5 features + theme toggle + sync toggle.
- Performance pass on Gantt scrolling and the notes editor.
- README: build and install instructions.

Done when: release APK installs on the phone and all features work offline; sync works when enabled.

## Out of scope (Phases 0-8, UI-first)

- Real database, drift codegen, migrations.
- Turso sync, app mode, remote schema setup.
- HTTP page-title fetch (until Phase 8), accounts, auth, multi-user.
- Notifications, reminders, home-screen widgets, export/backup.
- Broad automated test coverage and CI. (Targeted high-value tests for timestamp, schema conformance, and sync merge are in scope - see Tests decision and Phases 2/9/10.)
- iOS-specific work (code must stay platform-agnostic; no Android-only APIs).

## Risks and notes

- ForUI 0.22+ requires Flutter 3.44+; check `flutter --version` before Phase 0. ForUI is pre-1.0: minors can break; pin the version, upgrade with `flutter pub upgrade forui --major-versions` and apply `dart fix --apply`.
- flutter_markdown is the pragmatic preview choice but low-activity; isolate it behind the MarkdownPreview wrapper so swapping packages later is a one-file change.
- Gantt on phones: horizontal scroll + dialog editing only; if week_count grows large, build columns lazily (fixed-extent list) to avoid jank.
- LWW sync limitation: deletes made on another device while this device is offline can resurrect rows; pending_deletes covers this device going offline, not the reverse direction. An improvement over the desktop (which loses offline deletes entirely), but not full two-device offline convergence.
- Multi-client clock skew: LWW on updated_at means a device with a wrong clock can win or lose edits incorrectly. Keep client-stamped timestamps (port fidelity) but on sync compare against Turso server time and warn the user on gross skew; also keep the phone on automatic date/time.
- app_settings key collisions across clients are silent: a mobile key that accidentally matches a desktop key will overwrite it via LWW. Follow the namespacing rule in the compatibility contract.
- Schema drift is the highest-severity risk in this project: one wrong column or value format from Flutter breaks the desktop and TUI clients. Mitigations: binding compatibility contract, the automated schema conformance script (Phase 9) that diffs schema.ts against the drift schema and remote-DDL port on every commit, Dart enums enforcing CHECK value domains, and the cross-client verification pass in Phase 10 before sync is considered done.
- InMemoryStore must use a broadcast StreamController; a single-subscription stream breaks the second listener (dashboard + feature page).
- Tag edits are insert-only (delete all + re-insert on save) to match the reference schema and keep sync simple.
- Offline tag and phase edits do not fully converge: tags are insert-only with no tombstones, so an offline tag edit (delete-all + re-insert) leaves stale tags that resurrect on pull; project_phases has no updated_at and no tombstone, and phase edits/deletes rely on immediate remote mirroring that is silently dropped offline. Matches the desktop app; treat tag and phase edits as best-effort when offline. Accepted decision: the schema freeze rules out adding tombstones/updated_at, so this parity is intended, not a gap.
- No broad unit-test suite is deliberate; the targeted high-value areas get tests - clock/timestamp, schema conformance, Home stream wiring, stream combination, and tag-timestamp semantics, plus sync merge in Phase 10 - and everything else is compensated with analyze-clean plus the per-phase Done-when checklist executed manually on every phase.
