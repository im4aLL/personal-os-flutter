# Personal OS (Flutter)

Mobile client for Personal OS: todos, notes, links, work log, and a week-based Gantt planner, with optional bidirectional Turso sync that shares one database with the desktop (`../personal-os`) and terminal (`../personal-os-tui`) clients.

Built with [ForUI](https://forui.dev) as the UI kit (Material only as the host shell) and `flutter_riverpod` for state. Local persistence is [drift](https://drift.simonbinder.eu) (SQLite); the local database is the source of truth and the app works fully offline.

## Features

- Home: greeting, due/overdue todos, per-feature counts, recent activity.
- Todo: three status tabs, priorities, due dates, archive, search, "add to work log".
- Notes: markdown editor with preview, autosave, pin, tags, search.
- Links: favicon list, search, tag filter, external open, auto-fetched page titles.
- Work Log: date-ranged entries grouped by ISO week, filters and presets.
- Projects: phase-colored week Gantt with drag reorder and dialog editing.
- Sync (optional): cloud mode against a Turso database (local, desktop, and TUI clients converge via last-write-wins on `updated_at`). Credentials stay device-local.

## Requirements

- Flutter 3.47+ (Dart 3.13+). ForUI 0.27+ requires Flutter 3.47+.
- Android SDK with an API 36 platform/tools; the Flutter default `minSdkVersion` is 24 (see below).
- For the targeted checks: Node.js (the schema conformance script).

## Run (debug)

```sh
flutter pub get
flutter run            # pick a device, e.g. -d emulator-5554
```

## Android identity and minSdk

- Application id and namespace: `com.hadi.personalos`.
- Display name: "Personal OS" (AndroidManifest `android:label`; iOS `CFBundleDisplayName`).
- minSdk stays at Flutter's default 24, which is sufficient: ForUI ships no native Android code (it is pure Dart), and drift's SQLite comes from `sqlite3`, whose Android prebuilt libraries target the standard NDK ABIs at the API level Flutter passes down from `minSdk`. No package raises the floor above 24, so `minSdk = flutter.minSdkVersion` is left as-is.

## Release signing

Release builds are signed with a local keystore that is never committed. A fresh checkout still builds: when `android/key.properties` is missing, the release build falls back to the debug signing config (fine for personal sideloading).

To set up real release signing:

```sh
# 1. Create the keystore (keytool ships with a JDK; Android Studio bundles one at
#    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool").
keytool -genkeypair -v \
  -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# 2. Create android/key.properties (gitignored) next to the gradle files:
#    storePassword=<your store password>
#    keyPassword=<your key password>
#    keyAlias=upload
#    storeFile=upload-keystore.jks
```

Both `android/key.properties` and the `*.jks` / `*.keystore` files are ignored by `android/.gitignore`, so nothing secret is committed.

## Build and install

```sh
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

# adb is not on PATH by default; on macOS it is usually:
# /Users/hadi/Library/Android/sdk/platform-tools/adb
```

If `adb` reports the app already installed with a different signature, uninstall it first (`adb uninstall com.hadi.personalos`).

## Targeted checks

```sh
node tool/schema_conformance.js   # diffs schema.ts vs the drift tables + generated DB code
flutter analyze                   # must stay clean (zero issues)
```

There is no unit-test suite by design (behavior is verified by running the app); the only automated check is the schema conformance script, `node tool/schema_conformance.js`, which guards the remote schema shared with the desktop and TUI clients.

## Architecture and notes

See [PLAN.md](PLAN.md) for the full architecture, the phase log, and the binding Turso compatibility contract (schema freeze, timestamp/id formats, sync semantics) shared with the desktop and TUI clients.
