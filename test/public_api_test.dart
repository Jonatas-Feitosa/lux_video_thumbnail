import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail/src/thumbnail_session.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'support/thumbnail_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ThumbnailPlatformFake platform;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform = ThumbnailPlatformFake();
    VideoThumbnailPlatform.setInstance(platform);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    VideoThumbnailPlatform.reset();
  });
  final source = VideoSource.url('https://example.com/video.webm');

  test('iOS public generation opens, reads and disposes a session', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final thumbnail = await LuxVideoThumbnail.generate(
      source: VideoSource.path('/tmp/video.mp4'),
      timestamp: Duration.zero,
    );
    expect(thumbnail.bytes, imageBytes);
    expect(platform.opens, 1);
    expect(platform.closes, 1);
    expect(platform.results.single.disposals, 1);
  });

  test(
    'public API returns a usable image and disposes intermediates',
    () async {
      final thumbnail = await LuxVideoThumbnail.generate(
        source: source,
        timestamp: const Duration(milliseconds: 2500),
        width: 160,
        quality: 90,
      );
      expect(thumbnail.bytes, imageBytes);
      expect(thumbnail.timestamp, const Duration(milliseconds: 2500));
      expect(thumbnail.format, ThumbnailFormat.png);
      expect(thumbnail.width, 1);
      expect(platform.requests.single.width, 160);
      expect(platform.requests.single.quality, 90);
      expect(platform.closes, 1);
      expect(platform.results.single.disposals, 1);
      thumbnail.bytes[0] = 0;
      expect(
        imageBytes[0],
        137,
      ); // The caller owns its copy, not the decoder's buffer.
    },
  );

  test(
    'path and bytes inputs are routed without deleting caller sources',
    () async {
      await LuxVideoThumbnail.generate(
        source: VideoSource.path('/borrowed/video.mp4'),
        timestamp: Duration.zero,
      );
      expect(platform.lastSource, '/borrowed/video.mp4');
      await LuxVideoThumbnail.generate(
        source: VideoSource.bytes(imageBytes, mimeType: 'video/webm'),
        timestamp: Duration.zero,
      );
      expect(platform.lastBytes, imageBytes);
      expect(platform.lastMimeType, 'video/webm');
      expect(platform.requests.last.width, 320);
      expect(platform.closes, 2);
    },
  );

  test('invalid options fail before opening a decoder', () async {
    for (final width in [0, -1, 4097]) {
      await expectLater(
        LuxVideoThumbnail.generate(
          source: source,
          timestamp: Duration.zero,
          width: width,
        ),
        throwsArgumentError,
      );
    }
    for (final quality in [0, 101]) {
      await expectLater(
        LuxVideoThumbnail.generate(
          source: source,
          timestamp: Duration.zero,
          quality: quality,
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      LuxVideoThumbnail.generate(
        source: source,
        timestamp: const Duration(milliseconds: -1),
      ),
      throwsArgumentError,
    );
    expect(platform.opens, 0);
  });

  test('read failure still disposes output and closes decoder', () async {
    final result = TracedResult(failReading: true);
    platform.onGenerate = (_) async => result;
    await expectLater(
      LuxVideoThumbnail.generate(source: source, timestamp: Duration.zero),
      throwsStateError,
    );
    expect(result.disposals, 1);
    expect(platform.closes, 1);
  });

  test('decode and empty output failures close decoder', () async {
    platform.onGenerate = (_) async => throw StateError('decode failed');
    await expectLater(
      LuxVideoThumbnail.generate(source: source, timestamp: Duration.zero),
      throwsStateError,
    );
    final empty = TracedResult(empty: true);
    platform.onGenerate = (_) async => empty;
    await expectLater(
      LuxVideoThumbnail.generate(source: source, timestamp: Duration.zero),
      throwsA(isA<GenerationFailedException>()),
    );
    expect(empty.disposals, 1);
    expect(platform.closes, 2);
  });

  test('out-of-range requests close decoder without generating', () async {
    await expectLater(
      LuxVideoThumbnail.generate(
        source: source,
        timestamp: const Duration(seconds: 11),
      ),
      throwsA(isA<TimestampOutOfRangeException>()),
    );
    expect(platform.requests, isEmpty);
    expect(platform.closes, 1);
  });

  test('queue survives failure and close waits for all queued work', () async {
    final session = await ThumbnailSession.open(source);
    final gate = Completer<void>();
    platform.onGenerate = (options) async {
      if (options.timestamp == Duration.zero) {
        await gate.future;
        throw StateError('first failed');
      }
      return TracedResult();
    };
    final first = session.generate(ThumbnailOptions(timestamp: Duration.zero));
    final failure = expectLater(first, throwsStateError);
    final second = session.generate(
      ThumbnailOptions(timestamp: const Duration(seconds: 1)),
    );
    final closing = session.close();
    expect(platform.closes, 0);
    gate.complete();
    await failure;
    expect((await second).timestamp, const Duration(seconds: 1));
    await closing;
    expect(platform.maxActive, 1);
    expect(platform.closes, 1);
    await session.close();
    expect(platform.closes, 1);
    await expectLater(
      session.generate(ThumbnailOptions(timestamp: Duration.zero)),
      throwsStateError,
    );
  });

  test('unsupported platforms report a typed error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await expectLater(
      LuxVideoThumbnail.generate(source: source, timestamp: Duration.zero),
      throwsA(isA<PlatformNotSupportedException>()),
    );
    expect(platform.opens, 0);
  });

  test('invalid source input is rejected', () {
    expect(
      () => VideoSource.bytes(Uint8List(0), mimeType: 'video/mp4'),
      throwsArgumentError,
    );
    expect(
      () => VideoSource.bytes(imageBytes, mimeType: 'text/plain'),
      throwsArgumentError,
    );
    expect(() => VideoSource.path(' '), throwsArgumentError);
    expect(() => VideoSource.url('file:///video.mp4'), throwsArgumentError);
  });

  test(
    'default byte bridge sends bytes rather than a caller-created path',
    () async {
      VideoThumbnailPlatform.reset();
      const channel = MethodChannel('lux_video_thumbnail');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'openSessionFromBytes') {
          expect(call.arguments, {
            'bytes': imageBytes,
            'mimeType': 'video/mp4',
          });
          return {
            'nativeHandle': 1,
            'duration': 1000,
            'nativeWidth': 1,
            'nativeHeight': 1,
          };
        }
        if (call.method == 'generateThumbnails') {
          return [
            {
              'width': 1,
              'height': 1,
              'format': 'png',
              'actualTimestamp': 0,
              'backingType': 'memory',
              'bytes': imageBytes,
            },
          ];
        }
        return null;
      });
      try {
        final result = await LuxVideoThumbnail.generate(
          source: VideoSource.bytes(imageBytes, mimeType: 'video/mp4'),
          timestamp: Duration.zero,
        );
        expect(result.bytes, imageBytes);
        expect(calls, [
          'openSessionFromBytes',
          'generateThumbnails',
          'closeSession',
        ]);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );

  test(
    'byte bridge reports null and decoder failures without a bogus close',
    () async {
      VideoThumbnailPlatform.reset();
      const channel = MethodChannel('lux_video_thumbnail');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'openSessionFromBytes');
        return null;
      });
      try {
        final source = VideoSource.bytes(imageBytes, mimeType: 'video/mp4');
        await expectLater(
          LuxVideoThumbnail.generate(source: source, timestamp: Duration.zero),
          throwsA(isA<GenerationFailedException>()),
        );
        messenger.setMockMethodCallHandler(channel, (_) async {
          calls++;
          throw PlatformException(code: 'UNSUPPORTED_FORMAT');
        });
        await expectLater(
          LuxVideoThumbnail.generate(source: source, timestamp: Duration.zero),
          throwsA(isA<UnsupportedFormatException>()),
        );
        expect(calls, 2);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
