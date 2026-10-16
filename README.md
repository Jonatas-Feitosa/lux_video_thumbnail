# lux_video_thumbnail

Generate an encoded video thumbnail at a requested position, or let a user select
one with an embedded widget or dialog. Initial platforms: **Android and web**.

> This project is at an early stage of development. Contributions, feedback, and
> issue reports are welcome.

This source checkout is prepared for the initial release; the four federated
packages have not been published yet. See
[PUBLICATION_CHECKLIST.md](PUBLICATION_CHECKLIST.md) for validation and remaining
launch prerequisites.

## Installation and support

After the federated packages are published, add `lux_video_thumbnail: ^0.0.1`
to your app's dependencies and run `flutter pub get`. For this source checkout,
follow the local override instructions below until hosted packages are available.
Requires Dart 3.10.9+, Flutter 3.38.10+ and Android API 24+ or a supported browser.

| Platform | Status |
| --- | --- |
| Android | Implemented; manually tested on a physical Android device and APK/JVM validated. Native media/picker coverage is not exhaustive. |
| Chrome / Edge | Real media tests in JavaScript and Wasm |
| Firefox | Real media tests in JavaScript fallback |
| Safari / mobile browsers | Not validated |
| iOS / desktop | Thumbnail generation not implemented |

## Generate a thumbnail

```dart
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';

final thumbnail = await LuxVideoThumbnail.generate(
  source: VideoSource.bytes(videoBytes, mimeType: 'video/mp4'),
  timestamp: const Duration(milliseconds: 1500),
  width: 320,
  format: ThumbnailFormat.jpeg,
  quality: 85,
);

Image.memory(thumbnail.bytes);
```

Other sources:

```dart
VideoSource.path('/path/to/video.mp4'); // Android only; the file is borrowed.
VideoSource.path('content://...');     // Android content URI with access granted.
VideoSource.url('https://example.com/video.mp4');
```

The API returns `VideoThumbnailData`: encoded `bytes`, requested `timestamp`,
`width`, `height`, and actual encoded `format`. It releases decoder sessions and
intermediate thumbnails automatically. You can upload or save the returned bytes
using the storage/download APIs appropriate to your application and platform.

The timestamp is the **requested position**, not the exact presentation timestamp
of the decoded frame. Video frame rate and platform decoder behavior determine
which nearby frame is available. Negative positions and positions beyond a known
video duration are rejected. The final endpoint selects the nearest available
last frame. Optional dimensions must be from 1 to 4096 pixels; quality is 1–100.

## Let the user select a frame

```dart
VideoThumbnailPicker(
  onChanged: (thumbnail) {
    // Called when the current preview is ready, including the initial frame.
    // Use thumbnail.bytes and thumbnail.timestamp in your application.
  },
  onError: (error) {
    // Handle access, unsupported codec, timeout or other decoder errors.
  },
  selectVideoLabel: 'Choose video',
  loadingLabel: 'Generating preview…',
  emptyLabel: 'Select a video to choose a frame.',
  errorLabel: 'Could not generate a thumbnail.',
  previewLabel: 'Preview',
  backTenFramesTooltip: 'Back 10 frames',
  backOneFrameTooltip: 'Back 1 frame',
  forwardOneFrameTooltip: 'Forward 1 frame',
  forwardTenFramesTooltip: 'Forward 10 frames',
  width: 320,
  previewHeight: 180,
  frameRate: 30, // Use the source FPS when it is known.
)
```

The widget includes a system video picker, a timestamp slider and an image preview.
Below the slider, icon-only controls jump back 10 frames, back 1 frame, forward 1
frame and forward 10 frames. Their default 30-fps step is a requested timestamp,
not a claim that the decoder exposes an exact video-frame presentation timestamp;
set `frameRate` to the source FPS when available. The loading spinner is centered
over the preview while a new image is being generated.
It debounces slider movements and serializes extraction. An older result cannot
replace a newer selection. Cancelling file selection preserves the previous video.
Sessions and widget-owned browser URLs are released on replacement or disposal.
The displayed preview time identifies the image currently shown while a new
position is still loading.

