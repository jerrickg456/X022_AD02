package com.sonicmesh.app.acoustic

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class AudioPlayer(private val config: AcousticConfig = AcousticConfig.DEFAULT) {
    private var audioTrack: AudioTrack? = null
    private var isPlaying = false

    suspend fun play(pcm: ShortArray, onProgress: ((Float) -> Unit)? = null) = withContext(Dispatchers.IO) {
        stop()

        val bufferSize = pcm.size * 2
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(config.sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        audioTrack = track
        track.write(pcm, 0, pcm.size)
        track.play()
        isPlaying = true

        val totalDurationMs = (pcm.size * 1000L) / config.sampleRate
        val stepMs = 50L
        var elapsed = 0L

        while (isPlaying && elapsed < totalDurationMs) {
            delay(stepMs)
            elapsed += stepMs
            val progress = (elapsed.toFloat() / totalDurationMs).coerceIn(0f, 1f)
            onProgress?.invoke(progress)
        }

        stop()
    }

    fun stop() {
        isPlaying = false
        try {
            audioTrack?.let {
                if (it.state == AudioTrack.STATE_INITIALIZED) {
                    it.pause()
                    it.flush()
                    it.stop()
                    it.release()
                }
            }
        } catch (_: Exception) {
        } finally {
            audioTrack = null
        }
    }
}
