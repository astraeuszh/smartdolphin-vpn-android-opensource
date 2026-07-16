package com.smartdolphin.vpn.update

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

object NativeUpdateManager {
    private const val PREFS = "smartdolphin_native_update"
    private const val CHANNEL = "smartdolphin_updates"
    private const val COMPLETE_NOTIFICATION_ID = 7304
    private const val BUFFER_SIZE = 256 * 1024
    private const val MAX_APK_BYTES = 1024L * 1024L * 1024L
    private const val MAX_MANIFEST_BYTES = 2L * 1024L * 1024L
    private const val MAX_CHUNK_BYTES = 64L * 1024L * 1024L
    private const val MAX_CHUNKS = 16_384
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var running = false

    data class State(
        val status: String,
        val received: Long = 0,
        val total: Long = 0,
        val version: String = "",
        val path: String = "",
    )

    private data class Chunk(
        val index: Int,
        val name: String,
        val size: Long,
        val sha256: String,
    )

    fun enqueue(
        context: Context,
        version: String,
        apkUrl: String,
        sha256: String,
        size: Long,
        chunkManifestUrl: String,
        downloadUrls: List<String>,
    ): Long {
        require(size in 0..MAX_APK_BYTES) { "invalid APK size" }
        require(version.matches(Regex("[A-Za-z0-9._+-]+"))) { "invalid version" }
        require(apkUrl.startsWith("https://")) { "invalid APK URL" }
        require(
            chunkManifestUrl.isBlank() || chunkManifestUrl.startsWith("https://"),
        ) { "invalid manifest URL" }
        val preferences = prefs(context)
        val normalizedSha256 = sha256.lowercase()
        if (
            preferences.getString("version", "") == version &&
            preferences.getString("sha256", "") == normalizedSha256 &&
            preferences.getLong("size", -1) == size &&
            preferences.getString("apk_url", "") == apkUrl &&
            preferences.getString("manifest_url", "") == chunkManifestUrl &&
            state(context).status in setOf("pending", "running", "successful")
        ) {
            return 1L
        }
        val target = File(
            context.getExternalFilesDir(null),
            "updates/SmartDolphinVPN-$version.apk",
        )
        target.parentFile?.mkdirs()
        preferences.edit()
            .putString("version", version)
            .putString("sha256", normalizedSha256)
            .putLong("size", size)
            .putString("path", target.absolutePath)
            .putString("status", "pending")
            .putLong("received", 0)
            .putString("apk_url", apkUrl)
            .putString("manifest_url", chunkManifestUrl)
            .putString("download_urls", downloadUrls.joinToString("\n"))
            .apply()
        if (!running) executor.execute { download(context.applicationContext) }
        return 1L
    }

    fun state(context: Context): State {
        val preferences = prefs(context)
        return State(
            preferences.getString("status", "idle") ?: "idle",
            preferences.getLong("received", 0),
            preferences.getLong("size", 0),
            preferences.getString("version", "") ?: "",
            preferences.getString("path", "") ?: "",
        )
    }

    private fun download(context: Context) {
        running = true
        val preferences = prefs(context)
        preferences.edit().putString("status", "running").apply()
        try {
            val manifestUrl = preferences.getString("manifest_url", "") ?: ""
            if (manifestUrl.isNotBlank()) {
                downloadChunks(context, manifestUrl)
            } else {
                downloadWhole(context)
            }
            val target = File(preferences.getString("path", "") ?: error("missing target"))
            val expectedSize = preferences.getLong("size", 0)
            val expectedSha = preferences.getString("sha256", "") ?: ""
            check(target.isFile && target.length() <= MAX_APK_BYTES)
            check(expectedSize <= 0 || target.length() == expectedSize)
            check(expectedSha.isBlank() || sha256(target).equals(expectedSha, true))
            preferences.edit()
                .putString("status", "successful")
                .putLong("received", target.length())
                .apply()
            verifyAndNotify(context)
        } catch (_: Throwable) {
            preferences.edit().putString("status", "failed").apply()
        } finally {
            running = false
        }
    }

