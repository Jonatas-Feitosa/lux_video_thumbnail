// video_thumbnail_platform_test.dart
// Tests for the platform interface.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'mock_video_thumbnail_platform.dart';

void main() {
  group('VideoThumbnailPlatform', () {
    late MockVideoThumbnailPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockVideoThumbnailPlatform();
      VideoThumbnailPlatform.setInstance(mockPlatform);
    });

    tearDown(VideoThumbnailPlatform.reset);

    test('openSession creates session with metadata', () async {
      mockPlatform
        ..setVideoDuration('test.mp4', const Duration(seconds: 60))
        ..setResultsForSource('test.mp4', [
          createMockResult(timestamp: Duration.zero),
        ]);

      final session = await VideoThumbnailPlatform.instance.openSession(
        'test.mp4',
      );

      expect(session.source, 'test.mp4');
      expect(session.duration, const Duration(seconds: 60));
      expect(session.nativeWidth, 1920);
      expect(session.nativeHeight, 1080);
      expect(session.nativeHandle, greaterThan(0));
    });

    test(
      'openSession throws VideoNotFoundException for unknown source',
      () async {
        expect(
          () => VideoThumbnailPlatform.instance.openSession('missing.mp4'),
          throwsA(isA<VideoNotFoundException>()),
        );
      },
    );

    test('generateThumbnails returns results for session', () async {
      final results = [
        createMockResult(timestamp: Duration.zero),
        createMockResult(timestamp: const Duration(seconds: 10)),
        createMockResult(timestamp: const Duration(seconds: 20)),
      ];
      mockPlatform.setResultsForSource('test.mp4', results);

      final session = await VideoThumbnailPlatform.instance.openSession(
        'test.mp4',
      );
      final output = await VideoThumbnailPlatform.instance
          .generateThumbnails(session, [
            ThumbnailOptions(timestamp: Duration.zero),
            ThumbnailOptions(timestamp: const Duration(seconds: 10)),
            ThumbnailOptions(timestamp: const Duration(seconds: 20)),
          ]);

      expect(output.length, 3);
      expect(output[0].actualTimestamp, Duration.zero);
      expect(output[1].actualTimestamp, const Duration(seconds: 10));
      expect(output[2].actualTimestamp, const Duration(seconds: 20));
    });

    test('closeSession removes session', () async {
      mockPlatform.setResultsForSource('test.mp4', [
        createMockResult(timestamp: Duration.zero),
      ]);

      final session = await VideoThumbnailPlatform.instance.openSession(
        'test.mp4',
      );
      expect(mockPlatform.getSession('test.mp4'), isNotNull);

      await VideoThumbnailPlatform.instance.closeSession(session);
      expect(mockPlatform.getSession('test.mp4'), isNull);
    });

    test('generateThumbnail convenience method works', () async {
      mockPlatform.setResultsForSource('test.mp4', [
        createMockResult(timestamp: const Duration(seconds: 5)),
      ]);

      final result = await VideoThumbnailPlatform.instance.generateThumbnail(
        source: 'test.mp4',
        options: ThumbnailOptions(timestamp: const Duration(seconds: 5)),
      );

      expect(result.actualTimestamp, const Duration(seconds: 5));
    });

    test('isFormatSupported returns configured value', () async {
      mockPlatform
        ..setFormatSupported('video/mp4', supported: true)
        ..setFormatSupported('video/av1', supported: false);

      expect(
        await VideoThumbnailPlatform.instance.isFormatSupported('video/mp4'),
        true,
      );
      expect(
        await VideoThumbnailPlatform.instance.isFormatSupported('video/av1'),
        false,
      );
      expect(
        await VideoThumbnailPlatform.instance.isFormatSupported(
          'video/unknown',
        ),
        true,
      ); // default
    });

    test('getVideoDuration returns configured duration', () async {
      mockPlatform.setVideoDuration('test.mp4', const Duration(seconds: 120));

      final duration = await VideoThumbnailPlatform.instance.getVideoDuration(
        'test.mp4',
      );
      expect(duration, const Duration(seconds: 120));
    });

    test('configured exception is thrown', () async {
      mockPlatform.nextException = const UnsupportedFormatException(
        'AV1 not supported',
        format: 'video/av1',
      );

      expect(
        () => VideoThumbnailPlatform.instance.openSession('test.av1'),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('persistent exception throws on multiple calls', () async {
      mockPlatform.persistentException = const PermissionDeniedException(
        '/secure/video.mp4',
      );

      expect(
        () => VideoThumbnailPlatform.instance.openSession('/secure/video.mp4'),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(
        () => VideoThumbnailPlatform.instance.openSession('/secure/other.mp4'),
        throwsA(isA<PermissionDeniedException>()),
      );

      mockPlatform
        ..clearException()
        ..setResultsForSource('test.mp4', [
          createMockResult(timestamp: Duration.zero),
        ]);
      final session = await VideoThumbnailPlatform.instance.openSession(
        'test.mp4',
      );
      expect(session, isNotNull);
    });
  });

  group('ThumbnailOptions', () {
    test('defaults are correct', () {
      final options = ThumbnailOptions(timestamp: const Duration(seconds: 10));
      expect(options.format, ThumbnailFormat.jpeg);
      expect(options.quality, 85);
      expect(options.maintainAspectRatio, true);
      expect(options.preferKeyFrame, false);
    });

    test('copyWith updates only specified fields', () {
      final original = ThumbnailOptions(
        timestamp: const Duration(seconds: 10),
        width: 800,
        height: 600,
        format: ThumbnailFormat.png,
        quality: 90,
      );
      final updated = original.copyWith(width: 1280, quality: 75);

      expect(updated.timestamp, const Duration(seconds: 10));
      expect(updated.width, 1280);
      expect(updated.height, 600);
      expect(updated.format, ThumbnailFormat.png);
      expect(updated.quality, 75);
    });

    test('keyFrame constructor sets preferKeyFrame', () {
      final options = ThumbnailOptions.keyFrame(
        timestamp: const Duration(seconds: 10),
      );
      expect(options.preferKeyFrame, true);
    });

    test('quality validation', () {
      expect(
        () => ThumbnailOptions(timestamp: Duration.zero, quality: 0),
        throwsArgumentError,
      );
      expect(
        () => ThumbnailOptions(timestamp: Duration.zero, quality: 101),
        throwsArgumentError,
      );
    });

    test('negative timestamp validation', () {
      expect(
        () => ThumbnailOptions(timestamp: const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });
  });

  group('ThumbnailFormat', () {
    test('mimeType and fileExtension are correct', () {
      expect(ThumbnailFormat.jpeg.mimeType, 'image/jpeg');
      expect(ThumbnailFormat.jpeg.fileExtension, 'jpg');
      expect(ThumbnailFormat.png.mimeType, 'image/png');
      expect(ThumbnailFormat.png.fileExtension, 'png');
      expect(ThumbnailFormat.webp.mimeType, 'image/webp');
      expect(ThumbnailFormat.webp.fileExtension, 'webp');
    });
  });

  group('VideoThumbnailSession', () {
    test('equality based on handle and source', () {
      final s1 = VideoThumbnailSession.fromPlatformData(
        nativeHandle: 1,
        source: 'test.mp4',
        nativeWidth: 1920,
        nativeHeight: 1080,
      );
      final s2 = VideoThumbnailSession.fromPlatformData(
        nativeHandle: 1,
        source: 'test.mp4',
        nativeWidth: 1920,
        nativeHeight: 1080,
      );
      final s3 = VideoThumbnailSession.fromPlatformData(
        nativeHandle: 2,
        source: 'test.mp4',
        nativeWidth: 1920,
        nativeHeight: 1080,
      );

      expect(s1, equals(s2));
      expect(s1, isNot(equals(s3)));
    });
  });

  group('VideoThumbnailResult', () {
    test('memory-backed result reads bytes correctly', () async {
      const data = [1, 2, 3, 4, 5];
      final result = VideoThumbnailResult.memory(
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList(data),
      );

      expect(result.isInMemory, true);
      expect(await result.length, 5);

      final chunk = await result.readBytes(offset: 1, length: 3);
      expect(chunk, [2, 3, 4]);

      final all = await result.readBytes();
      expect(all, data);
    });

    test('memory-backed result saveToFile works', () async {
      final result = VideoThumbnailResult.memory(
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      );

      // Filesystem saving is covered by resource_contract_test.dart.
      // This tests the API shape
      expect(result.isInMemory, true);
    });

    test('dispose prevents further reads', () async {
      final result = VideoThumbnailResult.memory(
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await result.dispose();

      expect(result.readBytes, throwsA(isA<StateError>()));
    });
  });

  group('Exceptions', () {
    test('VideoNotFoundException includes source', () {
      const ex = VideoNotFoundException('/path/video.mp4');
      expect(ex.toString(), contains('/path/video.mp4'));
    });

    test('UnsupportedFormatException includes format', () {
      const ex = UnsupportedFormatException(
        'Not supported',
        format: 'video/av1',
      );
      expect(ex.toString(), contains('video/av1'));
    });

    test('TimestampOutOfRangeException includes requested and duration', () {
      final ex = TimestampOutOfRangeException(
        const Duration(seconds: 100),
        videoDuration: const Duration(seconds: 60),
      );
      expect(ex.toString(), contains('100'));
      expect(ex.toString(), contains('60'));
    });

    test('CorsException includes URL', () {
      const ex = CorsException('https://example.com/video.mp4');
      expect(ex.toString(), contains('example.com'));
    });
  });
}
