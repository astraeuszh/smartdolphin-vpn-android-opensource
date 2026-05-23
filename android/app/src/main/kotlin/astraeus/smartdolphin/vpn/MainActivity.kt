package astraeus.smartdolphin.vpn

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.TrafficStats
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import java.io.File
import android.app.ActivityManager
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import astraeus.smartdolphin.vpn.game.GameModeLocalService
import astraeus.smartdolphin.vpn.vpn.SmartDolphinTileService
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.example.vpn/VpnChannel"
    private val prefsName = "smartdolphin_vpn"
    private var prepareResult: MethodChannel.Result? = null

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        Log.d(TAG, "VPN permission result: ${result.resultCode}")
        prepareResult?.success(result.resultCode == Activity.RESULT_OK)
        prepareResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "astraeus.smartdolphin.vpn/game_traffic")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "applyMode" -> {
                        val mode = call.arguments as? String ?: "accel"
                        getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                            .putString("game_traffic_mode", mode)
                            .apply()
                        Log.d(TAG, "game_traffic applyMode=$mode")
                        result.success(null)
                    }
                    "syncGameModeOverlay" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<*, *>
                        val visible = args?.get("visible") as? Boolean ?: false
                        val mode = args?.get("mode") as? String ?: "accel"
                        Log.d(TAG, "game_traffic overlay visible=$visible mode=$mode")
                        if (visible && mode == GameModeLocalService.MODE_ACCEL) {
                            GameModeLocalService.start(applicationContext, mode)
                        } else {
                            GameModeLocalService.stop(applicationContext)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        GameModeLocalService.stop(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> handlePrepare(result)
                "getInstalledApps" -> result.success(fetchInstalledApps())
                "updateQuickTile" -> {
                    SmartDolphinTileService.requestTileUpdate(this)
                    result.success(null)
                }
                "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
                "openLogDirectory" -> openLogDirectory(call.argument<String>("path"), result)
                "copyToClipboard" -> copyToClipboard(call.argument<String>("text") ?: "", result)
                "requestBatteryOptimizationExemption" -> requestBatteryOptimizationExemption(result)
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "getTotalRamMb" -> {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val mi = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(mi)
                    result.success((mi.totalMem / (1024 * 1024)).toInt())
                }
                "getNetworkTotals" -> {
                    result.success(
                        mapOf(
                            "rx" to TrafficStats.getTotalRxBytes(),
                            "tx" to TrafficStats.getTotalTxBytes(),
                        )
                    )
                }
                "setWakeOnBootEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                        .putBoolean("wake_on_boot", enabled).apply()
                    result.success(null)
                }
                "setHasActiveSession" -> {
                    val hasSession = call.arguments as? Boolean ?: false
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                        .putBoolean("has_active_session", hasSession).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handlePrepare(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        Log.d(TAG, "VpnService.prepare returned: ${if (intent != null) "intent (need permission)" else "null (already granted)"}")
        if (intent != null) {
            prepareResult = result
            vpnPermissionLauncher.launch(intent)
        } else {
            result.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        OpenVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == RESULT_OK)
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun fetchInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(0)
        return apps
            .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
            .map {
                mapOf(
                    "package" to it.packageName,
                    "name" to pm.getApplicationLabel(it).toString(),
                )
            }
            .sortedBy { it["name"] }
    }

    private fun openLogDirectory(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("INVALID_PATH", "Log path is empty", null)
            return
        }
        try {
            val dir = File(path)
            if (!dir.exists()) dir.mkdirs()
            val logFile = File(dir, "vpn.log")
            val target = when {
                logFile.exists() -> logFile
                dir.exists() -> dir
                else -> {
                    result.error("NOT_FOUND", "Log directory not found", null)
                    return
                }
            }

            val uri = FileProvider.getUriForFile(this, "$packageName.files", target)
            val mimeType = if (target.isDirectory) {
                "vnd.android.document/directory"
            } else {
                "text/plain"
            }

            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            val packageManager = packageManager
            if (viewIntent.resolveActivity(packageManager) != null) {
                startActivity(Intent.createChooser(viewIntent, getString(R.string.open_with_file_manager)))
                result.success(true)
                return
            }

            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (sendIntent.resolveActivity(packageManager) != null) {
                startActivity(Intent.createChooser(sendIntent, getString(R.string.open_with_file_manager)))
                result.success(true)
                return
            }

            result.error("OPEN_FAILED", "No app can open log files", null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open log", e)
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    private fun copyToClipboard(text: String, result: MethodChannel.Result) {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("log_path", text))
            result.success(true)
        } catch (e: Exception) {
            result.error("COPY_FAILED", e.message, null)
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationExemption(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        if (isIgnoringBatteryOptimizations()) {
            result.success(true)
            return
        }
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request battery exemption", e)
            result.error("BATTERY_EXEMPTION", e.message, null)
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
