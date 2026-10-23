# Development and publication

## iOS preview release

On 2026-10-22, the pub.dev API reported `lux_video_thumbnail 0.0.1` and
platform interface/Android/web `1.0.0` already published. The iOS package name
returned 404; that does not reserve the name.

This checkout prepares **lux_video_thumbnail_ios 1.0.0-dev.1**, followed by
**lux_video_thumbnail 0.0.2-ios.1**. The existing interface, Android and web
versions are reused. No change to their implementation or republication is
required. The iOS implementation awaits native Mac/device validation; this is
an opt-in preview for that validation, not a claim of verified iOS support.

## Check before publishing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/prepare_local_dependencies.ps1
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
powershell -NoProfile -ExecutionPolicy Bypass -File tool/check_publication.ps1
python tool/test_audit_package_content.py
python tool/audit_package_content.py
```

The dry-run script checks all five package archives serially, copies Pub's
complete transcripts into `.dart_tool/publication/content/`, and never uploads.
Do not run other Pub commands concurrently, because Pub shares its cache log.
Use [IOS_VALIDATION.md](IOS_VALIDATION.md) for native validation on macOS.

## Publish this preview

Publication is a separate, explicit user action. Authenticate with the pub.dev
account that owns the main package. Review and commit the changes, or use an
isolated source export, before publishing: Pub warns about modified tracked
files in the working checkout. No commit was created by this preparation.
From the repository root:

```sh
cd packages/lux_video_thumbnail_ios
dart pub publish
cd ../..
```

Wait for `lux_video_thumbnail_ios 1.0.0-dev.1` to be available on pub.dev. Resolve
and dry-run the main package with hosted dependencies, rather than trusting
checkout overrides. Temporarily move the root and example
`pubspec_overrides.yaml` files outside the checkout, preserving their contents;
run `flutter pub get` and `dart pub publish --dry-run` from the root. The main
package must resolve the hosted iOS prerelease. Then publish:

```sh
dart pub publish
```

Restore the development overrides afterwards. Do not republish unchanged
`1.0.0` packages, skip validation, or ignore warnings. A hosted installation of
the new main package can only be verified after its iOS dependency is published.

On the work Mac, add this exact preview to a consumer app:

```yaml
dependencies:
  lux_video_thumbnail: 0.0.2-ios.1
```

Run `flutter pub get`, add `NSPhotoLibraryUsageDescription` to the app's
Info.plist for the gallery picker, then build/run on iOS. A normal dependency
on `^0.0.1` will not select this preview. After native validation, prepare stable
versions and update the main package's iOS dependency accordingly.

## Source checkout development

Dart 3.10.9+, Flutter 3.38.10+, Android API 24+, iOS 13+ and supported browsers.
Native iOS compilation requires macOS/Xcode. Published manifests use hosted
versions; development overrides are excluded from archives.

On macOS/Linux, prepare a full checkout with:

```sh
python3 tool/prepare_local_dependencies.py
flutter pub get
```

On Windows use `tool/prepare_local_dependencies.ps1`. Both scripts preserve
custom override files and upgrade the known pre-iOS overrides. The example owns
its own overrides because overrides do not propagate from dependencies. An
extracted package or consumer app should resolve hosted dependencies directly.

## Archive review

The main archive includes the example's iOS scaffold and native tests. The new
iOS dependency includes Swift sources, CocoaPods/SwiftPM metadata, privacy
manifest, Dart registration tests and legal/documentation files. Legacy root
`android/` and `ios/` directories remain excluded.

Every package excludes local overrides, caches, locks, generated registrants,
credentials, machine configuration and build artifacts. The archive auditor
checks Pub's exact file list, recognizable credential patterns, local machine
paths and packaged Markdown links. It reports filenames/hashes/rules without
printing possible credential values. Pattern checks are not a complete security
audit. Re-run the checks for the exact files being published.
