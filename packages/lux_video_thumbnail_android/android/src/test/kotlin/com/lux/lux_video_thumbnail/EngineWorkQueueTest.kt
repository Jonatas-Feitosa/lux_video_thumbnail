package com.lux.lux_video_thumbnail

import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class EngineWorkQueueTest {
    private class RecordingResult : Result {
        val calls = mutableListOf<String>()
        override fun success(value: Any?) { calls.add("success:$value") }
        override fun error(code: String, message: String?, details: Any?) { calls.add(code) }
        override fun notImplemented() { calls.add("missing") }
    }

    @Test fun `worker is separate serial and posts replies to supplied dispatcher`() {
        val caller = Thread.currentThread()
        val replies = LinkedBlockingQueue<() -> Unit>()
        val cleaned = CountDownLatch(1)
        val queue = EngineWorkQueue({ replies.add(it) }, { cleaned.countDown() })
        val first = RecordingResult()
        val second = RecordingResult()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val order = mutableListOf<Int>()
        try {
            queue.submit(first) {
                assertNotSame(caller, Thread.currentThread())
                order.add(1)
                started.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                it.success(1)
                it.error("duplicate", null, null)
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            queue.submit(second) { order.add(2); it.success(2) }
            assertTrue(first.calls.isEmpty())
            assertTrue(second.calls.isEmpty())
            release.countDown()
            replies.poll(5, TimeUnit.SECONDS)!!.invoke()
            replies.poll(5, TimeUnit.SECONDS)!!.invoke()
            assertEquals(listOf(1, 2), order)
            assertEquals(listOf("success:1"), first.calls)
            assertEquals(listOf("success:2"), second.calls)
            assertTrue(replies.isEmpty())
        } finally { release.countDown(); queue.detach() }
        assertTrue(cleaned.await(5, TimeUnit.SECONDS))
    }

    @Test fun `detach cancels pending and new work without waiting for active decoder`() {
        val replies = LinkedBlockingQueue<() -> Unit>()
        val cleaned = CountDownLatch(1)
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val queue = EngineWorkQueue({ replies.add(it) }, { cleaned.countDown() })
        val active = RecordingResult()
        val pending = RecordingResult()
        val late = RecordingResult()
        try {
            queue.submit(active) {
                started.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                it.success("obsolete")
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            queue.submit(pending) { fail("Pending operation ran after detach") }
            queue.detach()
            queue.detach()
            queue.submit(late) { fail("New operation ran after detach") }
            repeat(3) { replies.poll(5, TimeUnit.SECONDS)!!.invoke() }
            for (result in listOf(active, pending, late)) assertEquals(listOf("ENGINE_DETACHED"), result.calls)
            assertEquals(1L, cleaned.count)
        } finally { release.countDown(); queue.detach() }
        assertTrue(cleaned.await(5, TimeUnit.SECONDS))
        assertTrue(replies.isEmpty())
    }

    @Test fun `queue rejects excess calls and excess byte budget`() {
        val replies = LinkedBlockingQueue<() -> Unit>()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val cleaned = CountDownLatch(1)
        val queue = EngineWorkQueue({ replies.add(it) }, { cleaned.countDown() })
        val rejected = RecordingResult()
        val bytesRejected = RecordingResult()
        try {
            queue.submit(RecordingResult(), ThumbnailLimits.MAX_BYTES) {
                started.countDown(); check(release.await(5, TimeUnit.SECONDS)); it.success(null)
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            queue.submit(RecordingResult(), ThumbnailLimits.MAX_BYTES) { it.success(null) }
            queue.submit(bytesRejected, 1) { fail("Byte overflow executed") }
            replies.poll(5, TimeUnit.SECONDS)!!.invoke()
            assertEquals(listOf("RESOURCE_LIMIT"), bytesRejected.calls)
            repeat(14) { queue.submit(RecordingResult()) { it.success(null) } }
            queue.submit(rejected) { fail("Queue overflow executed") }
            replies.poll(5, TimeUnit.SECONDS)!!.invoke()
            assertEquals(listOf("RESOURCE_LIMIT"), rejected.calls)
        } finally { queue.detach(); release.countDown() }
        assertTrue(cleaned.await(5, TimeUnit.SECONDS))
    }

    @Test fun `unexpected failure does not stop subsequent work and replies once`() {
        val replies = LinkedBlockingQueue<() -> Unit>()
        val cleaned = CountDownLatch(1)
        val queue = EngineWorkQueue({ replies.add(it) }, { cleaned.countDown() })
        val failed = RecordingResult()
        val recovered = RecordingResult()
        try {
            queue.submit(failed) { throw IllegalArgumentException("private detail") }
            queue.submit(recovered) { it.notImplemented(); throw IllegalStateException() }
            repeat(2) { replies.poll(5, TimeUnit.SECONDS)!!.invoke() }
            assertEquals(listOf("GENERAL_FAILED"), failed.calls)
            assertEquals(listOf("missing"), recovered.calls)
        } finally { queue.detach() }
        assertTrue(cleaned.await(5, TimeUnit.SECONDS))
        assertTrue(replies.isEmpty())
    }
}
