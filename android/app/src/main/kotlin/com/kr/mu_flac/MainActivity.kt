package com.kr.mu_flac

import android.content.Context
import android.database.ContentObserver
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * MainActivity must extend AudioServiceActivity (just_audio_background).
 * Hosts the `mu_flac/audio` MethodChannel and `mu_flac/audio_events`
 * EventChannel. The EQ / audio state lives in [AudioNative] (process-wide),
 * because audio_service keeps the Flutter engine alive across activities.
 */
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ctx = applicationContext
        AudioNative.init(ctx)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mu_flac/audio")
            .setMethodCallHandler { call, result -> AudioNative.handle(call, result) }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mu_flac/audio_events")
            .setStreamHandler(AudioNative.streamHandler)
    }
}

object AudioNative {
    private const val TAG = "MuFlacAudio"

    private var appContext: Context? = null
    private var audioManager: AudioManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var deviceCallback: AudioDeviceCallback? = null
    private var volumeObserver: ContentObserver? = null

    // EQ state
    private var dynamics: DynamicsProcessing? = null
    private var dynamicsSession: Int = 0

    fun init(context: Context) {
        if (appContext != null) return
        appContext = context
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    val streamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            registerCallbacks()
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
            unregisterCallbacks()
        }
    }

    private fun emit(event: String) {
        mainHandler.post {
            try {
                eventSink?.success(mapOf("event" to event))
            } catch (e: Exception) {
                Log.w(TAG, "emit failed", e)
            }
        }
    }

    private fun registerCallbacks() {
        val am = audioManager ?: return
        if (deviceCallback == null) {
            val cb = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                    emit("outputChanged")
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                    emit("outputChanged")
                }
            }
            am.registerAudioDeviceCallback(cb, mainHandler)
            deviceCallback = cb
        }
        val ctx = appContext ?: return
        if (volumeObserver == null) {
            val obs = object : ContentObserver(mainHandler) {
                override fun onChange(selfChange: Boolean) {
                    emit("volumeChanged")
                }
            }
            try {
                ctx.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, obs)
                volumeObserver = obs
            } catch (e: Exception) {
                Log.w(TAG, "volume observer failed", e)
            }
        }
    }

    private fun unregisterCallbacks() {
        val am = audioManager
        val cb = deviceCallback
        if (am != null && cb != null) {
            am.unregisterAudioDeviceCallback(cb)
        }
        deviceCallback = null
        val obs = volumeObserver
        val ctx = appContext
        if (obs != null && ctx != null) {
            ctx.contentResolver.unregisterContentObserver(obs)
        }
        volumeObserver = null
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "outputInfo" -> result.success(outputInfo())
                "setPreferredSampleRate" -> result.success(0)
                "eqSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                "eqApply" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val freqs = call.argument<List<Number>>("frequencies") ?: emptyList()
                    val gains = call.argument<List<Number>>("gains") ?: emptyList()
                    val preamp = call.argument<Number>("preamp")?.toFloat() ?: 0f
                    result.success(
                        eqApply(
                            sessionId,
                            enabled,
                            freqs.map { it.toFloat() },
                            gains.map { it.toFloat() },
                            preamp
                        )
                    )
                }
                "getVolume" -> result.success(getVolume())
                "setVolume" -> {
                    val value = call.argument<Number>("value")?.toDouble() ?: 0.0
                    result.success(setVolume(value))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "method ${call.method} failed", e)
            result.error("native_error", e.message, null)
        }
    }

    // ------------------------------------------------------------------
    // Output info
    // ------------------------------------------------------------------

    private fun kindOf(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_LINE_ANALOG,
            AudioDeviceInfo.TYPE_LINE_DIGITAL,
            AudioDeviceInfo.TYPE_AUX_LINE -> "wired"
            AudioDeviceInfo.TYPE_HDMI,
            AudioDeviceInfo.TYPE_HDMI_ARC -> "hdmi"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "speaker"
            // TYPE_BLE_HEADSET (26) / TYPE_BLE_SPEAKER (27) exist on API 31+.
            26, 27 -> "bluetooth"
            // TYPE_HDMI_EARC (29) on API 31+.
            29 -> "hdmi"
            else -> "other"
        }
    }

    private fun priorityOf(kind: String): Int {
        return when (kind) {
            "usb" -> 5
            "wired" -> 4
            "bluetooth" -> 3
            "hdmi" -> 2
            "speaker" -> 1
            else -> 0
        }
    }

    private fun outputInfo(): Map<String, Any> {
        val am = audioManager ?: return mapOf("name" to "", "kind" to "unknown", "sampleRate" to 0)
        val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        var best: AudioDeviceInfo? = null
        var bestKind = "unknown"
        var bestPriority = -1
        for (d in devices) {
            if (d.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE) continue
            if (d.type == AudioDeviceInfo.TYPE_TELEPHONY) continue
            val kind = kindOf(d.type)
            if (kind == "other") continue
            val prio = priorityOf(kind)
            if (prio > bestPriority) {
                best = d
                bestKind = kind
                bestPriority = prio
            }
        }
        // Android's mixer output rate (what the HAL runs at for the primary
        // output). Not per-device; still the most honest number available.
        val mixerRate = am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 0
        val name = when {
            best == null -> ""
            bestKind == "speaker" -> "Phone speaker"
            else -> best.productName?.toString() ?: ""
        }
        return mapOf(
            "name" to name,
            "kind" to bestKind,
            "sampleRate" to mixerRate
        )
    }

    // ------------------------------------------------------------------
    // EQ: DynamicsProcessing pre-EQ, 10 bands, API 28+
    // ------------------------------------------------------------------

    private fun releaseDynamics() {
        try {
            dynamics?.setEnabled(false)
            dynamics?.release()
        } catch (e: Exception) {
            Log.w(TAG, "release dynamics failed", e)
        }
        dynamics = null
        dynamicsSession = 0
    }

    /**
     * Applies the full EQ state. Disabled (or no session) releases the effect
     * so the signal path is untouched. Returns true when the EQ is active.
     */
    private fun eqApply(
        sessionId: Int,
        enabled: Boolean,
        freqs: List<Float>,
        gains: List<Float>,
        preampDb: Float
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        if (!enabled || sessionId <= 0 || freqs.isEmpty() || freqs.size != gains.size) {
            releaseDynamics()
            return false
        }
        val bandCount = freqs.size
        val existing = dynamics
        val dp: DynamicsProcessing = if (existing != null && dynamicsSession == sessionId) {
            existing
        } else {
            releaseDynamics()
            val config = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                2, // channel count
                true, bandCount, // pre-EQ
                false, 0, // multi-band compressor
                false, 0, // post-EQ
                false // limiter
            ).build()
            val created = DynamicsProcessing(0, sessionId, config)
            dynamics = created
            dynamicsSession = sessionId
            created
        }
        // Band i covers (cutoff[i-1], cutoff[i]]: cutoffs halfway (geometric)
        // between the graphic EQ centre frequencies; last band reaches 20 kHz.
        for (i in 0 until bandCount) {
            val cutoff = if (i < bandCount - 1) {
                sqrt(freqs[i] * freqs[i + 1])
            } else {
                20000f
            }
            val gain = gains[i].coerceIn(-12f, 12f)
            dp.setPreEqBandAllChannelsTo(i, DynamicsProcessing.EqBand(true, cutoff, gain))
        }
        // Preamp (user-set, -12..0 dB) gives headroom for boosted bands.
        dp.setInputGainAllChannelsTo(preampDb.coerceIn(-12f, 0f))
        dp.setEnabled(true)
        return true
    }

    // ------------------------------------------------------------------
    // Volume (STREAM_MUSIC)
    // ------------------------------------------------------------------

    private fun getVolume(): Map<String, Any> {
        val am = audioManager ?: return mapOf("value" to 0.0, "steps" to 15)
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        return mapOf("value" to cur.toDouble() / max.toDouble(), "steps" to max)
    }

    private fun setVolume(value: Double): Double {
        val am = audioManager ?: return 0.0
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val index = (value.coerceIn(0.0, 1.0) * max).roundToInt()
        am.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        return cur.toDouble() / max.toDouble()
    }
}
