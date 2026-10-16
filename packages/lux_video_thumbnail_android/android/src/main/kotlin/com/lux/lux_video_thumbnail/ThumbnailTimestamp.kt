package com.lux.lux_video_thumbnail

/** Requested timestamps are independent of the decoder's actual frame PTS. */
internal class TimestampOutOfRange(val requestedUs: Long, val durationMs: Long?) :
    IllegalArgumentException("Timestamp is outside the video timeline")

internal object ThumbnailTimestamp {
    fun resolve(options: Map<String, Any?>, durationMs: Long?): Long {
        val raw = options["timestampUs"] ?: options["timestampMs"] ?: 0L
        require(raw is Number && raw.toDouble().isFinite()) { "Invalid timestamp" }
        val requested = if (options["timestampUs"] != null) raw.toLong()
            else Math.multiplyExact(raw.toLong(), 1000L)
        val end = durationMs?.takeIf { it > 0 }?.let { Math.multiplyExact(it, 1000L) }
        if (requested < 0 || (end != null && requested > end)) {
            throw TimestampOutOfRange(requested, durationMs)
        }
        return if (end != null && requested == end) (end - 1).coerceAtLeast(0) else requested
    }
}
