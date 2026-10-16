import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'support/thumbnail_platform.dart';

void main() {
  late ThumbnailPlatformFake platform;
  final source = VideoSource.url('https://example.com/video.webm');
  setUp(() {
    platform = ThumbnailPlatformFake();
    VideoThumbnailPlatform.setInstance(platform);
  });
  tearDown(VideoThumbnailPlatform.reset);
  Widget preview(BuildContext _, VideoThumbnailData _) => const SizedBox();
  Finder getConfirm() => find.byKey(const ValueKey('lux-video-dialog-confirm'));
  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(getConfirm()).onPressed != null;

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty dialog cancels without opening a decoder', (tester) async {
    VideoThumbnailData? result;
    var completed = false;
    await host(tester, (context) async {
      result = await videoThumbnailDialog(
        context: context,
        previewBuilder: preview,
      );
      completed = true;
    });
    expect(enabled(tester), isFalse);
    expect(find.byType(VideoThumbnailPicker), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lux-video-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(platform.opens, 0);
  });

  testWidgets('returns only confirmed latest image and closes its session', (
    tester,
  ) async {
    VideoThumbnailData? result;
    final gate = Completer<VideoThumbnailResult>();
    platform.onGenerate = (options) async =>
        options.timestamp == Duration.zero ? TracedResult() : gate.future;
    await host(tester, (context) async {
      result = await videoThumbnailDialog(
        context: context,
        initialSource: source,
        previewBuilder: preview,
        format: ThumbnailFormat.png,
        quality: 70,
      );
    });
    expect(enabled(tester), isTrue);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(2500);
    await tester.pump();
    expect(
      enabled(tester),
      isFalse,
    ); // Before the debounce even starts decoding.
    await tester.pump(const Duration(milliseconds: 170));
    expect(enabled(tester), isFalse);
    gate.complete(TracedResult());
    await tester.pumpAndSettle();
    expect(enabled(tester), isTrue);
    expect(result, isNull);
    await tester.tap(getConfirm());
    await tester.pumpAndSettle();
    expect(result!.timestamp, const Duration(milliseconds: 2500));
    expect(result!.bytes, isNotEmpty);
    expect(platform.closes, 1);
    expect(platform.requests.last.quality, 70);
    expect(platform.requests.last.format, ThumbnailFormat.png);
  });

  testWidgets(
    'selection cancellation restores confirmation, selection error blocks it',
    (tester) async {
      final picked = Completer<VideoSource?>();
      var picks = 0;
      await host(tester, (context) async {
        await videoThumbnailDialog(
          context: context,
          initialSource: source,
          previewBuilder: preview,
          videoPicker: () {
            if (picks++ == 0) {
              return picked.future;
            }
            throw StateError('picker failed');
          },
        );
      });
      await tester.tap(find.byKey(const ValueKey('lux-video-select')));
      await tester.pump();
      expect(enabled(tester), isFalse);
      picked.complete(null);
      await tester.pumpAndSettle();
      expect(enabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('lux-video-select')));
      await tester.pumpAndSettle();
      expect(enabled(tester), isFalse);
      await tester.tap(find.byKey(const ValueKey('lux-video-dialog-cancel')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('failed new seek never confirms the previous visible frame', (
    tester,
  ) async {
    platform.onGenerate = (options) async {
      if (options.timestamp != Duration.zero) {
        throw StateError('decoder failed');
      }
      return TracedResult();
    };
    await host(tester, (context) async {
      await videoThumbnailDialog(
        context: context,
        initialSource: source,
        previewBuilder: preview,
      );
    });
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1000);
    slider.onChangeEnd!(1000);
    await tester.pumpAndSettle();
    expect(enabled(tester), isFalse);
    expect(find.textContaining('Preview: 00:00:00.000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lux-video-dialog-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'dismiss during decoding returns null and releases late results',
    (tester) async {
      final gate = Completer<VideoThumbnailResult>();
      platform.onGenerate = (_) => gate.future;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  expect(
                    await videoThumbnailDialog(
                      context: context,
                      initialSource: source,
                      previewBuilder: preview,
                    ),
                    isNull,
                  );
                  completed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      final late = TracedResult();
      gate.complete(late);
      await tester.pumpAndSettle();
      expect(late.disposals, 1);
      expect(platform.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom labels and appearance fit a narrow viewport and Back cancels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VideoThumbnailData? result;
      var completed = false;
      await host(tester, (context) async {
        result = await videoThumbnailDialog(
          context: context,
          initialSource: source,
          previewBuilder: preview,
          title: 'Choose a frame',
          confirmLabel: 'Use image',
          cancelLabel: 'Close',
          selectVideoLabel: 'Choose video',
          previewLabel: 'Frame preview',
          backTenFramesTooltip: 'Back ten',
          backOneFrameTooltip: 'Back one',
          forwardOneFrameTooltip: 'Forward one',
          forwardTenFramesTooltip: 'Forward ten',
          backgroundColor: Colors.amber,
          shape: const RoundedRectangleBorder(),
          barrierDismissible: false,
        );
        completed = true;
      });
      expect(find.text('Choose a frame'), findsOneWidget);
      expect(find.text('Choose video'), findsOneWidget);
      expect(find.textContaining('Frame preview:'), findsOneWidget);
      expect(find.byTooltip('Back ten'), findsOneWidget);
      expect(find.byTooltip('Back one'), findsOneWidget);
      expect(find.byTooltip('Forward one'), findsOneWidget);
      expect(find.byTooltip('Forward ten'), findsOneWidget);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
        Colors.amber,
      );
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
    },
  );
  testWidgets('uses and closes the requested nested navigator', (tester) async {
    final root = GlobalKey<NavigatorState>();
    final nested = GlobalKey<NavigatorState>();
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        home: Navigator(
          key: nested,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  expect(
                    await videoThumbnailDialog(
                      context: context,
                      useRootNavigator: false,
                      previewBuilder: preview,
                    ),
                    isNull,
                  );
                  completed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(root.currentState!.canPop(), isFalse);
    expect(nested.currentState!.canPop(), isTrue);
    await tester.tap(find.byKey(const ValueKey('lux-video-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(nested.currentState!.canPop(), isFalse);
    expect(find.text('Open'), findsOneWidget);
  });
}
