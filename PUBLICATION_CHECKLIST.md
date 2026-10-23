# iOS preview validation - 2026-10-22

The current release candidate is `lux_video_thumbnail 0.0.2-ios.1` plus
`lux_video_thumbnail_ios 1.0.0-dev.1`. Interface/Android/web reuse their hosted
`1.0.0` versions. Prior initial-release notes below are historical and do not
represent the current pub.dev state or current test counts.

- [x] Add endorsed iOS package and permit iOS in public API and native picker.
- [x] Implement AVFoundation sessions, byte/path/URL sources, JPEG/PNG, dimensions,
  timestamps, owned files, chunk/copy/disposal methods and engine cleanup.
- [x] Add CocoaPods/SwiftPM manifests, example permission description and native
  integration/XCTest regressions for the Mac.
- [x] Dart analysis clean; 118 distinct Dart/Flutter/browser tests and five Python
  auditor regressions passed. Five isolated-export dry runs exited zero with
  zero content-audit findings. Root/iOS tests also passed against hosted shared
  dependencies.
- [ ] Compile and execute native tests on macOS/Xcode; validate both dependency
  managers, orientation, HEVC/HDR, remote sources, picker and engine lifecycle.
- [ ] Validate the hosted main-package dependency after publishing the iOS preview.

See [IOS_VALIDATION.md](IOS_VALIDATION.md) for current executable commands,
results and limitations; see [PUBLICATION.md](PUBLICATION.md) for release order.
No publication is performed by the validation scripts.

---

## Historical initial-release checklist

# Publication readiness checklist

This checklist records local work completed before the first pub.dev release.
It is not evidence that any package has been published, reserved, installed from
pub.dev, or assigned a pub.dev score.

## GitHub repository preparation

- [x] A root `.gitignore` excludes build output, caches, generated registrants,
  IDE/assistant configuration, local overrides, signing material, credential
  files, and other machine-specific state at every package level.
- [x] A temporary bare Git metadata directory was used to inspect the candidate
  repository content. No real Git repository was initialized, and no commit,
  remote, or push was created.
- [x] The candidate scan found no matching private keys, common cloud/API tokens,
  credential URLs, assigned secrets, or local user/workspace paths. It reports
  rule identifiers and file names only, never potential secret values.
- [x] Publishable archive review uses Pub's complete verbose file list and an
  isolated source copy. Generated review state remains under `.dart_tool/`.

## Completed release items

- [x] **1. Android file ownership.** Caller-provided paths, URIs, and byte
  sources remain caller-owned. The plugin only reads, copies, or removes tracked
  output and temporary files that it created, with path and symbolic-link checks.
- [x] **2. Public API and reusable widget.** `VideoSource`,
  `LuxVideoThumbnail.generate`, `VideoThumbnailPicker`, and their platform
  contracts provide timestamp-based thumbnail generation on Android and web.
- [x] **3. Local selection and web interoperability.** File/Blob selection,
  browser cancellation, CORS boundaries, unknown duration, and seek behavior are
  covered without reading an entire selected web video into Dart memory.
- [x] **4. Dependency configuration.** The federated packages use hosted
  dependency declarations. Local monorepo overrides are separate and excluded
  from published archives. Publication remains blocked until hosted dependencies
  exist and the missing public URL is supplied.
- [x] **5. Archive content.** Four restrictive `.pubignore` files limit each
  archive to its own reviewable sources, documentation, legal files, and required
  example or platform files. Credentials, builds, caches, and local configuration
  are excluded.
- [x] **6. Timestamp seeking and concurrency.** Negative/out-of-range requests,
  stale UI responses, session queues, native microsecond timestamps, web seeking,
  and bounded recovery are handled without claiming exact decoded-frame PTS.
- [x] **7. Android worker and engine detachment.** Metadata, extraction,
  compression, and I/O use a serial worker per engine. Replies return on the main
  handler; detach rejects pending/new requests and releases only owned resources.
