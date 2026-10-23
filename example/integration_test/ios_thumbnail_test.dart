import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

import 'fixtures/video.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lux_video_thumbnail');
  final platform = MethodChannelVideoThumbnail();
  late Directory directory;
  late File video;
  final bytes = base64Decode(redBlueMp4Base64);

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('lux-ios-test-');
    video = await File(
      '${directory.path}/video with spaces.mp4',
    ).writeAsBytes(bytes);
  });
  tearDownAll(() => directory.delete(recursive: true));

  Future<void> color(VideoThumbnailResult result, {required bool blue}) async {
    try {
      final codec = await ui.instantiateImageCodec(await result.readBytes());
      try {
        final frame = await codec.getNextFrame();
        try {
          final pixels = (await frame.image.toByteData())!;
          final offset =
              (frame.image.height ~/ 2 * frame.image.width +
                  frame.image.width ~/ 2) *
              4;
          expect(pixels.getUint8(offset + (blue ? 2 : 0)), greaterThan(180));
          expect(pixels.getUint8(offset + (blue ? 0 : 2)), lessThan(70));
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      await result.dispose();
    }
  }

  testWidgets('native iOS registers and reads real metadata', (_) async {
    expect(defaultTargetPlatform, TargetPlatform.iOS);
    expect(await platform.getPlatformVersion(), startsWith('iOS '));
    final session = await platform.openSession(video.path);
    try {
      expect(session.nativeWidth, 64);
      expect(session.nativeHeight, 48);
      expect(session.duration!.inMilliseconds, closeTo(2000, 10));
      expect(
        await platform.getVideoDuration(video.uri.toString()),
        session.duration,
      );
      expect(await platform.isFormatSupported('video/mp4'), isTrue);
      expect(await platform.isFormatSupported('video/not-real'), isFalse);
    } finally {
      await platform.closeSession(session);
    }
    expect(await video.exists(), isTrue);
  });

  testWidgets('byte sessions decode red/blue JPEG and PNG at requested times', (
    _,
  ) async {
    final session = await platform.openSessionFromBytes(
      bytes,
      mimeType: 'video/mp4',
    );
    try {
      final results = await platform.generateThumbnails(session, [
        ThumbnailOptions(
          timestamp: const Duration(milliseconds: 200),
          width: 32,
        ),
        ThumbnailOptions(
          timestamp: const Duration(microseconds: 1500123),
          width: 32,
          format: ThumbnailFormat.png,
        ),
      ]);
      expect(results.map((r) => r.width), [32, 32]);
      expect(results.map((r) => r.height), [24, 24]);
      expect(results[1].actualTimestamp.inMicroseconds, 1500123);
      expect((await results[0].readBytes()).take(2), [255, 216]);
      expect((await results[1].readBytes()).take(4), [137, 80, 78, 71]);
      await color(results[0], blue: false);
      await color(results[1], blue: true);
    } finally {
      await platform.closeSession(session);
    }
  });

  testWidgets('file URL, single extraction, endpoint and stretched geometry', (
    _,
  ) async {
    final output = await platform.generateThumbnail(
      source: video.uri.toString(),
      options: ThumbnailOptions(
        timestamp: const Duration(seconds: 2),
        width: 40,
        height: 40,
        maintainAspectRatio: false,
      ),
    );
    expect(output.width, 40);
    expect(output.height, 40);
    expect(output.actualTimestamp.inMicroseconds, 1999999);
    await color(output, blue: true);
    expect(await video.exists(), isTrue);
  });

  testWidgets('chunks, saving and disposal keep caller files intact', (
    _,
  ) async {
    final session = await platform.openSession(video.path);
    late VideoThumbnailResult output;
    late String path;
    try {
      final raw =
          (await channel.invokeListMethod<dynamic>('generateThumbnails', {
                'sessionHandle': session.nativeHandle,
                'options': [
                  {'timestampUs': 0},
                ],
              }))!.single
              as Map<dynamic, dynamic>;
      path = raw['tempPath'] as String;
      output = VideoThumbnailResult.file(
        width: raw['width'] as int,
        height: raw['height'] as int,
        format: ThumbnailFormat.jpeg,
        actualTimestamp: Duration.zero,
        nativeTempPath: path,
        channel: channel,
      );
    } finally {
      await platform.closeSession(session);
    }
    final data = await output.readBytes();
    late String saved;
    try {
      expect(
        await MethodChannelVideoThumbnail.readThumbnailChunk(
          path: path,
          offset: 2,
          length: 5,
        ),
        data.sublist(2, 7),
      );
      saved = await output.saveToFile(
        directory: directory.path,
        fileName: 'saved.jpg',
      );
      expect(await File(saved).readAsBytes(), data);
      final copied = '${directory.path}/copied.jpg';
      await MethodChannelVideoThumbnail.copyThumbnailFile(
        sourcePath: path,
        targetPath: copied,
      );
      expect(await File(copied).readAsBytes(), data);
    } finally {
      await output.dispose();
    }
    expect(await video.exists(), isTrue);
    expect(await File(saved).exists(), isTrue);
  });

  testWidgets(
    'native validation rejects invalid timestamps, WebP and borrowed paths',
    (_) async {
      final session = await platform.openSession(video.path);
      try {
        Future<void> rejects(Map<String, Object?> options, String code) async {
          await expectLater(
            channel.invokeMethod<Object?>('generateThumbnails', {
              'sessionHandle': session.nativeHandle,
              'options': [options],
            }),
            throwsA(
              isA<PlatformException>().having((e) => e.code, 'code', code),
            ),
          );
        }

        await rejects({'timestampUs': -1}, 'TIMESTAMP_OUT_OF_RANGE');
        await rejects({'timestampUs': 2000001}, 'TIMESTAMP_OUT_OF_RANGE');
        await rejects({
          'timestampUs': 0,
          'format': 'webp',
        }, 'UNSUPPORTED_FORMAT');
        await rejects({'timestampUs': 0, 'width': 4097}, 'ARGUMENT_ERROR');
        await expectLater(
          MethodChannelVideoThumbnail.deleteThumbnailFile(video.path),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'PERMISSION_DENIED',
            ),
          ),
        );
        expect(await video.exists(), isTrue);
      } finally {
        await platform.closeSession(session);
      }
    },
  );

  testWidgets('public iOS API returns usable bytes and releases sessions', (
    _,
  ) async {
    for (var index = 0; index < 6; index++) {
      final data = await LuxVideoThumbnail.generate(
        source: VideoSource.path(video.path),
        timestamp: const Duration(milliseconds: 1500),
        width: 32,
      );
      expect(data.bytes, isNotEmpty);
      expect(data.width, 32);
      expect(data.height, 24);
    }
  });

  testWidgets(
    'session limit recovers after close and closed handles reject generation',
    (_) async {
      final sessions = <VideoThumbnailSession>[];
      try {
        for (var index = 0; index < 4; index++) {
          sessions.add(await platform.openSession(video.path));
        }
        await expectLater(
          platform.openSession(video.path),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'RESOURCE_LIMIT',
            ),
          ),
        );
      } finally {
        for (final session in sessions) {
          await platform.closeSession(session);
        }
      }
      await expectLater(
        channel.invokeMethod<Object?>('generateThumbnails', {
          'sessionHandle': sessions.first.nativeHandle,
          'options': [
            {'timestampUs': 0},
          ],
        }),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'SESSION_INVALID',
          ),
        ),
      );
      final recovered = await platform.openSession(video.path);
      await platform.closeSession(recovered);
    },
  );
}
