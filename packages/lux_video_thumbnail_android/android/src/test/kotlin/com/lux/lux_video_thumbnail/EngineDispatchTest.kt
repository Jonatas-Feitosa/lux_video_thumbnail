package com.lux.lux_video_thumbnail

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.*

class EngineDispatchTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `production channel schedules worker replies through main Handler`() {
        val callbacks = LinkedBlockingQueue<Runnable>()
        val main = Thread.currentThread()
        mockStatic(Looper::class.java).use { loopers ->
            loopers.`when`<Looper> { Looper.getMainLooper() }.thenReturn(mock(Looper::class.java))
            mockConstruction(Handler::class.java) { handler, _ ->
                `when`(handler.post(any(Runnable::class.java))).thenAnswer {
                    assertNotSame(main, Thread.currentThread())
                    callbacks.add(it.arguments[0] as Runnable)
                    true
                }
            }.use {
                val context = mock(Context::class.java)
                `when`(context.cacheDir).thenAnswer {
                    assertNotSame(main, Thread.currentThread())
                    temporary.root
                }
                val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
                `when`(binding.applicationContext).thenReturn(context)
                `when`(binding.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
                val plugin = LuxVideoThumbnailPlugin()
                var completed = false
                plugin.onAttachedToEngine(binding)
                try {
                    plugin.onMethodCall(MethodCall("unknownMethod", null), object : MethodChannel.Result {
                        override fun success(value: Any?) { fail("Unexpected success") }
                        override fun error(code: String, message: String?, details: Any?) { fail(code) }
                        override fun notImplemented() {
                            assertSame(main, Thread.currentThread())
                            completed = true
                        }
                    })
                    assertFalse(completed)
                    // Initialization and then the channel response.
                    repeat(2) { callbacks.poll(5, TimeUnit.SECONDS)!!.run() }
                    assertTrue(completed)
                } finally { plugin.onDetachedFromEngine(binding) }
            }
        }
    }
}
