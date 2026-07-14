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
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var running = false

    data class State(val status: String, val received: Long = 0, val total: Long = 0, val version: String = "", val path: String = "")
    private data class Chunk(val index: Int, val name: String, val size: Long, val sha256: String)

    fun enqueue(context: Context, version: String, apkUrl: String, sha256: String, size: Long, chunkManifestUrl: String, downloadUrls: List<String>): Long {
        val p = prefs(context)
        if (p.getString("version", "") == version && state(context).status in setOf("pending", "running", "successful")) return 1L
        val target = File(context.getExternalFilesDir(null), "updates/SmartDolphinVPN-$version.apk")
        target.parentFile?.mkdirs()
        p.edit().putString("version", version).putString("sha256", sha256.lowercase()).putLong("size", size).putString("path", target.absolutePath).putString("status", "pending").putLong("received", 0).putString("apk_url", apkUrl).putString("manifest_url", chunkManifestUrl).putString("download_urls", downloadUrls.joinToString("\n")).apply()
        if (!running) executor.execute { download(context.applicationContext) }
        return 1L
    }

    fun state(context: Context): State { val p=prefs(context); return State(p.getString("status","idle")?:"idle",p.getLong("received",0),p.getLong("size",0),p.getString("version","")?:"",p.getString("path","")?:"") }

    private fun download(context: Context) {
        running = true
        val p = prefs(context)
        p.edit().putString("status", "running").apply()
        try {
            val manifestUrl = p.getString("manifest_url", "") ?: ""
            if (manifestUrl.isNotBlank()) downloadChunks(context, manifestUrl) else downloadWhole(context)
            val target = File(p.getString("path", "") ?: error("missing target"))
            val expectedSize = p.getLong("size", 0)
            val expectedSha = p.getString("sha256", "") ?: ""
            check(target.isFile && (expectedSize <= 0 || target.length() == expectedSize))
            check(expectedSha.isBlank() || sha256(target).equals(expectedSha, true))
            p.edit().putString("status", "successful").putLong("received", target.length()).apply()
            verifyAndNotify(context)
        } catch (_: Throwable) {
            p.edit().putString("status", "failed").apply()
        } finally { running = false }
    }

    private fun downloadChunks(context: Context, manifestUrl: String) {
        val p = prefs(context)
        val manifest = JSONObject(getBytes(manifestUrl).toString(Charsets.UTF_8))
        val mirrorsJson = manifest.getJSONArray("mirror_bases")
        val mirrors = (0 until mirrorsJson.length()).map { mirrorsJson.getString(it).trimEnd('/') }
        val chunksJson = manifest.getJSONArray("chunks")
        val chunks = (0 until chunksJson.length()).map { i -> chunksJson.getJSONObject(i).let { Chunk(it.getInt("index"),it.getString("name"),it.getLong("size"),it.getString("sha256")) } }
        val platform=manifest.getString("platform"); val version=manifest.getString("version")
        val root = File(context.getExternalFilesDir(null), "updates/chunks/$platform/$version").apply { mkdirs() }
        val queue = ConcurrentLinkedQueue(chunks.filter { chunk -> val f=File(root,chunk.name); !f.isFile || f.length()!=chunk.size || !sha256(f).equals(chunk.sha256,true) })
        val received = AtomicLong(chunks.sumOf { chunk -> File(root,chunk.name).takeIf { it.isFile && it.length()==chunk.size && sha256(it).equals(chunk.sha256,true) }?.length() ?: 0 })
        p.edit().putLong("received",received.get()).apply()
        val pool = Executors.newFixedThreadPool(mirrors.size.coerceAtLeast(1))
        val futures = mirrors.indices.map { worker -> pool.submit { while (true) { val chunk=queue.poll()?:break; var ok=false; for(offset in mirrors.indices){ val base=mirrors[(worker+offset)%mirrors.size]; try { val bytes=getBytes("$base/chunks/$platform/$version/${chunk.name}", 45_000); if(bytes.size.toLong()!=chunk.size || sha256(bytes)!=chunk.sha256) continue; val tmp=File(root,".${chunk.name}.tmp"); tmp.writeBytes(bytes); tmp.renameTo(File(root,chunk.name)); received.addAndGet(bytes.size.toLong()); p.edit().putLong("received",received.get()).apply(); ok=true; break } catch(_:Throwable){} }; if(!ok) throw IllegalStateException("chunk failed") } } }
        futures.forEach { it.get() }; pool.shutdown()
        val target=File(p.getString("path","")?:error("missing target")); FileOutputStream(target).use { output -> chunks.sortedBy { it.index }.forEach { chunk -> File(root,chunk.name).inputStream().use { it.copyTo(output,256*1024) } } }
    }

    private fun downloadWhole(context: Context) {
        val p=prefs(context); val urls=(p.getString("download_urls","")?:"").lines().filter { it.startsWith("https://") }.ifEmpty { listOf(p.getString("apk_url","")?:"") }; val target=File(p.getString("path","")?:error("missing target")); var last:Throwable?=null
        for(url in urls){ try { val bytes=getBytes(url,180_000); target.writeBytes(bytes); p.edit().putLong("received",bytes.size.toLong()).apply(); return } catch(t:Throwable){last=t} }; throw last?:IllegalStateException("download failed")
    }

    private fun getBytes(rawUrl:String, timeout:Int=30_000):ByteArray { val c=URL(rawUrl).openConnection() as HttpURLConnection; c.connectTimeout=8_000;c.readTimeout=timeout;c.setRequestProperty("Accept-Encoding","identity");check(c.responseCode in 200..299);return c.inputStream.use { it.readBytes() } }
    private fun sha256(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
    private fun sha256(file:File):String { val d=MessageDigest.getInstance("SHA-256");file.inputStream().use{input->val b=ByteArray(256*1024);while(true){val n=input.read(b);if(n<=0)break;d.update(b,0,n)}};return d.digest().joinToString(""){"%02x".format(it)} }

    fun verifyAndNotify(context:Context):Boolean { val p=prefs(context);val file=File(p.getString("path","")?:return false);if(!file.isFile)return false;ensureChannel(context);val pending=PendingIntent.getActivity(context,7304,installIntent(context,file),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);val notification=NotificationCompat.Builder(context,CHANNEL).setSmallIcon(android.R.drawable.stat_sys_download_done).setContentTitle("SmartDolphin VPN 更新已下载").setContentText("${p.getString("version","")} 已准备完成，点击安装").setContentIntent(pending).setAutoCancel(true).setPriority(NotificationCompat.PRIORITY_HIGH).build();(context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(COMPLETE_NOTIFICATION_ID,notification);return true }
    fun openInstaller(context:Context):Boolean { val file=File(prefs(context).getString("path","")?:return false);if(!file.isFile)return false;context.startActivity(installIntent(context,file));return true }
    fun checkAndEnqueueForced(context:Context) { /* Flutter startup performs the authoritative forced check. */ }
    private fun installIntent(context:Context,file:File)=Intent(Intent.ACTION_VIEW).apply{setDataAndType(FileProvider.getUriForFile(context,"${context.packageName}.files",file),"application/vnd.android.package-archive");addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)}
    private fun prefs(context:Context)=context.getSharedPreferences(PREFS,Context.MODE_PRIVATE)
    private fun ensureChannel(context:Context){if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.O)(context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(NotificationChannel(CHANNEL,"应用更新",NotificationManager.IMPORTANCE_HIGH))}
}
