# lux_video_thumbnail_android

Android implementation of `lux_video_thumbnail`. Applications should depend on
the main package; its federated plugin configuration selects this implementation.

## Behavior

Uses `MediaMetadataRetriever` for local paths, readable content URIs, HTTP(S)
sources and byte buffers. Byte inputs become plugin-owned cache files. Borrowed
video paths, including legacy `vx://bytes/` paths, are never deleted.

Opening, metadata, extraction, compression and file IO run on a serial worker per
engine. Replies use the main Handler and complete once. On engine detach, pending
and new calls are rejected; an active decoder is allowed to finish before cleanup.
This avoids UI waits but cannot force cancellation of a stuck native decoder.

Ordinary seeks request the nearest decoded frame; `preferKeyFrame` requests a
nearby sync frame. Positions use microseconds with a legacy millisecond fallback.
`actualTimestamp` identifies the normalized request, not measured frame PTS.
Codec support and precise output depend on Android's media stack.

Limits include four sessions, batches up to 16 thumbnails, dimensions up to 4096
per axis, 64 MiB byte sources, 8 MiB encoded images/chunks and 64 retained thumbnail
temporaries. Dispose advanced results and close sessions when finished. The public
one-shot API handles their cleanup automatically.

## Requirements and permissions

Android API 24+, Dart 3.10.9+, Flutter 3.38.10+. Build configuration uses compile
SDK 36 and Java 17. The plugin declares INTERNET for remote videos and no broad
storage permissions. Paths/content URIs must already be readable by the host app.

File reading, size lookup, copying and deletion are restricted to registered
thumbnail outputs, with path/link checks. Legacy copy calls reject existing
destinations. The advanced Dart `saveToFile` returns a path string to a new
caller-owned copy in a private subdirectory of the chosen/system-temp parent.

## Validation

JVM tests use real files and worker threads but mock Android media/engine APIs.
They verify ownership, cleanup, limits, ordering and detach, not physical-device
decoder accuracy or performance. An example APK has been compiled. Device tests
remain required for codecs, native file selection and memory/latency measurements.

See [FILE_OWNERSHIP.md](FILE_OWNERSHIP.md) for ownership details. In a full source
checkout, use the root local-dependency preparation script; installed packages
use hosted dependencies. Native Gradle tests run through the example Android host.

## License

MIT, Copyright (c) 2026 Jônatas Feitosa. See [LICENSE](LICENSE).
