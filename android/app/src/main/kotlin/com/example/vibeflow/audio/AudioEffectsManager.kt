package com.example.vibeflow.audio

import android.content.Context
import android.media.audiofx.*
import android.os.Build
import android.util.Log

class AudioEffectsManager(private val context: Context) {
    private val TAG = "AudioEffectsManager"
    
    private var audioSessionId: Int = 0
    
    // Effect instances
    private var bassBoost: BassBoost? = null
    private var equalizer: Equalizer? = null
    private var presetReverb: PresetReverb? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var virtualizer: Virtualizer? = null
    
    // Current effect values (for persistence and reattachment)
    private var currentBassBoostStrength: Short = 0
    private var currentLoudnessGain: Int = 0
    private var currentReverbPreset: Short = PresetReverb.PRESET_NONE
    private var currentVirtualizerStrength: Short = 0
    private var currentEqBandLevels = mutableMapOf<Int, Short>()
    private var currentAudioBalance: Float = 0.5f
    
    // Safe limits
    companion object {
        const val SAFE_BASS_BOOST_LIMIT = 1000 // millibels
        const val SAFE_LOUDNESS_LIMIT = 1000 // millibels
        const val SAFE_EQ_BAND_LIMIT = 1500 // millibels
        const val SAFE_VIRTUALIZER_LIMIT = 1000 // 0-1000
        const val MIN_BALANCE = 0.0f
        const val MAX_BALANCE = 1.0f
        const val CENTER_BALANCE = 0.5f
    }
    
    // Audio presets
    data class AudioPreset(
        val name: String,
        val bassBoost: Short,
        val loudnessEnhancer: Int,
        val equalizerBands: ShortArray,
        val reverbPreset: Short,
        val virtualizerStrength: Short
    )
    
    private val presets = mapOf(
        "Normal" to AudioPreset(
            "Normal", 0, 0, 
            shortArrayOf(0, 0, 0, 0, 0), 
            PresetReverb.PRESET_NONE, 0
        ),
        "Rock" to AudioPreset(
            "Rock", 500, 400,
            shortArrayOf(400, 300, -200, 200, 500),
            PresetReverb.PRESET_LARGEROOM, 300
        ),
        "Pop" to AudioPreset(
            "Pop", 300, 300,
            shortArrayOf(200, 300, 400, 300, 200),
            PresetReverb.PRESET_MEDIUMROOM, 200
        ),
        "Jazz" to AudioPreset(
            "Jazz", 200, 200,
            shortArrayOf(300, 200, 100, 200, 300),
            PresetReverb.PRESET_LARGEHALL, 400
        ),
        "Classical" to AudioPreset(
            "Classical", 100, 100,
            shortArrayOf(300, 100, 0, 100, 300),
            PresetReverb.PRESET_LARGEHALL, 500
        ),
        "Bass Boost" to AudioPreset(
            "Bass Boost", 800, 500,
            shortArrayOf(800, 600, 400, 200, 0),
            PresetReverb.PRESET_SMALLROOM, 100
        ),
        "Vocal" to AudioPreset(
            "Vocal", 0, 300,
            shortArrayOf(-100, 300, 500, 500, 200),
            PresetReverb.PRESET_MEDIUMROOM, 300
        )
    )
    
    // Initialize effects with audio session ID
    fun initialize(sessionId: Int): Boolean {
        // Use session ID 0 for default output (works with just_audio)
        audioSessionId = if (sessionId == 0) 0 else sessionId
        
        return try {
            Log.i(TAG, "🎛️ Initializing audio effects with session ID: $audioSessionId")
            
            // Release any existing effects
            releaseEffects()
            
            // Initialize new effects
            initializeEffects()
            
            // Load saved settings from SharedPreferences
            loadSavedSettings()
            
            // Apply saved settings to the effects
            applyCurrentSettings()
            
            Log.i(TAG, "✅ Audio effects initialized successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error initializing effects: ${e.message}", e)
            false
        }
    }
    