    private fun downloadChunks(context: Context, manifestUrl: String) {
        val preferences = prefs(context)
        val manifestFile = File.createTempFile("update-manifest-", ".json", context.cacheDir)
        val manifest = try {
            streamDownload(
                rawUrl = manifestUrl,
                target = manifestFile,
                timeout = 30_000,
                maximumBytes = MAX_MANIFEST_BYTES,
            )
            JSONObject(manifestFile.readText(Charsets.UTF_8))
        } finally {
            manifestFile.delete()
        }
        val mirrorsJson = manifest.getJSONArray("mirror_bases")
        check(mirrorsJson.length() in 1..32) { "invalid mirror count" }
        val mirrors = (0 until mirrorsJson.length()).map { index ->
            mirrorsJson.getString(index).trimEnd('/').also {
                check(it.startsWith("https://")) { "invalid mirror URL" }
            }
        }
        val chunksJson = manifest.getJSONArray("chunks")
        check(chunksJson.length() in 1..MAX_CHUNKS) { "invalid chunk count" }
        val chunks = (0 until chunksJson.length()).map { index ->
            chunksJson.getJSONObject(index).let { value ->
                Chunk(
                    value.getInt("index"),
                    value.getString("name"),
                    value.getLong("size"),
                    value.getString("sha256"),
                ).also { chunk ->
                    check(isSafeChunkName(chunk.name)) { "invalid chunk name" }
                    check(chunk.size in 1..MAX_CHUNK_BYTES) { "invalid chunk size" }
                }
            }
        }
        check(chunks.map { it.index }.distinct().size == chunks.size) {
            "duplicate chunk index"
        }
        val totalSize = chunks.fold(0L) { total, chunk ->
            Math.addExact(total, chunk.size).also {
                check(it <= MAX_APK_BYTES) { "APK package is too large" }
            }
        }
        val expectedSize = preferences.getLong("size", 0)
        check(expectedSize <= 0 || totalSize == expectedSize) {
            "manifest size mismatch"
        }
        val platform = manifest.getString("platform")
        val version = manifest.getString("version")
        check(platform.matches(Regex("[A-Za-z0-9._-]+"))) { "invalid platform" }
        check(version.matches(Regex("[A-Za-z0-9._+-]+"))) { "invalid version" }
        val root = File(
            context.getExternalFilesDir(null),
            "updates/chunks/$platform/$version",
        ).apply { mkdirs() }
        val validChunks = chunks.associateWith { chunk ->
            validChunk(File(root, chunk.name), chunk)
        }
        val queue = ConcurrentLinkedQueue(chunks.filterNot { validChunks.getValue(it) })
        val received = AtomicLong(
            chunks.sumOf { chunk ->
                if (validChunks.getValue(chunk)) chunk.size else 0L
            },
        )
        preferences.edit().putLong("received", received.get()).apply()
        val workerCount = minOf(mirrors.size, 4)
        val pool = Executors.newFixedThreadPool(workerCount)
        try {
            val futures = (0 until workerCount).map { worker ->
                pool.submit {
                    while (true) {
                        val chunk = queue.poll() ?: break
                        var downloaded = false
                        for (offset in mirrors.indices) {
                            val base = mirrors[(worker + offset) % mirrors.size]
                            val destination = File(root, chunk.name)
                            val temporary = File(root, ".${chunk.name}.$worker.tmp")
                            try {
                                val length = streamDownload(
                                    rawUrl = "$base/chunks/$platform/$version/${chunk.name}",
                                    target = temporary,
                                    timeout = 45_000,
                                    maximumBytes = chunk.size,
                                    expectedBytes = chunk.size,
                                )
                                check(sha256(temporary).equals(chunk.sha256, true)) {
                                    "chunk hash mismatch"
                                }
                                replaceFile(temporary, destination)
                                received.addAndGet(length)
                                preferences.edit().putLong("received", received.get()).apply()
                                downloaded = true
                                break
                            } catch (_: Throwable) {
                                temporary.delete()
                            }
                        }
                        check(downloaded) { "chunk failed" }
                    }
                }
            }
            futures.forEach { it.get() }
        } finally {
            pool.shutdownNow()
        }
        val target = File(preferences.getString("path", "") ?: error("missing target"))
        val temporaryTarget = File(target.parentFile, ".${target.name}.tmp")
        try {
            BufferedOutputStream(FileOutputStream(temporaryTarget), BUFFER_SIZE).use { output ->
                chunks.sortedBy { it.index }.forEach { chunk ->
                    BufferedInputStream(File(root, chunk.name).inputStream(), BUFFER_SIZE).use { input ->
                        input.copyTo(output, BUFFER_SIZE)
                    }
                }
            }
            check(temporaryTarget.length() == totalSize) { "assembled APK size mismatch" }
            replaceFile(temporaryTarget, target)
        } finally {
            temporaryTarget.delete()
        }
    }

