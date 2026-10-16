@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail/src/picking/pick_video_web.dart' as picker;
import 'package:lux_video_thumbnail/src/picking/picked_video.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'package:lux_video_thumbnail_web/lux_video_thumbnail_web.dart';
import 'package:web/web.dart' as web;
import 'fixtures/video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = base64Decode(redBlueVideoBase64);
  setUp(() => LuxVideoThumbnailWeb.registerWith());

  Future<List<int>> pixel(VideoThumbnailData data) async {
    final codec = await ui.instantiateImageCodec(data.bytes);
    final frame = await codec.getNextFrame();
    try {
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return pixels!.buffer.asUint8List().take(4).toList();
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  }

  test(
    'real video bytes produce red frame zero and blue frame at 1.5s',
    () async {
      final source = VideoSource.bytes(
        bytes.asUnmodifiableView(),
        mimeType: 'video/webm',
      );
      final red = await LuxVideoThumbnail.generate(
        source: source,
        timestamp: Duration.zero,
        width: 32,
        format: ThumbnailFormat.png,
      );
      expect(red.width, 32);
      expect(red.height, 24);
      expect(red.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final redPixel = await pixel(red);
      expect(redPixel[0], greaterThan(200));
      expect(redPixel[2], lessThan(40));
      final blue = await LuxVideoThumbnail.generate(
        source: source,
        timestamp: const Duration(milliseconds: 1500),
        format: ThumbnailFormat.jpeg,
      );
      expect(blue.bytes.take(2), [255, 216]);
      final bluePixel = await pixel(blue);
      expect(bluePixel[2], greaterThan(200));
      expect(bluePixel[0], lessThan(40));
    },
  );

  test('parallel seeks in one real browser session remain ordered', () async {
    final platform = VideoThumbnailPlatform.instance;
    final session = await platform.openSessionFromBytes(
      bytes,
      mimeType: 'video/webm',
    );
    try {
      final batches = await Future.wait([
        platform.generateThumbnails(session, [
          ThumbnailOptions(
            timestamp: const Duration(milliseconds: 1500),
            format: ThumbnailFormat.png,
          ),
        ]),
        platform.generateThumbnails(session, [
          ThumbnailOptions(
            timestamp: const Duration(milliseconds: 500),
            format: ThumbnailFormat.png,
          ),
        ]),
      ]);
      final colors = <List<int>>[];
      for (final batch in batches) {
        final image = batch.single;
        colors.add(
          await pixel(
            VideoThumbnailData(
              bytes: await image.readBytes(),
              timestamp: image.actualTimestamp,
              width: image.width,
              height: image.height,
              format: image.format,
            ),
          ),
        );
        await image.dispose();
      }
      expect(colors[0][2], greaterThan(200));
      expect(colors[1][0], greaterThan(200));
    } finally {
      await platform.closeSession(session);
    }
    await expectLater(
      platform.generateThumbnails(session, [
        ThumbnailOptions(timestamp: Duration.zero),
      ]),
      throwsA(isA<SessionException>()),
    );
  });

  test('native paths are rejected on web', () async {
    await expectLater(
      LuxVideoThumbnail.generate(
        source: VideoSource.path('/video.mp4'),
        timestamp: Duration.zero,
      ),
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });

  test(
    'cancel removes the file input and a later picker can still open',
    () async {
      for (var attempt = 0; attempt < 2; attempt++) {
        final pending = picker.pickVideo();
        final input = web.document.querySelector('input[type=file]')!;
        input.dispatchEvent(web.Event('cancel'));
        expect(await pending, isNull);
        expect(web.document.querySelector('input[type=file]'), isNull);
      }
    },
  );

  test(
    'selecting a real file returns a usable Blob and releases its URL',
    () async {
      final pending = picker.pickVideo();
      final input =
          web.document.querySelector('input[type=file]')!
              as web.HTMLInputElement;
      final transfer = web.DataTransfer();
      transfer.items.add(
        web.File(
          <web.BlobPart>[bytes.toJS].toJS,
          'fixture.webm',
          web.FilePropertyBag(type: 'video/webm'),
        ),
      );
      input.files = transfer.files;
      input.dispatchEvent(web.Event('change'));
      final picked = (await pending)!;
      final image = await LuxVideoThumbnail.generate(
        source: picked.source,
        timestamp: const Duration(milliseconds: 1500),
        format: ThumbnailFormat.png,
      );
      expect((await pixel(image))[2], greaterThan(200));
      await picked.dispose();
      expect(web.document.querySelector('input[type=file]'), isNull);
      // A revoked URL cannot be fetched, whereas caller-owned URLs remain valid.
      await expectLater(
        web.window.fetch(picked.source.location!.toJS).toDart,
        throwsA(anything),
      );
    },
  );

  test(
    'disposing a pending selector removes its DOM input immediately',
    () async {
      final cancellation = PickerCancellation();
      final pending = picker.pickVideo(cancellation: cancellation);
      expect(web.document.querySelector('input[type=file]'), isNotNull);
      cancellation.cancel();
      expect(await pending, isNull);
      expect(web.document.querySelector('input[type=file]'), isNull);
    },
  );

  testWidgets(
    'public widget selects a real browser file and previews its first frame',
    (tester) async {
      final results = <VideoThumbnailData>[];
      final errors = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoThumbnailPicker(
              onChanged: results.add,
              onError: errors.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('lux-video-select')));
      await tester.pump();
      final input =
          web.document.querySelector('input[type=file]')!
              as web.HTMLInputElement;
      final transfer = web.DataTransfer();
      transfer.items.add(
        web.File(
          <web.BlobPart>[bytes.toJS].toJS,
          'fixture.webm',
          web.FilePropertyBag(type: 'video/webm'),
        ),
      );
      input.files = transfer.files;
      input.dispatchEvent(web.Event('change'));
      // Browser video decoding needs real event-loop time, outside the fake clock.
      for (
        var attempt = 0;
        attempt < 100 && results.isEmpty && errors.isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
      expect(results, hasLength(1));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'public dialog selects a browser file and returns only on confirm',
    (tester) async {
      VideoThumbnailData? confirmed;
      var completed = false;
      final errors = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  confirmed = await videoThumbnailDialog(
                    context: context,
                    onError: errors.add,
                  );
                  completed = true;
                },
                child: const Text('Open dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lux-video-select')));
      await tester.pump();
      final input =
          web.document.querySelector('input[type=file]')!
              as web.HTMLInputElement;
      final transfer = web.DataTransfer();
      transfer.items.add(
        web.File(
          <web.BlobPart>[bytes.toJS].toJS,
          'dialog.webm',
          web.FilePropertyBag(type: 'video/webm'),
        ),
      );
      input.files = transfer.files;
      input.dispatchEvent(web.Event('change'));
      final button = find.byKey(const ValueKey('lux-video-dialog-confirm'));
      for (var attempt = 0; attempt < 100 && errors.isEmpty; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        if (tester.widget<FilledButton>(button).onPressed != null) break;
      }
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
      expect(confirmed, isNull);
      expect(completed, isFalse);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(confirmed!.timestamp, Duration.zero);
      final color = await tester.runAsync(() => pixel(confirmed!));
      expect(color![0], greaterThan(180));
      expect(color[2], lessThan(70));
      expect(web.document.querySelector('input[type=file]'), isNull);
    },
  );
}
