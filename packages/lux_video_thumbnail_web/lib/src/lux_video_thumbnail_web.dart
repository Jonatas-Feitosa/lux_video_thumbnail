import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'package:web/web.dart';
import 'canvas_renderer.dart';
import 'video_element_manager.dart';

/// Browser implementation, registered automatically through the Flutter plugin.
class LuxVideoThumbnailWeb extends VideoThumbnailPlatform {
  final Map<int, VideoElementManager> _sessions = {};
  final Map<int, String> _blobUrls = {};
  final Map<int, Future<void>> _closing = {};
  int _nextHandle = 1;
  int _opening = 0;

  void _checkSessionLimit() {
    if (_sessions.length + _closing.length + _opening >=
        ThumbnailLimits.maxSessions) {
      throw StateError('At most four video sessions may be open');
    }
  }

  static void registerWith([Registrar? registrar]) {
    VideoThumbnailPlatform.setInstance(LuxVideoThumbnailWeb());
  }

  @override
  Future<VideoThumbnailSession> openSession(String source) async {
    ThumbnailLimits.source(source);
    _checkSessionLimit();
    _opening++;
    try {
      return await _openSession(source);
    } finally {
      _opening--;
    }
  }

  Future<VideoThumbnailSession> _openSession(String source) async {
    final manager = VideoElementManager(source: source);
    try {
      final metadata = manager.waitForMetadata();
      manager.load();
      await metadata;
      if (manager.videoWidth <= 0 || manager.videoHeight <= 0) {
        throw const UnsupportedFormatException('Video has no decodable image');
      }
      ThumbnailLimits.dimensions(manager.videoWidth, manager.videoHeight);
      final handle = _nextHandle++;
      _sessions[handle] = manager;
      return VideoThumbnailSession.fromPlatformData(
        nativeHandle: handle,
        source: source,
        duration: manager.duration.isFinite
            ? Duration(
                microseconds:
                    (manager.duration * Duration.microsecondsPerSecond).round(),
              )
            : null,
        nativeWidth: manager.videoWidth,
        nativeHeight: manager.videoHeight,
        metadata: {'platform': 'web'},
      );
    } catch (_) {
      manager.dispose();
      rethrow;
    }
  }

  @override
  Future<VideoThumbnailSession> openSessionFromBytes(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    ThumbnailLimits.videoBytes(bytes.length);
    ThumbnailLimits.mimeType(mimeType);
    _checkSessionLimit();
    final parts = <BlobPart>[Uint8List.fromList(bytes).toJS].toJS;
    final url = URL.createObjectURL(
      Blob(parts, BlobPropertyBag(type: mimeType)),
    );
    try {
      final session = await openSession(url);
      _blobUrls[session.nativeHandle] = url;
      return session;
    } catch (_) {
      URL.revokeObjectURL(url);
      rethrow;
    }
  }

  @override
  Future<List<VideoThumbnailResult>> generateThumbnails(
    VideoThumbnailSession session,
    List<ThumbnailOptions> optionsList,
  ) async {
    ThumbnailLimits.batch(optionsList.length);
    final acceptedOptions = List<ThumbnailOptions>.of(optionsList);
    final manager = _sessions[session.nativeHandle];
    if (manager == null) {
      throw SessionException(
        'Session is closed',
        sessionHandle: session.nativeHandle,
      );
    }
    return manager.exclusive(() async {
      for (final options in acceptedOptions) {
        options.validateTimestamp(session.duration);
        options.dimensionsFor(session.nativeWidth, session.nativeHeight);
      }
      final results = <VideoThumbnailResult>[];
      try {
        for (final options in acceptedOptions) {
          options.validateTimestamp(session.duration);
          var position = options.timestamp;
          final duration = session.duration;
          if (duration != null && position == duration) {
            position = Duration(
              microseconds: math.max(0, duration.inMicroseconds - 1),
            );
          }
          final dimensions = options.dimensionsFor(
            session.nativeWidth,
            session.nativeHeight,
          );
          await manager.seekTo(position);
          final image = await CanvasRenderer.renderVideoFrame(
            video: manager.video,
            width: dimensions.width,
            height: dimensions.height,
            format: options.format,
            quality: options.quality,
          );
          results.add(
            VideoThumbnailResult.memory(
              width: image.width,
              height: image.height,
              format: image.format,
              actualTimestamp: position,
              bytes: image.data,
            ),
          );
        }
        return results;
      } catch (_) {
        for (final result in results) {
          await result.dispose();
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> closeSession(VideoThumbnailSession session) {
    final handle = session.nativeHandle;
    return _closing.putIfAbsent(
      handle,
      () => _closeSession(session).whenComplete(() {
        _closing.remove(handle);
      }),
    );
  }

  Future<void> _closeSession(VideoThumbnailSession session) async {
    final manager = _sessions.remove(session.nativeHandle);
    try {
      await manager?.close();
    } finally {
      final url = _blobUrls.remove(session.nativeHandle);
      if (url != null) URL.revokeObjectURL(url);
    }
  }

  @override
  Future<VideoThumbnailResult> generateThumbnail({
    required String source,
    required ThumbnailOptions options,
  }) async {
    options.validateTimestamp();
    final session = await openSession(source);
    try {
      return (await generateThumbnails(session, [options])).single;
    } finally {
      await closeSession(session);
    }
  }

  @override
  Future<bool> isFormatSupported(String mimeType) async {
    final video = HTMLVideoElement();
    try {
      return video.canPlayType(mimeType).isNotEmpty;
    } finally {
      video.remove();
    }
  }

  @override
  Future<Duration?> getVideoDuration(String source) async {
    final session = await openSession(source);
    try {
      return session.duration;
    } finally {
      await closeSession(session);
    }
  }

  @override
  Future<String> getPlatformVersion() async => 'Web';
}
