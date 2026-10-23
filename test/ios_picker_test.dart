import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail/src/picking/pick_video_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // FilePickerIO selects its codec from the actual test host OS.
  const channel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
    JSONMethodCodec(),
  );
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FilePickerIO.registerWith();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'iOS picker requests a video path without copying bytes over channel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'video');
            expect(call.arguments['withData'], isFalse);
            return [
              {'name': 'clip.mov', 'path': '/tmp/clip.mov', 'size': 20},
            ];
          });
      final picked = await pickVideo();
      expect(picked!.source.location, '/tmp/clip.mov');
    },
  );

  test('iOS picker cancellation returns no video', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    expect(await pickVideo(), isNull);
  });
}
