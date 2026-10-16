package com.lux.lux_video_thumbnail

import java.io.OutputStream

/** Stops encoder output before retaining an unbounded compressed image. */
internal class BoundedThumbnailOutput(private val target: OutputStream) : OutputStream() {
    private var size = 0L
    private fun reserve(count: Int) {
        if (size + count > ThumbnailLimits.MAX_IMAGE_BYTES) throw ResourceLimit("Encoded thumbnail exceeds 8 MiB")
        size += count
    }
    override fun write(value: Int) { reserve(1); target.write(value) }
    override fun write(bytes: ByteArray, offset: Int, length: Int) {
        reserve(length)
        target.write(bytes, offset, length)
    }
}
