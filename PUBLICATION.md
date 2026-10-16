# Development and publication

## Current release status

The four federated packages have MIT licenses with `Copyright (c) 2026 Jônatas
Feitosa`, their own README and CHANGELOG files, and generated API documentation.
The example includes CupertinoIcons and retains icon tree shaking.

The static analysis and the completed local validation suites are documented in
[PUBLICATION_CHECKLIST.md](PUBLICATION_CHECKLIST.md). Historical counts in that
file belong to the release stages in which they were recorded.

A real public `repository` or `homepage` URL is still required in all four
pubspec files. It is deliberately absent rather than publishing an invented URL.
The current Pub dry runs therefore end with one URL warning per package (exit
code 65), plus local-override hints in dependent packages. No warning was
suppressed and no package, remote repository, commit, or release was created by
this preparation.

The four package names returned HTTP 404 from the pub.dev API on 2026-10-15.
That does not reserve a name. A fully hosted installation can only be validated
after the packages are published in the order below.

## Final release procedure

1. Provide a real repository or website URL and add it to every pubspec.
2. Recheck name availability, archive content, advisories, licenses, and package
   metadata.
3. In a full checkout, run the serial dry-run and content checks:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tool/check_publication.ps1 -Dart dart
   python tool/test_audit_package_content.py
   python tool/audit_package_content.py
   ```

   The script only runs `publish --dry-run`; it never publishes or ignores
   warnings. It copies the complete Pub transcript immediately after each
   command because Pub shares its log cache. Do not run other Pub commands in
   parallel. Logs and review copies are kept under `.dart_tool/`, outside the
   distributed archives.
4. Validate the platform interface without overrides. With separate approval,
   publish `lux_video_thumbnail_platform_interface 1.0.0` and wait until it is
   available.
5. Resolve and validate Android and web against the hosted interface, without
   overrides. With separate approval, publish each `1.0.0` implementation.
6. Resolve and validate the main package against all three hosted packages,
   without overrides. With separate approval, publish
   `lux_video_thumbnail 0.0.1`.
7. Test a new consumer that depends only on `lux_video_thumbnail: ^0.0.1`, with
   no `path` dependency or override. Review the pub.dev package pages and docs.
8. Before broad support claims, complete physical Android, native-picker,
   Safari/mobile-browser, memory, and latency validation.

Do not use `--ignore-warnings` or `--skip-validation` as evidence that a package
is ready. A pub.dev score and publisher registration have not been verified by a
real publication.

## Versions and requirements

| Package | Initial version | Hosted federated dependencies |
| --- | --- | --- |
| `lux_video_thumbnail_platform_interface` | `1.0.0` | None |
| `lux_video_thumbnail_android` | `1.0.0` | Interface `^1.0.0` |
| `lux_video_thumbnail_web` | `1.0.0` | Interface `^1.0.0` |
| `lux_video_thumbnail` | `0.0.1` | Interface, Android, and web `^1.0.0` |

The manifests require Dart `^3.10.9` and Flutter `>=3.38.10`. This is the
validated support floor, not a measurement of the lowest technically possible
SDK version. `web 1.1.1`, `file_picker 8.3.7`, and
`plugin_platform_interface 2.1.8` are the validated versions; no major-version
upgrade was made as part of release preparation.

## Local development

This section requires a full checkout containing `packages/`. A package
extracted from pub.dev resolves hosted dependencies directly and must not receive
the local overrides described here.

Published manifests use hosted versions. Monorepo paths are isolated in local
`pubspec_overrides.yaml` files, ignored by version control and excluded from all
four simulated publication archives. Prepare a source checkout with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/prepare_local_dependencies.ps1
flutter pub get
```

The script prepares the main package, example, and Android/web implementations.
It preserves customized override files and reports files that require manual
attention. Run `flutter pub get` from a subpackage when working on it separately.
Overrides do not propagate to consumers, so the example owns its override file.
See the [Pub override documentation](https://dart.dev/tools/pub/dependencies#pubspec_overridesyaml).

The example is private (`publish_to: none`) and uses a relative path to the main
package. That does not alter any distributed manifest.

## Publication content and review

Each package has a restrictive `.pubignore` allowlist. The main package includes
its library, tests and fixtures, review tools, documentation, and the Android/web
example. Federated implementations include their own libraries and tests; the
Android package also includes Gradle, manifests, resources, Kotlin code, and JVM
regressions.

Build output, caches, hidden tooling state, logs, IDE settings, local overrides
and lockfiles, machine paths, generated registrants, signing keys, and credential
files are excluded. Legal files such as LICENSE, NOTICE, AUTHORS, and COPYING are
allowed. See [What files are published](https://dart.dev/tools/pub/publishing#what-files-are-published).

`tool/audit_package_content.py` reads Pub's exact archive list, checks forbidden
paths, recognizable credential patterns, local machine paths, and relative
Markdown links. Its output records file names, hashes, and rule identifiers; it
never prints possible credential values. Reviewed source files are copied to an
isolated directory outside the publishable archive. Pattern scanning does not
prove that every possible secret or vulnerability is absent.

The archive review reduced the historical compressed archive sizes as follows:

| Package | Before | After cleanup |
| --- | --- | --- |
| Main | 40 MB | 91 KB |
| Interface | 13 MB | 12 KB |
| Android | 13 MB | 15 KB |
| Web | 13 MB | 5 KB |

Later tests and documentation may change those sizes. Re-run the dry runs before
publication rather than relying on historical values.

## Runtime behavior and boundaries

Public and platform APIs reject negative timestamps and requests beyond known
duration. An exact end position is normalized to the last valid earlier position.
Unknown duration stays unknown and does not reset a requested position. The
returned timestamp is the normalized request, not a measured presentation
timestamp. Frame availability depends on decoder and browser behavior.

For finite web media, a large seek discrepancy can be recovered by muted forward
decoding from the start with bounded 15-second waits. This is slower and cannot
guarantee an exact frame PTS. Autoplay refusal, missing progress, browser
scheduling, sparse frames, variable frame rates, and background throttling can
still prevent a result.

Android performs metadata, extraction, compression, and I/O through a dedicated
serial worker per engine. Platform-channel replies return on the main handler.
Detaching an engine rejects pending/new work, lets active decoder work finish on
the worker, and cleans only tracked temporary resources. The cleanup is
best-effort when native work is stuck.

Shared limits include four sessions, batches of 1-16 thumbnails, 16 queued
session operations, byte sources up to 64 MiB, encoded images/chunks up to 8 MiB,
and source/output dimensions from 1 to 4096 per axis. Android additionally caps
its engine queue at 16 calls/128 MiB payloads and retains at most 64 temporary
thumbnails. These limits are not a global memory budget or a guarantee against
decoder/application out-of-memory failures.

`saveToFile` returns `Future<String>` and creates a caller-owned copy in a new
subdirectory of either the selected parent or `Directory.systemTemp`. The caller
must remove that output when finished. Web throws `UnsupportedError` for
filesystem saving and continues to provide bytes for an application-owned
download/upload flow. The plugin and example do not request broad Android storage
permissions; callers must provide readable paths or URIs.

The JVM tests simulate media, engine, Handler/Looper, and queue behavior. Browser
tests exercise real decoding. A manual physical-Android test is reported in the
README, but these results do not establish exhaustive native media/picker coverage,
Safari support, peak-memory characteristics, or latency for long videos.
