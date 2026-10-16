// models.dart
// Core models for lux_video_thumbnail platform interface.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lux_video_thumbnail_platform_interface/src/exceptions.dart';
import 'package:lux_video_thumbnail_platform_interface/src/saving/save_file_stub.dart'
    if (dart.library.io) 'package:lux_video_thumbnail_platform_interface/src/saving/save_file_io.dart'
    as saving;
import 'package:lux_video_thumbnail_platform_interface/src/thumbnail_limits.dart';

/// Supported thumbnail output formats.
enum ThumbnailFormat {
  /// JPEG format (lossy, good compression)
  jpeg,

  /// PNG format (lossless, transparency support)
  png,

  /// WebP format (lossy/lossless, good compression)
  webp;

  /// MIME type for this format.
  String get mimeType => switch (this) {
    ThumbnailFormat.jpeg => 'image/jpeg',
    ThumbnailFormat.png => 'image/png',
    ThumbnailFormat.webp => 'image/webp',
  };

  /// File extension for this format.
  String get fileExtension => switch (this) {
    ThumbnailFormat.jpeg => 'jpg',
    ThumbnailFormat.png => 'png',
    ThumbnailFormat.webp => 'webp',
  };
}

/// Configuration options for thumbnail generation.
@immutable
class ThumbnailOptions {
  /// Creates validated extraction options.
  ThumbnailOptions({
    required this.timestamp,
    this.width,
    this.height,
    this.format = ThumbnailFormat.jpeg,
    this.quality = 85,
    this.maintainAspectRatio = true,
    this.preferKeyFrame = false,
  }) {
    validateTimestamp();
  }

  /// Creates options for a keyframe thumbnail (faster, approximate timestamp).
  ThumbnailOptions.keyFrame({
    required this.timestamp,
    this.width,
    this.height,
    this.format = ThumbnailFormat.jpeg,
    this.quality = 85,
    this.maintainAspectRatio = true,
    this.preferKeyFrame = true,
  }) {
    validateTimestamp();
  }

  /// The timestamp in the video from which to capture the thumbnail.
  final Duration timestamp;

  /// Desired width of the output thumbnail. If null, uses video's native width
  /// or maintains aspect ratio based on [height].
  final int? width;

  /// Desired height of the output thumbnail. If null, uses video's native
  /// height
  /// or maintains aspect ratio based on [width].
  final int? height;

  /// Output format of the thumbnail.
  final ThumbnailFormat format;

  /// Quality for lossy formats (jpeg, webp). Range: 1-100.
  /// Ignored for png.
  final int quality;

  /// If true, maintains the video's aspect ratio when both width and height
  /// are specified. The resulting thumbnail will fit within the specified
  /// dimensions.
  final bool maintainAspectRatio;

  /// Requests a nearby keyframe instead of the nearest decoded frame.
  /// This is a speed hint, not a guarantee of the frame's exact timestamp.
  /// Web uses the browser's ordinary seek; keyframe preference is a native
  /// hint.
  final bool preferKeyFrame;

  /// Checks generation options and timeline bounds, including release builds.
  /// An unknown duration never clamps a nonnegative timestamp to zero.
  void validateTimestamp([Duration? duration]) {
    if (quality < 1 || quality > 100) {
      throw ArgumentError('Quality must be 1 to 100');
    }
    for (final value in [width, height]) {
      if (value != null &&
          (value < 1 || value > ThumbnailLimits.maxDimension)) {
        throw ArgumentError('Dimensions must be 1 to 4096');
      }
    }
    if (timestamp.inMicroseconds > ThumbnailLimits.maxTimestampUs) {
      throw ArgumentError('Timestamp exceeds the supported integer range');
    }
    if (timestamp < Duration.zero) throw ArgumentError('Negative timestamp');
    if (duration != null && duration > Duration.zero && timestamp > duration) {
      throw TimestampOutOfRangeException(timestamp, videoDuration: duration);
    }
  }

  /// Resolves and validates output geometry before seeking or allocating a
  /// canvas.
  ({int width, int height}) dimensionsFor(int nativeWidth, int nativeHeight) {
    validateTimestamp();
    ThumbnailLimits.dimensions(nativeWidth, nativeHeight);
    var outputWidth = width ?? nativeWidth;
    var outputHeight = height ?? nativeHeight;
    final aspect = nativeWidth / nativeHeight;
    if (width == null && height != null) {
      outputWidth = (outputHeight * aspect).round();
    } else if (height == null && width != null) {
      outputHeight = (outputWidth / aspect).round();
    } else if (maintainAspectRatio && width != null && height != null) {
      if (outputWidth / outputHeight > aspect) {
        outputWidth = (outputHeight * aspect).round();
      } else {
        outputHeight = (outputWidth / aspect).round();
      }
    }
    if (outputWidth < 1) outputWidth = 1;
    if (outputHeight < 1) outputHeight = 1;
    ThumbnailLimits.dimensions(outputWidth, outputHeight);
    return (width: outputWidth, height: outputHeight);
  }

