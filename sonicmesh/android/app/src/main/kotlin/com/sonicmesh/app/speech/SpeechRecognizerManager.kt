package com.sonicmesh.app.speech

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.Locale

class SpeechRecognizerManager(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit
) {
    private var speechRecognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    var isListening: Boolean = false
        private set

    fun startListening() {
        mainHandler.post {
            try {
                if (!SpeechRecognizer.isRecognitionAvailable(context)) {
                    onEvent(mapOf(
                        "type" to "STT_ERROR",
                        "error" to "Speech recognition is not available on this device"
                    ))
                    return@post
                }

                stopListening()

                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
                    setRecognitionListener(object : RecognitionListener {
                        override fun onReadyForSpeech(params: Bundle?) {
                            isListening = true
                            onEvent(mapOf("type" to "STT_LISTENING"))
                        }

                        override fun onBeginningOfSpeech() {
                            onEvent(mapOf("type" to "STT_SPEECH_STARTED"))
                        }

                        override fun onRmsChanged(rmsdB: Float) {
                            onEvent(mapOf(
                                "type" to "STT_RMS",
                                "rms" to rmsdB
                            ))
                        }

                        override fun onBufferReceived(buffer: ByteArray?) {}

                        override fun onEndOfSpeech() {
                            isListening = false
                            onEvent(mapOf("type" to "STT_SPEECH_ENDED"))
                        }

                        override fun onError(error: Int) {
                            isListening = false
                            val errorMsg = when (error) {
                                SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                                SpeechRecognizer.ERROR_CLIENT -> "Client side error"
                                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
                                SpeechRecognizer.ERROR_NETWORK -> "Network error"
                                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                                SpeechRecognizer.ERROR_NO_MATCH -> "No speech recognized. Try speaking again."
                                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                                SpeechRecognizer.ERROR_SERVER -> "Server error"
                                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected"
                                else -> "Recognition error: $error"
                            }
                            onEvent(mapOf(
                                "type" to "STT_ERROR",
                                "errorCode" to error,
                                "error" to errorMsg
                            ))
                        }

                        override fun onResults(results: Bundle?) {
                            isListening = false
                            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            val recognizedText = matches?.firstOrNull() ?: ""
                            onEvent(mapOf(
                                "type" to "STT_RESULT",
                                "text" to recognizedText
                            ))
                        }

                        override fun onPartialResults(partialResults: Bundle?) {
                            val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            val text = matches?.firstOrNull() ?: ""
                            if (text.isNotEmpty()) {
                                onEvent(mapOf(
                                    "type" to "STT_PARTIAL",
                                    "text" to text
                                ))
                            }
                        }

                        override fun onEvent(eventType: Int, params: Bundle?) {}
                    })
                }

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
                    // Request offline recognition explicitly
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                }

                speechRecognizer?.startListening(intent)
            } catch (e: Exception) {
                isListening = false
                onEvent(mapOf(
                    "type" to "STT_ERROR",
                    "error" to (e.message ?: "Failed to start speech recognition")
                ))
            }
        }
    }

    fun stopListening() {
        mainHandler.post {
            try {
                isListening = false
                speechRecognizer?.stopListening()
                speechRecognizer?.destroy()
                speechRecognizer = null
            } catch (_: Exception) {}
        }
    }

    fun destroy() {
        stopListening()
    }
}
