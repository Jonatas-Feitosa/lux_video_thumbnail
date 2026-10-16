import 'dart:async';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

/// Allows a widget to release an unfinished browser selector on disposal.
class PickerCancellation {
  final Completer<void> _completion = Completer<void>();
  Future<void> get cancelled => _completion.future;
  void cancel() {
    if (!_completion.isCompleted) _completion.complete();
  }
}

/// A picker-owned input and its optional browser resource cleanup.
class PickedVideo {
  PickedVideo(this.source, {this.release});
  final VideoSource source;
  final FutureOr<void> Function()? release;
  bool _disposed = false;
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await release?.call();
  }
}
