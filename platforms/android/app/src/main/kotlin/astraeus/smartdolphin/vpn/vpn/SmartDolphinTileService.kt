package astraeus.smartdolphin.vpn.vpn

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import astraeus.smartdolphin.vpn.MainActivity

class SmartDolphinTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val launch = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }
        startActivityAndCollapse(launch)
        refreshTile()
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        tile.state = Tile.STATE_INACTIVE
        tile.label = "SmartDolphinVPN"
        tile.updateTile()
    }

    companion object {
        fun requestTileUpdate(context: Context) {
            val intent = Intent(context, SmartDolphinTileService::class.java)
            requestListeningState(context, ComponentName(context, SmartDolphinTileService::class.java))
            context.startService(intent)
        }
    }
}
