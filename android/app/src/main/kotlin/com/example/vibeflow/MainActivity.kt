package com.example.vibeflow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.ryanheise.audioservice.AudioServiceActivity
import com.example.vibeflow.installer.VibeFlowCoreInstaller
import com.example.vibeflow.audio.AudioEffectsPlugin
import android.util.Log

class MainActivity : AudioServiceActivity() {
    
    private var installer: VibeFlowCoreInstaller? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        Log.d("MainActivity", "🚀 Configuring Flutter engine...")
        
        // Register the installer (manual method channel)
        installer = VibeFlowCoreInstaller(this, flutterEngine)
        Log.d("MainActivity", "✅ VibeFlowCoreInstaller registered")
        
        // Register the audio effects plugin (FlutterPlugin - auto handles its own channel)
        flutterEngine.plugins.add(AudioEffectsPlugin())
        Log.d("MainActivity", "✅ AudioEffectsPlugin registered")
    }
    
    override fun onDestroy() {
        Log.d("MainActivity", "🧹 MainActivity destroying...")
        super.onDestroy()
        installer = null
    }
}