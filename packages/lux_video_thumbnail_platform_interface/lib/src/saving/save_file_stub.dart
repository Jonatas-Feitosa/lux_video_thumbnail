import 'dart:typed_data';

/// Reports unsupported filesystem operations on browser platforms.
Future<String> saveFile(
  Uint8List bytes, {
  required String extension,
  String? directory,
  String? fileName,
}) async {
  throw UnsupportedError(
    'Filesystem saving is unavailable on web; use readBytes()',
  );
}
