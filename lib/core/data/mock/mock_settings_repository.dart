import '../../models/app_setting.dart';
import '../../utils/clock.dart';
import '../in_memory_store.dart';
import '../repositories.dart';

/// In-memory [SettingsRepository] seeded with one mobile-namespaced key.
class MockSettingsRepository implements SettingsRepository {
  MockSettingsRepository._(this._store);

  /// Creates a repository with a minimal mobile-namespaced seed.
  factory MockSettingsRepository.seeded() => MockSettingsRepository._(
    InMemoryStore<AppSetting>([
      AppSetting(key: 'mobile.seed.version', value: '1', updatedAt: nowIso()),
    ]),
  );

  final InMemoryStore<AppSetting> _store;

  @override
  Stream<List<AppSetting>> watchAll() => _store.watch();

  @override
  Future<String?> get(String key) async {
    for (final setting in _store.snapshot) {
      if (setting.key == key) return setting.value;
    }
    return null;
  }

  @override
  Future<void> set(String key, String value) async {
    final setting = AppSetting(key: key, value: value, updatedAt: nowIso());
    _store.mutate((items) {
      final index = items.indexWhere((s) => s.key == key);
      if (index == -1) {
        items.add(setting);
      } else {
        items[index] = setting;
      }
    });
  }

  @override
  Future<void> delete(String key) async {
    _store.mutate((items) => items.removeWhere((s) => s.key == key));
  }
}
