# Temporary file ownership

Video paths supplied by callers are read-only inputs. Absolute paths,
`file://` sources, and the legacy `vx://bytes/<path>` source do not transfer
ownership to the plugin. They are never deleted when generation fails,
generation succeeds, or a session closes. Callers that previously used
`vx://bytes/` for their own temporary files must now clean those files up.

For bytes, use the native `openSessionFromBytes` channel method with `bytes`
and `mimeType`. Android creates the input in its private cache and removes it
when opening fails or the session closes. Public byte sources use this method.

Only files created and registered by the current plugin instance can be
deleted as temporaries. Inputs and output thumbnails have separate ownership
categories. `deleteThumbnailFile` rejects unregistered files and input videos
with `PERMISSION_DENIED`, including files manually placed in the cache.
Paths containing traversal aliases or redirected by symbolic links are rejected.
Saving a thumbnail to another location does not transfer ownership of the copy.

Regression tests use real filesystem operations and mock Android media decoding.
From the root of a full source checkout (which includes the example):

```sh
cd example/android
./gradlew :lux_video_thumbnail_android:testDebugUnitTest
```

Symbolic-link tests require a filesystem and OS account allowed to create links;
JUnit marks these tests skipped if the host does not provide that capability.
