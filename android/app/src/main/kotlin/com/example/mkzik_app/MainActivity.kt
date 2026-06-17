package com.example.mkzik_app

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (au lieu de FlutterActivity) est requis par
// just_audio_background pour la lecture / les contrôles en arrière-plan.
class MainActivity : AudioServiceActivity()