Use `initialSource` to start with a video, `videoPicker` to provide your own
asynchronous selector (return null on cancellation), and `previewBuilder` to
customize the image display. Sources supplied by the application remain owned by
that application; caller-created Blob URLs must be revoked by the caller when
no longer needed. The built-in web selector uses a file-backed Blob URL instead
of reading the whole video into Dart memory.

## Choose a frame in a dialog

Keep the embedded widget for inline layouts, or call `videoThumbnailDialog` from
a button using the same main package import:

```dart
final thumbnail = await videoThumbnailDialog(
  context: context,
  // Optional: omit this to choose a video inside the dialog.
  initialSource: VideoSource.url('https://example.com/video.mp4'),
  width: 320,
  title: 'Choose a thumbnail',
  selectVideoLabel: 'Choose video',
  confirmLabel: 'Use thumbnail',
  cancelLabel: 'Cancel',
);

if (thumbnail != null) {
  // User confirmed: thumbnail.bytes and thumbnail.timestamp are ready to use.
}
```

The return type is `Future<VideoThumbnailData?>`. Only Confirm returns an image;
Cancel, Back and barrier dismissal return null. Confirm is disabled before a
preview is available, during selection/decoding/slider debounce, and after errors.
It cannot confirm the old image while a newer timestamp is pending. Cancelling
the file picker preserves the previous valid selection inside the open dialog.

The dialog reuses `VideoThumbnailPicker`, including resource ownership and
cleanup on route disposal. `initialSource` and a custom `videoPicker` remain
caller-owned. Options include encoding dimensions/format/quality, localized title,
buttons, picker labels and frame-control tooltips, `previewBuilder`, `previewHeight`, `maxWidth`, `shape`,
`backgroundColor`, `frameRate`, `barrierDismissible` and `useRootNavigator`. The content scrolls
on small screens. `barrierDismissible: false` prevents outside-tap dismissal;
Back still cancels. For nested navigators, set `useRootNavigator: false` as needed.

All three entry points remain available: `LuxVideoThumbnail.generate` for code,
`VideoThumbnailPicker` for embedding, and `videoThumbnailDialog` for modal selection.
The example app demonstrates both UI variants. Embedded-widget consumers that
provide their own confirmation UI can use `onReadyChanged` (initially false) to
track whether the latest requested preview is ready, alongside `onChanged`.

## Platform behavior

- Depend on the main package and import its public library. No manual web plugin
  registration or dependency on implementation packages is needed.
- Web decoding uses the browser's video and canvas APIs. Supported containers and
  codecs depend on the browser. Remote URLs must permit CORS frame access; the
  package cannot bypass the video's server policy.
- A generic browser media error cannot conclusively distinguish CORS, a missing
  resource and an unsupported format. Only a canvas security failure reports
  `CorsBlockedException`. The widget shows a generic error; application callbacks
  receive diagnostic errors and should avoid logging signed URLs or tokens.
- WebM streams without a duration/seek index depend on browser seek support.
  A large difference between the requested position and the presented frame can
  also be valid for a low or variable frame rate. For finite media, the web
  implementation can recover by decoding forward from the start. This is slower
  than seeking and uses bounded 15-second waits; playback refusal or failure to
  reach the position reports `GenerationFailedException` (`SEEK_UNAVAILABLE`).
  Browser scheduling and decoder behavior still determine the nearby frame;
  recovery does not promise an exact presentation timestamp.
  A missing duration disables the widget's slider. Indexed MP4/WebM is preferable
  for selecting arbitrary timestamps.
- Native filesystem paths do not work in a browser. Use bytes, a picked file or a
  suitable URL. Remote URLs must also support the browser's video loading/seeking.
- Android uses MediaMetadataRetriever. Original input files are never deleted.
  Only temporaries created and tracked by the plugin can be deleted by it;
  supplying a video path does not transfer ownership of that file.
  Native seeks use the nearest decoded frame. Advanced `preferKeyFrame` requests
  use a sync frame instead; the browser uses its ordinary seek for either hint.
