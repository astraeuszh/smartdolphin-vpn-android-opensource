package astraeus.smartdolphin.vpn.core

import android.os.Handler
import android.os.Looper
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

    fun emitStage(stage: String) {
        connected = stage == "connected"
        main.post { runCatching { stageSink?.success(stage) } }
    }

    fun emitStatus(json: String) {
        main.post { runCatching { statusSink?.success(json) } }
    }
}
