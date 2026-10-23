# iOS preview validation

The preview consists of `lux_video_thumbnail 0.0.2-ios.1` and
`lux_video_thumbnail_ios 1.0.0-dev.1`. The existing interface, Android and web
packages stay at hosted `1.0.0`. Publishing is separate from this preparation;
see [PUBLICATION.md](PUBLICATION.md).

## Evidence boundary

Validation completed on Windows on 2026-10-22:

| Check | Result |
| --- | --- |
| Dart static analysis | No issues |
| Main package unit/widget tests | 44 passed |
| iOS Dart registration/channel tests | 2 passed |
| Platform interface tests | 30 passed |
| Android Dart contract tests | 15 passed |
| Web Dart contract tests | 13 passed |
| Example tests | 6 passed |
| Chrome real-video/picker/dialog regressions | 8 passed |
| Archive-auditor Python regressions | 5 passed |
| Five package publication dry runs in an isolated export | All exit 0; no warnings |
| Exact archive content review, all five packages | Zero findings |
| Main package against hosted interface/Android/web | Analysis and 44 tests passed |
| iOS package against hosted interface | 2 Dart channel tests passed |
| Swift build, AVFoundation, XCTest, simulator/device | Not run; macOS/Xcode required |

The 118 Dart/Flutter/browser tests above are distinct tests; repeat hosted checks
are not counted twice. Chrome used the local Flutter tool source because the
installed prebuilt snapshot referenced a missing browser-runner asset. No SDK
repair was necessary. Metadata/plist parsing, shell syntax and `git diff --check`
also passed. The exported dry runs retain local overrides for unpublished iOS;
the main package's fully hosted installation must be checked after iOS is
published. A dirty checkout can separately produce Pub's uncommitted-files
warning; no commit was created to suppress it.

Windows can verify Dart analysis, unit/widget tests, method-channel contracts,
Flutter's discovery of the iOS plugin, and exact Pub archive contents. These
checks do **not** compile Swift, link Apple frameworks, install CocoaPods/SwiftPM,
or exercise AVFoundation on a simulator/device. Native tests below are prepared
for the first Mac validation. The preview is suitable for opt-in testing subject
to this limitation; stable iOS support awaits that validation.

## Mac: full checkout before publication

With Flutter 3.38.10+, Xcode selected, CocoaPods installed, and an iOS simulator
booted, run from the root:

```sh
python3 tool/prepare_local_dependencies.py
flutter devices
bash tool/check_ios.sh <simulator-UDID>
```

This runs Dart checks, an iOS simulator build, seven real-media integration
tests and four native XCTest regressions. The example uses a synthetic
two-second H.264 MP4 with red and blue halves; tests inspect decoded pixel colors,
not just nonempty output. Integration cases cover metadata, path/file-URL/bytes,
JPEG/PNG headers, microsecond timestamps, exact endpoint, stretching, chunks,
copy/save/disposal, borrowed-file protection, malformed requests, public API
cleanup, session limits and closed handles.

XCTest covers timestamp normalization, geometry/integer validation, separate
input/output ownership and main-thread worker replies. Run once with CocoaPods,
then separately with Swift Package Manager enabled if supported by the Flutter
version. The validation script does not change global Flutter settings. The
SwiftPM manifest accommodates older SDKs and FlutterFramework-based SDKs; both
paths still need native build validation.

## Mac: after publication

Pin `lux_video_thumbnail: 0.0.2-ios.1` in the work app, then `flutter pub get`.
The new dependency is endorsed automatically; no manual plugin registration is
needed. Add this localized permission explanation for the gallery picker:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select a video to choose its thumbnail.</string>
```

For the complete test suite, download/extract the **main package archive** from
pub.dev. It includes `example/ios`, integration fixtures and the check script.
Do not generate local overrides: the root/example resolve hosted dependencies.
Run `bash tool/check_ios.sh <simulator-UDID>` from the extracted root.

## Manual device checks still required

- Open the embedded picker and dialog, select/cancel a gallery video, seek,
  confirm, replace the source and dismiss while decoding.
- Test an iPhone portrait recording, MOV, HEVC/HDR and a large video within the
  4096-pixel source ceiling; confirm orientation, dimensions and colors.
- Test an HTTPS video with seeking support, offline/network failure, invalid
  data and an unreadable path. HTTP follows the app's ATS policy.
- Exercise repeated opens/disposals and Flutter engine teardown under load;
  monitor temporary files, memory and responsiveness.

JPEG and PNG output are implemented. WebP encoding explicitly returns
`UNSUPPORTED_FORMAT`. MIME support checks query AVFoundation and cannot prove a
particular codec or file will decode. Metadata loading has a 30-second timeout;
native frame extraction itself may still block the serial worker. The 8 MiB
encoded-output limit is checked after encoding. Returned timestamps describe
normalized requests rather than measured frame PTS.

Implementation references: Flutter's [federated plugin guide](https://docs.flutter.dev/packages-and-plugins/developing-packages),
[SwiftPM guide](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors),
and Apple's [image generation tolerances](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/requestedtimetolerancebefore).
