// method_channel_video_thumbnail.dart
// Default MethodChannel implementation for lux_video_thumbnail.

import 'package:flutter/services.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'package:lux_video_thumbnail_platform_interface/src/session_operation_queue.dart';

/// Method channel name used for communication with platform implementations.
const String kLuxVideoThumbnailChannel = 'lux_video_thumbnail';

/// Method names for the platform channel.
class LuxVideoThumbnailMethods {
  /// Channel operation: `openSession`.
  static const String openSession = 'openSession';

  /// Channel operation: `generateThumbnails`.
  static const String generateThumbnails = 'generateThumbnails';

  /// Channel operation: `closeSession`.
  static const String closeSession = 'closeSession';

  /// Channel operation: `generateThumbnail`.
  static const String generateThumbnail = 'generateThumbnail';

  /// Channel operation: `isFormatSupported`.
  static const String isFormatSupported = 'isFormatSupported';

  /// Channel operation: `getVideoDuration`.
  static const String getVideoDuration = 'getVideoDuration';

  /// Channel operation: `readThumbnailChunk`.
  static const String readThumbnailChunk = 'readThumbnailChunk';

  /// Channel operation: `copyThumbnailFile`.
  static const String copyThumbnailFile = 'copyThumbnailFile';

  /// Channel operation: `deleteThumbnailFile`.
  static const String deleteThumbnailFile = 'deleteThumbnailFile';

  /// Channel operation: `getThumbnailFileSize`.
  static const String getThumbnailFileSize = 'getThumbnailFileSize';
}

/// Error codes returned by platform implementations.
class LuxVideoThumbnailErrorCodes {
  /// Native error identifier: `videoNotFound`.
  static const String videoNotFound = 'VIDEO_NOT_FOUND';

  /// Native error identifier: `unsupportedFormat`.
  static const String unsupportedFormat = 'UNSUPPORTED_FORMAT';

  /// Native error identifier: `permissionDenied`.
  static const String permissionDenied = 'PERMISSION_DENIED';

  /// Native error identifier: `timestampOutOfRange`.
  static const String timestampOutOfRange = 'TIMESTAMP_OUT_OF_RANGE';

  /// Native error identifier: `corsError`.
  static const String corsError = 'CORS_ERROR';

  /// Native error identifier: `sessionInvalid`.
  static const String sessionInvalid = 'SESSION_INVALID';

  /// Native error identifier: `durationUnknown`.
  static const String durationUnknown = 'DURATION_UNKNOWN';

  /// Native error identifier: `generationFailed`.
  static const String generationFailed = 'GENERATION_FAILED';
}

/// Default MethodChannel implementation for the platform interface.
///
/// This class provides the concrete MethodChannel implementation that
/// the platform interface uses as a fallback. Platform-specific plugins
/// (Android, iOS, Web) should register their own implementation via
/// [VideoThumbnailPlatform.setInstance].
///
/// The MethodChannel communicates with native code using the following
/// contract:
///
/// ### openSession
/// Input: `{source: String}`
/// Output contains `nativeHandle`, optional `duration`, `nativeWidth`,
/// `nativeHeight` and optional `metadata`.
///
/// ### generateThumbnails
/// Input: `{sessionHandle: int, options: List<ThumbnailOptionsJson>}`
/// Output: `List<ThumbnailResultJson>`
///
/// ### closeSession
/// Input: `{sessionHandle: int}`
///
/// ### generateThumbnail
/// Input: `{source: String, options: ThumbnailOptionsJson}`
/// Output: `ThumbnailResultJson`
///
/// ### isFormatSupported
/// Input: `{mimeType: String}`
/// Output: `bool`
///
/// ### getVideoDuration
/// Input: `{source: String}`
/// Output: `int?` (milliseconds)
///
/// ### readThumbnailChunk
/// Input: `{path: String, offset: int, length?: int}`
/// Output: `Uint8List`
///
/// ### copyThumbnailFile
/// Input: `{sourcePath: String, targetPath: String}`
///
/// ### deleteThumbnailFile
/// Input: `{path: String}`
///
/// ### getThumbnailFileSize
/// Input: `{path: String}`
/// Output: `int`
///
/// ### ThumbnailResultJson
/// ```json
/// {
///   "width": int,
///   "height": int,
///   "format": "jpeg" | "png" | "webp",
///   "actualTimestamp": int,  // legacy normalized request in milliseconds
///   "effectiveTimestampUs": int?, // normalized request in microseconds, not
/// PTS
///   "backingType": "file" | "memory",
///   "tempPath": String?,     // for file backing
///   "bytes": Uint8List?      // for memory backing
/// }
/// ```
class MethodChannelVideoThumbnail extends VideoThumbnailPlatform {
  /// Creates a new MethodChannel implementation.
  MethodChannelVideoThumbnail() : super();
  final Expando<SessionOperationQueue> _queues = Expando();
  SessionOperationQueue _queue(VideoThumbnailSession session) =>
      _queues[session] ??= SessionOperationQueue(session.nativeHandle);

