/// Resource ceilings shared by the public API and platform implementations.
abstract final class ThumbnailLimits {
  /// Maximum width or height, including decoded source metadata.
  static const maxDimension = 4096;

  /// Maximum image pixel count.
  static const maxPixels = 16777216;

  /// Maximum in-memory video source size (64 MiB).
  static const maxVideoBytes = 64 * 1024 * 1024;

  /// Maximum encoded image or read chunk size (8 MiB).
  static const maxThumbnailBytes = 8 * 1024 * 1024;

  /// Maximum thumbnails generated in one batch.
  static const maxBatchSize = 16;

  /// Maximum simultaneous decoder sessions per backend.
  static const maxSessions = 4;

  /// Maximum active and waiting operations per session queue.
  static const maxPendingOperations = 16;

  /// Largest microsecond position exactly representable by JavaScript integers.
  static const maxTimestampUs = 9007199254740991;

  /// Rejects invalid or oversized image geometry.
  static void dimensions(int width, int height) {
    if (width < 1 ||
        height < 1 ||
        width > maxDimension ||
        height > maxDimension ||
        width * height > maxPixels) {
      throw ArgumentError('Thumbnail dimensions exceed resource limits');
    }
  }

  /// Checks the byte-source ceiling before making bridge/Blob copies.
  static void videoBytes(int length) {
    if (length < 1 || length > maxVideoBytes) {
      throw ArgumentError('Video bytes must be 1–64 MiB');
    }
  }

  /// Rejects empty and oversized generation batches.
  static void batch(int length) {
    if (length < 1 || length > maxBatchSize) {
      throw ArgumentError('Batch must contain 1–16 options');
    }
  }

  /// Validates a byte range; a requested length may extend to EOF.
  static void range(int offset, int? length, [int? size]) {
    if (offset < 0 ||
        offset > maxTimestampUs ||
        (size != null && offset > size) ||
        (length != null && (length < 0 || length > maxThumbnailBytes))) {
      throw RangeError('Invalid thumbnail byte range');
    }
  }

  /// Rejects empty, oversized and NUL-containing source identifiers.
  static void source(String value) {
    if (value.trim().isEmpty ||
        value.length > 16384 ||
        value.contains('\u0000')) {
      throw ArgumentError('Invalid video source');
    }
  }

  /// Validates the MIME type used for an in-memory video source.
  static void mimeType(String value) {
    if (value.length > 128 ||
        !RegExp(r'^video/[a-zA-Z0-9.+-]+$').hasMatch(value)) {
      throw ArgumentError('Expected a video MIME type');
    }
  }
}
