package com.smartdolphin.vpn.update

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

object NativeUpdateManager {
    private const val PREFS = "smartdolphin_native_update"
    private const val KEY_ID = "download_id"
    private const val KEY_VERSION = "version"
    private const val KEY_SHA = "sha256"
    private const val KEY_SIZE = "size"
    private const val KEY_PATH = "path"
    private const val VERSION_URL = "https://api.smartdolphinvpn.com/api/auth/android-version"
    private const val CHANNEL = "smartdolphin_updates"
    private const val COMPLETE_NOTIFICATION_ID = 7304

    data class State(
        val status: String,
        val received: Long = 0,
        val total: Long = 0,
        val version: String = "",
        val path: String = "",
    )

    fun enqueue(
        context: Context,
        version: String,
        apkUrl: String,
        sha256: String,
        size: Long,
    ): Long {
        val current = state(context)
        if (current.version == version && current.status in setOf("pending", "running", "successful")) {
            return prefs(context).getLong(KEY_ID, -1L)
        }
        val uri = Uri.parse(if (apkUrl.startsWith("http")) apkUrl else "https://smartdolphinvpn.com$apkUrl")
        val relativePath = "updates/SmartDolphinVPN-$version.apk"
        val target = File(context.getExternalFilesDir(null), relativePath)
        target.parentFile?.mkdirs()
        if (target.exists()) target.delete()
        val request = DownloadManager.Request(uri)
            .setTitle("SmartDolphin VPN $version")
            .setDescription("正在后台下载强制更新")
            .setMimeType("application/vnd.android.package-archive")
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(context, null, relativePath)
        val id = manager(context).enqueue(request)
        prefs(context).edit()
            .putLong(KEY_ID, id)
            .putString(KEY_VERSION, version)
            .putString(KEY_SHA, sha256.lowercase())
            .putLong(KEY_SIZE, size)
            .putString(KEY_PATH, target.absolutePath)
            .apply()
        return id
    }

    fun state(context: Context): State {
        val p = prefs(context)
        val id = p.getLong(KEY_ID, -1L)
        val version = p.getString(KEY_VERSION, "") ?: ""
        val path = p.getString(KEY_PATH, "") ?: ""
        if (id < 0) return State("idle", version = version, path = path)
        var cursor: Cursor? = null
        return try {
            cursor = manager(context).query(DownloadManager.Query().setFilterById(id))
            if (cursor != null && cursor.moveToFirst()) {
                val raw = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val received = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                State(statusName(raw), received, total, version, path)
            } else State("idle", version = version, path = path)
        } finally { cursor?.close() }
    }

    fun verifyAndNotify(context: Context): Boolean {
        val p = prefs(context)
        val path = p.getString(KEY_PATH, "") ?: return false
        val expectedSha = p.getString(KEY_SHA, "") ?: ""
        val expectedSize = p.getLong(KEY_SIZE, 0L)
        val file = File(path)
        if (!file.isFile || (expectedSize > 0 && file.length() != expectedSize)) return false
        if (expectedSha.isNotEmpty() && sha256(file) != expectedSha) {
            file.delete()
            return false
        }
        ensureChannel(context)
        val install = installIntent(context, file)
        val pending = PendingIntent.getActivity(
            context, 7304, install,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val version = p.getString(KEY_VERSION, "") ?: ""
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("SmartDolphin VPN 更新已下载")
            .setContentText("$version 已准备完成，点击安装")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(COMPLETE_NOTIFICATION_ID, notification)
        return true
    }

    fun openInstaller(context: Context): Boolean {
        val file = File(prefs(context).getString(KEY_PATH, "") ?: return false)
        if (!file.isFile || !verifyAndNotify(context)) return false
        context.startActivity(installIntent(context, file))
        return true
    }

    fun checkAndEnqueueForced(context: Context) {
        Thread {
            runCatching {
                val connection = URL(VERSION_URL).openConnection() as HttpURLConnection
                connection.connectTimeout = 12_000
                connection.readTimeout = 12_000
                connection.setRequestProperty("Accept", "application/json")
                connection.setRequestProperty("X-SmartDolphin-Client", "android")
                connection.setRequestProperty("X-SmartDolphin-Version", currentVersion(context))
                connection.setRequestProperty("X-SmartDolphin-Build", currentBuild(context).toString())
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(body)
                if (!json.optBoolean("ok") || !json.optBoolean("published") || !json.optBoolean("force_update")) return@runCatching
                val version = json.optString("version_name")
                if (compareVersions(version, currentVersion(context)) <= 0) return@runCatching
                enqueue(
                    context,
                    version,
                    json.optString("apk_url"),
                    json.optString("sha256"),
                    json.optLong("package_size"),
                )
            }
        }.start()
    }

    private fun currentVersion(context: Context): String {
        @Suppress("DEPRECATION")
        return context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0"
    }

    private fun currentBuild(context: Context): Long {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
    }

    private fun compareVersions(left: String, right: String): Int {
        val a = left.split('.').map { it.toIntOrNull() ?: 0 }
        val b = right.split('.').map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(a.size, b.size)) {
            val result = (a.getOrNull(i) ?: 0).compareTo(b.getOrNull(i) ?: 0)
            if (result != 0) return result
        }
        return 0
    }

    private fun installIntent(context: Context, file: File): Intent {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(256 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count <= 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun statusName(status: Int) = when (status) {
        DownloadManager.STATUS_PENDING -> "pending"
        DownloadManager.STATUS_RUNNING -> "running"
        DownloadManager.STATUS_PAUSED -> "paused"
        DownloadManager.STATUS_SUCCESSFUL -> "successful"
        DownloadManager.STATUS_FAILED -> "failed"
        else -> "idle"
    }

    private fun manager(context: Context) = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "应用更新", NotificationManager.IMPORTANCE_HIGH))
    }
}
