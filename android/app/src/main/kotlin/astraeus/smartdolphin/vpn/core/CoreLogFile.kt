package astraeus.smartdolphin.vpn.core

import android.content.Context
import java.io.File

/// Persists Dolphin-Core (libbox) log lines under the same vpn-core tree as Flutter.
object CoreLogFile {
    private const val MAX_BYTES = 8 * 1024 * 1024L
    @Volatile private var logFile: File? = null

    fun init(context: Context) {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        val dir = File(base, "vpn-core/logs/runtime").apply { mkdirs() }
        logFile = File(dir, "dolphin-core.log")
    }

    fun append(message: String) {
        val f = logFile ?: return
        try {
            if (f.exists() && f.length() > MAX_BYTES) {
                val backup = File(f.parent, "dolphin-core.log.1")
                f.copyTo(backup, overwrite = true)
                f.writeText("")
            }
            f.appendText("${System.currentTimeMillis()} $message\n")
        } catch (_: Exception) {
        }
    }
}
