import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail_platform_interface.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockLuxVideoThumbnailPlatform
    with MockPlatformInterfaceMixin
    implements LuxVideoThumbnailPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final LuxVideoThumbnailPlatform initialPlatform =
      LuxVideoThumbnailPlatform.instance;

  test('$MethodChannelLuxVideoThumbnail is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelLuxVideoThumbnail>());
  });

  test('getPlatformVersion', () async {
    LuxVideoThumbnail luxVideoThumbnailPlugin = LuxVideoThumbnail();
    MockLuxVideoThumbnailPlatform fakePlatform =
        MockLuxVideoThumbnailPlatform();
    LuxVideoThumbnailPlatform.instance = fakePlatform;

    expect(await luxVideoThumbnailPlugin.getPlatformVersion(), '42');
  });
}
