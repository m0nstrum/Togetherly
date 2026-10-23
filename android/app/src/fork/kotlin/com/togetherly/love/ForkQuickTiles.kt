package com.togetherly.love

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Disabled manifest components are the source of truth for this opt-in. */
class ForkQuickTiles(private val context: Context) : MethodChannel.MethodCallHandler {
    private val components = listOf(
        ComponentName(context, "com.togetherly.love.ForkMissYouTileService"),
        ComponentName(context, "com.togetherly.love.ForkTouchTileService")
    )
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 24) { result.success(null); return }
        val pm = context.packageManager
        when (call.method) {
            "getEnabled" -> result.success(components.all {
                pm.getComponentEnabledSetting(it) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            })
            "setEnabled" -> {
                if (call.arguments !is Boolean) { result.error("arguments", "Expected bool", null); return }
                val previous = components.map { pm.getComponentEnabledSetting(it) }
                try {
                    for (component in components) {
                        pm.setComponentEnabledSetting(component,
                            if (call.arguments == true) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            PackageManager.DONT_KILL_APP)
                        TileService.requestListeningState(context, component)
                    }
                    result.success(null)
                } catch (_: Exception) {
                    components.forEachIndexed { i, component ->
                        try { pm.setComponentEnabledSetting(component, previous[i], PackageManager.DONT_KILL_APP) }
                        catch (_: Exception) { /* leave the last known OS state */ }
                    }
                    result.error("unavailable", "Could not update quick tiles", null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

abstract class ForkQuickTileService(private val action: String, private val label: Int) : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.let { tile -> tile.label = getString(label); tile.state = Tile.STATE_ACTIVE; tile.updateTile() }
    }
    @Suppress("DEPRECATION")
    override fun onClick() {
        super.onClick()
        val launch = Runnable {
            val intent = Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW).setData(Uri.parse("loveapp://$action"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            try {
                if (Build.VERSION.SDK_INT >= 34) {
                    val pending = PendingIntent.getActivity(this, if (action == "touch") 7201 else 7202, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    startActivityAndCollapse(pending)
                } else startActivityAndCollapse(intent)
            } catch (_: Exception) { /* system no longer permits this tile */ }
        }
        if (isLocked) unlockAndRun(launch) else launch.run()
    }
}

class ForkMissYouTileService : ForkQuickTileService("fork-miss", R.string.fork_tile_miss)
class ForkTouchTileService : ForkQuickTileService("touch", R.string.fork_tile_touch)
