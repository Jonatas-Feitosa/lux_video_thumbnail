import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lux_video_thumbnail_platform_interface.dart';

/// An implementation of [LuxVideoThumbnailPlatform] that uses method channels.
class MethodChannelLuxVideoThumbnail extends LuxVideoThumbnailPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('lux_video_thumbnail');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
