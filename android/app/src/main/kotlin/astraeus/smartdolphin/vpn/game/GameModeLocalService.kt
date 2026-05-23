package astraeus.smartdolphin.vpn.game

import android.app.GameManager
import android.app.GameState
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import astraeus.smartdolphin.vpn.MainActivity

/**
 * 游戏加速（本机、无 Root、不经 VPN）：前台 + 可选唤醒锁 + 系统 GameManager 提示。
 * 效果因机型而异，不保证固定毫秒数，但属于无 Root 下常见「尽力」手段。
 */
class GameModeLocalService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mode = intent?.getStringExtra(EXTRA_MODE) ?: MODE_ACCEL
        applyAccelHints(mode)
        val notification = buildNotification(mode)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, 0)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseAccelHints()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    /** 加速：唤醒锁 + 向系统上报「游戏中」（对本应用进程；部分 ROM 会调整调度）。减速：全部释放。 */
    private fun applyAccelHints(mode: String) {
        releaseAccelHints()
        if (mode == MODE_ACCEL) {
            acquirePartialWakeLock()
            reportGamePlayingStateIfAvailable()
        }
    }

    private fun releaseAccelHints() {
        releasePartialWakeLock()
    }

    private fun acquirePartialWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "SmartDolphin:GameAccel",
            ).apply {
                setReferenceCounted(false)
                acquire(WAKE_MAX_MS)
            }
        } catch (e: Exception) {
            Log.w(TAG, "wake lock", e)
        }
    }

    private fun releasePartialWakeLock() {
        try {
            wakeLock?.let { wl ->
                if (wl.isHeld) wl.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "wake release", e)
        }
        wakeLock = null
    }

    /** API 33+：GameState / setGameState 才齐全；向系统上报「不可中断对战」类状态（对本应用进程）。 */
    private fun reportGamePlayingStateIfAvailable() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        try {
            val gm = getSystemService(Context.GAME_SERVICE) as? GameManager ?: return
            gm.setGameState(
                GameState(false, GameState.MODE_GAMEPLAY_UNINTERRUPTIBLE),
            )
        } catch (e: Exception) {
            Log.w(TAG, "GameManager.setGameState", e)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setShowBadge(false)
        }
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(mode: String): Notification {
        val (title, text) = if (mode == MODE_DECEL) {
            "游戏模式 · 减速" to "降低本机资源占用（未使用 VPN 隧道）"
        } else {
            "游戏加速" to "本机侧已尽力优化（前台、唤醒、系统提示）"
        }
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        private const val TAG = "GameModeLocal"

        /** 单次会话最长持有唤醒锁，防止异常未释放时永久耗电 */
        private const val WAKE_MAX_MS = 10L * 60L * 60L * 1000L

        private const val CHANNEL_ID = "game_mode_local_v1"
        private const val CHANNEL_NAME = "游戏模式"
        private const val NOTIFICATION_ID = 0x4741
        private const val EXTRA_MODE = "mode"
        const val MODE_ACCEL = "accel"
        const val MODE_DECEL = "decel"

        fun start(ctx: Context, mode: String) {
            val i = Intent(ctx, GameModeLocalService::class.java).apply {
                putExtra(EXTRA_MODE, mode)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, GameModeLocalService::class.java))
        }
    }
}
