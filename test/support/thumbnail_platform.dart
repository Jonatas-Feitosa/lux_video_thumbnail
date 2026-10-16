import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

final imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);

class TracedResult extends MemoryBackedResult {
  TracedResult({this.failReading = false, bool empty = false})
    : super(
        width: 1,
        height: 1,
        format: ThumbnailFormat.png,
        actualTimestamp: Duration.zero,
        bytes: empty ? Uint8List(0) : imageBytes,
      );
  final bool failReading;
  int disposals = 0;
  @override
  Future<Uint8List> readBytes({int offset = 0, int? length}) async {
    if (failReading) throw StateError('read failed');
    return super.readBytes(offset: offset, length: length);
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await super.dispose();
  }
}

class ThumbnailPlatformFake extends VideoThumbnailPlatform {
  Duration? duration = const Duration(seconds: 10);
  int opens = 0;
  int closes = 0;
  int active = 0;
  int maxActive = 0;
  String? lastSource;
  Uint8List? lastBytes;
  String? lastMimeType;
  final List<ThumbnailOptions> requests = [];
  final List<TracedResult> results = [];
  Future<void> Function()? onOpen;
  Future<VideoThumbnailResult> Function(ThumbnailOptions)? onGenerate;

  @override
  Future<VideoThumbnailSession> openSession(String source) async {
    opens++;
    lastSource = source;
    final handle = opens;
    await onOpen?.call();
    return VideoThumbnailSession.fromPlatformData(
      nativeHandle: handle,
      source: source,
      duration: duration,
      nativeWidth: 320,
      nativeHeight: 180,
    );
  }

  @override
  Future<VideoThumbnailSession> openSessionFromBytes(
    Uint8List bytes, {
    required String mimeType,
  }) {
    lastBytes = bytes;
    lastMimeType = mimeType;
    return openSession('bytes');
  }

  @override
  Future<List<VideoThumbnailResult>> generateThumbnails(
    VideoThumbnailSession session,
    List<ThumbnailOptions> optionsList,
  ) async {
    final options = optionsList.single;
    requests.add(options);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      final custom = onGenerate;
      if (custom != null) return [await custom(options)];
      final result = TracedResult();
      results.add(result);
      return [result];
    } finally {
      active--;
    }
  }

  @override
  Future<void> closeSession(VideoThumbnailSession session) async {
    closes++;
  }

  @override
  Future<VideoThumbnailResult> generateThumbnail({
    required String source,
    required ThumbnailOptions options,
  }) => throw UnimplementedError();
  @override
  Future<bool> isFormatSupported(String mimeType) async => true;
  @override
  Future<Duration?> getVideoDuration(String source) async =>
      const Duration(seconds: 10);
  @override
  Future<String> getPlatformVersion() async => 'test';
}
