## 0.0.1

* Use English defaults in the picker, dialog, and example; expose the preview
  label and frame-control tooltips for application localization.
* Add icon-only frame-jump controls (`-10`, `-1`, `+1`, `+10`) to the picker
  and dialog, with a configurable `frameRate` (30 fps by default); center the
  loading indicator over the preview.
* Add `videoThumbnailDialog` returning a confirmed `VideoThumbnailData` or null on
  dismissal, with customizable labels/appearance and safe confirmation gating.
* Expose picker readiness through `onReadyChanged`; demonstrate dialog and embedded
  selection side by side in the example app.
* Complete federated package documentation and apply the MIT license with
  Copyright (c) 2026 Jônatas Feitosa.
* Enforce runtime option/range validation and bounded sessions, queues, batches,
  source buffers, images and Android-owned temporaries.
* Recycle Android bitmaps on resize/temp-file failures and clean partial batches;
  restrict thumbnail reading/copying to owned outputs and prevent copy overwrite.
* Change advanced `saveToFile` to return a native path string, use a fresh
  system-temp/custom-parent subdirectory and reject filesystem saving on web.
* Remove broad Android storage permissions from the plugin and example.
* Run Android media and file operations on a dedicated serial worker per engine,
  dispatch replies on the main thread, reject work on detach and clean up owned
  resources after active decoding without blocking the UI.
* Unify timestamp bounds across public and legacy APIs; preserve unknown-duration
  requests and microsecond native positions, and honor Android keyframe preference.
* Recover large browser seek discrepancies without rejecting valid sparse frames.
* Drain session queues on close, survive failures, share concurrent web close
  operations, and skip obsolete picker requests and stale selections.
* Limit each publication archive to its own sources and supporting files, omit
  generated state and local credentials, and retain the Android/web example.
* Add content auditing from Pub's exact file lists and verify isolated copies.
* Prepare hosted dependencies for all federated packages, separate local
  development overrides, and align the declared SDK floor with validation.
* Remove placeholder repository metadata and unused development dependencies.
* Avoid focus/cancel races in modern browser file selection and reject browser
  seeks that silently land at a different position.
* Distinguish ambiguous media loading errors from confirmed canvas CORS errors.
* Add real-browser format, network, cancellation and JavaScript/Wasm regressions.
* Add the public `VideoSource`, `LuxVideoThumbnail.generate` and
  `VideoThumbnailPicker` APIs for Android and web.
* Register the web implementation automatically, serialize seeks, release decoder
  resources and use file-backed Blob URLs for browser selection.
* Return encoded image bytes and document the requested timestamp separately
  from decoder frame precision.
* Android preserves caller-owned videos, including legacy `vx://bytes/` paths.
* Restrict temporary input and thumbnail deletion to files created and tracked
  by the plugin, with checks for redirected paths and symbolic links.
* Send local video bytes directly to Android in the example.
