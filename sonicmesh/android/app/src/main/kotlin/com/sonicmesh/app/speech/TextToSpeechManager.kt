package com.sonicmesh.app.speech

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

class TextToSpeechManager(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit
) : TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    private var isInitialized = false
    var isSpeaking: Boolean = false
        private set
    private var currentUtteranceId: String? = null

    init {
        tts = TextToSpeech(context.applicationContext, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isInitialized = true
            tts?.language = Locale.getDefault()
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    isSpeaking = true
                    onEvent(mapOf(
                        "type" to "TTS_STARTED",
                        "utteranceId" to (utteranceId ?: "")
                    ))
                }

                override fun onDone(utteranceId: String?) {
                    isSpeaking = false
                    onEvent(mapOf(
                        "type" to "TTS_COMPLETED",
                        "utteranceId" to (utteranceId ?: "")
                    ))
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    isSpeaking = false
                    onEvent(mapOf(
                        "type" to "TTS_ERROR",
                        "utteranceId" to (utteranceId ?: ""),
                        "error" to "Speech synthesis error"
                    ))
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    isSpeaking = false
                    onEvent(mapOf(
                        "type" to "TTS_ERROR",
                        "utteranceId" to (utteranceId ?: ""),
                        "errorCode" to errorCode,
                        "error" to "Speech synthesis error ($errorCode)"
                    ))
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    isSpeaking = false
                    onEvent(mapOf(
                        "type" to "TTS_STOPPED",
                        "utteranceId" to (utteranceId ?: ""),
                        "interrupted" to interrupted
                    ))
                }
            })
            onEvent(mapOf("type" to "TTS_READY"))
        } else {
            isInitialized = false
            onEvent(mapOf(
                "type" to "TTS_ERROR",
                "error" to "Failed to initialize Android TextToSpeech engine ($status)"
            ))
        }
    }

    fun speak(text: String, utteranceId: String = System.currentTimeMillis().toString()): Boolean {
        if (!isInitialized || tts == null) return false
        stop()
        currentUtteranceId = utteranceId
        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        }
        val result = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        return result == TextToSpeech.SUCCESS
    }

    fun pause() {
        stop()
    }

    fun stop() {
        try {
            if (isSpeaking) {
                tts?.stop()
                isSpeaking = false
                onEvent(mapOf(
                    "type" to "TTS_STOPPED",
                    "utteranceId" to (currentUtteranceId ?: "")
                ))
            }
        } catch (_: Exception) {}
    }

    fun destroy() {
        try {
            stop()
            tts?.shutdown()
            tts = null
            isInitialized = false
        } catch (_: Exception) {}
    }
}
