// mock_video_thumbnail_platform.dart
// Mock implementation of VideoThumbnailPlatform for testing.

import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';

/// Mock implementation of [VideoThumbnailPlatform] for unit testing.
///
/// Provides configurable behavior for testing the app-facing package
/// without requiring native implementations.
class MockVideoThumbnailPlatform extends VideoThumbnailPlatform {
  MockVideoThumbnailPlatform();

  // Configurable behavior
  final Map<String, VideoThumbnailSession> _sessions = {};
  final Map<String, List<VideoThumbnailResult>> _sessionResults = {};
  final Map<String, Duration?> _videoDurations = {};
  final Map<String, bool> _formatSupport = {};
  VideoThumbnailException? _nextException;
  VideoThumbnailException? _persistentException;
  int _nextHandle = 1;

  /// Sets a result for a specific video source.
  ///
  /// When [generateThumbnails] is called for [source], returns [results]
  /// in order (clamped to the number of requested options).
  void setResultsForSource(String source, List<VideoThumbnailResult> results) {
    _sessionResults[source] = results;
  }

  /// Sets the video duration for a source.
  void setVideoDuration(String source, Duration? duration) {
    _videoDurations[source] = duration;
  }

  /// Sets format support for a MIME type.
  void setFormatSupported(String mimeType, bool supported) {
    _formatSupport[mimeType.toLowerCase()] = supported;
  }

  /// Configures the next call to throw an exception (one-time).
  void setNextException(VideoThumbnailException exception) {
    _nextException = exception;
  }

  /// Configures all calls to throw an exception until cleared.
  void setPersistentException(VideoThumbnailException exception) {
    _persistentException = exception;
  }

  /// Clears any configured exception.
  void clearException() {
    _nextException = null;
    _persistentException = null;
  }

  /// Returns the last opened session for a source (for verification).
  VideoThumbnailSession? getSession(String source) => _sessions[source];

  /// Returns all opened sessions.
  Map<String, VideoThumbnailSession> get allSessions =>
      Map.unmodifiable(_sessions);

  @override
  Future<VideoThumbnailSession> openSession(String source) async {
    // Check persistent exception first
    if (_persistentException != null) {
      throw _persistentException!;
    }
    // Then check one-time exception
    if (_nextException != null) {
      final ex = _nextException!;
      _nextException = null;
      throw ex;
    }

    if (!_sessionResults.containsKey(source)) {
      throw VideoNotFoundException(source);
    }

    final duration = _videoDurations[source];
    final session = VideoThumbnailSession.fromPlatformData(
      nativeHandle: _nextHandle++,
      source: source,
      duration: duration,
      nativeWidth: 1920,
      nativeHeight: 1080,
      metadata: {'mock': true},
    );
    _sessions[source] = session;
    return session;
  }

  @override
  Future<List<VideoThumbnailResult>> generateThumbnails(
    VideoThumbnailSession session,
    List<ThumbnailOptions> optionsList,
  ) async {
    // Check persistent exception first
    if (_persistentException != null) {
      throw _persistentException!;
    }
    // Then check one-time exception
    if (_nextException != null) {
      final ex = _nextException!;
      _nextException = null;
      throw ex;
    }

    final results = _sessionResults[session.source] ?? [];
    if (results.isEmpty) {
      // Generate fake results based on options
      return optionsList.map((opt) => _createFakeResult(opt)).toList();
    }

    // Return results matching the requested count
    return List.generate(optionsList.length, (i) {
      if (i < results.length) {
        return results[i];
      }
      return _createFakeResult(optionsList[i]);
    });
  }

  @override
  Future<void> closeSession(VideoThumbnailSession session) async {
    if (_persistentException != null) {
      throw _persistentException!;
    }
    if (_nextException != null) {
      final ex = _nextException!;
      _nextException = null;
      throw ex;
    }
    _sessions.remove(session.source);
  }

  @override
  Future<VideoThumbnailResult> generateThumbnail({
    required String source,
    required ThumbnailOptions options,
  }) async {
    if (_persistentException != null) {
      throw _persistentException!;
    }
    if (_nextException != null) {
      final ex = _nextException!;
      _nextException = null;
      throw ex;
    }

    final results = _sessionResults[source] ?? [];
    if (results.isNotEmpty) {
      return results.first;
    }
    return _createFakeResult(options);
  }

  @override
  Future<bool> isFormatSupported(String mimeType) async {
    return _formatSupport[mimeType.toLowerCase()] ?? true;
  }

  @override
  Future<Duration?> getVideoDuration(String source) async {
    return _videoDurations[source];
  }

  @override
  Future<String> getPlatformVersion() async {
    return 'mock';
  }

  VideoThumbnailResult _createFakeResult(ThumbnailOptions options) {
    return VideoThumbnailResult.memory(
      width: options.width ?? 1920,
      height: options.height ?? 1080,
      format: options.format,
      actualTimestamp: options.timestamp,
      bytes: Uint8List.fromList(List.filled(1024, 0xFF)), // 1KB fake JPEG
    );
  }

  /// Resets all mock state.
  void reset() {
    _sessions.clear();
    _sessionResults.clear();
    _videoDurations.clear();
    _formatSupport.clear();
    _nextException = null;
    _persistentException = null;
    _nextHandle = 1;
  }
}

/// Creates a mock [VideoThumbnailResult] with specified properties.
VideoThumbnailResult createMockResult({
  required Duration timestamp,
  int width = 1920,
  int height = 1080,
  ThumbnailFormat format = ThumbnailFormat.jpeg,
  int byteSize = 1024,
}) {
  return VideoThumbnailResult.memory(
    width: width,
    height: height,
    format: format,
    actualTimestamp: timestamp,
    bytes: Uint8List.fromList(List.filled(byteSize, 0xFF)),
  );
}
