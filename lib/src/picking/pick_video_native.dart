import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'picked_video.dart';

Future<PickedVideo?> pickVideo({PickerCancellation? cancellation}) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw PlatformNotSupportedException(defaultTargetPlatform.name);
  }
  final operation = FilePicker.platform.pickFiles(
    type: FileType.video,
    withData: false,
  );
  final result = cancellation == null
      ? await operation
      : await Future.any([
          operation,
          cancellation.cancelled.then<FilePickerResult?>((_) => null),
        ]);
  if (result == null || result.files.isEmpty) return null;
  final path = result.files.single.path;
  if (path == null) throw const VideoNotFoundException('Selected video');
  return PickedVideo(VideoSource.path(path));
}