    // ✅ NEW: Re-attach effects to new audio session (for song changes)
    fun reattach(sessionId: Int): Boolean {
        return try {
            Log.i(TAG, "🔄 Re-attaching effects to new session ID: $sessionId")
            
            // Release old effects
            releaseEffects()
            
            // Use session ID 0 for default output
            audioSessionId = if (sessionId == 0) 0 else sessionId
            
            // Re-initialize effects
            initializeEffects()
            
            // Re-apply current settings
            applyCurrentSettings()
            
            Log.i(TAG, "✅ Effects re-attached successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error re-attaching effects: ${e.message}", e)
            false
        }
    }
    
    private fun initializeEffects() {
        // Initialize Bass Boost
        try {
            bassBoost = BassBoost(0, audioSessionId).apply {
                enabled = false
            }
            Log.d(TAG, "✅ BassBoost initialized")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ BassBoost not supported: ${e.message}")
        }
        
        // Initialize Equalizer
        try {
            equalizer = Equalizer(0, audioSessionId).apply {
                enabled = false
            }
            Log.d(TAG, "✅ Equalizer initialized with ${equalizer?.numberOfBands} bands")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Equalizer not supported: ${e.message}")
        }
        
        // Initialize PresetReverb (more reliable than EnvironmentalReverb)
        try {
            presetReverb = PresetReverb(0, audioSessionId).apply {
                enabled = false
            }
            Log.d(TAG, "✅ PresetReverb initialized")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ PresetReverb not supported: ${e.message}")
        }
        
        // Initialize Loudness Enhancer (API 19+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            try {
                loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                    enabled = false
                }
                Log.d(TAG, "✅ LoudnessEnhancer initialized")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ LoudnessEnhancer not supported: ${e.message}")
            }
        }
        
        // Initialize Virtualizer (for audio balance/spatial effect)
        try {
            virtualizer = Virtualizer(0, audioSessionId).apply {
                enabled = false
            }
            Log.d(TAG, "✅ Virtualizer initialized")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Virtualizer not supported: ${e.message}")
        }
    }
    
    // Apply current settings to effects
    private fun applyCurrentSettings() {
        try {
            Log.d(TAG, "📋 Applying saved settings to effects...")
            
            // Apply bass boost
            if (currentBassBoostStrength > 0) {
                bassBoost?.setStrength(currentBassBoostStrength)
                bassBoost?.enabled = true
                Log.d(TAG, "   Bass boost: $currentBassBoostStrength")
            }
            
            // Apply loudness enhancer
            if (currentLoudnessGain > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.setTargetGain(currentLoudnessGain)
                loudnessEnhancer?.enabled = true
                Log.d(TAG, "   Loudness: $currentLoudnessGain")
            }
            
            // Apply reverb
            if (currentReverbPreset != PresetReverb.PRESET_NONE) {
                presetReverb?.preset = currentReverbPreset
                presetReverb?.enabled = true
                Log.d(TAG, "   Reverb preset: $currentReverbPreset")
            }
            
            // Apply virtualizer (for spatial effect)
            if (currentVirtualizerStrength > 0) {
                virtualizer?.setStrength(currentVirtualizerStrength)
                virtualizer?.enabled = true
                Log.d(TAG, "   Virtualizer: $currentVirtualizerStrength")
            }
            
            // Apply equalizer bands
            if (currentEqBandLevels.isNotEmpty()) {
                var hasAnyBand = false
                currentEqBandLevels.forEach { (band, level) ->
                    equalizer?.setBandLevel(band.toShort(), level)
                    if (level != 0.toShort()) hasAnyBand = true
                }
                if (hasAnyBand) {
                    equalizer?.enabled = true
                    Log.d(TAG, "   EQ bands: ${currentEqBandLevels.size} bands applied")
                }
            }
            
            Log.d(TAG, "✅ All settings applied")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error applying settings: ${e.message}", e)
        }
    }
    
    // Load saved settings from SharedPreferences
    private fun loadSavedSettings() {
        val prefs = context.getSharedPreferences("audio_effects_prefs", Context.MODE_PRIVATE)
        
        try {
            currentBassBoostStrength = prefs.getInt("bass_boost", 0).toShort()
            currentLoudnessGain = prefs.getInt("loudness_enhancer", 0)
            currentReverbPreset = prefs.getInt("reverb_preset", PresetReverb.PRESET_NONE.toInt()).toShort()
            currentVirtualizerStrength = prefs.getInt("virtualizer_strength", 0).toShort()
            currentAudioBalance = prefs.getFloat("audio_balance", CENTER_BALANCE)
            
            // Load equalizer bands
            currentEqBandLevels.clear()
            equalizer?.let { eq ->
                for (i in 0 until eq.numberOfBands) {
                    val savedLevel = prefs.getInt("eq_band_$i", 0).toShort()
                    currentEqBandLevels[i] = savedLevel
                }
            }
            
            Log.i(TAG, "📂 Loaded saved settings from SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error loading saved settings: ${e.message}")
        }
    }
    
    // Save settings to SharedPreferences
    private fun saveSettings() {
        val prefs = context.getSharedPreferences("audio_effects_prefs", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        
        try {
            editor.putInt("bass_boost", currentBassBoostStrength.toInt())
            editor.putInt("loudness_enhancer", currentLoudnessGain)
            editor.putInt("reverb_preset", currentReverbPreset.toInt())
            editor.putInt("virtualizer_strength", currentVirtualizerStrength.toInt())
            editor.putFloat("audio_balance", currentAudioBalance)
            
            // Save equalizer bands
            currentEqBandLevels.forEach { (band, level) ->
                editor.putInt("eq_band_$band", level.toInt())
            }
            
            editor.apply()
            Log.d(TAG, "💾 Settings saved to SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving settings: ${e.message}")
        }
    }
    
    // Apply preset
    fun applyPreset(presetName: String): Boolean {
        val preset = presets[presetName] ?: return false
        
        return try {
            Log.i(TAG, "🎵 Applying preset: $presetName")
            
            setBassBoost(preset.bassBoost)
            setLoudnessEnhancer(preset.loudnessEnhancer)
            setReverbPreset(preset.reverbPreset)
            setVirtualizerStrength(preset.virtualizerStrength)
            
            // Apply equalizer bands
            preset.equalizerBands.forEachIndexed { index, value ->
                setEqualizerBand(index, value)
            }
            
            saveSettings()
            Log.i(TAG, "✅ Preset '$presetName' applied successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error applying preset '$presetName': ${e.message}")
            false
        }
    }
    
    // Bass Boost controls
    fun setBassBoost(strength: Short): Boolean {
        return try {
            val clampedStrength = strength.coerceIn(0, SAFE_BASS_BOOST_LIMIT.toShort())
            currentBassBoostStrength = clampedStrength
            
            bassBoost?.let { effect ->
                effect.setStrength(clampedStrength)
                effect.enabled = clampedStrength > 0
                Log.d(TAG, "🔊 Bass boost set to: $clampedStrength mB")
            }
            
            saveSettings()
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting bass boost: ${e.message}")
            false
        }
    }
    
    fun getBassBoost(): Short {
        return currentBassBoostStrength
    }
    
    // Equalizer controls
    fun setEqualizerBand(band: Int, level: Short): Boolean {
        return try {
            equalizer?.let { eq ->
                if (band < 0 || band >= eq.numberOfBands) return false
                
                val safeLevel = level.coerceIn((-SAFE_EQ_BAND_LIMIT).toShort(), SAFE_EQ_BAND_LIMIT.toShort())
                currentEqBandLevels[band] = safeLevel
                
                eq.setBandLevel(band.toShort(), safeLevel)
                eq.enabled = true
                Log.d(TAG, "🎚️ EQ band $band set to: $safeLevel mB")
                
                saveSettings()
                true
            } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting equalizer band $band: ${e.message}")
            false
        }
    }
    
    fun getEqualizerBand(band: Int): Short {
        return currentEqBandLevels[band] ?: 0
    }
    
    fun getEqualizerBandCount(): Int {
        return try {
            equalizer?.numberOfBands?.toInt() ?: 5
        } catch (e: Exception) {
            5
        }
    }
    
    // Loudness Enhancer controls
    fun setLoudnessEnhancer(gainmB: Int): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                val clampedGain = gainmB.coerceIn(0, SAFE_LOUDNESS_LIMIT)
                currentLoudnessGain = clampedGain
                
                loudnessEnhancer?.let { effect ->
                    effect.setTargetGain(clampedGain)
                    effect.enabled = clampedGain > 0
                    Log.d(TAG, "🔊 Loudness enhancer set to: $clampedGain mB")
                }
                
                saveSettings()
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting loudness enhancer: ${e.message}")
            false
        }
    }
    
    fun getLoudnessEnhancer(): Int {
        return currentLoudnessGain
    }
    
    // Reverb controls (converted from percentage to preset)
    fun setEnvironmentalReverbLevel(levelPercentage: Int): Boolean {
        return try {
            val clampedLevel = levelPercentage.coerceIn(0, 100)
            
            // Convert percentage to preset
            val preset = when {
                clampedLevel == 0 -> PresetReverb.PRESET_NONE
                clampedLevel <= 20 -> PresetReverb.PRESET_SMALLROOM
                clampedLevel <= 40 -> PresetReverb.PRESET_MEDIUMROOM
                clampedLevel <= 60 -> PresetReverb.PRESET_LARGEROOM
                clampedLevel <= 80 -> PresetReverb.PRESET_MEDIUMHALL
                else -> PresetReverb.PRESET_LARGEHALL
            }
            
            setReverbPreset(preset)
            Log.d(TAG, "🎭 Reverb level $clampedLevel% -> preset $preset")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting reverb level: ${e.message}")
            false
        }
    }
    
    private fun setReverbPreset(preset: Short): Boolean {
        return try {
            currentReverbPreset = preset
            
            presetReverb?.let { effect ->
                effect.preset = preset
                effect.enabled = preset != PresetReverb.PRESET_NONE
                Log.d(TAG, "🎭 Reverb preset set to: $preset")
            }
            
            saveSettings()
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting reverb preset: ${e.message}")
            false
        }
    }
    
    fun getEnvironmentalReverbLevel(): Int {
        return try {
            // Convert preset back to percentage
            when (currentReverbPreset) {
                PresetReverb.PRESET_NONE -> 0
                PresetReverb.PRESET_SMALLROOM -> 20
                PresetReverb.PRESET_MEDIUMROOM -> 40
                PresetReverb.PRESET_LARGEROOM -> 60
                PresetReverb.PRESET_MEDIUMHALL -> 80
                PresetReverb.PRESET_LARGEHALL -> 100
                else -> 0
            }
        } catch (e: Exception) {
            0
        }
    }
    
    // Virtualizer controls (used for spatial effects)
    private fun setVirtualizerStrength(strength: Short): Boolean {
        return try {
            val clampedStrength = strength.coerceIn(0, SAFE_VIRTUALIZER_LIMIT.toShort())
            currentVirtualizerStrength = clampedStrength
            
            virtualizer?.let { effect ->
                effect.setStrength(clampedStrength)
                effect.enabled = clampedStrength > 0
                Log.d(TAG, "🎧 Virtualizer set to: $clampedStrength")
            }
            
            saveSettings()
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting virtualizer: ${e.message}")
            false
        }
    }
    
    // Audio Balance (simulated with virtualizer)
    fun setAudioBalance(balance: Float): Boolean {
        return try {
            val clampedBalance = balance.coerceIn(MIN_BALANCE, MAX_BALANCE)
            currentAudioBalance = clampedBalance
            
            // Use virtualizer strength to simulate balance
            // Note: This is a workaround - true balance requires custom audio routing
            val virtualizerValue = when {
                clampedBalance == CENTER_BALANCE -> 0.toShort()
                clampedBalance < CENTER_BALANCE -> ((CENTER_BALANCE - clampedBalance) * 2000).toInt().toShort()
                else -> ((clampedBalance - CENTER_BALANCE) * 2000).toInt().toShort()
            }
            
            Log.d(TAG, "⚖️ Audio balance set to: $clampedBalance (virtualizer: $virtualizerValue)")
            
            saveSettings()
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting audio balance: ${e.message}")
            false
        }
    }
    
    fun getAudioBalance(): Float = currentAudioBalance
    
    fun resetAudioBalance(): Boolean {
        return setAudioBalance(CENTER_BALANCE)
    }
    
    // Master controls
    fun disableAllEffects(): Boolean {
        return try {
            bassBoost?.enabled = false
            equalizer?.enabled = false
            presetReverb?.enabled = false
            loudnessEnhancer?.enabled = false
            virtualizer?.enabled = false
            Log.i(TAG, "🔇 All effects disabled")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error disabling all effects: ${e.message}")
            false
        }
    }
    
    fun resetAllEffects(): Boolean {
        return try {
            Log.i(TAG, "🔄 Resetting all effects to default...")
            
            currentBassBoostStrength = 0
            currentLoudnessGain = 0
            currentReverbPreset = PresetReverb.PRESET_NONE
            currentVirtualizerStrength = 0
            currentAudioBalance = CENTER_BALANCE
            currentEqBandLevels.clear()
            
            setBassBoost(0)
            setLoudnessEnhancer(0)
            setReverbPreset(PresetReverb.PRESET_NONE)
            setVirtualizerStrength(0)
            resetAudioBalance()
            
            // Reset equalizer bands
            equalizer?.let { eq ->
                for (i in 0 until eq.numberOfBands) {
                    currentEqBandLevels[i] = 0
                    eq.setBandLevel(i.toShort(), 0)
                }
            }
            
            disableAllEffects()
            saveSettings()
            
            Log.i(TAG, "✅ All effects reset successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error resetting all effects: ${e.message}")
            false
        }
    }
    
    // Get available presets
    fun getAvailablePresets(): List<String> {
        return presets.keys.toList().sorted()
    }
    
    // Get current settings
    fun getCurrentSettings(): Map<String, Any> {
        val settings = mutableMapOf<String, Any>(
            "bassBoost" to getBassBoost(),
            "loudnessEnhancer" to getLoudnessEnhancer(),
            "environmentalReverbLevel" to getEnvironmentalReverbLevel(),
            "audioBalance" to getAudioBalance(),
            "equalizerBandCount" to getEqualizerBandCount(),
            "availablePresets" to getAvailablePresets()
        )
        
        // Add individual EQ band values
        currentEqBandLevels.forEach { (band, level) ->
            settings["eq_band_$band"] = level.toInt()
        }
        
        return settings
    }
    
    // Release effects (but keep settings)
    private fun releaseEffects() {
        try {
            bassBoost?.let {
                it.enabled = false
                it.release()
            }
            equalizer?.let {
                it.enabled = false
                it.release()
            }
            presetReverb?.let {
                it.enabled = false
                it.release()
            }
            loudnessEnhancer?.let {
                it.enabled = false
                it.release()
            }
            virtualizer?.let {
                it.enabled = false
                it.release()
            }
            
            bassBoost = null
            equalizer = null
            presetReverb = null
            loudnessEnhancer = null
            virtualizer = null
            
            Log.d(TAG, "🧹 Effects released")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error releasing effects: ${e.message}")
        }
    }
    
    // Cleanup resources
    fun release() {
        try {
            // Save settings before final release
            saveSettings()
            
            // Release all effects
            releaseEffects()
            
            Log.i(TAG, "✅ AudioEffectsManager released and settings saved")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error releasing manager: ${e.message}")
        }
    }
}