# lux_video_thumbnail_platform_interface

Shared contracts for `lux_video_thumbnail`, a Flutter plugin for video thumbnails
on Android and web. Applications should normally depend on the main package,
which provides `LuxVideoThumbnail.generate` and `VideoThumbnailPicker`.

## Platform implementers and advanced users

Import `package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart`.
`VideoThumbnailPlatform` defines session opening, batch extraction, closing,
format checks and duration lookup. Implementations register with `setInstance`.
`MethodChannelVideoThumbnail` provides the Android channel implementation.

`VideoSource` supports byte buffers, borrowed native paths/content URIs and
HTTP(S)/browser Blob URLs. Source paths never transfer file ownership.
`ThumbnailOptions` validates timestamps, dimensions and quality in release builds.
`ThumbnailLimits` documents resource ceilings shared by the implementations.

For sessions, use `try/finally` to call `closeSession`. Dispose every advanced
`VideoThumbnailResult` after reading it. Closing drains accepted session work and
rejects new work. A failed operation does not poison subsequent operations.

## Timestamp and result contracts

Known-duration bounds are enforced; an exact endpoint targets the last valid
position, while unknown duration does not reset the request to zero. Seek results
depend on the decoder. Legacy `actualTimestamp` is the normalized requested
position, not a measured frame presentation timestamp.

`readBytes` supports bounded ranges. Negative ranges and offsets beyond EOF are
rejected. `saveToFile` returns `Future<String>` containing a native path, replacing
the prepublication `Future<File>` signature. It creates a fresh subdirectory under
the chosen parent or the system temporary directory and never overwrites an
existing file. The caller owns the saved file and directory after result disposal.
Web filesystem saving throws `UnsupportedError`; use bytes for app-managed
download/upload. Disposed results reject reads, size queries and saves.

## Support and development

Supported SDK floor: Dart 3.10.9 and Flutter 3.38.10. The package defines contracts;
it does not implement iOS, desktop or a browser decoder by itself. Errors are
represented by the exported exception hierarchy and platform channel codes.

In a full monorepo checkout, prepare the root local dependency overrides before
running Flutter commands in dependent packages. Consumers use hosted dependencies.
See the main package for the picker example, platform behavior and test coverage.

## License

MIT, Copyright (c) 2026 Jônatas Feitosa. See [LICENSE](LICENSE).
