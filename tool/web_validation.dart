// Standalone release probe, including Firefox (Flutter's runner is Chrome-only).
import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';
import 'package:lux_video_thumbnail/src/picking/pick_video_web.dart' as picker;
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'package:web/web.dart' as web;
import '../test/fixtures/format_fixtures.dart';
import '../test/fixtures/video_fixture.dart';
import '../test/temporal_checks.dart';
import '../test/resource_checks.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <String, String>{};
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> check(String name, Future<void> Function() work) async {
    try {
      await work();
      results[name] = 'passed';
    } catch (error, stack) {
      results[name] = '$error\n$stack';
    }
  }

  await check('runtime/automatic-registration', () async {
    require(
      kIsWasm == (Uri.base.queryParameters['wasm'] == 'true'),
      'Wrong compiler',
    );
    require(
      await LuxVideoThumbnail().getPlatformVersion() == 'Web',
      'No registration',
    );
  });
  for (final fixture in {
    'mp4': redBlueMp4Base64,
    'vp8': redBlueVideoBase64,
    'vp9': redBlueVp9Base64,
    'live': redBlueLiveBase64,
  }.entries) {
    for (final format in ThumbnailFormat.values) {
      await check('${fixture.key}/${format.name}', () async {
        final image = await LuxVideoThumbnail.generate(
          source: VideoSource.bytes(
            base64Decode(fixture.value).asUnmodifiableView(),
            mimeType: fixture.key == 'mp4' ? 'video/mp4' : 'video/webm',
          ),
          timestamp: const Duration(milliseconds: 1500),
          width: 32,
          format: format,
        );
        require(image.width == 32 && image.height == 24, 'Wrong dimensions');
        require(switch (image.format) {
          ThumbnailFormat.png => image.bytes[0] == 137 && image.bytes[1] == 80,
          ThumbnailFormat.jpeg =>
            image.bytes[0] == 255 && image.bytes[1] == 216,
          ThumbnailFormat.webp =>
            ascii.decode(image.bytes.sublist(8, 12)) == 'WEBP',
        }, 'Incorrect encoded image format');
        final codec = await ui.instantiateImageCodec(image.bytes);
        final frame = await codec.getNextFrame();
        try {
          final rgba = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          require(
            rgba!.getUint8(2) > 180 && rgba.getUint8(0) < 60,
            'Wrong frame',
          );
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      });
    }
  }
  await check('metadata/known-and-unknown-duration', () async {
    final platform = VideoThumbnailPlatform.instance;
    for (final fixture in [redBlueMp4Base64, redBlueLiveBase64]) {
      final session = await platform.openSessionFromBytes(
        base64Decode(fixture),
        mimeType: fixture == redBlueMp4Base64 ? 'video/mp4' : 'video/webm',
      );
      try {
        if (fixture == redBlueMp4Base64) {
          require(
            session.duration == const Duration(seconds: 2),
            'Wrong MP4 duration',
          );
        } else {
          final firefox = web.window.navigator.userAgent.contains('Firefox/');
          require(
            firefox
                ? session.duration == const Duration(seconds: 2)
                : session.duration == null,
            'Unexpected browser live metadata: ${session.duration}',
          );
        }
      } finally {
        await platform.closeSession(session);
      }
    }
  });
  await check('invalid/non-video', () async {
    try {
      await LuxVideoThumbnail.generate(
        source: VideoSource.bytes(
          Uint8List.fromList([1, 2, 3]),
          mimeType: 'video/mp4',
        ),
        timestamp: Duration.zero,
      );
    } on VideoThumbnailException {
      return;
    }
    throw StateError('Invalid bytes accepted');
  });
  await check('remote/allowed', () async {
    final image = await LuxVideoThumbnail.generate(
      source: VideoSource.url('http://127.0.0.1:18761/red_blue.mp4'),
      timestamp: Duration.zero,
    );
    require(image.bytes.isNotEmpty, 'Empty image');
  });
  for (final source in [
    'http://127.0.0.1:18762/red_blue.mp4',
    'http://127.0.0.1:18761/missing',
    'http://127.0.0.1:18761/disconnect',
  ]) {
    await check('failure/$source', () async {
      try {
        await LuxVideoThumbnail.generate(
          source: VideoSource.url(source),
          timestamp: Duration.zero,
        );
      } on VideoThumbnailException catch (error) {
        require(
          error is! CorsException && error is! CorsBlockedException,
          'False CORS diagnosis',
        );
        return;
      }
      throw StateError('Invalid source accepted');
    });
  }
  await check('picker/delayed-focus-repeated-release', () async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final pending = picker.pickVideo();
      final input =
          web.document.querySelector('input[type=file]')!
              as web.HTMLInputElement;
      web.window.dispatchEvent(web.Event('focus'));
      await Future<void>.delayed(const Duration(milliseconds: 650));
      require(input.isConnected, 'Focus cancelled valid selection');
      final transfer = web.DataTransfer();
      transfer.items.add(
        web.File(
          <web.BlobPart>[
            base64Decode(redBlueMp4Base64).toJS,
            Uint8List(16 * 1024 * 1024).toJS,
          ].toJS,
          'large.mp4',
          web.FilePropertyBag(type: 'video/mp4'),
        ),
      );
      input.files = transfer.files;
      input.dispatchEvent(web.Event('change'));
      final picked = (await pending)!;
      final image = await LuxVideoThumbnail.generate(
        source: picked.source,
        timestamp: Duration.zero,
      );
      require(image.bytes.isNotEmpty, 'No file thumbnail');
      await picked.dispose();
      await picked.dispose();
      require(!input.isConnected, 'Input retained');
      var revoked = false;
      try {
        await web.window.fetch(picked.source.location!.toJS).toDart;
      } catch (_) {
        revoked = true;
      }
      require(revoked, 'URL not revoked');
      final cancelled = picker.pickVideo();
      web.document
          .querySelector('input[type=file]')!
          .dispatchEvent(web.Event('cancel'));
      require(await cancelled == null, 'Cancel failed');
      require(
        web.document.querySelector('input[type=file]') == null,
        'Cancelled input retained',
      );
    }
  });
  for (final temporal in temporalChecks().entries) {
    await check('temporal/${temporal.key}', temporal.value);
  }
  for (final resource in resourceChecks().entries) {
    await check('resources/${resource.key}', resource.value);
  }
  final report = jsonEncode({
    'wasm': kIsWasm,
    'browser': web.window.navigator.userAgent,
    'results': results,
  });
  web.document.body!.textContent = report;
  await web.window
      .fetch('/report'.toJS, web.RequestInit(method: 'POST', body: report.toJS))
      .toDart;
}