- iOS and desktop are not implemented by the thumbnail API and report a typed
  unsupported-platform error. The legacy `getPlatformVersion()` remains available.

The example application consumes only the public API. Unit/widget tests simulate
platform decoding. Browser tests use a locally generated red/blue video and check
actual decoded pixel colors at different positions. Compilation and automated
browser results do not imply testing every native file dialog, codec or browser.

For development in a full source checkout (including `packages/`), prepare the
monorepo overrides with
`tool/prepare_local_dependencies.ps1` before `flutter pub get`. Distribution
manifests use hosted versions. See [development and publication](PUBLICATION.md)
for the supported SDK floor, package order and remaining release blockers.
The pub.dev archive contains the main package and its Android/web example;
the federated implementations are separate dependencies. In an extracted archive,
use the hosted dependencies directly rather than generating monorepo overrides.

Advanced session APIs follow the same timestamp bounds: a position beyond a known
duration is rejected, the exact end selects the last available frame, and an
unknown duration never forces a nonnegative position to zero. Android accepts
microsecond requests while retaining the legacy millisecond channel field. The
legacy result name `actualTimestamp` means the normalized requested position;
it is not a measured frame PTS. Session operations are serialized; closing drains
accepted work and rejects new work. The picker skips obsolete requests still in
its queue and ignores stale selections/results after source changes.

### Resource limits and saving

Generation validates options in release builds. Quality is 1–100; decoded source
and output dimensions are 1–4096 per axis (up to 16,777,216 pixels). Derived
aspect-ratio dimensions must also fit. An oversized source is rejected even when
requesting a small thumbnail, because Android may decode the native-size frame.

Each backend supports four open sessions, batches of 1–16 images, and up to 16
active/waiting operations per session. Android also limits its engine work queue
to 16 calls and 128 MiB of accepted byte payloads, each byte source to 64 MiB, and
retained thumbnail temporaries to 64. Encoded images and read chunks are limited
to 8 MiB. `ThumbnailLimits` exposes shared ceilings. Overflow rejects the request;
it never silently lowers quality or drops accepted session work. Dispose advanced
results and close sessions when finished. The public one-shot API handles both.

These ceilings do not guarantee a total process-memory budget: codecs, browsers,
bridge copies and images retained by the app also consume memory. Native paths,
picked browser files and URLs avoid copying an entire video into Dart memory;
the 64 MiB input limit applies to byte sources, not streamed paths/URLs/Blobs.

The advanced `VideoThumbnailResult.saveToFile()` now returns `Future<String>`
(the saved path), replacing the prepublication `Future<File>` contract. It works
only on native platforms. The default is `Directory.systemTemp`, with a fresh
`lux_thumbnail_*` subdirectory for every save; an explicit directory is treated
as the parent. `fileName` must be a plain name. Existing files are never replaced.
The caller owns the saved file and its new parent directory, which survive result
disposal; delete them when no longer needed. Default temporary storage is not
permanent storage. Pass an application-managed persistent parent if required.

On web, `saveToFile()` throws `UnsupportedError`; use `readBytes()` or the public
`VideoThumbnailData.bytes` with your application's download/upload mechanism.
Shared APIs no longer import `dart:io`; native saving uses a conditional helper.
Reads reject negative offsets/lengths and offsets beyond EOF, return empty at
EOF and truncate a valid requested length at EOF. Disposed results reject access.

The Android plugin and example declare no broad storage permissions. The picker
uses the system file selection flow; direct paths/content URIs must already be
readable by the host app. `INTERNET` remains for remote videos. Android channel
resource overflow reports `RESOURCE_LIMIT`; invalid arguments report
`ARGUMENT_ERROR`. Dart validates typed inputs with `ArgumentError`/`RangeError`
and rejects full queues/sessions with `StateError`. Existing typed temporal/session
errors remain available.

## License

MIT, Copyright (c) 2026 Jônatas Feitosa. See [LICENSE](LICENSE). External
dependencies retain their respective licenses; the MIT grant covers this project's
own code and does not replace third-party notices.
