package com.smartdolphin.vpn

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.TrafficStats
import android.net.Uri
import android.net.VpnService
import android.media.MediaRecorder
import android.media.MediaPlayer
import android.os.Build
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest
import android.app.ActivityManager
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.smartdolphin.vpn.core.BoxService
import com.smartdolphin.vpn.core.CoreBridge
import com.smartdolphin.vpn.game.GameModeLocalService
import com.smartdolphin.vpn.vpn.ProxyShareService
import com.smartdolphin.vpn.vpn.SmartDolphinTileService
import com.smartdolphin.vpn.update.NativeUpdateManager

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.example.vpn/VpnChannel"
    private val prefsName = "smartdolphin_vpn"
    private var prepareResult: MethodChannel.Result? = null
    private var voiceRecorder: MediaRecorder? = null
    private var voiceRecordingFile: File? = null
    private var voicePlayer: MediaPlayer? = null

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        Log.d(TAG, "VPN permission result: ${result.resultCode}")
        prepareResult?.success(result.resultCode == Activity.RESULT_OK)
        prepareResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Dolphin-Core (Go/libbox) engine channels 鈥?the entire VPN backend is Go.
        MethodChannel(messenger, "smartdolphin/core").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> handlePrepare(result)
                "start" -> {
                    val cfg = call.argument<String>("config")
                    if (cfg.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        CoreBridge.pendingConfig = cfg
                        val i = Intent(this, BoxService::class.java)
                            .setAction(BoxService.ACTION_START)
                            .putExtra(BoxService.EXTRA_CONFIG, cfg)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                        result.success(true)
                    }
                }
                "stop" -> {
                    startService(Intent(this, BoxService::class.java).setAction(BoxService.ACTION_STOP))
                    result.success(true)
                }
                "isConnected" -> result.success(CoreBridge.connected)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "smartdolphin/core/stage").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { CoreBridge.stageSink = events }
            override fun onCancel(arguments: Any?) { CoreBridge.stageSink = null }
        })
        EventChannel(messenger, "smartdolphin/core/status").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { CoreBridge.statusSink = events }
            override fun onCancel(arguments: Any?) { CoreBridge.statusSink = null }
        })

        MethodChannel(messenger, "smartdolphin/voice_recorder").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startVoiceRecording(result)
                "amplitude" -> result.success(voiceRecorder?.maxAmplitude ?: 0)
                "stop" -> stopVoiceRecording(result)
                "cancel" -> cancelVoiceRecording(result)
                "openMedia" -> openMedia(call.argument<String>("path"), result)
                "playVoice" -> playVoice(call.argument<String>("path"), call.argument<Double>("speed") ?: 1.0, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "smartdolphin/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "enqueue" -> {
                    val version = call.argument<String>("version") ?: ""
                    val url = call.argument<String>("url") ?: ""
                    if (version.isBlank() || url.isBlank()) {
                        result.error("INVALID_UPDATE", "Missing version or URL", null)
                    } else {
                        val id = NativeUpdateManager.enqueue(
                            applicationContext,
                            version,
                            url,
                            call.argument<String>("sha256") ?: "",
                            call.argument<Number>("size")?.toLong() ?: 0L,
                            call.argument<String>("chunkManifestUrl") ?: "",
                            call.argument<List<String>>("downloadUrls") ?: emptyList(),
                        )
                        result.success(id)
                    }
                }
                "state" -> {
                    val state = NativeUpdateManager.state(applicationContext)
                    result.success(mapOf(
                        "status" to state.status,
                        "received" to state.received,
                        "total" to state.total,
                        "version" to state.version,
                    ))
                }
                "install" -> result.success(NativeUpdateManager.openInstaller(applicationContext))
                else -> result.notImplemented()
            }
        }

        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.smartdolphin.vpn/game_traffic")
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
                "isAlwaysOnVpnEnabled" -> result.success(isAlwaysOnVpnEnabled())
                "isVpnLockdownEnabled" -> result.success(isVpnLockdownEnabled())
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
                "getAppMemoryMb" -> result.success(readAppMemoryMb())
                "getNetworkTotals" -> {
                    result.success(
                        mapOf(
                            "rx" to TrafficStats.getTotalRxBytes(),
                            "tx" to TrafficStats.getTotalTxBytes(),
                        )
                    )
                }
                "getHardwareDeviceId" -> result.success(computeHardwareDeviceId())
                "pingHost" -> {
                    val host = call.argument<String>("host") ?: "8.8.8.8"
                    val count = call.argument<Int>("count") ?: 1
                    Thread {
                        try {
                            result.success(measurePing(host, count.coerceIn(1, 16)))
                        } catch (e: Exception) {
                            result.error("PING_FAILED", e.message, null)
                        }
                    }.start()
                }
                "setWakeOnBootEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                        .putBoolean("wake_on_boot", enabled).apply()
                    result.success(null)
                }
                "setReconnectOnNetworkChange" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                        .putBoolean("reconnect_on_network_change", enabled).apply()
                    result.success(null)
                }
                "consumeLaunchFromBoot" -> {
                    val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                    val fromBoot = prefs.getBoolean("launch_from_boot", false)
                    prefs.edit().remove("launch_from_boot").apply()
                    result.success(fromBoot)
                }
                "syncUninstallMeta" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    val uid = (args?.get("uid") as? Number)?.toInt() ?: 0
                    val username = args?.get("username") as? String ?: ""
                    val deviceId = args?.get("device_id") as? String ?: ""
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                        .putInt("last_uid", uid)
                        .putString("last_username", username)
                        .putString("last_device_id", deviceId)
                        .apply()
                    result.success(null)
                }
                "setHasActiveSession" -> {
                    val hasSession = call.arguments as? Boolean ?: false
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                        .putBoolean("has_active_session", hasSession).apply()
                    result.success(null)
                }
                "startProxyShare" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    val mode = args?.get("mode") as? String ?: "http"
                    ProxyShareService.start(mode)
                    result.success(null)
                }
                "stopProxyShare" -> {
                    ProxyShareService.stop()
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

    /** True when this app is set as Android's always-on VPN (kill-switch companion). */
    private fun isAlwaysOnVpnEnabled(): Boolean {
        return try {
            Settings.Secure.getString(contentResolver, "always_on_vpn_app") == packageName
        } catch (_: Exception) {
            false
        }
    }

    private fun startVoiceRecording(result: MethodChannel.Result) {
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 8114)
            result.success(false)
            return
        }
        try {
            cancelVoiceRecording(null)
            val file = File(cacheDir, "support_voice_${System.currentTimeMillis()}.m4a")
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else MediaRecorder()
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(64000)
            recorder.setAudioSamplingRate(44100)
            recorder.setOutputFile(file.absolutePath)
            recorder.prepare()
            recorder.start()
            voiceRecorder = recorder
            voiceRecordingFile = file
            result.success(true)
        } catch (e: Exception) {
            cancelVoiceRecording(null)
            result.error("VOICE_START", e.message, null)
        }
    }

    private fun stopVoiceRecording(result: MethodChannel.Result?) {
        val recorder = voiceRecorder
        val file = voiceRecordingFile
        voiceRecorder = null
        voiceRecordingFile = null
        if (recorder == null || file == null) {
            result?.success(null)
            return
        }
        try {
            recorder.stop()
            recorder.release()
            result?.success(if (file.exists() && file.length() > 256) file.absolutePath else null)
        } catch (_: Exception) {
            runCatching { recorder.release() }
            file.delete()
            result?.success(null)
        }
    }

    private fun cancelVoiceRecording(result: MethodChannel.Result?) {
        val recorder = voiceRecorder
        val file = voiceRecordingFile
        voiceRecorder = null
        voiceRecordingFile = null
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        runCatching { file?.delete() }
        result?.success(null)
    }

    private fun openMedia(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("MEDIA_PATH", "Media path is empty", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("MEDIA_MISSING", "Media file is unavailable", null)
            return
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        val mime = when (file.extension.lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "mp4", "mkv", "webm" -> "video/*"
            "m4a", "aac", "mp3", "wav" -> "audio/*"
            "apk" -> "application/vnd.android.package-archive"
            else -> "*/*"
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error("MEDIA_VIEWER", "No media viewer is installed", null)
            return
        }
        startActivity(Intent.createChooser(intent, "Open media"))
        result.success(true)
    }

    private fun playVoice(path: String?, speed: Double, result: MethodChannel.Result) {
        if (path.isNullOrBlank() || !File(path).exists()) {
            result.error("VOICE_MISSING", "Voice file is unavailable", null)
            return
        }
        try {
            voicePlayer?.release()
            voicePlayer = MediaPlayer().apply {
                setDataSource(path)
                playbackParams = android.media.PlaybackParams().setSpeed(speed.coerceIn(0.5, 2.0).toFloat())
                setOnCompletionListener { player ->
                    player.release()
                    if (voicePlayer === player) voicePlayer = null
                }
                prepare()
                start()
            }
            result.success(true)
        } catch (e: Exception) {
            voicePlayer?.release()
            voicePlayer = null
            result.error("VOICE_PLAY", e.message, null)
        }
    }

    private fun isVpnLockdownEnabled(): Boolean {
        return try {
            Settings.Secure.getInt(contentResolver, "always_on_vpn_lockdown") == 1
        } catch (_: Exception) {
            false
        }
    }

    /** App process PSS (Proportional Set Size) in megabytes. */
    private fun readAppMemoryMb(): Int {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val pid = android.os.Process.myPid()
            val info = am.getProcessMemoryInfo(intArrayOf(pid)).firstOrNull()
            if (info != null) (info.totalPss / 1024).coerceAtLeast(0) else 0
        } catch (_: Exception) {
            0
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
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
            val candidates = listOf(
                File(dir, "logs/README.txt"),
                File(dir, "logs/runtime/runtime.log"),
                File(dir, "logs/user/action.log"),
                dir,
            )
            val target = candidates.firstOrNull { it.exists() }
            if (target == null) {
                result.error("NOT_FOUND", "Log directory not found", null)
                return
            }

            val uri = FileProvider.getUriForFile(this, "$packageName.files", target)
            val mimeType = if (target.isDirectory) "resource/folder" else "text/plain"

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

    private fun computeHardwareDeviceId(): String {
        val androidId =
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        val material = if (androidId.isNotEmpty() && androidId != "9774d56d682e549c") {
            "smartdolphin-vpn-hw-v1|$androidId|${Build.MANUFACTURER}|${Build.MODEL}|${Build.DEVICE}"
        } else {
            val fallback =
                "${Build.BOARD}|${Build.BRAND}|${Build.DEVICE}|${Build.HARDWARE}|${Build.MANUFACTURER}|${Build.MODEL}|${Build.PRODUCT}|${Build.FINGERPRINT}"
            "smartdolphin-vpn-hw-v1|$fallback"
        }
        return sha256Hex(material)
    }

    private fun sha256Hex(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(input.toByteArray(Charsets.UTF_8))
        return hash.joinToString("") { "%02x".format(it) }
    }

    private fun measurePing(host: String, count: Int): Map<String, Any?> {
        val process = ProcessBuilder(
            "/system/bin/ping",
            "-c",
            count.toString(),
            "-W",
            "2",
            host,
        )
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        process.waitFor()

        val lossRegex = Regex("(\\d+(?:\\.\\d+)?)% packet loss")
        val loss = lossRegex.find(output)?.groupValues?.get(1)?.toDoubleOrNull()

        val timeRegex = Regex("time=(\\d+(?:\\.\\d+)?) ms")
        val times = timeRegex.findAll(output)
            .mapNotNull { it.groupValues.getOrNull(1)?.toDoubleOrNull() }
            .toList()
        val avgMs = if (times.isNotEmpty()) {
            times.average().toInt().coerceAtLeast(1)
        } else {
            null
        }

        return mapOf(
            "ms" to avgMs,
            "loss" to (loss ?: if (avgMs != null) 0.0 else 100.0),
        )
    }
}
