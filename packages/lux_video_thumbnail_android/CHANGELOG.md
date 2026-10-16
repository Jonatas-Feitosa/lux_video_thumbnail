## 1.0.0

* Initial Android implementation with reusable MediaMetadataRetriever sessions.
* Preserve caller videos and restrict temporary file operations to owned outputs.
* Support microsecond requests, timestamp bounds and optional keyframe extraction.
* Serialize work outside the UI thread and clean up after engine detach.
* Validate channel inputs and bound sessions, queues, images and temporary files.
* Remove broad storage permissions; require readable paths/URIs from the host app.
* License under MIT, Copyright (c) 2026 Jônatas Feitosa.
