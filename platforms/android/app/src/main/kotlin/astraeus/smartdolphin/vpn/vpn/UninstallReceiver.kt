package com.smartdolphin.vpn.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

/**
 * Best-effort uninstall notification to console feedback API.
 * Android may kill the process quickly; fire-and-forget on a background thread.
 */
class UninstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_PACKAGE_REMOVED) return
        val pkg = intent.data?.schemeSpecificPart ?: return
        if (pkg != context.packageName) return
        if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val uid = prefs.getInt("last_uid", 0)
        val username = prefs.getString("last_username", "") ?: ""
        val deviceId = prefs.getString("last_device_id", "") ?: ""
        if (uid <= 0 && username.isEmpty()) return

        Thread {
            try {
                val body = JSONObject().apply {
                    put("uid", uid)
                    put("error_code", "E0000")
                    put(
                        "message",
                        "User ${username.ifEmpty { uid.toString() }} uninstalled the Android client.",
                    )
                    put("log_snapshot", "uninstall event device=$deviceId")
                    put("client", "android")
                    put("device_id", deviceId)
                }
                val url = URL("https://api.smartdolphin.top/api/client/feedback")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 4000
                    readTimeout = 4000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                }
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                conn.inputStream.close()
                conn.disconnect()
                Log.d(TAG, "Uninstall feedback sent for uid=$uid")
            } catch (e: Exception) {
                Log.w(TAG, "Uninstall feedback failed: ${e.message}")
            }
        }.start()
    }

    companion object {
        private const val TAG = "UninstallReceiver"
        const val PREFS = "smartdolphin_vpn"
    }
}
