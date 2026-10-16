import 'package:flutter/foundation.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'lux_video_thumbnail_platform_interface.dart' as legacy;
import 'src/thumbnail_data.dart';
import 'src/thumbnail_session.dart';

export 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart'
    show
        ThumbnailLimits,
        VideoSource,
        VideoSourceType,
        ThumbnailFormat,
        VideoThumbnailException,
        UnsupportedFormatException,
        VideoNotFoundException,
        PlatformNotSupportedException,
        PermissionDeniedException,
        TimestampOutOfRangeException,
        GenerationFailedException,
        SessionException,
        CorsException,
        CorsBlockedException,
        DurationUnknownException;
export 'src/thumbnail_data.dart';
export 'src/video_thumbnail_picker.dart';
export 'src/video_thumbnail_dialog.dart';

/// Generates video thumbnails on Android and web.
class LuxVideoThumbnail {
  /// Generates an image and releases the decoder and intermediate temporaries.
  /// Caller-owned video files and Blob URLs remain owned by the caller.
  static Future<VideoThumbnailData> generate({
    required VideoSource source,
    required Duration timestamp,
    int? width = 320,
    int? height,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int quality = 85,
    bool maintainAspectRatio = true,
  }) async {
    // Runtime validation is required even when Dart assertions are disabled.
    if (timestamp < Duration.zero || quality < 1 || quality > 100) {
      throw ArgumentError('Invalid timestamp or quality');
    }
    final options = ThumbnailOptions(
      timestamp: timestamp,
      width: width,
      height: height,
      format: format,
      quality: quality,
      maintainAspectRatio: maintainAspectRatio,
    );
    ThumbnailSession.validateOptions(options);
    final session = await ThumbnailSession.open(source);
    try {
      return await session.generate(options);
    } finally {
      await session.close();
    }
  }

  /// Legacy platform-version query retained for compatibility.
  Future<String?> getPlatformVersion() {
    if (kIsWeb) return VideoThumbnailPlatform.instance.getPlatformVersion();
    return legacy.LuxVideoThumbnailPlatform.instance.getPlatformVersion();
  }
}
