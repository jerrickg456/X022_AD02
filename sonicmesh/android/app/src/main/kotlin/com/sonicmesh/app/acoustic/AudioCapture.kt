package com.sonicmesh.app.acoustic

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class AudioCapture(private val config: AcousticConfig = AcousticConfig.DEFAULT) {
    private var audioRecord: AudioRecord? = null
    private var captureJob: Job? = null
    private var isRecording = false
    val isCapturing get() = isRecording

    @SuppressLint("MissingPermission")
    fun start(
        scope: CoroutineScope,
        onAudioData: (ShortArray, Int) -> Unit,
        onError: (String) -> Unit
    ) {
        if (isRecording) return

        val minBufSize = AudioRecord.getMinBufferSize(
            config.sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        if (minBufSize <= 0) {
            onError("Unsupported audio hardware configuration for 44.1kHz")
            return
        }

        val bufferSize = minBufSize * 4
        val sources = listOf(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.DEFAULT
        )

        var record: AudioRecord? = null
        for (source in sources) {
            try {
                record = AudioRecord(
                    source,
                    config.sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize
                )
                if (record.state == AudioRecord.STATE_INITIALIZED) {
                    break
                } else {
                    record.release()
                    record = null
                }
            } catch (_: Exception) {
                record = null
            }
        }

        if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
            onError("Failed to initialize AudioRecord with any audio source")
            return
        }

        audioRecord = record
        try {
            record.startRecording()
        } catch (e: Exception) {
            onError("Failed to start audio recording: ${e.message}")
            stop()
            return
        }

        isRecording = true
        captureJob = scope.launch(Dispatchers.IO) {
            val chunk = ShortArray(config.samplesPerSymbol * 4) // Read a few symbols worth
            while (isActive && isRecording) {
                val readCount = record.read(chunk, 0, chunk.size)
                if (readCount > 0) {
                    onAudioData(chunk, readCount)
                }
            }
        }
    }

    fun stop() {
        isRecording = false
        captureJob?.cancel()
        captureJob = null
        try {
            audioRecord?.let {
                if (it.state == AudioRecord.STATE_INITIALIZED) {
                    it.stop()
                    it.release()
                }
            }
        } catch (_: Exception) {
        } finally {
            audioRecord = null
        }
    }
}
