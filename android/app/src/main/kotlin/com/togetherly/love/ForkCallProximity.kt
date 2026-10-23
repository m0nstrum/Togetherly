package com.togetherly.love

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager

/** Keep cheeks away from controls, without darkening wired/Bluetooth calls. */
class ForkCallProximity(context: Context) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val handler = Handler(Looper.getMainLooper())
    private var active = false
    private var closed = false
    private val lock = if (power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK))
        power.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "Tethered:call-proximity") else null
    private val refresh = Runnable { update() }
    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = changed()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = changed()
    }
    private var communicationListener: AudioManager.OnCommunicationDeviceChangedListener? = null

    init {
        lock?.setReferenceCounted(false)
        audio.registerAudioDeviceCallback(devices, handler)
        if (Build.VERSION.SDK_INT >= 31) {
            communicationListener = AudioManager.OnCommunicationDeviceChangedListener { update() }
            audio.addOnCommunicationDeviceChangedListener(context.mainExecutor, communicationListener!!)
        }
    }

    fun setActive(value: Boolean) { active = value; changed() }

    private fun changed() {
        update()
        handler.removeCallbacks(refresh)
        handler.postDelayed(refresh, 300) // AudioSwitch applies route changes asynchronously.
    }

    @Suppress("DEPRECATION")
    private fun update() {
        if (closed) return
        val earpiece = if (Build.VERSION.SDK_INT >= 31) {
            audio.communicationDevice?.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
        } else {
            !audio.isSpeakerphoneOn && !audio.isBluetoothScoOn && !audio.isWiredHeadsetOn
        }
        if (active && earpiece) {
            if (lock?.isHeld == false) lock.acquire()
        } else if (lock?.isHeld == true) lock.release()
    }

    fun close() {
        active = false
        if (lock?.isHeld == true) lock.release()
        closed = true
        handler.removeCallbacks(refresh)
        audio.unregisterAudioDeviceCallback(devices)
        if (Build.VERSION.SDK_INT >= 31) {
            communicationListener?.let { audio.removeOnCommunicationDeviceChangedListener(it) }
        }
    }
}
