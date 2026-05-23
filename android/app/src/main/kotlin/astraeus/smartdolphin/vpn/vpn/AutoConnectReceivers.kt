package astraeus.smartdolphin.vpn.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import astraeus.smartdolphin.vpn.MainActivity

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }
        val prefs = context.getSharedPreferences("smartdolphin_vpn", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("wake_on_boot", false)) {
            Log.d(TAG, "Boot completed; wake-on-boot disabled, skipping.")
            return
        }
        Log.d(TAG, "Boot completed; launching app for auto-reconnect.")
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(launch)
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}

class NetworkChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("smartdolphin_vpn", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("has_active_session", false)) {
            return
        }
        Log.d(TAG, "Network change while session active; launching app to reconnect.")
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        context.startActivity(launch)
    }

    companion object {
        private const val TAG = "NetworkReceiver"
    }
}
