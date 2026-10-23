import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

/// iOS registration helper. Native registration uses Flutter's generated
/// registrant; the platform interface also defaults to the same method channel.
class LuxVideoThumbnailIOS {
  /// Registers the shared method channel implementation.
  static void registerWith() {
    VideoThumbnailPlatform.setInstance(MethodChannelVideoThumbnail());
  }
}
