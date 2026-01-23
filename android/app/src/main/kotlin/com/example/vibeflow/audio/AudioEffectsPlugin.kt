package com.example.vibeflow.audio

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioEffectsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var audioEffectsManager: AudioEffectsManager? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        audioEffectsManager = AudioEffectsManager(context)

        channel = MethodChannel(binding.binaryMessenger, "audio_effects")
        channel.setMethodCallHandler(this)

        Log.d("AudioEffectsPlugin", "✅ AudioEffectsPlugin attached")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val manager = audioEffectsManager

        if (manager == null) {
            result.error("NOT_READY", "AudioEffectsManager not initialized", null)
            return
        }

        try {
            when (call.method) {

                // GET AUDIO SESSION ID
                "getAudioSessionId" -> {
                    val manager = audioEffectsManager ?: run {
                        result.error("NOT_READY", "AudioEffectsManager not initialized", null)
                        return
                    }
                    // Return 0 for default audio output session
                    Log.d("AudioEffectsPlugin", "Returning audio session ID: 0")
                    result.success(0)
                }

                // ---------- INIT ----------
               "initializeEffects" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val managera = audioEffectsManager ?: run {
                        result.error("NOT_READY", "AudioEffectsManager not initialized", null)
                        return
                    }
                    Log.d("AudioEffectsPlugin", "Initializing with session ID: $sessionId")
                    result.success(managera.initialize(sessionId))
                }

                 

                // ---------- BASS ----------
                "setBassBoost" -> {
                    val strength = (call.argument<Int>("strength") ?: 0).toShort()
                    result.success(manager.setBassBoost(strength))
                }

                "getBassBoost" -> {
                    result.success(manager.getBassBoost().toInt())
                }

                // ---------- EQ ----------
                "setEqualizerBand" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val level = (call.argument<Int>("level") ?: 0).toShort()
                    result.success(manager.setEqualizerBand(band, level))
                }

                "getEqualizerBand" -> {
                    val band = call.argument<Int>("band") ?: 0
                    result.success(manager.getEqualizerBand(band).toInt())
                }

                "getEqualizerBandCount" -> {
                    result.success(manager.getEqualizerBandCount())
                }

                // ---------- LOUDNESS ----------
                "setLoudnessEnhancer" -> {
                    val gain = call.argument<Int>("gain") ?: 0
                    result.success(manager.setLoudnessEnhancer(gain))
                }

                "getLoudnessEnhancer" -> {
                    result.success(manager.getLoudnessEnhancer())
                }

                // ---------- REVERB ----------
                "setEnvironmentalReverbLevel" -> {
                    val level = call.argument<Int>("level") ?: 0
                    result.success(manager.setEnvironmentalReverbLevel(level))
                }

                "getEnvironmentalReverbLevel" -> {
                    result.success(manager.getEnvironmentalReverbLevel())
                }

                // ---------- BALANCE ----------
                "setAudioBalance" -> {
                    val balance = call.argument<Double>("balance")?.toFloat() ?: 0.5f
                    result.success(manager.setAudioBalance(balance))
                }

                "getAudioBalance" -> {
                    result.success(manager.getAudioBalance().toDouble())
                }

                "resetAudioBalance" -> {
                    result.success(manager.resetAudioBalance())
                }

                // ---------- PRESETS ----------
                "applyPreset" -> {
                    val presetName = call.argument<String>("presetName") ?: "Normal"
                    result.success(manager.applyPreset(presetName))
                }

                "getAvailablePresets" -> {
                    result.success(manager.getAvailablePresets())
                }

                // ---------- GLOBAL ----------
                "resetAllEffects" -> {
                    result.success(manager.resetAllEffects())
                }

                "disableAllEffects" -> {
                    result.success(manager.disableAllEffects())
                }

                "getCurrentSettings" -> {
                    result.success(manager.getCurrentSettings())
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e("AudioEffectsPlugin", "❌ Error handling ${call.method}", e)
            result.error("AUDIO_EFFECT_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        audioEffectsManager?.release()
        audioEffectsManager = null
        channel.setMethodCallHandler(null)

        Log.d("AudioEffectsPlugin", "🧹 AudioEffectsPlugin detached")
    }
}
