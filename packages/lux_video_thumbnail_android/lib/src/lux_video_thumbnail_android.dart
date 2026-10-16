import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

/// Android implementation of the lux_video_thumbnail plugin.
///
/// The Android plugin communicates via MethodChannel to the native
/// `LuxVideoThumbnailPlugin` Kotlin class which uses MediaMetadataRetriever
/// for video frame extraction.
///
/// This class serves as the Dart-side registration entry point for the
/// Android platform. When the app runs on Android, Flutter's
/// GeneratedPluginRegistrant will call [registerWith], which sets the
/// platform interface instance to use the MethodChannel implementation
/// that communicates with the native Kotlin plugin.
///
/// The plugin is automatically registered when you depend on
/// `lux_video_thumbnail_android` in your app's pubspec.yaml.
class LuxVideoThumbnailAndroid {
  /// Registers the Android implementation with the platform interface.
  ///
  /// This sets [VideoThumbnailPlatform.instance] to a
  /// [MethodChannelVideoThumbnail] that delegates to the native Android
  /// plugin via the 'lux_video_thumbnail' MethodChannel.
  ///
  /// The optional [registrar] parameter is accepted for compatibility with
  /// Flutter's plugin registration system but is not used.
  static void registerWith([dynamic registrar]) {
    VideoThumbnailPlatform.setInstance(MethodChannelVideoThumbnail());
  }
}
