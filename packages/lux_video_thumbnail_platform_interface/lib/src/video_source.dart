import 'dart:typed_data';
import 'package:lux_video_thumbnail_platform_interface/src/thumbnail_limits.dart';

/// The kind of input supplied to the video decoder.
enum VideoSourceType {
  /// An in-memory video buffer.
  bytes,

  /// A borrowed native path or Android content URI.
  path,

  /// A remote HTTP(S) or browser Blob URL.
  url,
}

/// A video input, independent of browser and filesystem APIs.
///
/// Caller-owned paths are borrowed and are never deleted by the plugin.
class VideoSource {
  const VideoSource._(this.type, this.location, this.data, this.mimeType);

  /// Uses video bytes. Do not modify [data] while decoding is in progress.
  factory VideoSource.bytes(Uint8List data, {required String mimeType}) {
    ThumbnailLimits.videoBytes(data.length);
    ThumbnailLimits.mimeType(mimeType);
    if (data.isEmpty) {
      throw ArgumentError.value(data.length, 'data', 'Empty video');
    }
    if (!mimeType.startsWith('video/')) {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'Expected a video MIME type',
      );
    }
    return VideoSource._(VideoSourceType.bytes, null, data, mimeType);
  }

  /// Uses a native file path or Android content URI. Not supported on web.
  factory VideoSource.path(String path) {
    ThumbnailLimits.source(path);
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path');
    return VideoSource._(VideoSourceType.path, path, null, null);
  }

  /// Uses HTTP(S), or a browser Blob URL owned by the caller.
  /// Remote web videos must allow cross-origin frame access through CORS.
  factory VideoSource.url(String url) {
    ThumbnailLimits.source(url);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https', 'blob'].contains(uri.scheme) ||
        (uri.scheme != 'blob' && uri.host.isEmpty)) {
      throw ArgumentError.value(url, 'url', 'Expected an HTTP(S) or Blob URL');
    }
    return VideoSource._(VideoSourceType.url, url, null, null);
  }

  /// Input representation.
  final VideoSourceType type;

  /// A borrowed path or URL, when applicable.
  final String? location;

  /// Caller-supplied bytes, when applicable.
  final Uint8List? data;

  /// MIME type of the byte input.
  final String? mimeType;
}
