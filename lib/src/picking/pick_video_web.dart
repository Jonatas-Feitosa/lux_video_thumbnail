import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'picked_video.dart';

/// File-backed Blob URLs avoid copying an entire video into Dart memory.
Future<PickedVideo?> pickVideo({PickerCancellation? cancellation}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'video/*';
  input.style.display = 'none';
  final result = Completer<PickedVideo?>();
  final subscriptions = <StreamSubscription<web.Event>>[];
  void complete(PickedVideo? video) {
    if (result.isCompleted) {
      unawaited(video?.dispose());
      return;
    }
    result.complete(video);
  }

  unawaited(cancellation?.cancelled.then((_) => complete(null)));
  subscriptions.add(
    input.onChange.listen((_) {
      final file = input.files?.item(0);
      if (file == null) {
        complete(null);
        return;
      }
      final url = web.URL.createObjectURL(file);
      complete(
        PickedVideo(
          VideoSource.url(url),
          release: () => web.URL.revokeObjectURL(url),
        ),
      );
    }),
  );
  subscriptions.add(
    web.EventStreamProviders.cancelEvent
        .forTarget(input)
        .listen((_) => complete(null)),
  );
  // Modern browsers deliver cancel reliably. A focus timeout there can race a
  // valid (slow) file selection, so use it only on older implementations.
  final supportsCancel = input.hasProperty('oncancel'.toJS).toDart;
  Timer? focusTimer;
  final focus = web.EventStreamProviders.focusEvent
      .forTarget(web.window)
      .listen((_) {
        if (supportsCancel) return;
        focusTimer?.cancel();
        focusTimer = Timer(const Duration(milliseconds: 500), () {
          if (input.files == null || input.files!.length == 0) complete(null);
        });
      });
  try {
    final body = web.document.body;
    if (body == null) throw StateError('Document has no body');
    body.append(input);
    input.click();
    return await result.future;
  } finally {
    focusTimer?.cancel();
    await focus.cancel();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    input.remove();
  }
}
