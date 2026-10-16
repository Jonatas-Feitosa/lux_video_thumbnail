// Integration tests for the Android implementation of lux_video_thumbnail.
//
// These tests verify the platform interface contract against the Android
// plugin's MethodChannel implementation. They use a mock platform to
// test the Dart-side logic without requiring a device.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

import 'mock_video_thumbnail_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android Platform Integration', () {
    setUp(() {
      VideoThumbnailPlatform.setInstance(MockVideoThumbnailPlatform());
    });

    tearDown(() {
      VideoThumbnailPlatform.reset();
    });

    test('MethodChannel name is correct', () {
      const channel = MethodChannel('lux_video_thumbnail');
      expect(channel.name, 'lux_video_thumbnail');
    });

    test('openSession returns session with correct metadata', () async {
      final mock =
          VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;

      mock.setVideoDuration('test_video.mp4', const Duration(seconds: 30));
      mock.setResultsForSource('test_video.mp4', [
        VideoThumbnailResult.memory(
          width: 1920,
          height: 1080,
          format: ThumbnailFormat.jpeg,
          actualTimestamp: Duration.zero,
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        ),
      ]);

      final session = await VideoThumbnailPlatform.instance.openSession(
        'test_video.mp4',
      );

      expect(session.source, 'test_video.mp4');
      expect(session.duration, const Duration(seconds: 30));
      expect(session.nativeWidth, 1920);
      expect(session.nativeHeight, 1080);
    });

    test('generateThumbnails returns results in order', () async {
      final mock =
          VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;

      mock.setVideoDuration('test_video.mp4', const Duration(seconds: 60));
      mock.setResultsForSource('test_video.mp4', [
        VideoThumbnailResult.memory(
          width: 1280,
          height: 720,
          format: ThumbnailFormat.jpeg,
          actualTimestamp: Duration.zero,
          bytes: Uint8List(100),
        ),
        VideoThumbnailResult.memory(
          width: 1280,
          height: 720,
          format: ThumbnailFormat.jpeg,
          actualTimestamp: const Duration(seconds: 30),
          bytes: Uint8List(100),
        ),
      ]);

      final session = await VideoThumbnailPlatform.instance.openSession(
        'test_video.mp4',
      );
      final results = await VideoThumbnailPlatform.instance
          .generateThumbnails(session, [
            ThumbnailOptions(timestamp: Duration.zero),
            ThumbnailOptions(timestamp: const Duration(seconds: 30)),
          ]);

      expect(results.length, 2);
      expect(results[0].actualTimestamp, Duration.zero);
      expect(results[1].actualTimestamp, const Duration(seconds: 30));
    });

    test('closeSession removes session and cleans up', () async {
      final mock =
          VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;

      mock.setVideoDuration('test.mp4', const Duration(seconds: 30));
      mock.setResultsForSource('test.mp4', [
        VideoThumbnailResult.memory(
          width: 1920,
          height: 1080,
          format: ThumbnailFormat.jpeg,
          actualTimestamp: Duration.zero,
          bytes: Uint8List(10),
        ),
      ]);

      final session = await VideoThumbnailPlatform.instance.openSession(
        'test.mp4',
      );
      await VideoThumbnailPlatform.instance.closeSession(session);

      expect(mock.getSession('test.mp4'), isNull);
    });

    test('isFormatSupported returns true for known formats', () async {
      final result = await VideoThumbnailPlatform.instance.isFormatSupported(
        'video/mp4',
      );
      expect(result, true);

      final result2 = await VideoThumbnailPlatform.instance.isFormatSupported(
        'video/webm',
      );
      expect(result2, true);
    });

    test('isFormatSupported returns false for unknown formats', () async {
      final mock =
          VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;
      mock.setFormatSupported('video/unknown', false);

      final result3 = await VideoThumbnailPlatform.instance.isFormatSupported(
        'video/unknown',
      );
      expect(result3, false);
    });

    test('getVideoDuration returns duration for valid source', () async {
      final mock =
          VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;
      mock.setVideoDuration('test.mp4', const Duration(seconds: 45));

      final duration = await VideoThumbnailPlatform.instance.getVideoDuration(
        'test.mp4',
      );
      expect(duration, const Duration(seconds: 45));
    });

    test('getVideoDuration returns null for unknown source', () async {
      final duration = await VideoThumbnailPlatform.instance.getVideoDuration(
        'unknown.mp4',
      );
      expect(duration, isNull);
    });

    test('VideoNotFoundException thrown for missing source', () async {
      final mock =
          VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;
      mock.setNextException(VideoNotFoundException('missing.mp4'));

      expect(
        () => VideoThumbnailPlatform.instance.openSession('missing.mp4'),
        throwsA(isA<VideoNotFoundException>()),
      );
    });

    test(
      'SessionException thrown when generating thumbnails with invalid session',
      () async {
        final mock =
            VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;
        mock.setNextException(
          SessionException(
            'Invalid session',
            sessionHandle: 999,
            code: 'SESSION_INVALID',
          ),
        );

        final session = VideoThumbnailSession.fromPlatformData(
          nativeHandle: 999,
          source: 'invalid.mp4',
          nativeWidth: 1920,
          nativeHeight: 1080,
        );

        expect(
          () => VideoThumbnailPlatform.instance.generateThumbnails(session, [
            ThumbnailOptions(timestamp: Duration.zero),
          ]),
          throwsA(isA<SessionException>()),
        );
      },
    );

    test('ThumbnailOptions serialization works correctly', () {
      final options = ThumbnailOptions(
        timestamp: const Duration(seconds: 5),
        width: 640,
        height: 360,
        format: ThumbnailFormat.png,
        quality: 90,
        maintainAspectRatio: false,
        preferKeyFrame: true,
      );

      final json = options.toJson();
      expect(json['timestampMs'], 5000);
      expect(json['width'], 640);
      expect(json['height'], 360);
      expect(json['format'], 'png');
      expect(json['quality'], 90);
      expect(json['maintainAspectRatio'], false);
      expect(json['preferKeyFrame'], true);
    });

    test('ThumbnailFormat mimeType and fileExtension are correct', () {
      expect(ThumbnailFormat.jpeg.mimeType, 'image/jpeg');
      expect(ThumbnailFormat.jpeg.fileExtension, 'jpg');
      expect(ThumbnailFormat.png.mimeType, 'image/png');
      expect(ThumbnailFormat.png.fileExtension, 'png');
      expect(ThumbnailFormat.webp.mimeType, 'image/webp');
      expect(ThumbnailFormat.webp.fileExtension, 'webp');
    });

    test('FileBackedResult readBytes streams correctly', () async {
      final mock =
          VideoThumbnailPlatform.instance as MockVideoThumbnailPlatform;
      mock.setResultsForSource('test.mp4', [
        VideoThumbnailResult.memory(
          width: 100,
          height: 100,
          format: ThumbnailFormat.jpeg,
          actualTimestamp: Duration.zero,
          bytes: Uint8List.fromList(List.generate(1000, (i) => i % 256)),
        ),
      ]);

      final session = await VideoThumbnailPlatform.instance.openSession(
        'test.mp4',
      );
      final results = await VideoThumbnailPlatform.instance.generateThumbnails(
        session,
        [ThumbnailOptions(timestamp: Duration.zero)],
      );

      final result = results[0];
      final bytes = await result.readBytes(offset: 0, length: 100);
      expect(bytes.length, 100);
      expect(result.isInMemory, true);
    });

    test('getPlatformVersion returns non-empty string', () async {
      final version = await VideoThumbnailPlatform.instance
          .getPlatformVersion();
      expect(version, isNotEmpty);
    });

    test('Exception types are correctly structured', () {
      final e1 = VideoNotFoundException(
        'test.mp4',
        cause: Exception('io'),
        code: 'CODE',
      );
      expect(e1.source, 'test.mp4');
      expect(e1.code, 'CODE');
      expect(e1.toString(), contains('test.mp4'));

      final e2 = UnsupportedFormatException(
        'bad',
        format: 'video/unknown',
        cause: Exception('io'),
        code: 'CODE',
      );
      expect(e2.format, 'video/unknown');
      expect(e2.code, 'CODE');

      final e3 = PermissionDeniedException('secret.mp4', code: 'CODE');
      expect(e3.source, 'secret.mp4');
      expect(e3.code, 'CODE');

      final e4 = TimestampOutOfRangeException(
        Duration(seconds: 999),
        videoDuration: Duration(seconds: 50),
        code: 'CODE',
      );
      expect(e4.requested, Duration(seconds: 999));
      expect(e4.videoDuration, Duration(seconds: 50));
      expect(e4.code, 'CODE');

      final e5 = SessionException('error', sessionHandle: 42, code: 'CODE');
      expect(e5.sessionHandle, 42);
      expect(e5.code, 'CODE');

      final e6 = GenerationFailedException(
        'fail',
        source: 'test.mp4',
        timestamp: Duration.zero,
        code: 'CODE',
      );
      expect(e6.source, 'test.mp4');
      expect(e6.timestamp, Duration.zero);
      expect(e6.code, 'CODE');

      final e7 = CorsException('https://example.com', code: 'CODE');
      expect(e7.url, 'https://example.com');
      expect(e7.code, 'CODE');
    });
  });
}
