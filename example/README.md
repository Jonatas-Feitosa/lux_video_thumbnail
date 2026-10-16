# Example

Run this app on Android or web to compare the two selection flows from the main
package. Tap **Choose thumbnail in dialog** to call `videoThumbnailDialog`,
choose a video, move the slider and confirm. The confirmed image and timestamp
appear on the screen; cancelling preserves the previously confirmed selection.
Below it, `VideoThumbnailPicker` demonstrates selection embedded in the screen,
with preview updates through `onChanged`. The app does not import or register
implementation packages.

Open `example/lib/main.dart` and run `flutter run -d chrome` from `example/` for
the web version, or choose an Android device with `flutter run`.

For the independent `LuxVideoThumbnail.generate` function, see the package README.

In the full source checkout, run `tool/prepare_local_dependencies.ps1` from the
repository root before resolving dependencies. In a published/extracted package,
the example uses the main package in its parent directory and resolves the
federated dependencies from pub.dev. The distributed example includes Android
and web scaffolds; iOS thumbnail generation is not implemented.
