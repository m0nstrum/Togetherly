package com.togetherly.love

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/** Only the OS verifies biometrics or the device credential. No app PIN exists. */
class ForkAppLock(private val activity: Activity) {
    companion object { const val REQUEST_CREDENTIAL = 8107 }
    private val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null

    fun available(): Boolean = keyguard.isDeviceSecure

    @Suppress("DEPRECATION")
    fun authenticate(title: String, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "Authentication is already open", null); return }
        if (!available()) { result.success(false); return }
        pending = result
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val builder = BiometricPrompt.Builder(activity).setTitle(title)
                if (Build.VERSION.SDK_INT >= 30) {
                    builder.setAllowedAuthenticators(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL)
                } else builder.setDeviceCredentialAllowed(true)
                val signal = CancellationSignal()
                cancellation = signal
                builder.build().authenticate(signal, activity.mainExecutor,
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) = finish(true)
                        override fun onAuthenticationError(code: Int, message: CharSequence) = finish(false)
                    })
            } else {
                val intent = keyguard.createConfirmDeviceCredentialIntent(title, null)
                if (intent == null) finish(false)
                else activity.startActivityForResult(intent, REQUEST_CREDENTIAL)
            }
        } catch (_: Exception) { finish(false) }
    }

    fun activityResult(request: Int, result: Int): Boolean {
        if (request != REQUEST_CREDENTIAL) return false
        finish(result == Activity.RESULT_OK)
        return true
    }

    // On older Android, Dart holds a shared FLAG_SECURE lease instead.
    fun protectRecents(enabled: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        activity.setRecentsScreenshotEnabled(!enabled)
        return true
    }

    fun settings() { activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)) }

    private fun finish(success: Boolean) {
        val result = pending ?: return
        pending = null
        cancellation = null
        result.success(success)
    }

    fun close() { cancellation?.cancel(); finish(false) }
}