- [x] **8. Limits and saving.** Runtime validation covers options, source types,
  batches, reads, and native arguments. Explicit limits apply to sessions, queues,
  buffers, images, and temporaries. `saveToFile` returns a caller-owned path and
  web rejects filesystem saving. Broad Android storage permissions are absent.
- [x] **9. Local documentation and release preparation.** MIT is identical in all
  four packages with `Copyright (c) 2026 Jônatas Feitosa`; package documentation,
  migration notes, support boundaries, and the release procedure are included.
- [x] **10. English documentation and example.** Public README files, CHANGELOGs,
  release documentation, API docs, and the example use English. Picker and dialog
  defaults are English and remain customizable by the consuming application,
  including preview labels and frame-control tooltips.

## Validation evidence

| Verification | Result and boundary |
| --- | --- |
| Main package VM tests | 41 passed after dialog, frame-control, readiness, spinner, and localization coverage |
| Example tests | 6 passed with English default labels |
| Platform interface VM tests | 30 passed in the final release stage |
| Android package VM tests | 15 passed in the final release stage |
| Web package VM tests | 13 passed in the final release stage |
| Android JVM tests | 38 passed with no failures, errors, or ignored tests |
| Chrome/Wasm | 32 real-browser tests passed in the final release stage |
| Edge/JavaScript | 32 real-browser tests passed in the final release stage |
| Firefox/JavaScript | Release probes passed; Wasm was not run on Firefox |
| Main API documentation | Generated with zero warnings and errors |
| Static analysis | Zero diagnostics in the latest targeted main-package validation |
| Example builds | Release JavaScript/Wasm and debug APK builds passed before the English-label update |
| Content-audit parser | 4 Python tests passed; reviewed copies and hashes were recorded |

The dialog addition was independently validated with browser tests in Chrome/Wasm
and Edge/JavaScript. Frame controls, spinner positioning, custom labels, and the
English defaults are covered by the current VM and example tests. Repeat the full
release/browser matrix before publication.

## Resource limits

| Resource | Limit |
| --- | --- |
| Byte source | 64 MiB; selected paths, URLs, and Blob sources use the decoder path |
| Sessions | 4 per web instance or Android engine, including opening web sessions |
| Batch | 1-16 thumbnails |
| Session queue | 16 accepted operations not yet completed |
| Android engine queue | 16 calls; byte payloads total at most 128 MiB |
| Decoded source/output image | 1-4096 per axis; at most 16,777,216 pixels |
| Encoded image/chunk | 8 MiB |
| Android temporaries | 64 thumbnails and 4 owned byte inputs |

These are operational limits, not a global memory budget or a performance claim.

## Dry-run and publication status

All four `publish --dry-run` commands currently return exit code 65 with one
release warning per package: a real `homepage` or `repository` URL is absent.
The main package has three local-override hints; Android and web have one each;
the platform interface has none. Overrides are local and excluded from archives.
No `--ignore-warnings`, `--skip-validation`, or forced publication was used.

The package names returned HTTP 404 from the public pub.dev API at the recorded
check. That does not reserve the names. The required publication order is:

1. `lux_video_thumbnail_platform_interface`
2. `lux_video_thumbnail_android` and `lux_video_thumbnail_web`
3. `lux_video_thumbnail`

At each step, resolve and validate without local overrides, then validate a clean
consumer using only hosted versions. No package has been published.

## Known validation boundaries

- A manual physical-Android test was reported. Interactive native-picker,
  Safari, and mobile-browser coverage remains incomplete.
- No peak-memory or latency benchmark for long video files has been completed.
- JVM tests simulate media/engine behavior; browser tests exercise real decoding.
- Archive and pattern scans reduce exposure risk but cannot prove the absence of
  every secret, vulnerability, or legal/provenance issue.
- The missing public URL remains the current explicit release blocker.
