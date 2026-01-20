package com.example.vibeflow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.ryanheise.audioservice.AudioServiceActivity
import com.example.vibeflow.installer.VibeFlowCoreInstaller
import com.example.vibeflow.audio.AudioEffectsPlugin

class MainActivity : AudioServiceActivity() {
    
    private var installer: VibeFlowCoreInstaller? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the installer (manual method channel)
        installer = VibeFlowCoreInstaller(this, flutterEngine)
        
        // Register the audio effects plugin (FlutterPlugin - auto handles its own channel)
        flutterEngine.plugins.add(AudioEffectsPlugin())
    }
    
    override fun onDestroy() {
        super.onDestroy()
        installer = null
    }
}