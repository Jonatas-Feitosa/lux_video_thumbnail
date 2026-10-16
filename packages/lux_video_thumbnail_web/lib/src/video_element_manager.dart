import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

extension type _PresentedFrame(JSObject _) implements JSObject {
  external double get mediaTime;
}

/// Owns a video element, bounded event waits and a serial extraction queue.
class VideoElementManager {
  VideoElementManager({required this.source, this.isLocalBytes = false})
    : video = HTMLVideoElement() {
    video.preload = 'auto';
    if (source.startsWith('http:') || source.startsWith('https:')) {
      video.crossOrigin = 'anonymous';
    }
    video.muted = true;
    video.playsInline = true;
    if (video.hasProperty('requestVideoFrameCallback'.toJS).toDart) {
      _observeFrames();
    }
  }

  final HTMLVideoElement video;
  final String source;
  bool isLocalBytes;
  bool _disposed = false;
  bool _closing = false;
  Future<void>? _closed;
  int? _frameCallback;
  double? _presentedTime;
  void _observeFrames() {
    _frameCallback = video.requestVideoFrameCallback(
      ((num _, _PresentedFrame metadata) {
        _presentedTime = metadata.mediaTime;
        if (!_disposed) _observeFrames();
      }).toJS,
    );
  }

  int _queued = 0;
  Future<void> _tail = Future<void>.value();
  final Set<Completer<void>> _pending = {};
  num get duration => video.duration;
  int get videoWidth => video.videoWidth;
  int get videoHeight => video.videoHeight;
  MediaError? get error => video.error;

  void load() {
    if (_disposed) throw StateError('Video has been disposed');
    video.src = source;
    video.load();
  }

  Future<void> waitForMetadata() =>
      _wait([video.onLoadedMetadata], () => video.readyState >= 1);

  Future<void> seekTo(Duration timestamp) async {
    final target = timestamp.inMicroseconds / Duration.microsecondsPerSecond;
    if ((video.currentTime - target).abs() > 0.000001 || video.seeking) {
      await _wait(
        [video.onSeeked],
        () => !video.seeking,
        start: () => video.currentTime = target,
      );
    }
    // loadedmetadata alone does not guarantee that frame zero is drawable.
    await _wait([
      video.onLoadedData,
      video.onCanPlay,
      video.onSeeked,
    ], () => video.readyState >= 2 && !video.seeking);
    // Some sources have no seek index (for example live WebM in Firefox).
    // A completed seek can silently land at zero. Never return that frame as
    // though the requested position had been reached.
    if ((video.currentTime - target).abs() > 0.05) {
      throw GenerationFailedException(
        'Browser could not seek to requested position',
        source: 'video',
        timestamp: timestamp,
        code: 'SEEK_UNAVAILABLE',
      );
    }
    await _waitForPresentation();
    final frameTime = _presentedTime;
    if (_frameCallback != null &&
        duration.isFinite &&
        frameTime != null &&
        (frameTime - target).abs() >= 1) {
      // A long-held frame can be correct. A large PTS gap alone is not proof of
      // failure. Decode forward from zero to disambiguate sparse frames from a
      // browser that silently ignored a seek (notably unindexed WebM).
      await _decodeForward(target);
    }
  }

  Future<void> _waitForPresentation() async {
    if (_frameCallback == null) return;
    final presented = Completer<void>();
    int? animation;
    animation = window.requestAnimationFrame(
      ((num _) {
        animation = window.requestAnimationFrame(
          ((num _) {
            if (!presented.isCompleted) presented.complete();
          }).toJS,
        );
      }).toJS,
    );
    try {
      await presented.future.timeout(const Duration(milliseconds: 250));
    } on TimeoutException {
      // Background tabs may suspend presentation callbacks.
    } finally {
      if (animation != null) window.cancelAnimationFrame(animation!);
    }
  }

  Future<void> _decodeForward(double target) async {
    if (video.currentTime != 0 || video.seeking) {
      await _wait(
        [video.onSeeked],
        () => !video.seeking,
        start: () => video.currentTime = 0,
      );
    }
    if (target == 0) {
      await _waitForPresentation();
      return;
    }
    int? positionPoll;
    try {
      await video.play().toDart.timeout(const Duration(seconds: 15));
      // timeupdate is too infrequent near a frame boundary. Stop playback on
      // the media clock, while still allowing a genuinely long-held frame.
      positionPoll = window.setInterval(
        (() {
          if (_disposed || video.currentTime >= target || video.ended) {
            video.pause();
          }
        }).toJS,
        8.toJS,
      );
      await _wait([
        video.onTimeUpdate,
        video.onEnded,
        video.onPause,
      ], () => video.currentTime >= target || video.ended);
    } catch (error) {
      if (_disposed) rethrow;
      throw GenerationFailedException(
        'Browser could not decode to requested position',
        source: 'video',
        code: 'SEEK_UNAVAILABLE',
        cause: error,
      );
    } finally {
      if (positionPoll != null) window.clearInterval(positionPoll);
      video.pause();
    }
    await _waitForPresentation();
  }

  Future<T> exclusive<T>(Future<T> Function() work) {
    if (_closing) return Future<T>.error(StateError('Video is closing'));
    if (_queued >= ThumbnailLimits.maxPendingOperations) {
      return Future<T>.error(StateError('Video queue resource limit exceeded'));
    }
    _queued++;
    final operation = _tail.then((_) {
      if (_disposed) throw StateError('Video has been disposed');
      return work();
    });
    _tail = operation
        .whenComplete(() {
          _queued--;
        })
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> close() {
    _closing = true;
    return _closed ??= _tail.then((_) => dispose());
  }

  Future<void> _wait(
    List<Stream<Event>> events,
    bool Function() ready, {
    void Function()? start,
  }) async {
    if (_disposed) throw StateError('Video has been disposed');
    if (start == null && ready()) return;
    if (error != null) throw _mediaError();
    final completer = Completer<void>();
    _pending.add(completer);
    final subscriptions = <StreamSubscription<Event>>[];
    for (final stream in events) {
      subscriptions.add(
        stream.listen((_) {
          if (!completer.isCompleted && ready()) completer.complete();
        }),
      );
    }
    subscriptions.add(
      video.onError.listen((_) {
        if (!completer.isCompleted) completer.completeError(_mediaError());
      }),
    );
    try {
      start?.call();
      if (start == null && ready() && !completer.isCompleted) {
        completer.complete();
      }
      await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      _pending.remove(completer);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  VideoThumbnailException _mediaError() {
    final code = error?.code;
    if (code == MediaError.MEDIA_ERR_DECODE) {
      return UnsupportedFormatException(
        'Browser could not decode the video',
        code: '$code',
      );
    }
    // SRC_NOT_SUPPORTED also covers inaccessible HTTP/CORS sources. Browsers
    // deliberately hide that distinction; do not claim a codec or CORS cause.
    return VideoNotFoundException(source, code: '$code');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final callback = _frameCallback;
    if (callback != null) video.cancelVideoFrameCallback(callback);
    for (final pending in _pending.toList()) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Video has been disposed'));
      }
    }
    video.pause();
    video.removeAttribute('src');
    video.load();
    video.remove();
  }
}
