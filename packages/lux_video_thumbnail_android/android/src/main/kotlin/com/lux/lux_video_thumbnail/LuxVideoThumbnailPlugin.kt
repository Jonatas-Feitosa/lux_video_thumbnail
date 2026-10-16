package com.lux.lux_video_thumbnail

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.WorkerThread
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMethodCodec
import java.io.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Session holding a MediaMetadataRetriever instance and optional input file.
 *
 * For VideoSource.bytes, the bytes are written to a temporary file in cacheDir
 * before being passed to MediaMetadataRetriever. This input temp file must be
 * cleaned up in closeSession, separate from the output thumbnail temp files.
 */
data class RetrieverSession(
    val handle: Int,
    val retriever: MediaMetadataRetriever,
    val ownedInputFile: File?, // Only files created by OwnedTemporaryFiles.
    val durationMs: Long?,
    val width: Int,
    val height: Int,
)

/**
 * Android implementation of the lux_video_thumbnail plugin.
 *
 * Uses MediaMetadataRetriever for video frame extraction. Each openSession
 * creates a MediaMetadataRetriever instance that is reused across multiple
 * generateThumbnails calls within that session.
 *
 * Supported video source types:
 * - Local file paths (absolute paths, file:// URIs)
 * - Remote HTTP/HTTPS URLs (MediaMetadataRetriever.setDataSource supports URLs natively)
 * - Raw bytes via VideoSource.bytes (written to cacheDir temp file first)
 *
 * Minimum supported Android SDK: 24.
 */
class LuxVideoThumbnailPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var workQueue: EngineWorkQueue? = null
    // JVM media mocks are thread-local. Separate queue tests use real threads.
    internal var synchronousHandlersForTest = false
    private var context: Context? = null
    private var temporaryFiles: OwnedTemporaryFiles? = null

    // Active sessions: handle -> RetrieverSession
    private val sessions = ConcurrentHashMap<Int, RetrieverSession>()

    // Supported MIME types (static list as defined in architecture)
    private val supportedMimeTypes = setOf(
        "video/mp4",
        "video/webm",
        "video/quicktime",
        "video/x-matroska",
        "video/x-msvideo",
        "video/x-ms-wmv",
        "video/mpeg",
        "video/3gpp",
        "video/x-m4v",
    )

    // Cache for isFormatSupported results
    private val formatSupportCache = ConcurrentHashMap<String, Boolean>()

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "lux_video_thumbnail", StandardMethodCodec.INSTANCE)
        channel.setMethodCallHandler(this)
        if (synchronousHandlersForTest) {
            context = binding.applicationContext
            temporaryFiles = OwnedTemporaryFiles(binding.applicationContext.cacheDir)
        } else {
            val backend = LuxVideoThumbnailPlugin()
            val applicationContext = binding.applicationContext
            val replies = Handler(Looper.getMainLooper())
            val queue = EngineWorkQueue({ action -> replies.post { action() }; Unit }, {
                backend.releaseEngineResources()
            })
            workQueue = queue
            // Initialization and cache-path IO also belong to the worker.
            queue.submit(object : Result {
                override fun success(value: Any?) {}
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            }) {
                backend.context = applicationContext
                backend.temporaryFiles = OwnedTemporaryFiles(applicationContext.cacheDir)
                it.success(null)
            }
            workerBackend = backend
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        workQueue?.detach()
        if (synchronousHandlersForTest) releaseEngineResources()
    }

    private var workerBackend: LuxVideoThumbnailPlugin? = null

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        val queue = workQueue
        if (queue != null) {
            val backend = workerBackend!!
            val weight = ((call.arguments as? Map<*, *>)?.get("bytes") as? ByteArray)?.size ?: 0
            queue.submit(result, weight) { backend.handleMethodCall(call, it) }
        } else if (synchronousHandlersForTest) {
            handleMethodCall(call, result)
        } else {
            result.error("ENGINE_DETACHED", "Flutter engine is not attached", null)
        }
    }

    private fun releaseEngineResources() {
        sessions.values.forEach { session ->
            try { session.retriever.release() } catch (_: Exception) { }
        }
        sessions.clear()
        temporaryFiles?.deleteAll()
        temporaryFiles = null
        context = null
        formatSupportCache.clear()
    }

    private fun handleMethodCall(call: MethodCall, result: Result) {
        try {
            ThumbnailLimits.validate(call)
            if (call.method in listOf("openSession", "openSessionFromBytes") && sessions.size >= ThumbnailLimits.MAX_SESSIONS) {
                throw ResourceLimit("At most four sessions may be open")
            }
            if (call.method in listOf("generateThumbnail", "generateThumbnails")) {
                val batch = if (call.method == "generateThumbnail") 1 else
                    ((call.arguments as Map<*, *>)["options"] as List<*>).size
                if (requireTemporaryFiles().count(OwnedTemporaryFiles.Kind.THUMBNAIL) + batch > 64) {
                    throw ResourceLimit("At most 64 thumbnail temporaries may be retained")
                }
            }
            dispatchMethodCall(call, result)
        } catch (error: ResourceLimit) {
            result.error("RESOURCE_LIMIT", error.message, null)
        } catch (error: IllegalArgumentException) {
            result.error("ARGUMENT_ERROR", error.message, null)
        } catch (error: SecurityException) {
            result.error("PERMISSION_DENIED", "Only owned thumbnails may be accessed", null)
        }
    }

    private fun dispatchMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.SDK_INT}")
            }
            "openSession" -> {
                val source = call.argument<String>("source") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'source' argument", null)
                    return
                }
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes != null) {
                    openSessionFromBytes(bytes, source, result)
                } else {
                    openSession(source, result)
                }
            }
            "openSessionFromBytes" -> {
                val bytes = call.argument<ByteArray>("bytes") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'bytes' argument", null)
                    return
                }
                val mimeType = call.argument<String>("mimeType") ?: "video/mp4"
                openSessionFromBytes(bytes, mimeType, result)
            }
            "generateThumbnails" -> {
                val sessionHandle = call.argument<Number>("sessionHandle")?.toInt() ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'sessionHandle' argument", null)
                    return
                }
                val options = call.argument<List<Map<String, Any?>>>("options") ?: emptyList()
                generateThumbnails(sessionHandle, options, result)
            }
            "closeSession" -> {
                val sessionHandle = call.argument<Number>("sessionHandle")?.toInt() ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'sessionHandle' argument", null)
                    return
                }
                closeSession(sessionHandle, result)
            }
            "generateThumbnail" -> {
                val source = call.argument<String>("source") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'source' argument", null)
                    return
                }
                val options = call.argument<Map<String, Any?>>("options") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'options' argument", null)
                    return
                }
                generateThumbnail(source, options, result)
            }
            "isFormatSupported" -> {
                val mimeType = call.argument<String>("mimeType") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'mimeType' argument", null)
                    return
                }
                isFormatSupported(mimeType, result)
            }
            "getVideoDuration" -> {
                val source = call.argument<String>("source") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'source' argument", null)
                    return
                }
                getVideoDuration(source, result)
            }
            "readThumbnailChunk" -> {
                val path = call.argument<String>("path") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'path' argument", null)
                    return
                }
                val offset = (call.argument<Number>("offset") ?: 0L).toLong()
                val length = call.argument<Number>("length")?.toLong()
                readThumbnailChunk(path, offset, length, result)
            }
            "copyThumbnailFile" -> {
                val sourcePath = call.argument<String>("sourcePath") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'sourcePath' argument", null)
                    return
                }
                val targetPath = call.argument<String>("targetPath") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'targetPath' argument", null)
                    return
                }
                copyThumbnailFile(sourcePath, targetPath, result)
            }
            "deleteThumbnailFile" -> {
                val path = call.argument<String>("path") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'path' argument", null)
                    return
                }
                deleteThumbnailFile(path, result)
            }
            "getThumbnailFileSize" -> {
                val path = call.argument<String>("path") ?: run {
                    result.error("ARGUMENT_ERROR", "Missing 'path' argument", null)
                    return
                }
                getThumbnailFileSize(path, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Opens a video session for batch thumbnail generation.
     *
     * Creates a MediaMetadataRetriever instance, extracts metadata, and
     * stores the session in memory for reuse.
     *
     * Source resolution:
     * - file:// or absolute path with /storage, /data, etc → local file
     * - http:// or https:// → remote URL
     * - vx://bytes/<path> remains a caller-owned, read-only legacy source
     */
    @WorkerThread
    private fun openSession(source: String, @NonNull result: Result) {
        val retriever = MediaMetadataRetriever()
        var sessionStored = false
        try {
            val handle = generateHandle()

            when {
                source.startsWith("vx://bytes/") -> {
                    // Legacy caller-provided paths remain readable, but are never owned.
                    val filePath = source.substring("vx://bytes/".length)
                    if (!File(filePath).exists()) {
                        result.error("VIDEO_NOT_FOUND", "Input file not found: $filePath", null)
                        return
                    }
                    retriever.setDataSource(filePath)
                }
                source.startsWith("http://") || source.startsWith("https://") -> {
                    retriever.setDataSource(source, HashMap())
                }
                source.startsWith("file://") -> {
                    val filePath = source.substring("file://".length)
                    if (!File(filePath).exists()) {
                        result.error("VIDEO_NOT_FOUND", "File not found: $filePath", null)
                        return
                    }
                    retriever.setDataSource(filePath)
                }
                isAbsolutePath(source) -> {
                    if (!File(source).exists()) {
                        result.error("VIDEO_NOT_FOUND", "File not found: $source", null)
                        return
                    }
                    retriever.setDataSource(source)
                }
                else -> {
                    // Try as absolute path or content URI
                    try {
                        val uri = Uri.parse(source)
                        val ctx = context ?: run {
                            result.error("CONTEXT_ERROR", "No context available", null)
                            return
                        }
                        retriever.setDataSource(ctx, uri)
                    } catch (e: Exception) {
                        result.error("VIDEO_NOT_FOUND", "Source not found: $source", e.toString())
                        return
                    }
                }
            }

            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0

            if (width <= 0 || height <= 0) {
                // Could be audio-only or unsupported format
                result.error(
                    "UNSUPPORTED_FORMAT",
                    "Unable to extract video metadata - possibly unsupported format",
                    mapOf("format" to detectMimeType(source, retriever))
                )
                return
            }

            ThumbnailLimits.dimensions(width, height)
            val session = RetrieverSession(
                handle = handle,
                retriever = retriever,
                ownedInputFile = null,
                durationMs = durationMs,
                width = width,
                height = height,
            )
            sessions[handle] = session
            sessionStored = true

            val response = mapOf(
                "nativeHandle" to handle,
                "duration" to durationMs?.takeIf { it > 0 },
                "nativeWidth" to width,
                "nativeHeight" to height,
                "metadata" to mapOf(
                    "inputFilePath" to null,
                    "mimeType" to detectMimeType(source, retriever),
                ),
            )
            result.success(response)
        } catch (e: ResourceLimit) {
            result.error("RESOURCE_LIMIT", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("UNSUPPORTED_FORMAT", "Unsupported format or corrupt file: ${e.message}", null)
        } catch (e: Exception) {
            result.error("GENERATION_FAILED", "Failed to open session: ${e.message}", e.toString())
        } finally {
            if (!sessionStored) {
                try { retriever.release() } catch (ex: Exception) { /* ignore */ }
            }
        }
    }

    /**
     * Opens a video session from raw bytes.
     *
     * Writes the bytes to a temporary file in cacheDir before opening
     * with MediaMetadataRetriever, since MediaMetadataRetriever does not
     * accept raw bytes directly.
     *
     * The temp input file is tracked and cleaned up in closeSession.
     * This is separate from the output thumbnail temp files.
     *
     * @param bytes The video file bytes
     * @param mimeType The MIME type (used for temp file extension)
     * @param result The result callback
     */
    @WorkerThread
    private fun openSessionFromBytes(
        bytes: ByteArray,
        mimeType: String,
        @NonNull result: Result,
    ) {
        val ctx = context
        if (ctx == null) {
            result.error("CONTEXT_ERROR", "No context available", null)
            return
        }

        val handle = generateHandle()
        val extension = when (mimeType.lowercase()) {
            "video/webm" -> ".webm"
            "video/quicktime" -> ".mov"
            "video/x-matroska", "video/x-m4v" -> ".mkv"
            else -> ".mp4"
        }

        var inputFile: File? = null
        var retriever: MediaMetadataRetriever? = null
        var sessionStored = false
        try {
            val ownedFile = requireTemporaryFiles().create(OwnedTemporaryFiles.Kind.INPUT, extension)
            inputFile = ownedFile
            ownedFile.outputStream().use { it.write(bytes) }
            val activeRetriever = MediaMetadataRetriever()
            retriever = activeRetriever
            activeRetriever.setDataSource(ownedFile.absolutePath)

            val durationMs = activeRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            val width = activeRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = activeRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0

            if (width <= 0 || height <= 0) {
                result.error(
                    "UNSUPPORTED_FORMAT",
                    "Unable to extract video metadata",
                    mapOf("format" to activeRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE))
                )
                return
            }

            ThumbnailLimits.dimensions(width, height)
            val session = RetrieverSession(
                handle = handle,
                retriever = activeRetriever,
                ownedInputFile = ownedFile,
                durationMs = durationMs,
                width = width,
                height = height,
            )
            sessions[handle] = session
            sessionStored = true

            val response = mapOf(
                "nativeHandle" to handle,
                "duration" to durationMs?.takeIf { it > 0 },
                "nativeWidth" to width,
                "nativeHeight" to height,
                "metadata" to mapOf(
                    "inputFilePath" to ownedFile.absolutePath,
                    "mimeType" to mimeType,
                ),
            )
            result.success(response)
        } catch (e: ResourceLimit) {
            result.error("RESOURCE_LIMIT", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("UNSUPPORTED_FORMAT", "Unsupported format or corrupt file: ${e.message}", null)
        } catch (e: IOException) {
            result.error("IO_ERROR", "Failed to prepare input file: ${e.message}", null)
        } catch (e: Exception) {
            result.error("GENERATION_FAILED", "Failed to open session: ${e.message}", e.toString())
        } finally {
            if (!sessionStored) {
                try { retriever?.release() } catch (ex: Exception) { /* ignore */ }
                inputFile?.let { deleteOwnedTemporary(it, OwnedTemporaryFiles.Kind.INPUT) }
            }
        }
    }

    /**
     * Opens a video session for batch thumbnail generation.
     *
     * Reuses the MediaMetadataRetriever from the session for efficiency.
     * Each thumbnail is written to a temp file in cacheDir.
     *
     * Timestamps beyond a known duration are rejected; the exact end uses the last frame.
     */
    @WorkerThread
    private fun generateThumbnails(
        sessionHandle: Int,
        options: List<Map<String, Any?>>,
        @NonNull result: Result,
    ) {
        val session = sessions[sessionHandle] ?: run {
            result.error("SESSION_INVALID", "Session not found or already closed", mapOf("handle" to sessionHandle))
            return
        }

        val results = mutableListOf<Map<String, Any?>>()
        try {
            options.forEach { ThumbnailTimestamp.resolve(it, session.durationMs) }
            options.forEachIndexed { index, opt ->
                try {
                    results.add(generateSingleThumbnail(session, opt))
                } catch (e: Exception) {
                    Log.e("LuxVideoThumbnail", "Failed to generate thumbnail $index", e)
                    throw e
                }
            }
            result.success(results)
        } catch (e: Exception) {
            // No results were returned: discard outputs from the failed batch.
            results.forEach { thumbnail ->
                deleteOwnedTemporary(File(thumbnail["tempPath"] as String), OwnedTemporaryFiles.Kind.THUMBNAIL)
            }
            // Map specific exceptions to error codes
            if (e is ResourceLimit) result.error("RESOURCE_LIMIT", e.message, null)
            else if (e is TimestampOutOfRange) timestampError(e, result)
            else result.error("GENERATION_FAILED", e.message ?: "Unknown error", e.toString())
        }
    }

    /**
     * Generates a single thumbnail from a new session (convenience method).
     *
     * Opens a temporary session, generates the thumbnail, and closes the session.
     * For multiple thumbnails, use openSession + generateThumbnails + closeSession instead.
     */
    @WorkerThread
    private fun generateThumbnail(
        source: String,
        options: Map<String, Any?>,
        @NonNull result: Result,
    ) {
        val handle = generateHandle()
        val retriever = MediaMetadataRetriever()

        try {
            when {
                source.startsWith("vx://bytes/") -> {
                    val filePath = source.substring("vx://bytes/".length)
                    if (!File(filePath).exists()) {
                        result.error("VIDEO_NOT_FOUND", "Input file not found: $filePath", null)
                        return
                    }
                    retriever.setDataSource(filePath)
                }
                source.startsWith("http://") || source.startsWith("https://") -> {
                    retriever.setDataSource(source, HashMap())
                }
                source.startsWith("file://") -> {
                    val filePath = source.substring("file://".length)
                    if (!File(filePath).exists()) {
                        result.error("VIDEO_NOT_FOUND", "File not found: $filePath", null)
                        return
                    }
                    retriever.setDataSource(filePath)
                }
                isAbsolutePath(source) -> {
                    if (!File(source).exists()) {
                        result.error("VIDEO_NOT_FOUND", "File not found: $source", null)
                        return
                    }
                    retriever.setDataSource(source)
                }
                else -> {
                    val uri = Uri.parse(source)
                    val ctx = context ?: run {
                        result.error("CONTEXT_ERROR", "No context available", null)
                        return
                    }
                    retriever.setDataSource(ctx, uri)
                }
            }

            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0

            if (width <= 0 || height <= 0) {
                result.error(
                    "UNSUPPORTED_FORMAT",
                    "Unable to extract video metadata",
                    mapOf("format" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE))
                )
                return
            }

            ThumbnailLimits.dimensions(width, height)
            val tempSession = RetrieverSession(
                handle = handle,
                retriever = retriever,
                ownedInputFile = null,
                durationMs = durationMs,
                width = width,
                height = height,
            )

            val thumbnailResult = generateSingleThumbnail(tempSession, options)
            result.success(thumbnailResult)
        } catch (e: TimestampOutOfRange) {
            timestampError(e, result)
        } catch (e: ResourceLimit) {
            result.error("RESOURCE_LIMIT", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("UNSUPPORTED_FORMAT", "Unsupported format or corrupt file: ${e.message}", null)
        } catch (e: Exception) {
            result.error("GENERATION_FAILED", "Failed to generate thumbnail: ${e.message}", e.toString())
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // Ignore
            }
            // A source string never transfers ownership of the caller's file.
            sessions.remove(handle)
        }
    }

    /**
     * Generates a single thumbnail bitmap from the session at the specified timestamp.
     *
     * Uses the nearest decoded frame, or nearest sync frame when requested.
     * The returned timestamp identifies the effective seek, not the frame PTS.
     */
    @WorkerThread
    private fun generateSingleThumbnail(
        session: RetrieverSession,
        options: Map<String, Any?>,
    ): Map<String, Any?> {
        ThumbnailLimits.options(options)
        ThumbnailLimits.dimensions(session.width, session.height)
        // Check metadata-derived output before decoding, then honor actual frame orientation.
        ThumbnailLimits.dimensionsFor(options, session.width, session.height)
        val format = options["format"] as? String ?: "jpeg"
        val quality = (options["quality"] as? Number)?.toInt() ?: 85
        val effectiveTimestampUs = ThumbnailTimestamp.resolve(options, session.durationMs)
        val seekOption = if (options["preferKeyFrame"] == true) MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            else MediaMetadataRetriever.OPTION_CLOSEST
        val bitmap = session.retriever.getFrameAtTime(effectiveTimestampUs, seekOption)
            ?: throw IOException("No frame could be extracted at requested position")
        var finalBitmap = bitmap
        var tempFile: File? = null
        try {
            val (width, height) = ThumbnailLimits.dimensionsFor(options, bitmap.width, bitmap.height)
            if (bitmap.width != width || bitmap.height != height) {
                finalBitmap = Bitmap.createScaledBitmap(bitmap, width, height, true)
            }
            val outputFile = requireTemporaryFiles().create(OwnedTemporaryFiles.Kind.THUMBNAIL, ".tmp")
            tempFile = outputFile
            val compressFormat = when (format) {
                "png" -> Bitmap.CompressFormat.PNG
                "webp" -> Bitmap.CompressFormat.WEBP
                else -> Bitmap.CompressFormat.JPEG
            }
            outputFile.outputStream().use { stream ->
                val bounded = BoundedThumbnailOutput(stream)
                if (!finalBitmap.compress(compressFormat, quality, bounded)) {
                    throw IOException("Failed to compress thumbnail")
                }
            }
            return mapOf(
                "width" to finalBitmap.width, "height" to finalBitmap.height,
                "format" to format, "actualTimestamp" to effectiveTimestampUs / 1000L,
                "effectiveTimestampUs" to effectiveTimestampUs,
                "backingType" to "file", "tempPath" to outputFile.absolutePath,
            )
        } catch (error: Exception) {
            tempFile?.let { deleteOwnedTemporary(it, OwnedTemporaryFiles.Kind.THUMBNAIL) }
            throw error
        } finally {
            finalBitmap.recycle()
            if (finalBitmap !== bitmap) bitmap.recycle()
        }
    }

    private fun timestampError(error: TimestampOutOfRange, result: Result) {
        result.error("TIMESTAMP_OUT_OF_RANGE", error.message, mapOf(
            "requestedUs" to error.requestedUs,
            "requestedMs" to error.requestedUs / 1000L,
            "durationMs" to error.durationMs,
        ))
    }

    /**
     * Closes a session and releases native resources.
     *
     * Releases the MediaMetadataRetriever and deletes any temporary input file
     * that was created for VideoSource.bytes.
     */
    @WorkerThread
    private fun closeSession(sessionHandle: Int, @NonNull result: Result) {
        val session = sessions.remove(sessionHandle)
        if (session == null) {
            result.error("SESSION_INVALID", "Session not found", mapOf("handle" to sessionHandle))
            return
        }

        try {
            session.retriever.release()
        } catch (e: Exception) {
            Log.w("LuxVideoThumbnail", "Error releasing retriever", e)
        }

        // Clean up input temp file for VideoSource.bytes sessions
        session.ownedInputFile?.let { deleteOwnedTemporary(it, OwnedTemporaryFiles.Kind.INPUT) }

        result.success(null)
    }

    /**
     * Checks if a MIME type is supported.
     *
     * Uses the static list first, then falls back to a trial MediaMetadataRetriever
     * setDataSource call if the MIME type is not in the known list.
     * Results are cached for performance.
     */
    @WorkerThread
    private fun isFormatSupported(mimeType: String, @NonNull result: Result) {
        val normalizedMimeType = mimeType.lowercase()

        if (formatSupportCache.containsKey(normalizedMimeType)) {
            result.success(formatSupportCache[normalizedMimeType])
            return
        }

        var supported = supportedMimeTypes.contains(normalizedMimeType)

        if (!supported) {
            // Fallback: try to see if MediaMetadataRetriever can handle it
            // This is a best-effort check - we can't fully test without a file
            // But we can check common patterns
            supported = when (normalizedMimeType) {
                "video/mp4", "video/webm", "video/quicktime",
                "video/x-matroska", "video/x-msvideo", "video/mpeg",
                "video/3gpp", "video/x-m4v", "video/mp2t" -> true
                else -> false
            }
        }

        if (formatSupportCache.size >= 64) formatSupportCache.clear()
        formatSupportCache[normalizedMimeType] = supported
        result.success(supported)
    }

    /**
     * Gets the duration of a video without generating a thumbnail.
     */
    @WorkerThread
    private fun getVideoDuration(source: String, @NonNull result: Result) {
        val retriever = MediaMetadataRetriever()
        try {
            when {
                source.startsWith("http://") || source.startsWith("https://") -> {
                    retriever.setDataSource(source, HashMap())
                }
                source.startsWith("file://") -> {
                    val filePath = source.substring("file://".length)
                    retriever.setDataSource(filePath)
                }
                isAbsolutePath(source) -> {
                    retriever.setDataSource(source)
                }
                source.startsWith("vx://bytes/") -> {
                    val filePath = source.substring("vx://bytes/".length)
                    retriever.setDataSource(filePath)
                }
                else -> {
                    val uri = Uri.parse(source)
                    val ctx = context ?: run {
                        result.error("CONTEXT_ERROR", "No context available", null)
                        return
                    }
                    retriever.setDataSource(ctx, uri)
                }
            }

            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val durationMs = durationStr?.toLongOrNull()
            result.success(durationMs?.takeIf { it > 0 })
        } catch (e: ResourceLimit) {
            result.error("RESOURCE_LIMIT", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("UNSUPPORTED_FORMAT", "Unsupported format: ${e.message}", null)
        } catch (e: Exception) {
            result.error("VIDEO_NOT_FOUND", "Cannot determine duration: ${e.message}", null)
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    // --- Helper methods for file operations ---

    /**
     * Reads a chunk of bytes from a thumbnail file.
     * Used for streaming thumbnail data from native to Dart.
     */
    @WorkerThread
    private fun readThumbnailChunk(path: String, offset: Long, length: Long?, @NonNull result: Result) {
        val file = requireTemporaryFiles().requireThumbnail(path)
        val size = file.length()
        require(offset in 0..size) { "Offset outside thumbnail" }
        val count = minOf(length ?: (size - offset), size - offset)
        require(count in 0..ThumbnailLimits.MAX_IMAGE_BYTES.toLong()) { "Chunk exceeds 8 MiB" }
        try {
            RandomAccessFile(file, "r").use { input ->
                input.seek(offset)
                val buffer = ByteArray(count.toInt())
                input.readFully(buffer)
                result.success(buffer)
            }
        } catch (e: Exception) {
            result.error("IO_ERROR", "Failed to read thumbnail", null)
        }
    }

    /**
     * Copies a thumbnail file to a target path.
     */
    @WorkerThread
    private fun copyThumbnailFile(sourcePath: String, targetPath: String, @NonNull result: Result) {
        val sourceFile = requireTemporaryFiles().requireThumbnail(sourcePath)
        if (!sourceFile.exists()) {
            result.error("FILE_NOT_FOUND", "Source file not found: $sourcePath", null)
            return
        }

        try {
            val targetFile = File(targetPath)
            targetFile.parentFile?.mkdirs()
            if (!targetFile.createNewFile()) {
                result.error("IO_ERROR", "Destination already exists", null)
                return
            }
            try { sourceFile.inputStream().use { input -> targetFile.outputStream().use { input.copyTo(it) } } }
            catch (error: Exception) { targetFile.delete(); throw error }
            result.success(null)
        } catch (e: Exception) {
            result.error("IO_ERROR", "Failed to copy file: ${e.message}", null)
        }
    }

    /**
     * Deletes a thumbnail file.
     */
    @WorkerThread
    private fun deleteThumbnailFile(path: String, @NonNull result: Result) {
        try {
            requireTemporaryFiles().delete(path, OwnedTemporaryFiles.Kind.THUMBNAIL)
            result.success(null)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Only owned thumbnail temporaries may be deleted", null)
        } catch (e: Exception) {
            result.error("IO_ERROR", "Failed to delete thumbnail: ${e.message}", null)
        }
    }

    /**
     * Gets the size of a file in bytes.
     */
    @WorkerThread
    private fun getThumbnailFileSize(path: String, @NonNull result: Result) {
        val file = requireTemporaryFiles().requireThumbnail(path)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "File not found: $path", null)
            return
        }
        result.success(file.length())
    }

    // --- Utility methods ---

    private var nextHandle = 1

    private fun generateHandle(): Int {
        while (true) {
            val handle = nextHandle++
            if (nextHandle <= 0) nextHandle = 1
            if (handle > 0 && !sessions.containsKey(handle)) return handle
        }
    }

    private fun isAbsolutePath(path: String): Boolean {
        return File(path).isAbsolute
    }

    private fun requireTemporaryFiles(): OwnedTemporaryFiles =
        temporaryFiles ?: throw IllegalStateException("Context not available")

    private fun deleteOwnedTemporary(file: File, kind: OwnedTemporaryFiles.Kind) {
        try {
            requireTemporaryFiles().delete(file.absolutePath, kind)
        } catch (e: Exception) {
            Log.w("LuxVideoThumbnail", "Could not clean up owned temporary", e)
        }
    }

    private fun detectMimeType(source: String, retriever: MediaMetadataRetriever): String? {
        return retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
    }
}