  /// Copies options, replacing the specified values.
  ThumbnailOptions copyWith({
    Duration? timestamp,
    int? width,
    int? height,
    ThumbnailFormat? format,
    int? quality,
    bool? maintainAspectRatio,
    bool? preferKeyFrame,
  }) {
    return ThumbnailOptions(
      timestamp: timestamp ?? this.timestamp,
      width: width ?? this.width,
      height: height ?? this.height,
      format: format ?? this.format,
      quality: quality ?? this.quality,
      maintainAspectRatio: maintainAspectRatio ?? this.maintainAspectRatio,
      preferKeyFrame: preferKeyFrame ?? this.preferKeyFrame,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThumbnailOptions &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          width == other.width &&
          height == other.height &&
          format == other.format &&
          quality == other.quality &&
          maintainAspectRatio == other.maintainAspectRatio &&
          preferKeyFrame == other.preferKeyFrame;

  @override
  int get hashCode => Object.hash(
    timestamp,
    width,
    height,
    format,
    quality,
    maintainAspectRatio,
    preferKeyFrame,
  );

  @override
  String toString() =>
      'ThumbnailOptions(timestamp: $timestamp, ${width}x$height, '
      'format: $format, quality: $quality, '
      'maintainAspectRatio: $maintainAspectRatio, '
      'preferKeyFrame: $preferKeyFrame)';
}

/// Opaque handle representing an open video session for batch thumbnail
/// generation.
@immutable
class VideoThumbnailSession {
  const VideoThumbnailSession._({
    required this.nativeHandle,
    required this.source,
    required this.nativeWidth,
    required this.nativeHeight,
    this.duration,
    this.metadata,
  });

  /// Creates a session from platform-specific data.
  factory VideoThumbnailSession.fromPlatformData({
    required int nativeHandle,
    required String source,
    required int nativeWidth,
    required int nativeHeight,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return VideoThumbnailSession._(
      nativeHandle: nativeHandle,
      source: source,
      duration: duration != null && duration > Duration.zero ? duration : null,
      nativeWidth: nativeWidth,
      nativeHeight: nativeHeight,
      metadata: metadata,
    );
  }

  /// Platform-specific opaque handle.
  final int nativeHandle;

  /// Source identifier (path or URL) this session was opened for.
  final String source;

  /// Duration of the video, if detected during session opening.
  final Duration? duration;

  /// Native video width in pixels.
  final int nativeWidth;

  /// Native video height in pixels.
  final int nativeHeight;

  /// Optional metadata map for platform-specific data.
  final Map<String, dynamic>? metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoThumbnailSession &&
          runtimeType == other.runtimeType &&
          nativeHandle == other.nativeHandle &&
          source == other.source;

  @override
  int get hashCode => Object.hash(nativeHandle, source);

  @override
  String toString() =>
      'VideoThumbnailSession(handle: $nativeHandle, source: $source, '
      'duration: $duration, ${nativeWidth}x$nativeHeight)';
}

/// Abstract result of a thumbnail generation operation.
///
/// Supports two internal backing strategies:
/// - File-based (Android/iOS): temporary native file, streamed on demand
/// - Memory-based (Web): Uint8List buffer from canvas.toBlob()
abstract class VideoThumbnailResult {
  /// Creates result metadata; concrete results own the underlying storage.
  const VideoThumbnailResult({
    required this.width,
    required this.height,
    required this.format,
    required this.actualTimestamp,
  });

  /// Width of the generated thumbnail in pixels.
  final int width;

  /// Height of the generated thumbnail in pixels.
  final int height;

  /// Format of the generated thumbnail.
  final ThumbnailFormat format;

  /// Normalized requested position; this historical field is not a measured
  /// PTS.
  // Concrete results preserve the normalized request, not a decoder PTS.
  final Duration actualTimestamp;

  /// Reads a chunk of bytes from the thumbnail.
  ///
  /// [offset] - Byte offset to start reading from (default: 0)
  /// [length] - Number of bytes to read (default: remaining bytes)
  ///
  /// Returns the requested byte range. Useful for streaming large thumbnails
  /// without loading the entire image into memory.
  Future<Uint8List> readBytes({int offset = 0, int? length});

  /// Saves the thumbnail to a permanent file accessible by the application.
  ///
  /// [directory] - Target directory (default: system temp directory)
  /// [fileName] - Custom file name (default: auto-generated with timestamp)
  ///
  /// Returns the saved path. Native only; web throws [UnsupportedError].
  /// A new private subdirectory prevents overwriting existing files.
  /// The caller owns the saved file and its parent directory.
  Future<String> saveToFile({String? directory, String? fileName});

  /// Releases native resources associated with this result.
  ///
  /// For file-backed results, deletes the temporary native file.
  /// For memory-backed results, clears the internal buffer.
  /// After disposal, [readBytes] and [saveToFile] will throw [StateError].
  Future<void> dispose();

  /// Whether the thumbnail data is held in memory (Web) vs native temp file
  /// (Android/iOS).
  bool get isInMemory;

  /// Total size of the thumbnail in bytes.
  Future<int> get length;

  /// Creates a file-backed result (Android/iOS implementation).
  static VideoThumbnailResult file({
    required int width,
    required int height,
    required ThumbnailFormat format,
    required Duration actualTimestamp,
    required String nativeTempPath,
    required MethodChannel channel,
  }) => FileBackedResult(
    width: width,
    height: height,
    format: format,
    actualTimestamp: actualTimestamp,
    nativeTempPath: nativeTempPath,
    channel: channel,
  );

  /// Creates a memory-backed result (Web implementation).
  static VideoThumbnailResult memory({
    required int width,
    required int height,
    required ThumbnailFormat format,
    required Duration actualTimestamp,
    required Uint8List bytes,
  }) => MemoryBackedResult(
    width: width,
    height: height,
    format: format,
    actualTimestamp: actualTimestamp,
    bytes: bytes,
  );
}

/// File-backed thumbnail result (Android/iOS).
class FileBackedResult implements VideoThumbnailResult {
  /// Creates a result backed by a plugin-owned native temporary.
  FileBackedResult({
    required this.width,
    required this.height,
    required this.format,
    required this.actualTimestamp,
    required String nativeTempPath,
    required MethodChannel channel,
  }) : _nativeTempPath = nativeTempPath,
       _channel = channel;
  @override
  final int width;

  @override
  final int height;

  @override
  final ThumbnailFormat format;

  @override
  // Concrete results preserve the normalized request, not a decoder PTS.
  final Duration actualTimestamp;

  final String _nativeTempPath;
  final MethodChannel _channel;
  bool _disposed = false;

  @override
  bool get isInMemory => false;

  @override
  Future<Uint8List> readBytes({int offset = 0, int? length}) async {
    if (_disposed) {
      throw StateError('Thumbnail has been disposed');
    }
    ThumbnailLimits.range(offset, length);
    final args = <String, dynamic>{'path': _nativeTempPath, 'offset': offset};
    if (length != null) {
      args['length'] = length;
    }
    final result = await _channel.invokeMethod<Uint8List>(
      'readThumbnailChunk',
      args,
    );
    return result ?? Uint8List(0);
  }

  @override
  Future<String> saveToFile({String? directory, String? fileName}) async {
    if (_disposed) {
      throw StateError('Thumbnail has been disposed');
    }
    return saving.saveFile(
      await readBytes(),
      directory: directory,
      fileName: fileName,
      extension: format.fileExtension,
    );
  }

  @override
  Future<void> dispose() async {
    if (!_disposed) {
      _disposed = true;
      await _channel.invokeMethod('deleteThumbnailFile', {
        'path': _nativeTempPath,
      });
    }
  }

  @override
  Future<int> get length async {
    if (_disposed) {
      throw StateError('Thumbnail has been disposed');
    }
    final result = await _channel.invokeMethod<int>('getThumbnailFileSize', {
      'path': _nativeTempPath,
    });
    return result ?? 0;
  }
}

/// Memory-backed thumbnail result (Web).
class MemoryBackedResult implements VideoThumbnailResult {
  /// Creates a bounded in-memory image result.
  MemoryBackedResult({
    required this.width,
    required this.height,
    required this.format,
    required this.actualTimestamp,
    required Uint8List bytes,
  }) : _bytes = bytes {
    ThumbnailLimits.dimensions(width, height);
    if (bytes.length > ThumbnailLimits.maxThumbnailBytes) {
      throw ArgumentError('Encoded thumbnail exceeds 8 MiB');
    }
  }
  @override
  final int width;

  @override
  final int height;

  @override
  final ThumbnailFormat format;

  @override
  // Concrete results preserve the normalized request, not a decoder PTS.
  final Duration actualTimestamp;

  Uint8List _bytes;
  bool _disposed = false;

  @override
  bool get isInMemory => true;

  @override
  Future<Uint8List> readBytes({int offset = 0, int? length}) async {
    if (_disposed) {
      throw StateError('Thumbnail has been disposed');
    }
    ThumbnailLimits.range(offset, length, _bytes.length);
    final end = length != null ? offset + length : _bytes.length;
    final clampedEnd = end.clamp(0, _bytes.length);
    final clampedOffset = offset.clamp(0, _bytes.length);
    if (clampedOffset >= clampedEnd) {
      return Uint8List(0);
    }
    return _bytes.sublist(clampedOffset, clampedEnd);
  }

  @override
  Future<String> saveToFile({String? directory, String? fileName}) async {
    if (_disposed) {
      throw StateError('Thumbnail has been disposed');
    }
    return saving.saveFile(
      _bytes,
      directory: directory,
      fileName: fileName,
      extension: format.fileExtension,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _bytes = Uint8List(0);
  }

  @override
  Future<int> get length async {
    if (_disposed) throw StateError('Thumbnail has been disposed');
    return _bytes.length;
  }
}
