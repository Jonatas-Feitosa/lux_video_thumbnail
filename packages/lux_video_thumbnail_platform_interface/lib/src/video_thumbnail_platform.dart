// video_thumbnail_platform.dart
// Platform interface for lux_video_thumbnail.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lux_video_thumbnail_platform_interface/src/exceptions.dart';
import 'package:lux_video_thumbnail_platform_interface/src/models.dart';
import 'package:lux_video_thumbnail_platform_interface/src/session_operation_queue.dart';
import 'package:lux_video_thumbnail_platform_interface/src/thumbnail_limits.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Platform interface for video thumbnail generation.
///
/// This is the core abstraction that platform-specific implementations
/// (Android, iOS, Web) must implement. The federated plugin pattern
/// uses [PlatformInterface] to ensure only one implementation is registered.
abstract class VideoThumbnailPlatform extends PlatformInterface {
  /// Constructs a [VideoThumbnailPlatform].
  VideoThumbnailPlatform() : super(token: _token);

  static final Object _token = Object();

  /// The default instance, set by the platform-specific plugin.
  static VideoThumbnailPlatform _instance = _MethodChannelVideoThumbnail();

  /// Returns the current platform implementation.
  ///
  /// Throws [PlatformNotSupportedException] if no implementation is registered.
  static VideoThumbnailPlatform get instance {
    if (_instance is _MethodChannelVideoThumbnail) {
      // Check if a real implementation has been registered
      // This is a fallback; real plugins should register via `setInstance`
    }
    return _instance;
  }

  /// Sets the platform-specific implementation.
  ///
  /// Called automatically by the generated platform interface registration.
  /// Can be overridden in tests via [setInstance].
  static void setInstance(VideoThumbnailPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Resets to the default MethodChannel implementation.
  /// Useful for testing.
  static void reset() {
    _instance = _MethodChannelVideoThumbnail();
  }

  /// Opens a video session for batch thumbnail generation.
  ///
  /// This allows reusing the native decoder/parser for multiple timestamps
  /// without reopening the video file each time.
  ///
  /// [source] - Local file path or remote URL.
  /// Returns a [VideoThumbnailSession] with native handle and video metadata.
  ///
  /// Throws:
  /// - [VideoNotFoundException] if source doesn't exist
  /// - [UnsupportedFormatException] if format not supported
  /// - [PermissionDeniedException] if access denied
  /// - [GenerationFailedException] on other errors
  Future<VideoThumbnailSession> openSession(String source);

  /// Opens bytes using a native-owned temporary. Web implementations use a
  /// Blob.
  Future<VideoThumbnailSession> openSessionFromBytes(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    ThumbnailLimits.videoBytes(bytes.length);
    ThumbnailLimits.mimeType(mimeType);
    const channel = MethodChannel('lux_video_thumbnail');
    final result = await channel.invokeMapMethod<String, dynamic>(
      'openSessionFromBytes',
      {'bytes': bytes, 'mimeType': mimeType},
    );
    if (result == null) {
      throw const GenerationFailedException(
        'Null byte session',
        source: 'bytes',
      );
    }
    return VideoThumbnailSession.fromPlatformData(
      nativeHandle: result['nativeHandle'] as int,
      source: 'bytes:$mimeType',
      duration: result['duration'] == null
          ? null
          : Duration(milliseconds: result['duration'] as int),
      nativeWidth: result['nativeWidth'] as int,
      nativeHeight: result['nativeHeight'] as int,
      metadata: result['metadata'] == null
          ? null
          : Map<String, dynamic>.from(result['metadata'] as Map),
    );
  }

  /// Generates multiple thumbnails using an existing session.
  ///
  /// More efficient than calling [generateThumbnail] multiple times
  /// as it reuses the native video decoder.
  ///
  /// [session] - Session returned by [openSession].
  /// [optionsList] - List of thumbnail options for each timestamp.
  /// Returns list of results in the same order as [optionsList].
  ///
  /// Throws:
  /// - [SessionException] if session is invalid/closed
  /// - [GenerationFailedException] on generation errors
  Future<List<VideoThumbnailResult>> generateThumbnails(
    VideoThumbnailSession session,
    List<ThumbnailOptions> optionsList,
  );

  /// Closes a video session and releases native resources.
  ///
  /// Must be called when done with batch generation to avoid leaks.
  ///
  /// [session] - Session to close.
  Future<void> closeSession(VideoThumbnailSession session);

  /// Generates a single thumbnail (convenience method).
  ///
  /// Internally opens a temporary session, generates the thumbnail,
  /// and closes the session. For multiple thumbnails, use
  /// [openSession] + [generateThumbnails] + [closeSession] instead.
  ///
  /// [source] - Local file path or remote URL.
  /// [options] - Thumbnail generation options.
  ///
  /// Throws:
  /// - [VideoNotFoundException] if source doesn't exist
  /// - [UnsupportedFormatException] if format not supported
  /// - [PermissionDeniedException] if access denied
  /// - [TimestampOutOfRangeException] if timestamp > video duration
  /// - [GenerationFailedException] on other errors
  Future<VideoThumbnailResult> generateThumbnail({
    required String source,
    required ThumbnailOptions options,
  });

  /// Checks if a video format is supported on the current platform.
  ///
  /// [mimeType] - MIME type to check (e.g., "video/mp4", "video/webm").
  /// Returns true if the platform can likely decode this format.
  ///
  /// Implementations may cache results for performance.
  Future<bool> isFormatSupported(String mimeType);

  /// Gets the video duration without generating a thumbnail.
  ///
  /// [source] - Local file path or remote URL.
  /// Returns the duration, or null if undetermined.
  ///
  /// Throws [VideoNotFoundException] if source doesn't exist.
  Future<Duration?> getVideoDuration(String source);

  /// Returns the platform version string (for debugging).
  Future<String> getPlatformVersion();
}

/// Default MethodChannel-based implementation.
///
/// This serves as the fallback implementation and reference for
/// platform-specific implementations. Real plugins should override
/// this by registering their own implementation via
/// [VideoThumbnailPlatform.setInstance].
class _MethodChannelVideoThumbnail extends VideoThumbnailPlatform {
  final Expando<SessionOperationQueue> _queues = Expando();
  SessionOperationQueue _queue(VideoThumbnailSession session) =>
      _queues[session] ??= SessionOperationQueue(session.nativeHandle);

