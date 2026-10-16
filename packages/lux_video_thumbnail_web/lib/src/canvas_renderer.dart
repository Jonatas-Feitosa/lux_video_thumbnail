import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

/// Encoded image and the actual format returned by the browser.
class RenderedImage {
  RenderedImage({
    required this.data,
    required this.width,
    required this.height,
    required this.format,
  });
  final Uint8List data;
  final int width;
  final int height;
  final ThumbnailFormat format;
}

/// Renders only after the video element has a decoded frame.
class CanvasRenderer {
  static Future<RenderedImage> renderVideoFrame({
    required HTMLVideoElement video,
    required int width,
    required int height,
    required ThumbnailFormat format,
    required int quality,
  }) async {
    if (width < 1 ||
        height < 1 ||
        width > 4096 ||
        height > 4096 ||
        quality < 1 ||
        quality > 100) {
      throw ArgumentError('Invalid thumbnail dimensions or quality');
    }
    if (video.videoWidth == 0 ||
        video.videoHeight == 0 ||
        video.readyState < 2) {
      throw const GenerationFailedException(
        'Video frame is not ready',
        source: 'video',
      );
    }
    final canvas = HTMLCanvasElement()
      ..width = width
      ..height = height;
    try {
      final context = canvas.getContext('2d') as CanvasRenderingContext2D?;
      if (context == null) throw StateError('Canvas 2D is unavailable');
      context.drawImage(
        video,
        0,
        0,
        video.videoWidth,
        video.videoHeight,
        0,
        0,
        width,
        height,
      );
      final completer = Completer<Blob>();
      canvas.toBlob(
        ((Blob? blob) {
          if (blob == null) {
            completer.completeError(
              const GenerationFailedException(
                'Image encoding failed',
                source: 'canvas',
              ),
            );
          } else {
            completer.complete(blob);
          }
        }).toJS,
        format.mimeType,
        (quality / 100).toJS,
      );
      final blob = await completer.future.timeout(const Duration(seconds: 15));
      if (blob.size > ThumbnailLimits.maxThumbnailBytes) {
        throw StateError('Encoded thumbnail exceeds 8 MiB');
      }
      final buffer = await blob.arrayBuffer().toDart.timeout(
        const Duration(seconds: 15),
      );
      final bytes = buffer.toDart.asUint8List();
      if (bytes.isEmpty) {
        throw const GenerationFailedException(
          'Image encoding returned no bytes',
          source: 'canvas',
        );
      }
      final actualFormat = switch (blob.type) {
        'image/jpeg' => ThumbnailFormat.jpeg,
        'image/png' => ThumbnailFormat.png,
        'image/webp' => ThumbnailFormat.webp,
        _ => throw UnsupportedFormatException(
          'Unexpected image encoding',
          format: blob.type,
        ),
      };
      return RenderedImage(
        data: bytes,
        width: width,
        height: height,
        format: actualFormat,
      );
    } catch (error) {
      if (isSecurityError(error)) {
        throw CorsBlockedException(video.src, cause: error);
      }
      rethrow;
    } finally {
      canvas.width = 0;
      canvas.height = 0;
      canvas.remove();
    }
  }

  static bool isSecurityError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('securityerror') || message.contains('tainted');
  }
}
