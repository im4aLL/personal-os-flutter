import 'dart:async';

/// Generic in-memory backing store for the mock repositories.
///
/// Holds a [List] and re-emits an immutable copy on a **broadcast**
/// [StreamController] after every mutation. Broadcast is mandatory: the Home
/// dashboard and a feature page can both watch the same store, and a
/// single-subscription stream would break the second listener.
class InMemoryStore<T> {
  /// Creates a store seeded with [seed].
  InMemoryStore([Iterable<T> seed = const []]) : _items = List<T>.of(seed);

  final StreamController<List<T>> _controller =
      StreamController<List<T>>.broadcast();
  List<T> _items;

  /// The current items as an unmodifiable list.
  List<T> get snapshot => List<T>.unmodifiable(_items);

  /// Watches the store.
  ///
  /// Every listener immediately receives the current [snapshot], then receives
  /// a fresh list after every mutation. Multiple listeners are supported.
  Stream<List<T>> watch() =>
      Stream<List<T>>.multi(isBroadcast: true, (listener) {
        listener.add(snapshot);
        final subscription = _controller.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = subscription.cancel;
      });

  /// Replaces the entire contents of the store.
  void replaceAll(Iterable<T> items) {
    _items = List<T>.of(items);
    _emit();
  }

  /// Mutates the underlying list in place, then re-emits.
  void mutate(void Function(List<T> items) change) {
    change(_items);
    _emit();
  }

  void _emit() => _controller.add(List<T>.unmodifiable(_items));

  /// Closes the store's stream.
  Future<void> dispose() => _controller.close();
}
