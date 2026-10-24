package com.togetherly.love

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Rational
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ForkPictureInPicture(private val activity: Activity, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private var active = false
    private fun available(): Boolean = Build.VERSION.SDK_INT >= 26 &&
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "available" -> result.success(available())
            "enter" -> {
                if (!available()) { result.success(false); return }
                try {
                    val view = activity.window.decorView
                    val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
                        .setSourceRectHint(Rect(0, 0, view.width, view.height))
                    if (Build.VERSION.SDK_INT >= 31) builder.setSeamlessResizeEnabled(true).setAutoEnterEnabled(false)
                    result.success(activity.enterPictureInPictureMode(builder.build()))
                } catch (_: Exception) { result.success(false) }
            }
            "settings" -> try {
                val packageUri = Uri.parse("package:${activity.packageName}")
                try {
                    activity.startActivity(Intent("android.settings.PICTURE_IN_PICTURE_SETTINGS", packageUri))
                } catch (_: Exception) {
                    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri))
                }
                result.success(null)
            } catch (_: Exception) { result.error("unavailable", "PiP settings unavailable", null) }
            else -> result.notImplemented()
        }
    }
    fun changed(value: Boolean) { active = value; channel.invokeMethod("modeChanged", value) }
    fun resumed() {
        if (Build.VERSION.SDK_INT >= 26) changed(activity.isInPictureInPictureMode)
    }
    fun stopped() {
        if (active) { active = false; channel.invokeMethod("closed", null) }
    }
    fun close() { channel.setMethodCallHandler(null) }
}
