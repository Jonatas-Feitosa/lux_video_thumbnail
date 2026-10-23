import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_ios/lux_video_thumbnail_ios.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lux_video_thumbnail');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    LuxVideoThumbnailIOS.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'openSession' || 'openSessionFromBytes' => {
              'nativeHandle': 7,
              'duration': 2000,
              'nativeWidth': 64,
              'nativeHeight': 48,
            },
            'generateThumbnails' => [
              {
                'width': 32,
                'height': 24,
                'format': 'png',
                'actualTimestamp': 1234,
                'effectiveTimestampUs': 1234567,
                'tempPath': '/tmp/owned.png',
                'backingType': 'file',
              },
            ],
            'getThumbnailFileSize' => 4,
            'readThumbnailChunk' => Uint8List.fromList([137, 80, 78, 71]),
            _ => null,
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    VideoThumbnailPlatform.reset();
  });

  test('iOS registration uses the native method channel', () async {
    final platform = VideoThumbnailPlatform.instance;
    expect(platform, isA<MethodChannelVideoThumbnail>());
    final session = await platform.openSession('/tmp/video.mp4');
    final output = (await platform.generateThumbnails(session, [
      ThumbnailOptions(
        timestamp: const Duration(microseconds: 1234567),
        width: 32,
        format: ThumbnailFormat.png,
      ),
    ])).single;
    expect(output.actualTimestamp.inMicroseconds, 1234567);
    expect(await output.readBytes(), [137, 80, 78, 71]);
    await output.dispose();
    await platform.closeSession(session);
    expect(
      calls.map((call) => call.method),
      containsAllInOrder([
        'openSession',
        'generateThumbnails',
        'readThumbnailChunk',
        'deleteThumbnailFile',
        'closeSession',
      ]),
    );
  });

  test('byte source preserves MIME and typed data', () async {
    await VideoThumbnailPlatform.instance.openSessionFromBytes(
      Uint8List.fromList([1, 2, 3]),
      mimeType: 'video/quicktime',
    );
    expect(calls.single.method, 'openSessionFromBytes');
    expect(calls.single.arguments['mimeType'], 'video/quicktime');
    expect(calls.single.arguments['bytes'], [1, 2, 3]);
  });
}
