import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'support/thumbnail_platform.dart';

void main() {
  late ThumbnailPlatformFake platform;
  final source = VideoSource.url('https://example.com/first.webm');
  setUp(() {
    platform = ThumbnailPlatformFake();
    VideoThumbnailPlatform.setInstance(platform);
  });
  tearDown(VideoThumbnailPlatform.reset);

  Widget host(VideoThumbnailPicker picker) =>
      MaterialApp(home: Scaffold(body: picker));
  Widget preview(BuildContext context, VideoThumbnailData data) =>
      const SizedBox();

  testWidgets('inline readiness listeners rebuild without notification loops', (
    tester,
  ) async {
    final changes = <bool>[];
    var ready = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => VideoThumbnailPicker(
              initialSource: source,
              previewBuilder: preview,
              onChanged: (_) {},
              onReadyChanged: (value) {
                changes.add(value);
                update(() => ready = value);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ready, isTrue);
    expect(changes, [true]);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1000);
    expect(ready, isFalse);
    slider.onChangeEnd!(1000);
    await tester.pumpAndSettle();
    expect(changes, [true, false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('frame buttons use the configured frame rate and clamp at ends', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        VideoThumbnailPicker(
          initialSource: source,
          onChanged: (_) {},
          previewBuilder: preview,
          frameRate: 30,
        ),
      ),
    );
    await tester.pumpAndSettle();

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(button('lux-video-jump-back-10').onPressed, isNull);
    expect(button('lux-video-jump-back-1').onPressed, isNull);
    expect(button('lux-video-jump-forward-1').onPressed, isNotNull);
    expect(button('lux-video-jump-forward-10').onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('lux-video-jump-forward-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lux-video-jump-forward-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lux-video-jump-back-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lux-video-jump-back-10')));
    await tester.pumpAndSettle();

    expect(platform.requests.map((request) => request.timestamp), [
      Duration.zero,
      const Duration(microseconds: 33333),
      const Duration(microseconds: 366666),
      const Duration(microseconds: 333333),
      Duration.zero,
    ]);
  });

  testWidgets('loading spinner is centered over the preview', (tester) async {
    final gate = Completer<VideoThumbnailResult>();
    platform.onGenerate = (_) => gate.future;
    await tester.pumpWidget(
      host(
        VideoThumbnailPicker(
          initialSource: source,
          onChanged: (_) {},
          previewBuilder: preview,
        ),
      ),
    );
    await tester.pump();
    final previewCenter = tester.getCenter(
      find.byKey(const ValueKey('lux-video-preview')),
    );
    final spinnerCenter = tester.getCenter(
      find.byType(CircularProgressIndicator),
    );
    expect(spinnerCenter, previewCenter);

    gate.complete(TracedResult());
    await tester.pumpAndSettle();
  });

  testWidgets('selection generates preview and cancellation preserves it', (
    tester,
  ) async {
    var picks = 0;
    final results = <VideoThumbnailData>[];
    await tester.pumpWidget(
      host(
        VideoThumbnailPicker(
          onChanged: results.add,
          previewBuilder: preview,
          videoPicker: () async => picks++ == 0 ? source : null,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('lux-video-select')));
    await tester.pumpAndSettle();
    expect(results, hasLength(1));
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lux-video-select')));
    await tester.pumpAndSettle();
    expect(platform.opens, 1);
    expect(platform.closes, 0);
    expect(results, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(platform.closes, 1);
  });

  testWidgets(
    'rapid seeks publish only latest response and reuse one session',
    (tester) async {
      final gate = Completer<VideoThumbnailResult>();
      platform.onGenerate = (options) async {
        if (options.timestamp == const Duration(seconds: 2)) return gate.future;
        return TracedResult();
      };
      final results = <VideoThumbnailData>[];
      await tester.pumpWidget(
        host(
          VideoThumbnailPicker(
            initialSource: source,
            onChanged: results.add,
            previewBuilder: preview,
          ),
        ),
      );
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(2000);
      slider.onChangeEnd!(2000);
      await tester.pump();
      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(3000);
      slider.onChangeEnd!(3000);
      await tester.pump();
      expect(platform.requests, hasLength(2));
      gate.complete(TracedResult());
      await tester.pumpAndSettle();
      expect(results.map((r) => r.timestamp), [
        Duration.zero,
        const Duration(seconds: 3),
      ]);
      expect(platform.opens, 1);
      expect(platform.maxActive, 1);
    },
  );

  testWidgets('replacing video and removing widget release both sessions', (
    tester,
  ) async {
    var picks = 0;
    await tester.pumpWidget(
      host(
        VideoThumbnailPicker(
          onChanged: (_) {},
          previewBuilder: preview,
          videoPicker: () async =>
              VideoSource.url('https://example.com/${picks++}.webm'),
        ),
      ),
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('lux-video-select')));
      await tester.pumpAndSettle();
    }
    expect(platform.opens, 2);
    expect(platform.closes, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(platform.closes, 2);
  });

  testWidgets('late opening after disposal closes without callbacks', (
    tester,
  ) async {
    final gate = Completer<void>();
    platform.onOpen = () => gate.future;
    var callbacks = 0;
    await tester.pumpWidget(
      host(
        VideoThumbnailPicker(
          initialSource: source,
          onChanged: (_) => callbacks++,
          previewBuilder: preview,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(callbacks, 0);
    expect(platform.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decoder error invokes callback and does not expose URL in UI', (
    tester,
  ) async {
    platform.onGenerate = (_) async =>
        throw StateError('https://private.example/video?token=secret');
    final errors = <Object>[];
    await tester.pumpWidget(
      host(
        VideoThumbnailPicker(
          initialSource: source,
          onChanged: (_) {},
          onError: errors.add,
          previewBuilder: preview,
          errorLabel: 'Não foi possível gerar',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(errors, hasLength(1));
    expect(find.text('Não foi possível gerar'), findsOneWidget);
    expect(find.textContaining('token=secret'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(platform.closes, 1);
  });
  testWidgets('late custom selection cannot replace a newer external source', (
    tester,
  ) async {
    final selected = Completer<VideoSource?>();
    final newer = VideoSource.url('https://example.com/newer.webm');
    Widget pickerFor(VideoSource input) => host(
      VideoThumbnailPicker(
        initialSource: input,
        videoPicker: () => selected.future,
        onChanged: (_) {},
        previewBuilder: preview,
      ),
    );
    await tester.pumpWidget(pickerFor(source));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lux-video-select')));
    await tester.pump();
    await tester.pumpWidget(pickerFor(newer));
    await tester.pump(const Duration(milliseconds: 1));
    selected.complete(VideoSource.url('https://example.com/stale.webm'));
    await tester.pumpAndSettle();
    expect(platform.opens, 2);
    expect(platform.lastSource, newer.location);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(platform.closes, 2);
  });

  testWidgets(
    'option changes while opening do not regenerate the previous source',
    (tester) async {
      final opening = Completer<void>();
      final newer = VideoSource.url('https://example.com/newer.webm');
      Widget pickerFor(VideoSource input, int width) => host(
        VideoThumbnailPicker(
          initialSource: input,
          width: width,
          onChanged: (_) {},
          previewBuilder: preview,
        ),
      );
      await tester.pumpWidget(pickerFor(source, 320));
      await tester.pumpAndSettle();
      platform.onOpen = () => opening.future;
      await tester.pumpWidget(pickerFor(newer, 320));
      await tester.pump();
      await tester.pumpWidget(pickerFor(newer, 160));
      await tester.pump();
      expect(platform.requests, hasLength(1));
      opening.complete();
      await tester.pumpAndSettle();
      expect(platform.requests, hasLength(2));
      expect(platform.requests.last.width, 160);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'unknown duration disables slider without preventing initial preview',
    (tester) async {
      platform.duration = null;
      await tester.pumpWidget(
        host(
          VideoThumbnailPicker(
            initialSource: source,
            onChanged: (_) {},
            previewBuilder: preview,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(platform.results, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('queued obsolete slider requests never reach the decoder', (
    tester,
  ) async {
    final gate = Completer<VideoThumbnailResult>();
    platform.onGenerate = (options) async =>
        options.timestamp == const Duration(seconds: 2)
        ? gate.future
        : TracedResult();
    final received = <Duration>[];
    await tester.pumpWidget(
      host(
        VideoThumbnailPicker(
          initialSource: source,
          onChanged: (image) => received.add(image.timestamp),
          previewBuilder: preview,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final milliseconds in [2000.0, 3000.0, 4000.0]) {
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(milliseconds);
      slider.onChangeEnd!(milliseconds);
      await tester.pump();
    }
    expect(platform.requests.map((o) => o.timestamp.inSeconds), [0, 2]);
    gate.complete(TracedResult());
    await tester.pumpAndSettle();
    expect(platform.requests.map((o) => o.timestamp.inSeconds), [0, 2, 4]);
    expect(received, [Duration.zero, const Duration(seconds: 4)]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
