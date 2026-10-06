import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Returns a new UUID v4, lowercase and hyphenated.
///
/// Matches the reference clients' `crypto.randomUUID()` output so ids written
/// from Flutter are indistinguishable from ids written by the desktop/TUI apps.
String newId() => _uuid.v4();
