package com.lux.lux_video_thumbnail

import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** One engine owns one serial worker. Detach never waits for a decoder. */
internal class EngineWorkQueue(
    private val postReply: (() -> Unit) -> Unit,
    private val cleanup: () -> Unit,
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "lux-video-thumbnail").apply { isDaemon = true }
    },
) {
    private var detached = false
    private val pending = mutableSetOf<Reply>()
    private var queuedBytes = 0L

    @Synchronized fun submit(result: Result, byteWeight: Int = 0, operation: (Result) -> Unit) {
        val reply = Reply(result)
        if (detached) {
            reply.disconnected()
            return
        }
        if (pending.size >= ThumbnailLimits.MAX_PENDING || byteWeight < 0 ||
            byteWeight > ThumbnailLimits.MAX_BYTES || queuedBytes + byteWeight > 128L * 1024 * 1024) {
            reply.error("RESOURCE_LIMIT", "Android queue resource limit exceeded", null)
            return
        }
        pending.add(reply)
        queuedBytes += byteWeight
        worker.execute {
            try { if (!reply.completed.get()) {
                try { operation(reply) }
                catch (error: Exception) {
                    reply.error("GENERAL_FAILED", "Android operation failed", null)
                }
            } } finally { synchronized(this@EngineWorkQueue) { queuedBytes -= byteWeight } }
        }
    }

    @Synchronized fun detach() {
        if (detached) return
        detached = true
        // Complete calls immediately; an active native decoder cannot safely be interrupted.
        pending.toList().forEach { it.disconnected() }
        worker.execute { try { cleanup() } finally { worker.shutdown() } }
    }

    private inner class Reply(private val target: Result) : Result {
        val completed = AtomicBoolean(false)
        private fun finish(action: () -> Unit) {
            if (!completed.compareAndSet(false, true)) return
            synchronized(this@EngineWorkQueue) { pending.remove(this) }
            postReply(action)
        }
        override fun success(value: Any?) = finish { target.success(value) }
        override fun error(code: String, message: String?, details: Any?) =
            finish { target.error(code, message, details) }
        override fun notImplemented() = finish { target.notImplemented() }
        fun disconnected() = error("ENGINE_DETACHED", "Flutter engine disconnected", null)
    }
}
