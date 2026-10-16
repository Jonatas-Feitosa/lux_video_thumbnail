@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'package:lux_video_thumbnail_platform_interface/src/session_operation_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MemoryBackedResult image() => MemoryBackedResult(
    width: 2,
    height: 2,
    format: ThumbnailFormat.png,
    actualTimestamp: Duration.zero,
    bytes: Uint8List.fromList([1, 2, 3, 4]),
  );

  test('runtime options, sources and byte ceilings reject invalid values', () {
    for (final keyframe in [false, true]) {
      for (final size in [0, -1, 4097]) {
        expect(
          () => keyframe
              ? ThumbnailOptions.keyFrame(
                  timestamp: Duration.zero,
                  height: size,
                )
              : ThumbnailOptions(timestamp: Duration.zero, width: size),
          throwsArgumentError,
        );
      }
    }
    expect(
      () => ThumbnailOptions(
        timestamp: const Duration(
          microseconds: ThumbnailLimits.maxTimestampUs + 1,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => ThumbnailLimits.videoBytes(ThumbnailLimits.maxVideoBytes + 1),
      throwsArgumentError,
    );
    expect(() => ThumbnailLimits.batch(17), throwsArgumentError);
    expect(() => ThumbnailLimits.batch(0), throwsArgumentError);
    expect(() => VideoSource.path('a\u0000b'), throwsArgumentError);
    expect(
      () => VideoSource.bytes(Uint8List(1), mimeType: 'video/mp4\r\n'),
      throwsArgumentError,
    );
  });

  test(
    'ranges reject negative and oversized requests, EOF remains valid',
    () async {
      final result = image();
      for (final offset in [-1, 5]) {
        await expectLater(result.readBytes(offset: offset), throwsRangeError);
      }
      await expectLater(result.readBytes(length: -1), throwsRangeError);
      await expectLater(
        result.readBytes(length: ThumbnailLimits.maxThumbnailBytes + 1),
        throwsRangeError,
      );
      expect(await result.readBytes(offset: 4), isEmpty);
      expect(await result.readBytes(offset: 3, length: 50), [4]);
      await result.dispose();
      await expectLater(result.length, throwsStateError);
      await expectLater(result.saveToFile(), throwsStateError);
    },
  );

  test(
    'saving creates unique caller-owned copies and rejects traversal',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'thumbnail_contract_',
      );
      final result = image();
      try {
        final original = File('${parent.path}/same.png');
        await original.writeAsString('keep');
        final first = await result.saveToFile(
          directory: parent.path,
          fileName: 'same.png',
        );
        final second = await result.saveToFile(
          directory: parent.path,
          fileName: 'same.png',
        );
        expect(first, isNot(second));
        expect(await original.readAsString(), 'keep');
        expect(await File(first).readAsBytes(), [1, 2, 3, 4]);
        await result.dispose();
        expect(File(second).statSync().type, FileSystemEntityType.file);
        for (final name in [
          '../escape',
          r'a\b',
          '/absolute',
          '..',
          'bad:stream',
          'bad\u0000',
        ]) {
          await expectLater(
            image().saveToFile(directory: parent.path, fileName: name),
            throwsArgumentError,
          );
        }
      } finally {
        await parent.delete(recursive: true);
      }
    },
  );

  test('default save uses the system temporary directory', () async {
    final path = await image().saveToFile();
    final file = File(path);
    try {
      expect(
        file.parent.parent.resolveSymbolicLinksSync(),
        Directory.systemTemp.resolveSymbolicLinksSync(),
      );
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
    } finally {
      await file.parent.delete(recursive: true);
    }
  });

  test(
    'session queue rejects overflow and recovers capacity after failure',
    () async {
      final gate = Completer<void>();
      final queue = SessionOperationQueue(1);
      final pending = [
        for (var i = 0; i < ThumbnailLimits.maxPendingOperations; i++)
          queue.run(() async {
            await gate.future;
            return i;
          }),
      ];
      await expectLater(queue.run(() async => 99), throwsStateError);
      gate.complete();
      expect(await Future.wait(pending), List.generate(16, (i) => i));
      await expectLater(
        queue.run(() async => throw StateError('failure')),
        throwsStateError,
      );
      expect(await queue.run(() async => 42), 42);
      await queue.close(() async {});
    },
  );

  for (final exported in [false, true]) {
    test('oversized batches never invoke channel ($exported)', () async {
      VideoThumbnailPlatform.reset();
      final platform = exported
          ? MethodChannelVideoThumbnail()
          : VideoThumbnailPlatform.instance;
      var invoked = false;
      const channel = MethodChannel('lux_video_thumbnail');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            invoked = true;
            return null;
          });
      try {
        final session = VideoThumbnailSession.fromPlatformData(
          nativeHandle: 1,
          source: 'video',
          nativeWidth: 2,
          nativeHeight: 2,
        );
        await expectLater(
          platform.generateThumbnails(
            session,
            List.generate(
              17,
              (_) => ThumbnailOptions(timestamp: Duration.zero),
            ),
          ),
          throwsArgumentError,
        );
        expect(invoked, isFalse);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });
  }
}
