import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'lux_video_thumbnail_method_channel.dart';

abstract class LuxVideoThumbnailPlatform extends PlatformInterface {
  /// Constructs a LuxVideoThumbnailPlatform.
  LuxVideoThumbnailPlatform() : super(token: _token);

  static final Object _token = Object();

  static LuxVideoThumbnailPlatform _instance = MethodChannelLuxVideoThumbnail();

  /// The default instance of [LuxVideoThumbnailPlatform] to use.
  ///
  /// Defaults to [MethodChannelLuxVideoThumbnail].
  static LuxVideoThumbnailPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LuxVideoThumbnailPlatform] when
  /// they register themselves.
  static set instance(LuxVideoThumbnailPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
