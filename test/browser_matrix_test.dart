@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail/src/picking/pick_video_web.dart' as picker;
import 'package:lux_video_thumbnail/src/picking/picked_video.dart';
import 'package:lux_video_thumbnail_web/lux_video_thumbnail_web.dart';
import 'package:web/web.dart' as web;
import 'fixtures/format_fixtures.dart';
import 'fixtures/video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => LuxVideoThumbnailWeb.registerWith());
  const allowed = 'http://127.0.0.1:18761';
  const blocked = 'http://127.0.0.1:18762';
  test('reports actual compiler and browser', () {
    debugPrint(
      'WEB_MATRIX wasm=$kIsWasm browser=${web.window.navigator.userAgent}',
    );
    expect(kIsWasm, const bool.fromEnvironment('EXPECT_WASM'));
  });
  for (final fixture in {
    'mp4': redBlueMp4Base64,
    'vp8': redBlueVideoBase64,
    'vp9': redBlueVp9Base64,
    'live-webm': redBlueLiveBase64,
  }.entries) {
    test(
      '${fixture.key}: decode real image, scale and output format',
      () async {
        for (final format in ThumbnailFormat.values) {
          final image = await LuxVideoThumbnail.generate(
            source: VideoSource.bytes(
              base64Decode(fixture.value),
              mimeType: fixture.key == 'mp4' ? 'video/mp4' : 'video/webm',
            ),
            timestamp: const Duration(milliseconds: 1500),
            height: 24,
            format: format,
          );
          expect(image.width, 32);
          expect(image.height, 24);
          final codec = await ui.instantiateImageCodec(image.bytes);
          final frame = await codec.getNextFrame();
          final rgba = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba!.getUint8(2), greaterThan(180));
          expect(rgba.getUint8(0), lessThan(60));
          frame.image.dispose();
          codec.dispose();
          switch (image.format) {
            case ThumbnailFormat.png:
              expect(image.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
            case ThumbnailFormat.jpeg:
              expect(image.bytes.take(2), [255, 216]);
            case ThumbnailFormat.webp:
              expect(ascii.decode(image.bytes.sublist(8, 12)), 'WEBP');
          }
        }
      },
    );
  }
  test(
    'corrupt and incompatible input fail and later valid source recovers',
    () async {
      for (final bytes in [
        Uint8List.fromList([1, 2, 3, 4]),
        Uint8List.fromList(utf8.encode('<html>not a video</html>')),
      ]) {
        await expectLater(
          LuxVideoThumbnail.generate(
            source: VideoSource.bytes(bytes, mimeType: 'video/mp4'),
            timestamp: Duration.zero,
          ),
          throwsA(isA<VideoThumbnailException>()),
        );
      }
      expect(
        (await LuxVideoThumbnail.generate(
          source: VideoSource.bytes(
            base64Decode(redBlueVideoBase64),
            mimeType: 'video/webm',
          ),
          timestamp: Duration.zero,
        )).bytes,
        isNotEmpty,
      );
    },
  );
  test(
    'remote allowed origin supports seek and keeps caller URL usable',
    () async {
      final result = await LuxVideoThumbnail.generate(
        source: VideoSource.url('$allowed/red_blue.mp4'),
        timestamp: const Duration(milliseconds: 1500),
      );
      expect(result.width, 320);
      expect(
        (await web.window.fetch('$allowed/red_blue.mp4'.toJS).toDart).status,
        200,
      );
    },
  );
  test(
    'blocked CORS, HTTP missing and disconnected sources fail without claiming CORS',
    () async {
      for (final url in [
        '$blocked/red_blue.mp4',
        '$allowed/missing?token=private',
        '$allowed/disconnect',
      ]) {
        await expectLater(
          LuxVideoThumbnail.generate(
            source: VideoSource.url(url),
            timestamp: Duration.zero,
          ),
          throwsA(
            allOf(
              isA<VideoThumbnailException>(),
              isNot(isA<CorsBlockedException>()),
              isNot(isA<CorsException>()),
            ),
          ),
        );
      }
    },
  );
  test(
    'stalled source times out and manager can be disposed repeatedly',
    () async {
      final manager = VideoElementManager(source: '$allowed/stall');
      final pending = manager.waitForMetadata();
      manager.load();
      try {
        await expectLater(pending, throwsA(isA<TimeoutException>()));
      } finally {
        manager.dispose();
        manager.dispose();
      }
      expect(manager.video.getAttribute('src'), isNull);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
  test(
    'disposing while loading interrupts wait without waiting for timeout',
    () async {
      final manager = VideoElementManager(source: '$allowed/stall');
      final pending = manager.waitForMetadata();
      manager.load();
      final assertion = expectLater(pending, throwsStateError);
      manager.dispose();
      await assertion;
    },
  );
  test(
    'focus does not cancel slow valid selection; repeated large file releases URLs',
    () async {
      for (var i = 0; i < 4; i++) {
        final pending = picker.pickVideo();
        final input =
            web.document.querySelector('input[type=file]')!
                as web.HTMLInputElement;
        web.window.dispatchEvent(web.Event('focus'));
        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(
          web.document.querySelector('input[type=file]')!.isSameNode(input),
          isTrue,
        );
        final transfer = web.DataTransfer();
        transfer.items.add(
          web.File(
            <web.BlobPart>[
              base64Decode(redBlueMp4Base64).toJS,
              Uint8List(16 * 1024 * 1024).toJS,
            ].toJS,
            'large.mp4',
            web.FilePropertyBag(type: 'video/mp4'),
          ),
        );
        input.files = transfer.files;
        input.dispatchEvent(web.Event('change'));
        final picked = (await pending)!;
        expect(
          (await LuxVideoThumbnail.generate(
            source: picked.source,
            timestamp: Duration.zero,
          )).bytes,
          isNotEmpty,
        );
        await picked.dispose();
        await picked.dispose();
        expect(web.document.querySelector('input[type=file]'), isNull);
        await expectLater(
          web.window.fetch(picked.source.location!.toJS).toDart,
          throwsA(anything),
        );
        final cancellation = PickerCancellation();
        final cancelled = picker.pickVideo(cancellation: cancellation);
        cancellation.cancel();
        expect(await cancelled, isNull);
      }
    },
  );
  testWidgets('remote failure UI does not expose signed URL parameters', (
    tester,
  ) async {
    final errors = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: VideoThumbnailPicker(
          initialSource: VideoSource.url('$allowed/missing?token=private'),
          onError: errors.add,
          onChanged: (_) {},
        ),
      ),
    );
    for (var i = 0; i < 100 && errors.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(errors, isNotEmpty);
    expect(find.textContaining('private'), findsNothing);
    expect(find.textContaining('token='), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
