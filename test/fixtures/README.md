# Synthetic test video

The fixtures are generated locally: two seconds, 64x48, 10 fps, red for the first
second and blue for the second. No third-party footage or network is required.
`video_fixture.dart` embeds the same bytes for browser tests without adding a
test asset to applications that depend on the package.

For Flutter 3.38 on Windows, prepare its local renderer assets before running
browser tests (this writes only an ignored test directory, not the SDK):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/prepare_browser_tests.ps1 -FlutterSdk C:\flutter
flutter test --platform chrome test/browser_thumbnail_test.dart
```

Additional fixtures are silent H.264/yuv420p MP4 with faststart, VP9 WebM and
VP8 live WebM (`-live 1`, no duration/seek index). `format_fixtures.dart` embeds
their exact bytes. Generate them from the VP8 fixture with:

```sh
ffmpeg -i red_blue.webm -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart red_blue.mp4
ffmpeg -i red_blue.webm -an -c:v libvpx-vp9 red_blue_vp9.webm
ffmpeg -i red_blue.webm -an -c:v copy -live 1 red_blue_live.webm
```

For the full browser matrix, start `node tool/web_fixture_servers.mjs` in another
terminal, then run:

```powershell
flutter test --platform chrome test/browser_thumbnail_test.dart test/browser_matrix_test.dart
flutter test --platform chrome --wasm --dart-define=EXPECT_WASM=true test/browser_thumbnail_test.dart test/browser_matrix_test.dart
```

Set `CHROME_EXECUTABLE` to Edge's executable to repeat that runner in Edge.
Ports 18761/18762 are loopback-only controlled origins (allowed/denied CORS).
Tests include 404, disconnect, a real 15-second stall, invalid files and a 16 MiB
file built from the MP4 plus padding. This is a resource-lifecycle regression,
not a long-video benchmark or a measurement of browser heap collection.

Firefox is covered by the standalone release probe; Flutter's test runner only
accepts Chrome. From `example/`, build the probe, then run the browser from the
repository root, keeping the fixture servers running:

```powershell
flutter build web --no-pub --no-web-resources-cdn --wasm --target ../tool/web_validation.dart
# Back in the repository root:
node tool/run_web_validation.mjs chrome true
node tool/run_web_validation.mjs edge true
node tool/run_web_validation.mjs firefox false
```

The last argument is the expected **actual** Wasm runtime, checked with `kIsWasm`.
Flutter 3.38 chooses JavaScript fallback for Firefox. To test a JS-only build,
omit `--wasm` in the build command and pass `false` for every browser. The probe
checks automatic plugin registration, pixels, formats, metadata, errors, file
selection, cancellation and URL release. Each run uses a temporary browser profile
and closes only its own process tree. Safari and native OS dialogs are untested.

## Temporal regressions (point 6)

`python tool/generate_temporal_fixtures.py` generates three silent, four-second
H.264 videos (64x48) and embeds their bytes in `temporal_fixtures.dart`:

- `long_gop.mp4`: 10 fps, only the initial frame is a keyframe; red until 2 s,
  then blue. Ordinary seeks must decode beyond that initial keyframe.
- `low_rate.mp4`: only two frames, at 0 s (red) and 2 s (blue), held for 2 s each.
- `variable_rate.mp4`: PTS 0, 0.25, 2.5 and 3.75 s; red until 2.5 s, then blue.

`browser_temporal_test.dart` uses the same checks as the standalone release probe
(`temporal_checks.dart`). It verifies real pixels, near-boundary held frames,
exact end, out-of-range rejection/recovery, concurrent seeks and close ordering.
The unindexed WebM now checks successful recovery rather than an expected Firefox
failure. Add `test/browser_temporal_test.dart` to the browser commands above.

The test is kept directly in `test/` because this SDK's Windows web runner also
misidentifies nested test paths. Test selection/cancellation events are automated;
the OS file dialog itself is not exercised by these tests.

```sh
ffmpeg -f lavfi -i 'color=c=red:s=64x48:d=1:r=10' -f lavfi -i 'color=c=blue:s=64x48:d=1:r=10' -filter_complex '[0:v][1:v]concat=n=2:v=1:a=0[v]' -map '[v]' -c:v libvpx -b:v 100k -an red_blue.webm
```
