package com.smartdolphin.vpn.game

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
import com.smartdolphin.vpn.MainActivity

/**
 * 娓告垙鍔犻€燂紙鏈満銆佹棤 Root銆佷笉缁?VPN锛夛細鍓嶅彴 + 鍙€夊敜閱掗攣 + 绯荤粺 GameManager 鎻愮ず銆?
 * 鏁堟灉鍥犳満鍨嬭€屽紓锛屼笉淇濊瘉鍥哄畾姣鏁帮紝浣嗗睘浜庢棤 Root 涓嬪父瑙併€屽敖鍔涖€嶆墜娈点€?
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

    /** 鍔犻€燂細鍞ら啋閿?+ 鍚戠郴缁熶笂鎶ャ€屾父鎴忎腑銆嶏紙瀵规湰搴旂敤杩涚▼锛涢儴鍒?ROM 浼氳皟鏁磋皟搴︼級銆傚噺閫燂細鍏ㄩ儴閲婃斁銆?*/
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

    /** API 33+锛欸ameState / setGameState 鎵嶉綈鍏紱鍚戠郴缁熶笂鎶ャ€屼笉鍙腑鏂鎴樸€嶇被鐘舵€侊紙瀵规湰搴旂敤杩涚▼锛夈€?*/
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
            "Game Mode - Low load" to "Local resource usage is reduced without using the VPN tunnel."
        } else {
            "Game acceleration" to "Local game-side optimizations are active."
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

        /** 鍗曟浼氳瘽鏈€闀挎寔鏈夊敜閱掗攣锛岄槻姝㈠紓甯告湭閲婃斁鏃舵案涔呰€楃數 */
        private const val WAKE_MAX_MS = 10L * 60L * 60L * 1000L

        private const val CHANNEL_ID = "game_mode_local_v1"
        private const val CHANNEL_NAME = "娓告垙妯″紡"
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
