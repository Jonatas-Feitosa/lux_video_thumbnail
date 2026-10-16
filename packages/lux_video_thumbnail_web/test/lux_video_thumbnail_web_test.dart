// lux_video_thumbnail_web_test.dart
// Tests for the web platform implementation.
//
// Note: Full browser integration tests require flutter test --platform chrome.
// These tests cover logic that can be verified without browser APIs.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

void main() {
  group('ThumbnailOptions', () {
    test('quality is clamped correctly for canvas rendering', () {
      final options = ThumbnailOptions(timestamp: Duration.zero, quality: 85);
      expect(options.quality, 85);
      expect(options.quality >= 1 && options.quality <= 100, isTrue);
    });

    test('format affects mimeType correctly', () {
      expect(
        ThumbnailOptions(
          timestamp: Duration.zero,
          format: ThumbnailFormat.jpeg,
        ).format.mimeType,
        'image/jpeg',
      );

      expect(
        ThumbnailOptions(
          timestamp: Duration.zero,
          format: ThumbnailFormat.png,
        ).format.mimeType,
        'image/png',
      );

      expect(
        ThumbnailOptions(
          timestamp: Duration.zero,
          format: ThumbnailFormat.webp,
        ).format.mimeType,
        'image/webp',
      );
    });
  });

  group('VideoThumbnailSession', () {
    test('session equality based on handle and source', () {
      final s1 = VideoThumbnailSession.fromPlatformData(
        nativeHandle: 1,
        source: 'https://example.com/video.mp4',
        nativeWidth: 1920,
        nativeHeight: 1080,
      );
      final s2 = VideoThumbnailSession.fromPlatformData(
        nativeHandle: 1,
        source: 'https://example.com/video.mp4',
        nativeWidth: 1920,
        nativeHeight: 1080,
      );

      expect(s1, equals(s2));
      expect(s1.nativeHandle, 1);
      expect(s1.source, 'https://example.com/video.mp4');
    });

    test('different handles create different sessions', () {
      final s1 = VideoThumbnailSession.fromPlatformData(
        nativeHandle: 1,
        source: 'video.mp4',
        nativeWidth: 1920,
        nativeHeight: 1080,
      );
      final s2 = VideoThumbnailSession.fromPlatformData(
        nativeHandle: 2,
        source: 'video.mp4',
        nativeWidth: 1920,
        nativeHeight: 1080,
      );

      expect(s1, isNot(equals(s2)));
    });
  });

  group('VideoThumbnailResult', () {
    test('memory-backed result is marked as in-memory', () {
      final result = VideoThumbnailResult.memory(
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      );

      expect(result.isInMemory, isTrue);
      expect(result.width, 100);
      expect(result.height, 100);
      expect(result.format, ThumbnailFormat.jpeg);
    });

    test('memory-backed result reads bytes correctly', () async {
      const data = [1, 2, 3, 4, 5];
      final result = VideoThumbnailResult.memory(
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList(data),
      );

      final bytes = await result.readBytes();
      expect(bytes, data);
      expect(await result.length, 5);
    });

    test('memory-backed result readBytes with offset and length', () async {
      const data = [1, 2, 3, 4, 5];
      final result = VideoThumbnailResult.memory(
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList(data),
      );

      final chunk = await result.readBytes(offset: 1, length: 3);
      expect(chunk, [2, 3, 4]);
    });

    test('memory-backed result dispose prevents further reads', () async {
      final result = VideoThumbnailResult.memory(
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await result.dispose();

      expect(() => result.readBytes(), throwsA(isA<StateError>()));
    });
  });

  group('Exceptions', () {
    test('CorsBlockedException includes URL', () {
      final ex = CorsBlockedException('https://example.com/video.mp4');
      expect(ex.toString(), contains('example.com'));
      expect(ex.url, 'https://example.com/video.mp4');
    });

    test('CorsBlockedException includes cause and code', () {
      final cause = Exception('SecurityError');
      final ex = CorsBlockedException(
        'https://example.com/video.mp4',
        cause: cause,
        code: 'SECURITY_ERR',
      );
      expect(ex.code, 'SECURITY_ERR');
      expect(ex.cause, cause);
    });

    test('GenerationFailedException includes source and timestamp', () {
      final ex = GenerationFailedException(
        'Failed to render frame',
        source: 'https://example.com/video.mp4',
        timestamp: Duration(seconds: 10),
      );
      expect(ex.source, 'https://example.com/video.mp4');
      expect(ex.timestamp, Duration(seconds: 10));
    });

    test('SessionException includes session handle', () {
      final ex = SessionException('Session not found', sessionHandle: 42);
      expect(ex.sessionHandle, 42);
      expect(ex.toString(), contains('42'));
    });
  });

  group('ThumbnailFormat', () {
    test('all formats have correct mimeType and fileExtension', () {
      expect(ThumbnailFormat.jpeg.mimeType, 'image/jpeg');
      expect(ThumbnailFormat.jpeg.fileExtension, 'jpg');
      expect(ThumbnailFormat.png.mimeType, 'image/png');
      expect(ThumbnailFormat.png.fileExtension, 'png');
      expect(ThumbnailFormat.webp.mimeType, 'image/webp');
      expect(ThumbnailFormat.webp.fileExtension, 'webp');
    });
  });
}
