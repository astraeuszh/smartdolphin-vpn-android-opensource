package com.smartdolphin.vpn.update

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val pending = goAsync()
        Thread {
            try { NativeUpdateManager.verifyAndNotify(context.applicationContext) }
            finally { pending.finish() }
        }.start()
    }
}
