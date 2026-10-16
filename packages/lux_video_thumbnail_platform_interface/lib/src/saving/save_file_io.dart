import 'dart:io';
import 'dart:typed_data';

/// Creates a new file, never replaces an existing caller file.
Future<String> saveFile(
  Uint8List bytes, {
  required String extension,
  String? directory,
  String? fileName,
}) async {
  if (fileName != null &&
      (fileName.isEmpty ||
          fileName.length > 200 ||
          fileName == '.' ||
          fileName == '..' ||
          RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(fileName) ||
          fileName.endsWith('.') ||
          fileName.endsWith(' '))) {
    throw ArgumentError('fileName must be a plain file name');
  }
  final parent = directory == null
      ? Directory.systemTemp
      : Directory(directory);
  await parent.create(recursive: true);
  // Exclusive directory creation prevents overwrite and filename collisions.
  final destination = await parent.createTemp('lux_thumbnail_');
  final name = fileName ?? 'thumbnail.$extension';
  final file = File('${destination.path}${Platform.pathSeparator}$name');
  try {
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    try {
      await file.delete();
    } on FileSystemException {
      /* Preserve write failure. */
    }
    try {
      await destination.delete();
    } on FileSystemException {
      /* Best effort. */
    }
    rethrow;
  }
}
