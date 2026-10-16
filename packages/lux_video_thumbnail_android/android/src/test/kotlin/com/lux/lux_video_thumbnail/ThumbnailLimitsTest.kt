package com.lux.lux_video_thumbnail

import io.flutter.plugin.common.MethodCall
import java.io.ByteArrayOutputStream
import org.junit.Assert.*
import org.junit.Test

class ThumbnailLimitsTest {
    @Test fun `malformed channel options are rejected before decoding`() {
        val invalid = listOf(
            mapOf("width" to 0), mapOf("height" to 4097), mapOf("width" to 1.5),
            mapOf("quality" to Double.NaN), mapOf("quality" to 101),
            mapOf("format" to "unknown"), mapOf("preferKeyFrame" to "true"),
            mapOf("timestampUs" to Double.POSITIVE_INFINITY), mapOf("timestampUs" to Long.MAX_VALUE),
            mapOf("timestampMs" to 0.5), mapOf("maintainAspectRatio" to 1),
        )
        invalid.forEach { options ->
            assertThrows(IllegalArgumentException::class.java) {
                ThumbnailLimits.validate(MethodCall("generateThumbnail", mapOf("source" to "video", "options" to options)))
            }
        }
    }

    @Test fun `batch and chunk bounds reject allocation overflow`() {
        assertThrows(ResourceLimit::class.java) {
            ThumbnailLimits.validate(MethodCall("generateThumbnails", mapOf("sessionHandle" to 1, "options" to List(17) { emptyMap<String, Any>() })))
        }
        for (value in listOf(-1L, Long.MAX_VALUE, Double.NaN, 0.5)) {
            assertThrows(IllegalArgumentException::class.java) {
                ThumbnailLimits.validate(MethodCall("readThumbnailChunk", mapOf("path" to "image", "length" to value)))
            }
        }
        ThumbnailLimits.validate(MethodCall("readThumbnailChunk", mapOf("path" to "image", "offset" to 0, "length" to 0)))
    }

    @Test fun `compression stops at byte ceiling without writing overflow`() {
        val output = ByteArrayOutputStream()
        val bounded = BoundedThumbnailOutput(output)
        bounded.write(ByteArray(ThumbnailLimits.MAX_IMAGE_BYTES))
        assertThrows(ResourceLimit::class.java) { bounded.write(1) }
        assertEquals(ThumbnailLimits.MAX_IMAGE_BYTES, output.size())
    }
}
