package com.example.vibeflow.audio

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.*
import android.media.MediaPlayer
import android.util.Log

class AudioEffectsManager(private val context: Context) {
    private val TAG = "AudioEffectsManager"
    
    private var audioSessionId: Int = 0
    private var mediaPlayer: MediaPlayer? = null
    
    // Effect instances
    private var bassBoost: BassBoost? = null
    private var equalizer: Equalizer? = null
    private var environmentalReverb: EnvironmentalReverb? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    
    // Audio balance (0.0 = full left, 0.5 = center, 1.0 = full right)
    private var audioBalance: Float = 0.5f
    
    // Safe limits
    companion object {
        const val SAFE_BASS_BOOST_LIMIT = 1000 // millibels
        const val SAFE_LOUDNESS_LIMIT = 1000 // millibels
        const val SAFE_EQ_BAND_LIMIT = 1500 // millibels
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
        val reverbLevel: Int,
        val audioBalance: Float
    )
    
    private val presets = mapOf(
        "Normal" to AudioPreset(
            "Normal", 0, 0, 
            shortArrayOf(0, 0, 0, 0, 0), 
            0, CENTER_BALANCE
        ),
        "Rock" to AudioPreset(
            "Rock", 500, 400,
            shortArrayOf(400, 300, -200, 200, 500),
            25, CENTER_BALANCE
        ),
        "Pop" to AudioPreset(
            "Pop", 300, 300,
            shortArrayOf(200, 300, 400, 300, 200),
            15, CENTER_BALANCE
        ),
        "Jazz" to AudioPreset(
            "Jazz", 200, 200,
            shortArrayOf(300, 200, 100, 200, 300),
            35, CENTER_BALANCE
        ),
        "Classical" to AudioPreset(
            "Classical", 100, 100,
            shortArrayOf(300, 100, 0, 100, 300),
            45, CENTER_BALANCE
        ),
        "Bass Boost" to AudioPreset(
            "Bass Boost", 800, 500,
            shortArrayOf(800, 600, 400, 200, 0),
            10, CENTER_BALANCE
        ),
        "Vocal" to AudioPreset(
            "Vocal", 0, 300,
            shortArrayOf(-100, 300, 500, 500, 200),
            20, CENTER_BALANCE
        )
    )
    
    // Initialize effects
    fun initialize(sessionId: Int, player: MediaPlayer? = null): Boolean {
        audioSessionId = if (sessionId == 0) {
            // Use default audio session (0 means default output mix)
            AudioManager.AUDIO_SESSION_ID_GENERATE
        } else {
            sessionId
        }
        
        mediaPlayer = player
        
        return try {
            initializeEffects()
            
            // Load saved settings after initialization
            loadSavedSettings()
            
            Log.i(TAG, "Audio effects initialized with session ID: $audioSessionId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing effects: ${e.message}")
            false
        }
    }
    