    private fun downloadWhole(context: Context) {
        val preferences = prefs(context)
        val urls = (preferences.getString("download_urls", "") ?: "")
            .lines()
            .filter { it.startsWith("https://") }
            .ifEmpty { listOf(preferences.getString("apk_url", "") ?: "") }
        val target = File(preferences.getString("path", "") ?: error("missing target"))
        val expectedSize = preferences.getLong("size", 0)
        val maximumBytes = if (expectedSize > 0) expectedSize else MAX_APK_BYTES
        var lastError: Throwable? = null
        for (url in urls) {
            val temporary = File(target.parentFile, ".${target.name}.tmp")
            try {
                val received = streamDownload(
                    rawUrl = url,
                    target = temporary,
                    timeout = 180_000,
                    maximumBytes = maximumBytes,
                    expectedBytes = expectedSize.takeIf { it > 0 },
                    onProgress = { bytes ->
                        preferences.edit().putLong("received", bytes).apply()
                    },
                )
                replaceFile(temporary, target)
                preferences.edit().putLong("received", received).apply()
                return
            } catch (error: Throwable) {
                temporary.delete()
                lastError = error
            }
        }
        throw lastError ?: IllegalStateException("download failed")
    }

    private fun streamDownload(
        rawUrl: String,
        target: File,
        timeout: Int,
        maximumBytes: Long,
        expectedBytes: Long? = null,
        onProgress: ((Long) -> Unit)? = null,
    ): Long {
        check(rawUrl.startsWith("https://")) { "HTTPS is required" }
        check(maximumBytes > 0) { "invalid download limit" }
        val connection = URL(rawUrl).openConnection() as HttpURLConnection
        try {
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 8_000
            connection.readTimeout = timeout
            connection.setRequestProperty("Accept-Encoding", "identity")
            check(connection.responseCode in 200..299) { "HTTP ${connection.responseCode}" }
            val contentLength = connection.contentLengthLong
            check(contentLength < 0 || contentLength <= maximumBytes) {
                "download exceeds limit"
            }
            check(
                expectedBytes == null ||
                    expectedBytes <= 0 ||
                    contentLength < 0 ||
                    contentLength == expectedBytes
            ) { "unexpected content length" }
            target.parentFile?.mkdirs()
            var received = 0L
            BufferedInputStream(connection.inputStream, BUFFER_SIZE).use { input ->
                BufferedOutputStream(FileOutputStream(target), BUFFER_SIZE).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        received = Math.addExact(received, count.toLong())
                        check(received <= maximumBytes) { "download exceeds limit" }
                        output.write(buffer, 0, count)
                        onProgress?.invoke(received)
                    }
                }
            }
            check(expectedBytes == null || expectedBytes <= 0 || received == expectedBytes) {
                "incomplete download"
            }
            return received
        } catch (error: Throwable) {
            target.delete()
            throw error
        } finally {
            connection.disconnect()
        }
    }

    private fun validChunk(file: File, chunk: Chunk): Boolean =
        file.isFile &&
            file.length() == chunk.size &&
            sha256(file).equals(chunk.sha256, true)

    private fun isSafeChunkName(name: String): Boolean =
        name.isNotBlank() &&
            name == File(name).name &&
            !name.contains('/') &&
            !name.contains('\\') &&
            name.matches(Regex("[A-Za-z0-9._-]+"))

    private fun replaceFile(source: File, destination: File) {
        if (destination.exists() && !destination.delete()) {
            throw IllegalStateException("unable to replace target")
        }
        if (!source.renameTo(destination)) {
            BufferedInputStream(source.inputStream(), BUFFER_SIZE).use { input ->
                BufferedOutputStream(FileOutputStream(destination), BUFFER_SIZE).use { output ->
                    input.copyTo(output, BUFFER_SIZE)
                }
            }
            if (!source.delete()) source.deleteOnExit()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        BufferedInputStream(file.inputStream(), BUFFER_SIZE).use { input ->
            val buffer = ByteArray(BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun verifyAndNotify(context: Context): Boolean {
        val preferences = prefs(context)
        val file = File(preferences.getString("path", "") ?: return false)
        if (!file.isFile) return false
        ensureChannel(context)
        val pendingIntent = PendingIntent.getActivity(
            context,
            7304,
            installIntent(context, file),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("SmartDolphin VPN 更新已下载")
            .setContentText("${preferences.getString("version", "")} 已准备完成，点击安装")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(COMPLETE_NOTIFICATION_ID, notification)
        return true
    }

    fun openInstaller(context: Context): Boolean {
        val file = File(prefs(context).getString("path", "") ?: return false)
        if (!file.isFile) return false
        context.startActivity(installIntent(context, file))
        return true
    }

    fun checkAndEnqueueForced(context: Context) {
        // Flutter startup performs the authoritative forced check.
    }

    private fun installIntent(context: Context, file: File) =
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(
                FileProvider.getUriForFile(context, "${context.packageName}.files", file),
                "application/vnd.android.package-archive",
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(
                    NotificationChannel(
                        CHANNEL,
                        "应用更新",
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                )
        }
    }
}
