import 'dart:typed_data';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

/// An image that remains usable after the decoder session has been released.
class VideoThumbnailData {
  /// Copies the encoded image into a caller-owned, browser-compatible buffer.
  VideoThumbnailData({
    required Uint8List bytes,
    required this.timestamp,
    required this.width,
    required this.height,
    required this.format,
  }) : bytes = Uint8List.fromList(bytes);

  /// Encoded image, suitable for Image.memory or uploading.
  final Uint8List bytes;

  /// Requested video position, not a measurement of the decoded frame's PTS.
  /// The selected frame depends on the platform decoder and video frame rate.
  final Duration timestamp;

  /// Encoded image width in pixels.
  final int width;

  /// Encoded image height in pixels.
  final int height;

  /// Actual encoded output format.
  final ThumbnailFormat format;
}