    private fun initializeEffects() {
        // Initialize Bass Boost
        try {
            bassBoost = BassBoost(0, audioSessionId).apply {
                enabled = false
                setStrength(0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "BassBoost not supported: ${e.message}")
        }
        
        // Initialize Equalizer
        try {
            equalizer = Equalizer(0, audioSessionId).apply {
                enabled = false
            }
        } catch (e: Exception) {
            Log.w(TAG, "Equalizer not supported: ${e.message}")
        }
        
        // Initialize Environmental Reverb
        try {
            environmentalReverb = EnvironmentalReverb(0, audioSessionId).apply {
                enabled = false
            }
        } catch (e: Exception) {
            Log.w(TAG, "EnvironmentalReverb not supported: ${e.message}")
        }
        
        // Initialize Loudness Enhancer (API 19+)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
            try {
                loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                    enabled = false
                    setTargetGain(0)
                }
            } catch (e: Exception) {
                Log.w(TAG, "LoudnessEnhancer not supported: ${e.message}")
            }
        }
    }
    
    // Load saved settings from SharedPreferences
    private fun loadSavedSettings() {
        val prefs = context.getSharedPreferences("audio_effects_prefs", Context.MODE_PRIVATE)
        
        try {
            // Load bass boost
            val savedBassBoost = prefs.getInt("bass_boost", 0).toShort()
            if (savedBassBoost > 0) {
                bassBoost?.setStrength(savedBassBoost)
                bassBoost?.enabled = true
            }
            
            // Load loudness enhancer
            val savedLoudness = prefs.getInt("loudness_enhancer", 0)
            if (savedLoudness > 0 && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.setTargetGain(savedLoudness)
                loudnessEnhancer?.enabled = true
            }
            
            // Load reverb
            val savedReverb = prefs.getInt("reverb_level", 0)
            if (savedReverb > 0) {
                setEnvironmentalReverbLevelInternal(savedReverb, false) // Don't save again
            }
            
            // Load audio balance
            val savedBalance = prefs.getFloat("audio_balance", CENTER_BALANCE)
            audioBalance = savedBalance
            
            // Load equalizer bands
            equalizer?.let { eq ->
                var hasAnyBand = false
                for (i in 0 until eq.numberOfBands) {
                    val savedLevel = prefs.getInt("eq_band_$i", 0).toShort()
                    if (savedLevel != 0.toShort()) {
                        eq.setBandLevel(i.toShort(), savedLevel)
                        hasAnyBand = true
                    }
                }
                if (hasAnyBand) {
                    eq.enabled = true
                }
            }
            
            Log.i(TAG, "Loaded saved audio effects settings")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading saved settings: ${e.message}")
        }
    }
    
    // Save settings to SharedPreferences
    private fun saveSettings() {
        val prefs = context.getSharedPreferences("audio_effects_prefs", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        
        try {
            // Save all settings
            editor.putInt("bass_boost", getBassBoost().toInt())
            editor.putInt("loudness_enhancer", getLoudnessEnhancer())
            editor.putInt("reverb_level", getEnvironmentalReverbLevel())
            editor.putFloat("audio_balance", getAudioBalance())
            
            // Save equalizer bands
            equalizer?.let { eq ->
                for (i in 0 until eq.numberOfBands) {
                    editor.putInt("eq_band_$i", eq.getBandLevel(i.toShort()).toInt())
                }
            }
            
            editor.apply()
            Log.d(TAG, "Settings saved to SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving settings: ${e.message}")
        }
    }
    
    // Apply preset
    fun applyPreset(presetName: String): Boolean {
        val preset = presets[presetName] ?: return false
        
        return try {
            Log.i(TAG, "Applying preset: $presetName")
            
            setBassBoost(preset.bassBoost)
            setLoudnessEnhancer(preset.loudnessEnhancer)
            setEnvironmentalReverbLevel(preset.reverbLevel)
            setAudioBalance(preset.audioBalance)
            
            // Apply equalizer bands
            preset.equalizerBands.forEachIndexed { index, value ->
                setEqualizerBand(index, value)
            }
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error applying preset '$presetName': ${e.message}")
            false
        }
    }
    
    // Bass Boost controls
    fun setBassBoost(strength: Short): Boolean {
        return try {
            bassBoost?.let { effect ->
                val clampedStrength = strength.coerceIn(0, SAFE_BASS_BOOST_LIMIT.toShort())
                effect.setStrength(clampedStrength)
                effect.enabled = clampedStrength > 0
                Log.d(TAG, "Bass boost set to: $clampedStrength mB")
                saveSettings()
                true
            } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Error setting bass boost: ${e.message}")
            false
        }
    }
    
    fun getBassBoost(): Short {
        return try {
            bassBoost?.roundedStrength ?: 0
        } catch (e: Exception) {
            0
        }
    }
    
    // Audio Balance controls
    fun setAudioBalance(balance: Float): Boolean {
        return try {
            val clampedBalance = balance.coerceIn(MIN_BALANCE, MAX_BALANCE)
            audioBalance = clampedBalance
            
            mediaPlayer?.let { player ->
                val leftVolume: Float
                val rightVolume: Float
                
                when {
                    clampedBalance < CENTER_BALANCE -> {
                        leftVolume = 1.0f
                        rightVolume = clampedBalance * 2.0f
                    }
                    clampedBalance > CENTER_BALANCE -> {
                        leftVolume = (1.0f - clampedBalance) * 2.0f
                        rightVolume = 1.0f
                    }
                    else -> {
                        leftVolume = 1.0f
                        rightVolume = 1.0f
                    }
                }
                
                player.setVolume(leftVolume, rightVolume)
                Log.d(TAG, "Audio balance set to: $clampedBalance")
            }
            
            saveSettings()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error setting audio balance: ${e.message}")
            false
        }
    }
    
    fun getAudioBalance(): Float = audioBalance
    
    fun resetAudioBalance(): Boolean = setAudioBalance(CENTER_BALANCE)
    
    // Equalizer controls
    fun setEqualizerBand(band: Int, level: Short): Boolean {
        return try {
            equalizer?.let { eq ->
                if (band < 0 || band >= eq.numberOfBands) return false
                
                val safeLevel = level.coerceIn((-SAFE_EQ_BAND_LIMIT).toShort(), SAFE_EQ_BAND_LIMIT.toShort())
                eq.setBandLevel(band.toShort(), safeLevel)
                eq.enabled = true
                Log.d(TAG, "EQ band $band set to: $safeLevel mB")
                saveSettings()
                true
            } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Error setting equalizer band $band: ${e.message}")
            false
        }
    }
    
    fun getEqualizerBand(band: Int): Short {
        return try {
            equalizer?.getBandLevel(band.toShort()) ?: 0
        } catch (e: Exception) {
            0
        }
    }
    
    fun getEqualizerBandCount(): Int {
        return try {
            equalizer?.numberOfBands?.toInt() ?: 0
        } catch (e: Exception) {
            0
        }
    }
    
    // Loudness Enhancer controls
    fun setLoudnessEnhancer(gainmB: Int): Boolean {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.let { effect ->
                    val clampedGain = gainmB.coerceIn(0, SAFE_LOUDNESS_LIMIT)
                    effect.setTargetGain(clampedGain)
                    effect.enabled = clampedGain > 0
                    Log.d(TAG, "Loudness enhancer set to: $clampedGain mB")
                    saveSettings()
                    true
                } ?: false
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting loudness enhancer: ${e.message}")
            false
        }
    }
    
    fun getLoudnessEnhancer(): Int {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.targetGain?.toInt() ?: 0
            } else {
                0
            }
        } catch (e: Exception) {
            0
        }
    }
    
    // Environmental Reverb controls
    fun setEnvironmentalReverbLevel(levelPercentage: Int): Boolean {
        return setEnvironmentalReverbLevelInternal(levelPercentage, true)
    }
    
    private fun setEnvironmentalReverbLevelInternal(levelPercentage: Int, shouldSave: Boolean): Boolean {
        return try {
            val clampedLevel = levelPercentage.coerceIn(0, 100)
            
            environmentalReverb?.let { effect ->
                if (clampedLevel == 0) {
                    effect.enabled = false
                    if (shouldSave) saveSettings()
                    return true
                }
                
                val intensity = clampedLevel / 100.0f
                val settings = EnvironmentalReverb.Settings().apply {
                    roomLevel = (-9000 + (8000 * intensity)).toInt().toShort()
                    roomHFLevel = (-4000 + (3900 * intensity)).toInt().toShort()
                    decayTime = (100 + (19900 * intensity)).toInt()
                    decayHFRatio = (100 + (1900 * intensity)).toInt().toShort()
                    reflectionsLevel = (-9000 + (8000 * intensity)).toInt().toShort()
                    reflectionsDelay = (0 + (300 * intensity)).toInt()
                    reverbLevel = (-9000 + (8000 * intensity)).toInt().toShort()
                    reverbDelay = (0 + (100 * intensity)).toInt()
                    diffusion = (0 + (1000 * intensity)).toInt().toShort()
                    density = (0 + (1000 * intensity)).toInt().toShort()
                }
                
                effect.properties = settings
                effect.enabled = true
                Log.d(TAG, "Environmental reverb level set to: $clampedLevel%")
                if (shouldSave) saveSettings()
                true
            } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Error setting environmental reverb level: ${e.message}")
            false
        }
    }
    
    fun getEnvironmentalReverbLevel(): Int {
        return try {
            environmentalReverb?.let { effect ->
                if (!effect.enabled) return 0
                val settings = effect.properties
                val reverbLevel = settings.reverbLevel.toFloat()
                ((reverbLevel + 9000) / 8000.0f * 100).toInt().coerceIn(0, 100)
            } ?: 0
        } catch (e: Exception) {
            0
        }
    }
    
    // Master controls
    fun disableAllEffects(): Boolean {
        return try {
            bassBoost?.enabled = false
            equalizer?.enabled = false
            environmentalReverb?.enabled = false
            loudnessEnhancer?.enabled = false
            Log.i(TAG, "All effects disabled")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error disabling all effects: ${e.message}")
            false
        }
    }
    
    fun resetAllEffects(): Boolean {
        return try {
            setBassBoost(0)
            setLoudnessEnhancer(0)
            setEnvironmentalReverbLevel(0)
            resetAudioBalance()
            
            // Reset equalizer bands
            equalizer?.let { eq ->
                for (i in 0 until eq.numberOfBands) {
                    eq.setBandLevel(i.toShort(), 0)
                }
            }
            
            disableAllEffects()
            saveSettings()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error resetting all effects: ${e.message}")
            false
        }
    }
    
    // Get available presets
    fun getAvailablePresets(): List<String> {
        return presets.keys.toList().sorted()
    }
    
    // Update MediaPlayer reference
    fun updateMediaPlayer(player: MediaPlayer?) {
        mediaPlayer = player
        if (player != null) {
            setAudioBalance(audioBalance)
        }
    }
    
    // Get current settings (including individual EQ band values)
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
        equalizer?.let { eq ->
            for (i in 0 until eq.numberOfBands) {
                settings["eq_band_$i"] = eq.getBandLevel(i.toShort()).toInt()
            }
        }
        
        return settings
    }
    
    // Cleanup resources
    fun release() {
        try {
            // Save settings before releasing
            saveSettings()
            
            bassBoost?.let {
                it.enabled = false
                it.release()
            }
            equalizer?.let {
                it.enabled = false
                it.release()
            }
            environmentalReverb?.let {
                it.enabled = false
                it.release()
            }
            loudnessEnhancer?.let {
                it.enabled = false
                it.release()
            }
            
            bassBoost = null
            equalizer = null
            environmentalReverb = null
            loudnessEnhancer = null
            mediaPlayer = null
            
            Log.i(TAG, "Audio effects resources released and settings saved")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing effects: ${e.message}")
        }
    }
}