  static const MethodChannel _channel = MethodChannel(
    kLuxVideoThumbnailChannel,
  );

  @override
  Future<String> getPlatformVersion() async {
    try {
      final result = await _channel.invokeMethod<String>('getPlatformVersion');
      return result ?? 'Unknown';
    } on PlatformException {
      return 'Unknown';
    }
  }

  @override
  Future<VideoThumbnailSession> openSession(String source) async {
    ThumbnailLimits.source(source);
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      LuxVideoThumbnailMethods.openSession,
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
  }

  @override
  Future<List<VideoThumbnailResult>> generateThumbnails(
    VideoThumbnailSession session,
    List<ThumbnailOptions> optionsList,
  ) async {
    ThumbnailLimits.batch(optionsList.length);
    final acceptedOptions = List<ThumbnailOptions>.of(optionsList);
    return _queue(session).run(() async {
      for (final option in acceptedOptions) {
        option
          ..validateTimestamp(session.duration)
          ..dimensionsFor(session.nativeWidth, session.nativeHeight);
      }
      final optionsArgs = acceptedOptions.map((o) => o.toJson()).toList();
      final result = await _invokeTemporal<List<dynamic>>(
        LuxVideoThumbnailMethods.generateThumbnails,
        {'sessionHandle': session.nativeHandle, 'options': optionsArgs},
      );
      if (result == null) {
        throw SessionException(
          'Failed to generate thumbnails: null response',
          sessionHandle: session.nativeHandle,
        );
      }
      return result
          .map((r) => _parseResult(r as Map<dynamic, dynamic>))
          .toList();
    });
  }

  @override
  Future<void> closeSession(VideoThumbnailSession session) async {
    return _queue(session).close(() async {
      await _channel.invokeMethod(LuxVideoThumbnailMethods.closeSession, {
        'sessionHandle': session.nativeHandle,
      });
    });
  }

  @override
  Future<VideoThumbnailResult> generateThumbnail({
    required String source,
    required ThumbnailOptions options,
  }) async {
    ThumbnailLimits.source(source);
    options.validateTimestamp();
    final result = await _invokeTemporal<Map<dynamic, dynamic>>(
      LuxVideoThumbnailMethods.generateThumbnail,
      {'source': source, 'options': options.toJson()},
    );
    if (result == null) {
      throw GenerationFailedException(
        'Failed to generate thumbnail: null response',
        source: source,
      );
    }
    return _parseResult(result);
  }

  @override
  Future<bool> isFormatSupported(String mimeType) async {
    final result = await _channel.invokeMethod<bool>(
      LuxVideoThumbnailMethods.isFormatSupported,
      {'mimeType': mimeType},
    );
    return result ?? false;
  }

  @override
  Future<Duration?> getVideoDuration(String source) async {
    final result = await _channel.invokeMethod<int>(
      LuxVideoThumbnailMethods.getVideoDuration,
      {'source': source},
    );
    if (result == null || result <= 0) return null;
    return Duration(milliseconds: result);
  }

  /// Reads a chunk of bytes from a file-backed thumbnail.
  ///
  /// This is a low-level method exposed for advanced use cases.
  /// Most consumers should use [VideoThumbnailResult.readBytes] instead.
  static Future<Uint8List> readThumbnailChunk({
    required String path,
    required int offset,
    int? length,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      LuxVideoThumbnailMethods.readThumbnailChunk,
      {'path': path, 'offset': offset, if (length != null) 'length': length},
    );
    return result ?? Uint8List(0);
  }

  /// Copies a thumbnail temp file to a permanent location.
  static Future<void> copyThumbnailFile({
    required String sourcePath,
    required String targetPath,
  }) async {
    await _channel.invokeMethod(LuxVideoThumbnailMethods.copyThumbnailFile, {
      'sourcePath': sourcePath,
      'targetPath': targetPath,
    });
  }

  /// Deletes a thumbnail temp file.
  static Future<void> deleteThumbnailFile(String path) async {
    await _channel.invokeMethod(LuxVideoThumbnailMethods.deleteThumbnailFile, {
      'path': path,
    });
  }

  /// Gets the size of a thumbnail temp file in bytes.
  static Future<int> getThumbnailFileSize(String path) async {
    final result = await _channel.invokeMethod<int>(
      LuxVideoThumbnailMethods.getThumbnailFileSize,
      {'path': path},
    );
    return result ?? 0;
  }

  Future<T?> _invokeTemporal<T>(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      if (error.code != 'TIMESTAMP_OUT_OF_RANGE') rethrow;
      final details = error.details is Map
          ? error.details as Map<dynamic, dynamic>
          : const <dynamic, dynamic>{};
      throw TimestampOutOfRangeException(
        Duration(
          microseconds:
              details['requestedUs'] as int? ??
              (details['requestedMs'] as int? ?? 0) * 1000,
        ),
        videoDuration: details['durationMs'] == null
            ? null
            : Duration(milliseconds: details['durationMs'] as int),
        cause: error,
        code: error.code,
      );
    }
  }

  VideoThumbnailResult _parseResult(Map<dynamic, dynamic> data) {
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
}