  static const String _channelName = 'lux_video_thumbnail';
  static const MethodChannel _channel = MethodChannel(_channelName);

  @override
  Future<VideoThumbnailSession> openSession(String source) async {
    ThumbnailLimits.source(source);
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'openSession',
        {'source': source},
      );
      if (result == null) {
        throw GenerationFailedException(
          'Failed to open session: null response',
          source: source,
        );
      }
      return VideoThumbnailSession.fromPlatformData(
        nativeHandle: result['nativeHandle'] as int,
        source: source,
        duration: result['duration'] != null
            ? Duration(milliseconds: result['duration'] as int)
            : null,
        nativeWidth: result['nativeWidth'] as int,
        nativeHeight: result['nativeHeight'] as int,
        metadata: result['metadata'] != null
            ? Map<String, dynamic>.from(result['metadata'] as Map)
            : null,
      );
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, source: source);
    }
  }

  @override
  Future<List<VideoThumbnailResult>> generateThumbnails(
    VideoThumbnailSession session,
    List<ThumbnailOptions> optionsList,
  ) async {
    ThumbnailLimits.batch(optionsList.length);
    final acceptedOptions = List<ThumbnailOptions>.of(optionsList);
    return _queue(session).run(() async {
      try {
        for (final option in acceptedOptions) {
          option
            ..validateTimestamp(session.duration)
            ..dimensionsFor(session.nativeWidth, session.nativeHeight);
        }
        final optionsArgs = acceptedOptions.map((o) => o.toJson()).toList();
        final result = await _channel.invokeMethod<List<dynamic>>(
          'generateThumbnails',
          {'sessionHandle': session.nativeHandle, 'options': optionsArgs},
        );
        if (result == null) {
          throw SessionException(
            'Failed to generate thumbnails: null response',
            sessionHandle: session.nativeHandle,
          );
        }
        return result
            .map(
              (r) => _parseResult(
                r as Map<dynamic, dynamic>,
                session.nativeHandle,
              ),
            )
            .toList();
      } on PlatformException catch (e) {
        throw _mapPlatformException(e, sessionHandle: session.nativeHandle);
      }
    });
  }

  @override
  Future<void> closeSession(VideoThumbnailSession session) async {
    return _queue(session).close(() async {
      try {
        await _channel.invokeMethod('closeSession', {
          'sessionHandle': session.nativeHandle,
        });
      } on PlatformException catch (e) {
        throw _mapPlatformException(e, sessionHandle: session.nativeHandle);
      }
    });
  }

  @override
  Future<VideoThumbnailResult> generateThumbnail({
    required String source,
    required ThumbnailOptions options,
  }) async {
    ThumbnailLimits.source(source);
    options.validateTimestamp();
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generateThumbnail',
        {'source': source, 'options': options.toJson()},
      );
      if (result == null) {
        throw GenerationFailedException(
          'Failed to generate thumbnail: null response',
          source: source,
        );
      }
      return _parseResult(result, 0);
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, source: source);
    }
  }

  @override
  Future<bool> isFormatSupported(String mimeType) async {
    try {
      final result = await _channel.invokeMethod<bool>('isFormatSupported', {
        'mimeType': mimeType,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Duration?> getVideoDuration(String source) async {
    try {
      final result = await _channel.invokeMethod<int>('getVideoDuration', {
        'source': source,
      });
      if (result == null || result <= 0) return null;
      return Duration(milliseconds: result);
    } on PlatformException catch (e) {
      if (e.code == 'VIDEO_NOT_FOUND') {
        throw VideoNotFoundException(source, cause: e, code: e.code);
      }
      return null;
    }
  }

  @override
  Future<String> getPlatformVersion() async {
    try {
      final result = await _channel.invokeMethod<String>('getPlatformVersion');
      return result ?? 'Unknown';
    } on PlatformException {
      return 'Unknown';
    }
  }

  VideoThumbnailResult _parseResult(
    Map<dynamic, dynamic> data,
    int sessionHandle,
  ) {
    final width = data['width'] as int;
    final height = data['height'] as int;
    final format = ThumbnailFormat.values.byName(data['format'] as String);
    final actualTimestamp = Duration(
      microseconds:
          data['effectiveTimestampUs'] as int? ??
          (data['actualTimestamp'] as int) * 1000,
    );
    final backingType = data['backingType'] as String? ?? 'file';

    if (backingType == 'memory') {
      final bytes = data['bytes'] as Uint8List;
      return VideoThumbnailResult.memory(
        width: width,
        height: height,
        format: format,
        actualTimestamp: actualTimestamp,
        bytes: bytes,
      );
    } else {
      final nativeTempPath = data['tempPath'] as String;
      return VideoThumbnailResult.file(
        width: width,
        height: height,
        format: format,
        actualTimestamp: actualTimestamp,
        nativeTempPath: nativeTempPath,
        channel: _channel,
      );
    }
  }

  VideoThumbnailException _mapPlatformException(
    PlatformException e, {
    String? source,
    int? sessionHandle,
  }) {
    final details = e.details is Map
        ? e.details as Map<dynamic, dynamic>
        : const <dynamic, dynamic>{};
    return switch (e.code) {
      'VIDEO_NOT_FOUND' => VideoNotFoundException(
        source ?? '',
        cause: e,
        code: e.code,
      ),
      'UNSUPPORTED_FORMAT' => UnsupportedFormatException(
        e.message ?? 'Unsupported format',
        format: details['format'] as String?,
        cause: e,
        code: e.code,
      ),
      'PERMISSION_DENIED' => PermissionDeniedException(
        source ?? '',
        cause: e,
        code: e.code,
      ),
      'TIMESTAMP_OUT_OF_RANGE' => TimestampOutOfRangeException(
        Duration(
          microseconds:
              details['requestedUs'] as int? ??
              (details['requestedMs'] as int? ?? 0) * 1000,
        ),
        videoDuration: details['durationMs'] != null
            ? Duration(milliseconds: details['durationMs'] as int)
            : null,
        cause: e,
        code: e.code,
      ),
      'CORS_ERROR' => CorsException(source ?? '', cause: e, code: e.code),
      'SESSION_INVALID' => SessionException(
        e.message ?? 'Invalid session',
        sessionHandle: sessionHandle ?? details['handle'] as int? ?? 0,
        cause: e,
        code: e.code,
      ),
      'DURATION_UNKNOWN' => DurationUnknownException(
        source ?? '',
        cause: e,
        code: e.code,
      ),
      _ => GenerationFailedException(
        e.message ?? 'Unknown error',
        source: source ?? '',
        timestamp: details['timestampMs'] != null
            ? Duration(milliseconds: details['timestampMs'] as int)
            : null,
        cause: e,
        code: e.code,
      ),
    };
  }
}

/// Extension to serialize [ThumbnailOptions] for MethodChannel.
extension ThumbnailOptionsJson on ThumbnailOptions {
  /// Serializes microsecond and legacy millisecond channel options.
  Map<String, dynamic> toJson() => {
    'timestampMs': timestamp.inMilliseconds,
    'timestampUs': timestamp.inMicroseconds,
    'width': width,
    'height': height,
    'format': format.name,
    'quality': quality,
    'maintainAspectRatio': maintainAspectRatio,
    'preferKeyFrame': preferKeyFrame,
  };
}
