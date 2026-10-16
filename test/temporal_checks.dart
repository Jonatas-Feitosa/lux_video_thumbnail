import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'package:lux_video_thumbnail_web/lux_video_thumbnail_web.dart';
import 'fixtures/temporal_fixtures.dart';
import 'fixtures/format_fixtures.dart';

void requireTemporal(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

Future<void> checkTemporalPixel(VideoThumbnailData image, bool red) async {
  final codec = await ui.instantiateImageCodec(image.bytes);
  final frame = await codec.getNextFrame();
  try {
    final data = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final r = data.getUint8(0), b = data.getUint8(2);
    requireTemporal(
      red ? r > 180 && b < 70 : b > 180 && r < 70,
      'Expected ${red ? 'red' : 'blue'}; observed R=$r B=$b',
    );
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

Map<String, Future<void> Function()> temporalChecks() {
  VideoSource source(String data, [String type = 'video/mp4']) =>
      VideoSource.bytes(base64Decode(data), mimeType: type);
  Future<void> color(
    String data,
    int milliseconds,
    bool red, {
    String mime = 'video/mp4',
  }) async {
    final requested = Duration(milliseconds: milliseconds);
    final image = await LuxVideoThumbnail.generate(
      source: source(data, mime),
      timestamp: requested,
      width: 32,
      format: ThumbnailFormat.png,
    );
    requireTemporal(image.timestamp == requested, 'Requested position changed');
    await checkTemporalPixel(image, red);
  }

  Future<void> resultColor(VideoThumbnailResult result, bool red) async {
    try {
      await checkTemporalPixel(
        VideoThumbnailData(
          bytes: await result.readBytes(),
          timestamp: result.actualTimestamp,
          width: result.width,
          height: result.height,
          format: result.format,
        ),
        red,
      );
    } finally {
      await result.dispose();
    }
  }

  return {
    'long GOP decodes ordinary frames away from the only keyframe': () async {
      await color(longGopBase64, 0, true);
      await color(longGopBase64, 1500, true);
      await color(longGopBase64, 3500, false);
    },
    'low FPS long-held frames are valid at intermediate positions': () async {
      await color(lowRateBase64, 1500, true);
      await color(lowRateBase64, 3500, false);
    },
    'variable frame intervals preserve the held frame and next color':
        () async {
          await color(variableRateBase64, 1500, true);
          await color(variableRateBase64, 2800, false);
        },
    'recovery stops before the next sparse frame boundary': () async {
      await color(lowRateBase64, 1950, true);
      await color(variableRateBase64, 2450, true);
    },
    'exact endpoints select last frame and preserve requested timestamp':
        () async {
          for (final data in [
            longGopBase64,
            lowRateBase64,
            variableRateBase64,
          ]) {
            await color(data, 4000, false);
          }
        },
    'unindexed WebM can recover the requested frame': () =>
        color(redBlueLiveBase64, 1500, false, mime: 'video/webm'),
    'invalid batch fails and same decoder recovers': () async {
      final platform = VideoThumbnailPlatform.instance;
      final session = await platform.openSessionFromBytes(
        base64Decode(longGopBase64),
        mimeType: 'video/mp4',
      );
      try {
        var rejected = false;
        try {
          await platform.generateThumbnails(session, [
            ThumbnailOptions(timestamp: Duration.zero),
            ThumbnailOptions(timestamp: const Duration(microseconds: 4000001)),
          ]);
        } on TimestampOutOfRangeException {
          rejected = true;
        }
        requireTemporal(rejected, 'Beyond-end batch was silently clamped');
        final image = (await platform.generateThumbnails(session, [
          ThumbnailOptions(
            timestamp: const Duration(milliseconds: 3500),
            format: ThumbnailFormat.png,
          ),
        ])).single;
        await resultColor(image, false);
      } finally {
        await platform.closeSession(session);
      }
    },
    'accepted concurrent seeks finish before close and late work is rejected':
        () async {
          final platform = VideoThumbnailPlatform.instance;
          final session = await platform.openSessionFromBytes(
            base64Decode(lowRateBase64),
            mimeType: 'video/mp4',
          );
          final first = platform.generateThumbnails(session, [
            ThumbnailOptions(
              timestamp: const Duration(milliseconds: 3500),
              format: ThumbnailFormat.png,
            ),
          ]);
          final second = platform.generateThumbnails(session, [
            ThumbnailOptions(
              timestamp: const Duration(milliseconds: 500),
              format: ThumbnailFormat.png,
            ),
          ]);
          final closing = platform.closeSession(session);
          var duplicateFinished = false;
          final duplicate = platform.closeSession(session).then((_) {
            duplicateFinished = true;
          });
          await Future<void>.delayed(const Duration(milliseconds: 30));
          requireTemporal(
            !duplicateFinished,
            'Duplicate close raced active decoder',
          );
          var rejected = false;
          try {
            await platform.generateThumbnails(session, [
              ThumbnailOptions(timestamp: Duration.zero),
            ]);
          } on SessionException {
            rejected = true;
          }
          requireTemporal(rejected, 'Late work accepted while closing');
          await resultColor((await first).single, false);
          await resultColor((await second).single, true);
          await closing;
          await duplicate;
          await platform.closeSession(session);
        },
    'manager close drains failure and queued work without accepting new work':
        () async {
          final manager = VideoElementManager(source: 'unused');
          final gate = Completer<void>();
          final first = manager.exclusive<void>(() async {
            await gate.future;
            throw StateError('injected');
          });
          final handled = first.then<void>(
            (_) => throw StateError('Failure lost'),
            onError: (Object _) {},
          );
          final second = manager.exclusive<int>(() async => 42);
          final closed = manager.close();
          var rejected = false;
          try {
            await manager.exclusive<int>(() async => 0);
          } on StateError {
            rejected = true;
          }
          requireTemporal(rejected, 'Manager accepted work after close');
          gate.complete();
          await handled;
          requireTemporal(await second == 42, 'Queue poisoned by failure');
          await closed;
          await manager.close();
          requireTemporal(
            manager.video.getAttribute('src') == null,
            'Disposed video retained its source',
          );
        },
  };
}
