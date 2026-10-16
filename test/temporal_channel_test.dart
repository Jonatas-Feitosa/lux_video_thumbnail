import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lux_video_thumbnail');
  for (final publicChannel in [false, true]) {
    group(publicChannel ? 'exported channel' : 'default channel', () {
      late VideoThumbnailPlatform platform;
      final calls = <MethodCall>[];
      Future<Object?> Function(MethodCall)? handler;
      VideoThumbnailSession session({
        Duration? duration = const Duration(seconds: 2),
      }) => VideoThumbnailSession.fromPlatformData(
        nativeHandle: 1,
        source: 'test',
        duration: duration,
        nativeWidth: 64,
        nativeHeight: 48,
      );
      Map<String, Object> result(int micros) => {
        'width': 1,
        'height': 1,
        'format': 'png',
        'actualTimestamp': micros ~/ 1000,
        'effectiveTimestampUs': micros,
        'backingType': 'memory',
        'bytes': Uint8List.fromList([1, 2, 3]),
      };
      setUp(() {
        calls.clear();
        handler = null;
        VideoThumbnailPlatform.reset();
        platform = publicChannel
            ? MethodChannelVideoThumbnail()
            : VideoThumbnailPlatform.instance;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (handler != null) {
                return handler!(call);
              }
              if (call.method == 'generateThumbnails') {
                return [
                  result((call.arguments['options'][0]['timestampUs'] as int)),
                ];
              }
              return null;
            });
      });
      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        VideoThumbnailPlatform.reset();
      });
      test('rejects a whole invalid batch before channel work', () async {
        await expectLater(
          platform.generateThumbnails(session(), [
            ThumbnailOptions(timestamp: Duration.zero),
            ThumbnailOptions(timestamp: const Duration(microseconds: 2000001)),
          ]),
          throwsA(isA<TimestampOutOfRangeException>()),
        );
        expect(calls, isEmpty);
      });
      test('preserves submillisecond position and unknown duration', () async {
        final unknown = session(duration: Duration.zero);
        expect(unknown.duration, isNull);
        final image = (await platform.generateThumbnails(unknown, [
          ThumbnailOptions(timestamp: const Duration(microseconds: 500)),
        ])).single;
        expect(image.actualTimestamp, const Duration(microseconds: 500));
        expect(calls.single.arguments['options'][0]['timestampMs'], 0);
        await platform.generateThumbnails(unknown, [
          ThumbnailOptions(timestamp: const Duration(seconds: 7)),
        ]);
        expect(calls.last.arguments['options'][0]['timestampUs'], 7000000);
      });
      test(
        'failure does not poison FIFO and close drains accepted work exactly once',
        () async {
          final current = session();
          final gate = Completer<void>();
          handler = (call) async {
            if (call.method != 'generateThumbnails') return null;
            final time = call.arguments['options'][0]['timestampUs'] as int;
            if (time == 0) {
              await gate.future;
              throw PlatformException(
                code: 'GENERATION_FAILED',
                details: 'native decoder error',
              );
            }
            return [result(time)];
          };
          final first = expectLater(
            platform.generateThumbnails(current, [
              ThumbnailOptions(timestamp: Duration.zero),
            ]),
            throwsA(
              publicChannel
                  ? isA<PlatformException>()
                  : isA<GenerationFailedException>(),
            ),
          );
          final second = platform.generateThumbnails(current, [
            ThumbnailOptions(timestamp: const Duration(seconds: 1)),
          ]);
          final closing = platform.closeSession(current);
          await expectLater(
            platform.generateThumbnails(current, [
              ThumbnailOptions(timestamp: Duration.zero),
            ]),
            throwsA(isA<SessionException>()),
          );
          expect(calls.map((c) => c.method), ['generateThumbnails']);
          gate.complete();
          await first;
          expect(
            (await second).single.actualTimestamp,
            const Duration(seconds: 1),
          );
          await closing;
          await platform.closeSession(current);
          expect(calls.map((c) => c.method), [
            'generateThumbnails',
            'generateThumbnails',
            'closeSession',
          ]);
        },
      );
      test(
        'one-shot native out-of-range retains microseconds and typed error',
        () async {
          handler = (_) async => throw PlatformException(
            code: 'TIMESTAMP_OUT_OF_RANGE',
            details: {'requestedUs': 2000001, 'durationMs': 2000},
          );
          await expectLater(
            platform.generateThumbnail(
              source: 'test',
              options: ThumbnailOptions(
                timestamp: const Duration(microseconds: 2000001),
              ),
            ),
            throwsA(
              isA<TimestampOutOfRangeException>().having(
                (e) => e.requested,
                'position',
                const Duration(microseconds: 2000001),
              ),
            ),
          );
        },
      );
    });
  }
}
