// platform_interface_integration_test.dart
// Integration test verifying workspace path dependencies resolve correctly.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'mock_video_thumbnail_platform.dart';

void main() {
  // Import the mock for workspace path dependency validation
  test(
    'Workspace path dependencies resolve - platform interface import works',
    () {
      final options = ThumbnailOptions(
        timestamp: Duration.zero,
        width: 100,
        height: 100,
        format: ThumbnailFormat.jpeg,
      );
      expect(options.timestamp, Duration.zero);
      expect(options.width, 100);
      expect(options.height, 100);
      expect(options.format, ThumbnailFormat.jpeg);
    },
  );

  test('Mock platform can be registered and called via setInstance', () async {
    final mockPlatform = MockVideoThumbnailPlatform();
    VideoThumbnailPlatform.setInstance(mockPlatform);

    // Configure mock data
    mockPlatform.setVideoDuration(
      'test_video.mp4',
      const Duration(seconds: 60),
    );
    mockPlatform.setResultsForSource('test_video.mp4', [
      VideoThumbnailResult.memory(
        width: 1920,
        height: 1080,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        bytes: Uint8List.fromList(List.filled(4, 0xFF)),
      ),
      VideoThumbnailResult.memory(
        width: 1920,
        height: 1080,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: const Duration(seconds: 30),
        bytes: Uint8List.fromList(List.filled(4, 0xFF)),
      ),
    ]);

    // Test openSession
    final session = await VideoThumbnailPlatform.instance.openSession(
      'test_video.mp4',
    );
    expect(session.source, 'test_video.mp4');
    expect(session.duration, const Duration(seconds: 60));
    expect(session.nativeWidth, 1920);
    expect(session.nativeHeight, 1080);

    // Test generateThumbnails
    final results = await VideoThumbnailPlatform.instance
        .generateThumbnails(session, [
          ThumbnailOptions(timestamp: Duration.zero, width: 1920, height: 1080),
          ThumbnailOptions(
            timestamp: const Duration(seconds: 30),
            width: 1920,
            height: 1080,
          ),
        ]);
    expect(results.length, 2);
    expect(results[0].width, 1920);
    expect(results[0].height, 1080);
    expect(results[0].actualTimestamp, Duration.zero);
    expect(results[1].actualTimestamp, const Duration(seconds: 30));

    // Test closeSession
    await VideoThumbnailPlatform.instance.closeSession(session);

    // Verify session is cleaned up
    expect(mockPlatform.getSession('test_video.mp4'), isNull);

    // Reset for other tests
    VideoThumbnailPlatform.reset();
  });

  test(
    'ThumbnailOptions and VideoThumbnailResult APIs are accessible from example',
    () {
      final options = ThumbnailOptions(
        timestamp: Duration(seconds: 10),
        width: 800,
        height: 600,
        format: ThumbnailFormat.png,
        quality: 95,
      );

      expect(options.timestamp, const Duration(seconds: 10));
      expect(options.width, 800);
      expect(options.height, 600);
      expect(options.format, ThumbnailFormat.png);
      expect(options.quality, 95);

      final result = VideoThumbnailResult.memory(
        width: 800,
        height: 600,
        format: ThumbnailFormat.png,
        actualTimestamp: Duration(seconds: 10),
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]), // PNG magic bytes
      );

      expect(result.width, 800);
      expect(result.height, 600);
      expect(result.format, ThumbnailFormat.png);
      expect(result.isInMemory, true);
    },
  );

  test('Exception types are accessible from example', () {
    expect(VideoNotFoundException('test.mp4').toString(), contains('test.mp4'));
    expect(
      UnsupportedFormatException('error', format: 'video/av1').toString(),
      contains('video/av1'),
    );
    expect(
      PermissionDeniedException('secret.mp4').toString(),
      contains('secret.mp4'),
    );
    expect(
      TimestampOutOfRangeException(Duration(seconds: 100)).toString(),
      contains('100'),
    );
    expect(
      CorsException('https://example.com').toString(),
      contains('example.com'),
    );
    expect(
      SessionException('error', sessionHandle: 1).toString(),
      contains('1'),
    );
    expect(
      GenerationFailedException('fail', source: 'test.mp4').toString(),
      contains('test.mp4'),
    );
  });
}
