package com.togetherly.love

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// fork (UX N2): системные настройки уведомлений своего пакета. url_launcher
// не разбирает intent:-ссылки, а зашитый пакет апстрима открывал чужое
// приложение.
class ForkSettingsChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "tethered/settings"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openNotificationSettings" -> result.success(openNotifications())
            // fork (UX G4): после отказа в геолокации диалог системы больше не
            // покажется — человеку остаётся только экран настроек.
            "openAppSettings" -> result.success(
                start(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
            )
            "openLocationSettings" -> result.success(start(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)))
            else -> result.notImplemented()
        }
    }

    private fun start(intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        false
    }

    private fun openNotifications(): Boolean {
        val pkg = context.packageName
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                add(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, pkg))
            }
            add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")))
        }
        for (intent in intents) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
                // следующий экран
            }
        }
        return false
    }
}
