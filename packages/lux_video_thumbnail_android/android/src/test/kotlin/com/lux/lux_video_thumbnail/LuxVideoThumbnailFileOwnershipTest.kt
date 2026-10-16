package com.lux.lux_video_thumbnail

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.OutputStream
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mockito.ArgumentMatchers.*
import org.mockito.MockedConstruction
import org.mockito.MockedStatic
import org.mockito.Mockito.*

/** Real plugin handlers and disk IO; only Android media/engine APIs are mocked. */
class LuxVideoThumbnailFileOwnershipTest {
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var cache: File
    private lateinit var plugin: LuxVideoThumbnailPlugin
    private lateinit var retrievers: MockedConstruction<MediaMetadataRetriever>
    private lateinit var logs: MockedStatic<Log>
    private lateinit var os: MockedStatic<Os>
    private lateinit var osConstants: MockedStatic<OsConstants>
    private var durationMetadata: String? = "1000"
    private val positions = mutableListOf<Long>()
    private val seekOptions = mutableListOf<Int>()
    private var failOpening = false
    private var invalidDimensions = false
    private var widthMetadata = "320"
    private lateinit var bitmap: Bitmap
    private var failCompression = false
    private var frameRequests = 0
    private var failFrameNumber = Int.MAX_VALUE

    @Before fun setUp() {
        cache = temporary.newFolder("cache")
        logs = mockStatic(Log::class.java)
        os = mockStatic(Os::class.java)
        osConstants = mockStatic(OsConstants::class.java)
        // Link redirection is exercised against the real filesystem in the
        // ownership-policy tests; Android lstat itself is unavailable on the JVM.
        os.`when`<StructStat> { Os.lstat(anyString()) }.thenReturn(mock(StructStat::class.java))
        bitmap = mock(Bitmap::class.java)
        `when`(bitmap.width).thenReturn(320)
        `when`(bitmap.height).thenReturn(180)
        `when`(bitmap.compress(any(Bitmap.CompressFormat::class.java), anyInt(), any(OutputStream::class.java)))
            .thenAnswer { invocation ->
                (invocation.arguments[2] as OutputStream).write(byteArrayOf(1, 2, 3))
                !failCompression
            }
        retrievers = mockConstruction(MediaMetadataRetriever::class.java) { retriever, _ ->
            if (failOpening) {
                doThrow(IllegalArgumentException("Corrupt video")).`when`(retriever).setDataSource(anyString())
            }
            `when`(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)).thenAnswer { durationMetadata }
            `when`(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH))
                .thenReturn(if (invalidDimensions) "0" else widthMetadata)
            `when`(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)).thenReturn("180")
            `when`(retriever.getFrameAtTime(anyLong(), anyInt())).thenAnswer {
                positions.add(it.arguments[0] as Long)
                seekOptions.add(it.arguments[1] as Int)
                frameRequests++
                if (frameRequests == failFrameNumber) null else bitmap
            }
        }
        val context = mock(Context::class.java)
        `when`(context.cacheDir).thenReturn(cache)
        val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.applicationContext).thenReturn(context)
        `when`(binding.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
        plugin = LuxVideoThumbnailPlugin()
        plugin.synchronousHandlersForTest = true
        plugin.onAttachedToEngine(binding)
    }

    @After fun tearDown() {
        retrievers.close()
        os.close()
        osConstants.close()
        logs.close()
    }

    @Test fun `successful generation preserves every form of caller source`() {
        for (sourceKind in 0..2) {
            val original = temporary.newFile("original-$sourceKind.mp4").apply { writeText("original") }
            val result = call("generateThumbnail", mapOf("source" to source(original, sourceKind), "options" to emptyMap<String, Any>()))
            assertNull(result.errorCode)
            val thumbnail = File((result.value as Map<*, *>)["tempPath"] as String)
            assertTrue(thumbnail.exists())
            assertNull(call("deleteThumbnailFile", mapOf("path" to thumbnail.absolutePath)).errorCode)
            assertFalse(thumbnail.exists())
            assertEquals("original", original.readText())
        }
    }

    @Test fun `failed generation preserves every form of caller source`() {
        failOpening = true
        for (sourceKind in 0..2) {
            val original = temporary.newFile("original-$sourceKind.mp4").apply { writeText("original") }
            val result = call("generateThumbnail", mapOf("source" to source(original, sourceKind), "options" to emptyMap<String, Any>()))
            assertEquals("UNSUPPORTED_FORMAT", result.errorCode)
            assertEquals("original", original.readText())
        }
    }

    @Test fun `closing a session preserves every form of caller source`() {
        for (sourceKind in 0..2) {
            val original = temporary.newFile("original-$sourceKind.mp4").apply { writeText("original") }
            val opened = call("openSession", mapOf("source" to source(original, sourceKind)))
            assertNull(opened.errorCode)
            val handle = (opened.value as Map<*, *>)["nativeHandle"]
            assertNull(call("closeSession", mapOf("sessionHandle" to handle)).errorCode)
            assertEquals("original", original.readText())
        }
    }

    @Test fun `failed session opening preserves caller files and releases the retriever`() {
        failOpening = true
        val original = temporary.newFile("original.mp4").apply { writeText("original") }
        val result = call("openSession", mapOf("source" to source(original, 2)))
        assertEquals("UNSUPPORTED_FORMAT", result.errorCode)
        assertEquals("original", original.readText())
        verify(retrievers.constructed().last()).release()
    }

    @Test fun `bytes create a private temporary that is removed on session close`() {
        val input = byteArrayOf(4, 5, 6)
        val opened = call("openSessionFromBytes", mapOf("bytes" to input, "mimeType" to "video/mp4"))
        assertNull(opened.errorCode)
        val data = opened.value as Map<*, *>
        val file = File((data["metadata"] as Map<*, *>)["inputFilePath"] as String)
        assertArrayEquals(input, file.readBytes())
        assertTrue(file.canonicalPath.startsWith(cache.canonicalPath + File.separator))
        // An input owned by the plugin is still not a thumbnail.
        assertEquals("PERMISSION_DENIED", call("deleteThumbnailFile", mapOf("path" to file.absolutePath)).errorCode)
        assertTrue(file.exists())
        assertNull(call("closeSession", mapOf("sessionHandle" to data["nativeHandle"])).errorCode)
        assertFalse(file.exists())
    }

    @Test fun `decoder failure removes only its owned byte temporary`() {
        failOpening = true
        val original = temporary.newFile("original.mp4").apply { writeText("original") }
        assertEquals("UNSUPPORTED_FORMAT", call("openSessionFromBytes", mapOf("bytes" to byteArrayOf(0))).errorCode)
        assertTrue(cache.walkTopDown().none { it.isFile })
        assertEquals("original", original.readText())
    }

    @Test fun `invalid metadata also removes the owned byte temporary`() {
        invalidDimensions = true
        assertEquals("UNSUPPORTED_FORMAT", call("openSessionFromBytes", mapOf("bytes" to byteArrayOf(0))).errorCode)
        assertTrue(cache.walkTopDown().none { it.isFile })
        verify(retrievers.constructed().last()).release()
    }

    @Test fun `deleteThumbnailFile rejects an original even inside the thumbnail directory`() {
        val directory = File(cache, "lux_video_thumbnail/thumbnails").apply { mkdirs() }
        val original = File(directory, "original.mp4").apply { writeText("original") }
        assertEquals("PERMISSION_DENIED", call("deleteThumbnailFile", mapOf("path" to original.absolutePath)).errorCode)
        assertEquals("original", original.readText())
    }

    @Test fun `compression failure removes incomplete output and preserves original`() {
        failCompression = true
        val original = temporary.newFile("original.mp4").apply { writeText("original") }
        val result = call("generateThumbnail", mapOf("source" to source(original, 2), "options" to emptyMap<String, Any>()))
        assertEquals("GENERATION_FAILED", result.errorCode)
        assertTrue(cache.walkTopDown().none { it.isFile })
        assertEquals("original", original.readText())
    }

    @Test fun `failed batch removes outputs that could not be returned`() {
        failFrameNumber = 2
        val original = temporary.newFile("original.mp4").apply { writeText("original") }
        val opened = call("openSession", mapOf("source" to source(original, 2)))
        val handle = (opened.value as Map<*, *>)["nativeHandle"]
        val result = call("generateThumbnails", mapOf("sessionHandle" to handle, "options" to listOf(emptyMap<String, Any>(), emptyMap<String, Any>())))
        assertEquals("GENERATION_FAILED", result.errorCode)
        assertTrue(cache.walkTopDown().none { it.isFile })
        assertNull(call("closeSession", mapOf("sessionHandle" to handle)).errorCode)
        assertEquals("original", original.readText())
    }

    @Test fun `negative and beyond-end positions are rejected without extracting frames`() {
        val original = temporary.newFile("range.mp4")
        for (time in listOf(-1L, 1000001L)) {
            val result = call("generateThumbnail", mapOf("source" to original.absolutePath,
                "options" to mapOf("timestampUs" to time)))
            assertEquals("TIMESTAMP_OUT_OF_RANGE", result.errorCode)
        }
        assertTrue(positions.isEmpty())
        assertTrue(original.exists())
    }

    @Test fun `exact endpoint and submillisecond requests retain microsecond precision`() {
        val original = temporary.newFile("end.mp4")
        for ((requested, effective) in listOf(1000000L to 999999L, 500L to 500L, 0L to 0L)) {
            val result = call("generateThumbnail", mapOf("source" to original.absolutePath,
                "options" to mapOf("timestampUs" to requested)))
            assertNull(result.errorCode)
            assertEquals(effective, positions.last())
            assertEquals(effective, (result.value as Map<*, *>)["effectiveTimestampUs"])
        }
    }

    @Test fun `unknown duration does not reset requested position to zero`() {
        durationMetadata = null
        val original = temporary.newFile("unknown.mp4")
        val opened = call("openSession", mapOf("source" to original.absolutePath))
        assertNull((opened.value as Map<*, *>)["duration"])
        val result = call("generateThumbnails", mapOf("sessionHandle" to (opened.value as Map<*, *>)["nativeHandle"],
            "options" to listOf(mapOf("timestampMs" to 7500L))))
        assertNull(result.errorCode)
        assertEquals(7500000L, positions.single())
    }

    @Test fun `keyframe preference selects sync option and ordinary extraction stays closest`() {
        val original = temporary.newFile("keyframe.mp4")
        for (prefer in listOf(true, false)) {
            assertNull(call("generateThumbnail", mapOf("source" to original.absolutePath,
                "options" to mapOf("timestampMs" to 500L, "preferKeyFrame" to prefer))).errorCode)
        }
        assertEquals(listOf(MediaMetadataRetriever.OPTION_CLOSEST_SYNC, MediaMetadataRetriever.OPTION_CLOSEST), seekOptions)
    }

    @Test fun `invalid batch produces no partial thumbnail and the session recovers`() {
        val original = temporary.newFile("batch-time.mp4")
        val opened = call("openSession", mapOf("source" to original.absolutePath))
        val handle = (opened.value as Map<*, *>)["nativeHandle"]
        val result = call("generateThumbnails", mapOf("sessionHandle" to handle,
            "options" to listOf(mapOf("timestampMs" to 0L), mapOf("timestampMs" to 1001L))))
        assertEquals("TIMESTAMP_OUT_OF_RANGE", result.errorCode)
        assertTrue(positions.isEmpty())
        assertTrue(cache.walkTopDown().none { it.isFile })
        assertNull(call("generateThumbnails", mapOf("sessionHandle" to handle,
            "options" to listOf(mapOf("timestampMs" to 500L)))).errorCode)
        assertNull(call("closeSession", mapOf("sessionHandle" to handle)).errorCode)
    }

    @Test fun `engine detach releases sessions and owned outputs but preserves caller files`() {
        val original = temporary.newFile("detach-original.mp4").apply { writeText("original") }
        assertNull(call("openSession", mapOf("source" to original.absolutePath)).errorCode)
        assertNull(call("openSessionFromBytes", mapOf("bytes" to byteArrayOf(1, 2), "mimeType" to "video/mp4")).errorCode)
        assertNull(call("generateThumbnail", mapOf("source" to original.absolutePath,
            "options" to emptyMap<String, Any>())).errorCode)
        assertTrue(cache.walkTopDown().any { it.isFile })
        plugin.onDetachedFromEngine(mock(FlutterPlugin.FlutterPluginBinding::class.java))
        assertTrue(cache.walkTopDown().none { it.isFile })
        assertEquals("original", original.readText())
        retrievers.constructed().forEach { verify(it).release() }
    }

    @Test fun `file operations accept only owned thumbnails and validate ranges`() {
        val original = temporary.newFile("private.mp4").apply { writeText("original") }
        for (method in listOf("readThumbnailChunk", "getThumbnailFileSize")) {
            assertEquals("PERMISSION_DENIED", call(method, mapOf("path" to original.absolutePath)).errorCode)
        }
        assertEquals("PERMISSION_DENIED", call("copyThumbnailFile", mapOf("sourcePath" to original.absolutePath,
            "targetPath" to temporary.root.resolve("copy").absolutePath)).errorCode)
        val generated = call("generateThumbnail", mapOf("source" to original.absolutePath, "options" to emptyMap<String, Any>()))
        val path = (generated.value as Map<*, *>)["tempPath"]
        assertEquals("ARGUMENT_ERROR", call("readThumbnailChunk", mapOf("path" to path, "offset" to -1)).errorCode)
        assertEquals("ARGUMENT_ERROR", call("readThumbnailChunk", mapOf("path" to path, "offset" to 4)).errorCode)
        val bytes = call("readThumbnailChunk", mapOf("path" to path, "offset" to 1, "length" to 99))
        assertArrayEquals(byteArrayOf(2, 3), bytes.value as ByteArray)
        assertArrayEquals(byteArrayOf(), call("readThumbnailChunk", mapOf("path" to path, "offset" to 3)).value as ByteArray)
        assertEquals("IO_ERROR", call("copyThumbnailFile", mapOf("sourcePath" to path, "targetPath" to original.absolutePath)).errorCode)
        assertEquals("original", original.readText())
    }

    @Test fun `session ceiling releases capacity after close`() {
        val original = temporary.newFile("sessions.mp4")
        val handles = (1..4).map {
            val opened = call("openSession", mapOf("source" to original.absolutePath))
            assertNull(opened.errorCode)
            (opened.value as Map<*, *>)["nativeHandle"]
        }
        assertEquals("RESOURCE_LIMIT", call("openSession", mapOf("source" to original.absolutePath)).errorCode)
        assertEquals(4, retrievers.constructed().size)
        assertNull(call("closeSession", mapOf("sessionHandle" to handles.first())).errorCode)
        assertNull(call("openSession", mapOf("source" to original.absolutePath)).errorCode)
    }

    @Test fun `oversized metadata is rejected without extracting frames`() {
        widthMetadata = "8192"
        val original = temporary.newFile("oversized.mp4")
        val result = call("generateThumbnail", mapOf("source" to original.absolutePath, "options" to emptyMap<String, Any>()))
        assertEquals("RESOURCE_LIMIT", result.errorCode)
        assertTrue(positions.isEmpty())
        verify(retrievers.constructed().single()).release()
    }

    @Test fun `bitmap is recycled when temporary creation fails`() {
        File(cache, "lux_video_thumbnail").writeText("blocked directory")
        val original = temporary.newFile("temp-failure.mp4")
        val result = call("generateThumbnail", mapOf("source" to original.absolutePath, "options" to emptyMap<String, Any>()))
        assertEquals("GENERATION_FAILED", result.errorCode)
        verify(bitmap).recycle()
        verify(retrievers.constructed().single()).release()
    }

    @Test fun `retained thumbnail ceiling rejects decoding and disposal restores capacity`() {
        val original = temporary.newFile("outputs.mp4")
        val opened = call("openSession", mapOf("source" to original.absolutePath))
        val handle = (opened.value as Map<*, *>)["nativeHandle"]
        val paths = mutableListOf<String>()
        repeat(4) {
            val generated = call("generateThumbnails", mapOf("sessionHandle" to handle,
                "options" to List(16) { emptyMap<String, Any>() }))
            assertNull(generated.errorCode)
            paths.addAll((generated.value as List<*>).map { (it as Map<*, *>)["tempPath"] as String })
        }
        assertEquals(64, positions.size)
        assertEquals("RESOURCE_LIMIT", call("generateThumbnails", mapOf("sessionHandle" to handle,
            "options" to listOf(emptyMap<String, Any>()))).errorCode)
        assertEquals(64, positions.size)
        assertNull(call("deleteThumbnailFile", mapOf("path" to paths.first())).errorCode)
        assertNull(call("generateThumbnails", mapOf("sessionHandle" to handle,
            "options" to listOf(emptyMap<String, Any>()))).errorCode)
    }

    @Test fun `actual frame geometry is preserved when metadata orientation differs`() {
        `when`(bitmap.width).thenReturn(180)
        `when`(bitmap.height).thenReturn(320)
        val original = temporary.newFile("rotated.mp4")
        val result = call("generateThumbnail", mapOf("source" to original.absolutePath, "options" to emptyMap<String, Any>()))
        assertNull(result.errorCode)
        assertEquals(180, (result.value as Map<*, *>)["width"])
        assertEquals(320, (result.value as Map<*, *>)["height"])
        verify(bitmap).recycle()
    }

    private fun source(file: File, kind: Int): String = when (kind) {
        0 -> file.absolutePath
        1 -> "file://${file.absolutePath}"
        else -> "vx://bytes/${file.absolutePath}"
    }

    private fun call(method: String, arguments: Map<String, Any?>): RecordingResult {
        val result = RecordingResult()
        plugin.onMethodCall(MethodCall(method, arguments), result)
        assertEquals("Handler must complete exactly once", 1, result.completions)
        return result
    }

    private class RecordingResult : MethodChannel.Result {
        var completions = 0
        var value: Any? = null
        var errorCode: String? = null
        override fun success(result: Any?) { completions++; value = result }
        override fun error(code: String, message: String?, details: Any?) { completions++; errorCode = code }
        override fun notImplemented() { completions++; errorCode = "NOT_IMPLEMENTED" }
    }
}
