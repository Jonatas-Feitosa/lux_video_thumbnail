// exceptions.dart
// Exception hierarchy for lux_video_thumbnail.

/// Base exception for all video thumbnail errors.
abstract class VideoThumbnailException implements Exception {
  /// Creates an error with optional underlying cause and platform code.
  const VideoThumbnailException(this.message, {this.cause, this.code});

  /// Human-readable error message.
  final String message;

  /// Optional underlying cause.
  final Object? cause;

  /// Optional platform-specific error code.
  final String? code;

  @override
  String toString() =>
      'VideoThumbnailException: $message${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when the video format/codec is not supported on the current platform.
class UnsupportedFormatException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const UnsupportedFormatException(
    super.message, {
    this.format,
    super.cause,
    super.code,
  });

  /// The MIME type or format that is not supported.
  final String? format;

  @override
  String toString() =>
      'UnsupportedFormatException: $message'
      '${format != null ? ' (format: $format)' : ''}'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when the video source cannot be found or accessed.
class VideoNotFoundException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const VideoNotFoundException(this.source, {super.cause, super.code})
    : super('Video not found: $source');

  /// The source path/URL that was not found.
  final String source;

  @override
  String toString() =>
      'VideoNotFoundException: $source'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when the current platform is not supported.
class PlatformNotSupportedException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const PlatformNotSupportedException(this.platform, {super.cause, super.code})
    : super('Platform not supported: $platform');

  /// The unsupported platform name.
  final String platform;

  @override
  String toString() =>
      'PlatformNotSupportedException: $platform'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when the video source is inaccessible due to permissions.
class PermissionDeniedException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const PermissionDeniedException(this.source, {super.cause, super.code})
    : super('Permission denied accessing: $source');

  /// The source that requires permission.
  final String source;

  @override
  String toString() =>
      'PermissionDeniedException: $source'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when the timestamp is outside the video duration.
class TimestampOutOfRangeException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  TimestampOutOfRangeException(
    this.requested, {
    this.videoDuration,
    super.cause,
    super.code,
  }) : super(
         'Timestamp out of range: ${requested.inMilliseconds}ms'
         '${_durationSuffix(videoDuration, 'video duration')}',
       );

  /// The requested timestamp.
  final Duration requested;

  /// The video duration (if known).
  final Duration? videoDuration;

  @override
  String toString() =>
      'TimestampOutOfRangeException: ${requested.inMilliseconds}ms'
      '${_durationSuffix(videoDuration, 'video')}'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when thumbnail generation fails due to platform-specific errors.
class GenerationFailedException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const GenerationFailedException(
    String message, {
    required this.source,
    this.timestamp,
    super.cause,
    super.code,
  }) : super('Generation failed for $source: $message');

  /// The source that failed to generate.
  final String source;

  /// The timestamp that was being generated (if applicable).
  final Duration? timestamp;

  @override
  String toString() =>
      'GenerationFailedException: $source'
      '${timestamp != null ? ' at ${timestamp!.inMilliseconds}ms' : ''}'
      ' - $message'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when a session operation fails (open/close/generate).
class SessionException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const SessionException(
    String message, {
    required this.sessionHandle,
    super.cause,
    super.code,
  }) : super('Session $sessionHandle error: $message');

  /// The session handle that failed.
  final int sessionHandle;

  @override
  String toString() =>
      'SessionException: handle=$sessionHandle - $message'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when CORS policy blocks access to a remote video (Web only).
class CorsException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const CorsException(this.url, {super.cause, super.code})
    : super('CORS blocked access to: $url');

  /// The URL that was blocked by CORS.
  final String url;

  @override
  String toString() =>
      'CorsException: $url'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when the video duration cannot be determined.
class DurationUnknownException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const DurationUnknownException(this.source, {super.cause, super.code})
    : super('Cannot determine duration of: $source');

  /// Source whose duration could not be determined.
  final String source;

  @override
  String toString() =>
      'DurationUnknownException: $source'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

/// Thrown when CORS policy blocks canvas access to video frames.
///
/// This typically happens when a video is loaded from a different origin
/// without proper CORS headers, causing the canvas to become "tainted"
/// and preventing pixel data extraction via toBlob().
class CorsBlockedException extends VideoThumbnailException {
  /// Creates an error with optional underlying cause and platform code.
  const CorsBlockedException(this.url, {super.cause, super.code})
    : super('CORS blocked canvas access to: $url');

  /// The URL that was blocked by CORS policy.
  final String url;

  @override
  String toString() =>
      'CorsBlockedException: $url'
      '${code != null ? ' (code: $code)' : ''}'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}

String _durationSuffix(Duration? duration, String label) =>
    duration == null ? '' : ' ($label: ${duration.inMilliseconds}ms)';
