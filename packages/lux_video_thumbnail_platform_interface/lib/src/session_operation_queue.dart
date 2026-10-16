import 'dart:async';

import 'package:lux_video_thumbnail_platform_interface/src/exceptions.dart';
import 'package:lux_video_thumbnail_platform_interface/src/thumbnail_limits.dart';

/// FIFO for one channel session; closing rejects new work and drains old work.
class SessionOperationQueue {
  /// Creates a queue for the native handle used in error reporting.
  SessionOperationQueue(this.handle);

  /// Handle associated with this queue.
  final int handle;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closed;
  int _pending = 0;

  /// Runs accepted work in order, without retaining a failed tail.
  Future<T> run<T>(Future<T> Function() operation) {
    if (_closed != null) {
      return Future<T>.error(
        SessionException('Session is closing', sessionHandle: handle),
      );
    }
    if (_pending >= ThumbnailLimits.maxPendingOperations) {
      return Future<T>.error(
        StateError('Session queue resource limit exceeded'),
      );
    }
    _pending++;
    final pending = _tail.then((_) => operation()).whenComplete(() {
      _pending--;
    });
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  /// Rejects new work immediately and releases once accepted work has settled.
  Future<void> close(Future<void> Function() release) =>
      _closed ??= _tail.then((_) => release());
}
