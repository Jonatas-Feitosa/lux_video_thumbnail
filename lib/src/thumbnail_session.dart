import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'thumbnail_data.dart';

/// Internal session shared by the one-shot API and picker.
class ThumbnailSession {
  ThumbnailSession._(this.platform, this.handle);

  final VideoThumbnailPlatform platform;
  final VideoThumbnailSession handle;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  int _pending = 0;

  static Future<ThumbnailSession> open(VideoSource source) async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      throw PlatformNotSupportedException(defaultTargetPlatform.name);
    }
    if (kIsWeb && source.type == VideoSourceType.path) {
      throw const PlatformNotSupportedException('Web native file paths');
    }
    final platform = VideoThumbnailPlatform.instance;
    try {
      final handle = source.type == VideoSourceType.bytes
          ? await platform.openSessionFromBytes(
              source.data!,
              mimeType: source.mimeType!,
            )
          : await platform.openSession(source.location!);
      return ThumbnailSession._(platform, handle);
    } on MissingPluginException catch (error) {
      throw PlatformNotSupportedException(
        kIsWeb ? 'Web' : 'Android',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw switch (error.code) {
        'UNSUPPORTED_FORMAT' => UnsupportedFormatException(
          'Video could not be decoded',
          cause: error,
          code: error.code,
        ),
        'PERMISSION_DENIED' => PermissionDeniedException(
          'video',
          cause: error,
          code: error.code,
        ),
        'VIDEO_NOT_FOUND' => VideoNotFoundException(
          'video',
          cause: error,
          code: error.code,
        ),
        _ => GenerationFailedException(
          'Could not open video',
          source: 'video',
          cause: error,
          code: error.code,
        ),
      };
    }
  }

  Future<VideoThumbnailData> generate(
    ThumbnailOptions options, {
    bool Function()? isCurrent,
  }) {
    if (_closing != null) return Future.error(StateError('Session is closing'));
    if (_pending >= ThumbnailLimits.maxPendingOperations) {
      return Future.error(StateError('Session queue resource limit exceeded'));
    }
    _pending++;
    final operation = _tail.then((_) async {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Superseded preview request');
      }
      validateOptions(options);
      options.validateTimestamp(handle.duration);
      final results = await platform.generateThumbnails(handle, [options]);
      if (results.length != 1) {
        for (final result in results) {
          await result.dispose();
        }
        throw const GenerationFailedException(
          'Expected one thumbnail',
          source: 'video',
        );
      }
      final result = results.single;
      try {
        final bytes = await result.readBytes();
        if (bytes.isEmpty) {
          throw const GenerationFailedException(
            'Empty thumbnail',
            source: 'video',
          );
        }
        return VideoThumbnailData(
          bytes: bytes,
          timestamp: options.timestamp,
          width: result.width,
          height: result.height,
          format: result.format,
        );
      } finally {
        await result.dispose();
      }
    });
    // Failures must not poison the queue or prevent session cleanup.
    _tail = operation
        .whenComplete(() {
          _pending--;
        })
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return operation;
  }

  Future<void> close() =>
      _closing ??= _tail.then((_) => platform.closeSession(handle));

  static void validateOptions(ThumbnailOptions options) {
    if (options.timestamp < Duration.zero) {
      throw ArgumentError('Negative timestamp');
    }
    if (options.quality < 1 || options.quality > 100) {
      throw ArgumentError('Quality must be 1–100');
    }
    for (final value in [options.width, options.height]) {
      if (value != null && (value < 1 || value > 4096)) {
        throw ArgumentError('Thumbnail dimensions must be 1–4096');
      }
    }
  }
}
