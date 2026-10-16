# lux_video_thumbnail_web

Web implementation of `lux_video_thumbnail`, using typed JS interop, a video
element and canvas encoding. Applications should depend on the main package;
Flutter registers this endorsed implementation automatically.

## Sources and timestamps

Supports byte buffers, HTTP(S) URLs and caller-owned Blob URLs. The main picker
creates a file-backed Blob without copying the whole selected video into Dart.
Native filesystem paths are unsupported. Remote videos must allow cross-origin
frame access (CORS), and their servers must support the browser's media loading.

Seeking uses the browser media clock and decoded frames. For finite media with
large presentation discrepancies, bounded muted sequential decoding can recover
the requested region. It is slower than indexed seeking and can fail on playback
refusal or timeout. Sparse/variable-rate frames are valid; no exact frame PTS is
promised. Unknown duration remains unknown, and the main widget disables its slider.

Sessions serialize operations and drain accepted work on close. Pending waits,
video elements and implementation-owned URLs are released on cleanup. Caller-owned
URLs remain caller-owned. Opening sessions reserves capacity before metadata loads.

## Output and limits

JPEG, PNG and WebP are requested through canvas; results report the actual encoded
format if the browser falls back. Use `readBytes`, or the main public API's bytes,
for app-managed downloads/uploads. `saveToFile` explicitly throws
`UnsupportedError` on web; the shared result contract contains no `dart:io` types.

Shared ceilings include four sessions, batches up to 16 images, 16 accepted
operations per session, source/output dimensions up to 4096 per axis, byte inputs
up to 64 MiB and encoded images/chunks up to 8 MiB. They are not a process-memory
guarantee: browser codecs, bridge copies and app-retained results also use memory.

## Support and development

Requires Dart 3.10.9+, Flutter 3.38.10+ and `package:web`. Real pixel-color tests
cover Chrome/Edge JavaScript and Wasm, plus Firefox's JavaScript fallback. Browser
codec support varies. Safari, mobile browser dialogs and background-tab performance
have not been validated. Compilation is not evidence of every codec's support.

In a full monorepo checkout, prepare root local overrides before running commands.
Consumers use hosted dependencies. The main package contains the public API,
picker example and real-browser test/probe tooling.

## License

MIT, Copyright (c) 2026 Jônatas Feitosa. See [LICENSE](LICENSE).
