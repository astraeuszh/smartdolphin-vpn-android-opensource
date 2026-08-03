package com.smartdolphin.vpn.core

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

/// Bridges the Go-backed [BoxService] (a separate Service) with the Flutter
/// engine's event channels (stage / status). All sink calls are marshalled to
/// the main thread.
object CoreBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile var stageSink: EventChannel.EventSink? = null
    @Volatile var statusSink: EventChannel.EventSink? = null

    /// True only while the tunnel is fully connected.
    @Volatile var connected: Boolean = false

    /// Last config requested from Flutter (consumed by BoxService on start).
    @Volatile var pendingConfig: String? = null

    @Volatile private var startRequestedAtMs: Long = 0
    @Volatile private var tunEstablishedAtMs: Long = 0
    @Volatile private var coreReadyAtMs: Long = 0

    fun markStartRequested() {
        startRequestedAtMs = SystemClock.elapsedRealtime()
        tunEstablishedAtMs = 0
        coreReadyAtMs = 0
    }

    fun markTunEstablished() {
        if (tunEstablishedAtMs == 0L) {
            tunEstablishedAtMs = SystemClock.elapsedRealtime()
        }
    }

    fun markCoreReady() {
        coreReadyAtMs = SystemClock.elapsedRealtime()
    }

    fun connectionMetrics(): Map<String, Long> {
        val start = startRequestedAtMs
        val tun = tunEstablishedAtMs
        val ready = coreReadyAtMs
        return mapOf(
            "tun_ms" to if (start > 0 && tun >= start) tun - start else -1,
            "core_ms" to if (start > 0 && ready >= start) ready - start else -1,
        )
    }

    fun emitStage(stage: String) {
        connected = stage == "connected"
        main.post { runCatching { stageSink?.success(stage) } }
    }

    fun emitStatus(json: String) {
        main.post { runCatching { statusSink?.success(json) } }
    }
}
