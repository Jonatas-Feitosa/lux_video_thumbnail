import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'package:lux_video_thumbnail_web/lux_video_thumbnail_web.dart';
import 'fixtures/temporal_fixtures.dart';

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> _reject(
  Future<Object?> Function() work,
  bool Function(Object) check,
) async {
  try {
    await work();
  } catch (error) {
    _require(check(error), 'Unexpected failure: $error');
    return;
  }
  throw StateError('Expected rejection');
}

Map<String, Future<void> Function()> resourceChecks() => {
  'web filesystem saving is explicitly unsupported': () async {
    final result = VideoThumbnailResult.memory(
      width: 1,
      height: 1,
      format: ThumbnailFormat.png,
      actualTimestamp: Duration.zero,
      bytes: Uint8List.fromList([1]),
    );
    try {
      await _reject(() => result.saveToFile(), (e) => e is UnsupportedError);
      await _reject(() => result.readBytes(offset: -1), (e) => e is RangeError);
      await result.dispose();
      await _reject(() => result.length, (e) => e is StateError);
    } finally {
      await result.dispose();
    }
  },
  'opening sessions reserves capacity before asynchronous metadata': () async {
    final platform = LuxVideoThumbnailWeb();
    final opening = [
      for (var i = 0; i < 4; i++)
        platform.openSessionFromBytes(
          base64Decode(lowRateBase64),
          mimeType: 'video/mp4',
        ),
    ];
    final sessions = <VideoThumbnailSession>[];
    try {
      await _reject(
        () => platform.openSessionFromBytes(
          base64Decode(lowRateBase64),
          mimeType: 'video/mp4',
        ),
        (e) => e is StateError,
      );
      sessions.addAll(await Future.wait(opening));
      await platform.closeSession(sessions.removeLast());
      sessions.add(
        await platform.openSessionFromBytes(
          base64Decode(lowRateBase64),
          mimeType: 'video/mp4',
        ),
      );
    } finally {
      // Wait for all accepted openings even if a regression causes the rejection check to fail.
      for (final future in opening) {
        final session = await future;
        await platform.closeSession(session);
      }
      for (final session in sessions) {
        await platform.closeSession(session);
      }
    }
  },
  'web queue rejects overflow and releases accepted work': () async {
    final manager = VideoElementManager(source: 'unused');
    final gate = Completer<void>();
    final pending = [
      for (var i = 0; i < 16; i++)
        manager.exclusive(() async {
          await gate.future;
          return i;
        }),
    ];
    try {
      await _reject(
        () => manager.exclusive(() async => 99),
        (e) => e is StateError,
      );
      gate.complete();
      _require((await Future.wait(pending)).length == 16, 'Accepted work lost');
      _require(
        await manager.exclusive(() async => 42) == 42,
        'Capacity did not recover',
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
      await manager.close();
    }
  },
  'web batch and derived dimensions reject before producing oversized images':
      () async {
        final platform = LuxVideoThumbnailWeb();
        final session = await platform.openSessionFromBytes(
          base64Decode(lowRateBase64),
          mimeType: 'video/mp4',
        );
        try {
          await _reject(
            () => platform.generateThumbnails(
              session,
              List.generate(
                17,
                (_) => ThumbnailOptions(timestamp: Duration.zero),
              ),
            ),
            (e) => e is ArgumentError,
          );
          // This 4:3 source would require width 5461 for a height of 4096.
          await _reject(
            () => platform.generateThumbnails(session, [
              ThumbnailOptions(timestamp: Duration.zero, height: 4096),
            ]),
            (e) => e is ArgumentError,
          );
          final result = (await platform.generateThumbnails(session, [
            ThumbnailOptions(timestamp: Duration.zero, width: 32),
          ])).single;
          _require(
            (await result.readBytes()).isNotEmpty,
            'Session did not recover',
          );
          await result.dispose();
        } finally {
          await platform.closeSession(session);
        }
      },
};
