import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/todo.dart';

/// Watches the todo with [id], re-emitting whenever the underlying store
/// changes.
///
/// Emits `null` when no such todo exists, e.g. it was deleted while its detail
/// page was open. The Home dashboard and the detail page share the same
/// [todoRepositoryProvider] instance, so a status change made on one is
/// reflected on the other without a refresh.
final todoByIdProvider = StreamProvider.family<Todo?, String>((ref, id) {
  return ref.watch(todoRepositoryProvider).watchAll().map((todos) {
    for (final todo in todos) {
      if (todo.id == id) return todo;
    }
    return null;
  });
});
