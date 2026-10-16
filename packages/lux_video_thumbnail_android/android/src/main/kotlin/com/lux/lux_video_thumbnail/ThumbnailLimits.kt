package com.lux.lux_video_thumbnail

import io.flutter.plugin.common.MethodCall
import kotlin.math.roundToInt

internal class ResourceLimit(message: String) : RuntimeException(message)

internal object ThumbnailLimits {
    const val MAX_BYTES = 64 * 1024 * 1024
    const val MAX_IMAGE_BYTES = 8 * 1024 * 1024
    const val MAX_SESSIONS = 4
    const val MAX_BATCH = 16
    const val MAX_PENDING = 16
    const val MAX_TIMESTAMP = 9007199254740991L

    fun integer(value: Any?, name: String, min: Long = 0, max: Long = MAX_TIMESTAMP): Long {
        require(value is Number) { "$name must be an integer" }
        val number = value.toDouble()
        require(number.isFinite() && number % 1.0 == 0.0 && number >= min.toDouble() && number <= max.toDouble()) {
            "$name is outside its supported range"
        }
        return value.toLong()
    }

    fun dimensions(width: Int, height: Int) {
        if (width !in 1..4096 || height !in 1..4096 || width.toLong() * height > 16777216) {
            throw ResourceLimit("Image dimensions exceed resource limits")
        }
    }

    fun dimensionsFor(options: Map<String, Any?>, nativeWidth: Int, nativeHeight: Int): Pair<Int, Int> {
        dimensions(nativeWidth, nativeHeight)
        val requestedWidth = (options["width"] as? Number)?.toInt()
        val requestedHeight = (options["height"] as? Number)?.toInt()
        val aspect = nativeWidth.toDouble() / nativeHeight
        var width = requestedWidth ?: nativeWidth
        var height = requestedHeight ?: nativeHeight
        if (requestedWidth == null && requestedHeight != null) width = (height * aspect).roundToInt().coerceAtLeast(1)
        else if (requestedHeight == null && requestedWidth != null) height = (width / aspect).roundToInt().coerceAtLeast(1)
        else if (options["maintainAspectRatio"] != false && requestedWidth != null && requestedHeight != null) {
            if (width.toDouble() / height > aspect) width = (height * aspect).roundToInt().coerceAtLeast(1)
            else height = (width / aspect).roundToInt().coerceAtLeast(1)
        }
        dimensions(width, height)
        return width to height
    }

    fun options(raw: Any?) {
        require(raw is Map<*, *>) { "options must be a map" }
        for (key in listOf("timestampUs", "timestampMs")) {
            if (raw[key] != null) integer(raw[key], key, -MAX_TIMESTAMP,
                if (key == "timestampMs") MAX_TIMESTAMP / 1000 else MAX_TIMESTAMP)
        }
        for (key in listOf("width", "height")) {
            if (raw[key] != null) integer(raw[key], key, 1, 4096)
        }
        if (raw["quality"] != null) integer(raw["quality"], "quality", 1, 100)
        if (raw["format"] != null) require(raw["format"] in listOf("jpeg", "png", "webp")) { "Invalid format" }
        for (key in listOf("maintainAspectRatio", "preferKeyFrame")) {
            if (raw[key] != null) require(raw[key] is Boolean) { "$key must be boolean" }
        }
    }

    fun validate(call: MethodCall) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        fun text(key: String, max: Int = 16384): String {
            val value = args[key]
            require(value is String && value.isNotBlank() && value.length <= max && !value.contains('\u0000')) { "Invalid $key" }
            return value
        }
        when (call.method) {
            "openSession", "getVideoDuration", "generateThumbnail" -> text("source")
            "openSessionFromBytes" -> {
                val mime = if (args["mimeType"] == null) "video/mp4" else text("mimeType", 128)
                require(Regex("^video/[a-zA-Z0-9.+-]+$").matches(mime)) { "Invalid MIME type" }
                require(args["bytes"] is ByteArray) { "Missing video bytes" }
            }
            "isFormatSupported" -> text("mimeType", 128)
            "readThumbnailChunk", "getThumbnailFileSize", "deleteThumbnailFile" -> text("path")
            "copyThumbnailFile" -> { text("sourcePath"); text("targetPath") }
        }
        if (args.containsKey("bytes")) {
            val bytes = args["bytes"]
            require(bytes is ByteArray && bytes.isNotEmpty()) { "Invalid video bytes" }
            if (bytes.size > MAX_BYTES) throw ResourceLimit("Video bytes exceed 64 MiB")
        }
        when (call.method) {
            "generateThumbnail" -> options(args["options"])
            "generateThumbnails" -> {
                integer(args["sessionHandle"], "sessionHandle", 1, Int.MAX_VALUE.toLong())
                val options = args["options"]
                require(options is List<*> && options.isNotEmpty()) { "Missing batch options" }
                if (options.size > MAX_BATCH) throw ResourceLimit("Batch exceeds 16 options")
                options.forEach { options(it) }
            }
            "closeSession" -> integer(args["sessionHandle"], "sessionHandle", 1, Int.MAX_VALUE.toLong())
            "readThumbnailChunk" -> {
                if (args["offset"] != null) integer(args["offset"], "offset")
                if (args["length"] != null) integer(args["length"], "length", 0, MAX_IMAGE_BYTES.toLong())
            }
        }
    }
}
