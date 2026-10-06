/// An `app_settings` row, mirroring the remote table.
///
/// `app_settings` is shared state across clients: keys written here propagate
/// to the desktop and TUI apps. Namespace mobile-only keys with `mobile.`.
class AppSetting {
  /// Creates an [AppSetting].
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  /// Primary key.
  final String key;

  /// Stored value.
  final String value;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;

  /// Returns a copy with the given fields replaced.
  AppSetting copyWith({String? key, String? value, String? updatedAt}) =>
      AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
