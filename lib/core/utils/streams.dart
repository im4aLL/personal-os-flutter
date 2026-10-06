import 'dart:async';

/// Combines the latest values of [a] and [b], emitting after both have emitted
/// at least once and then on every subsequent event from either stream.
///
/// The returned stream is broadcast, so it can back multiple listeners. When
/// either source completes, the combined stream completes and the sibling
/// subscription is cancelled, so a late event cannot be added to the closed
/// controller.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  A? latestA;
  B? latestB;
  var hasA = false;
  var hasB = false;
  var closed = false;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;

  late StreamController<R> controller;

  void emit() {
    if (closed || !hasA || !hasB) return;
    controller.add(combine(latestA as A, latestB as B));
  }

  void onError(Object error, StackTrace stackTrace) {
    if (!closed) controller.addError(error, stackTrace);
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await subA?.cancel();
    await subB?.cancel();
    subA = null;
    subB = null;
    await controller.close();
  }

  controller = StreamController<R>.broadcast(
    onListen: () {
      subA = a.listen(
        (value) {
          latestA = value;
          hasA = true;
          emit();
        },
        onError: onError,
        onDone: close,
      );
      subB = b.listen(
        (value) {
          latestB = value;
          hasB = true;
          emit();
        },
        onError: onError,
        onDone: close,
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
      subA = null;
      subB = null;
      hasA = false;
      hasB = false;
    },
  );

  return controller.stream;
}
