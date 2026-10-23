# lux_video_thumbnail_ios

The endorsed iOS implementation of `lux_video_thumbnail`. Depend on the main
package to use its API, embedded picker, and dialog. Requires iOS 13+, Flutter
3.38.10+ and Dart 3.10.9+.

Uses AVFoundation for local absolute paths, `file://` URLs, HTTP(S) URLs and raw
video bytes. Supports reusable sessions, microsecond seek requests, rotation,
aspect ratio or stretched sizing, JPEG/PNG, file-backed results, chunk reading,
copying and disposal. WebP output returns `UNSUPPORTED_FORMAT`. Video container
and codec support depends on AVFoundation and the device; MIME checks are hints.
Protected videos and unsupported codecs return an error. Remote HTTP access is
subject to the host app's App Transport Security policy; prefer HTTPS.

Media and file operations use a serial background worker with main-thread
replies. Limits: four sessions, batches of 16, 16 queued engine calls, 64 MiB
queued input bytes, 64 retained thumbnails, 4096 pixels per dimension and 8 MiB
per encoded output/read. The image limit is checked after native encoding.
Metadata loading has a 30-second timeout. Frame extraction itself has no hard
timeout; stuck native work can delay engine cleanup.

Only plugin-created input files and thumbnails are deleted. Closing a session
removes its byte-source temporary; returned thumbnails survive until disposed
or until the engine detaches. Borrowed input paths are never deleted. Output
timestamps identify normalized requests, rather than measured frame PTS.
`preferKeyFrame` permits approximate native seeking as a speed hint.

Includes CocoaPods and Swift Package Manager manifests. No third-party native
codec is bundled. For `file_picker`'s video gallery UI, add a localized
`NSPhotoLibraryUsageDescription` to your app's Info.plist. Direct extraction of
files already accessible to the app needs no photo-library permission.

Native compilation and runtime validation require macOS/Xcode. The repository
example contains an `ios_thumbnail_test.dart` integration suite and XCTest
regressions; these cannot run on Windows. See the root repository's
`IOS_VALIDATION.md` for commands and the current validation boundary.
