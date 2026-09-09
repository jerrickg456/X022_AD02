package com.sonicmesh.app.acoustic

import kotlin.math.PI
import kotlin.math.sin

class Modulator(private val config: AcousticConfig = AcousticConfig.DEFAULT) {

    /**
     * Converts raw bytes into continuous-phase FSK PCM 16-bit mono audio samples.
     */
    fun modulate(data: ByteArray, amplitude: Double = 0.85): ShortArray {
        val samplesPerSymbol = config.samplesPerSymbol
        val totalBits = data.size * 8
        // Add 50ms guard silence at start and end
        val guardSamples = (config.sampleRate * 0.05).toInt()
        val totalAudioSamples = guardSamples + (totalBits * samplesPerSymbol) + guardSamples
        val pcm = ShortArray(totalAudioSamples)

        val maxAmp = Short.MAX_VALUE * amplitude
        var phase = 0.0
        val twoPi = 2.0 * PI
        var writeIdx = guardSamples

        for (byte in data) {
            for (bitIdx in 7 downTo 0) {
                val bit = (byte.toInt() ushr bitIdx) and 1
                val freq = if (bit == 1) config.f1 else config.f0
                val phaseIncrement = twoPi * freq / config.sampleRate

                for (s in 0 until samplesPerSymbol) {
                    val sampleValue = sin(phase) * maxAmp
                    pcm[writeIdx++] = sampleValue.toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()

                    phase += phaseIncrement
                    if (phase >= twoPi) {
                        phase -= twoPi
                    }
                }
            }
        }

        // Apply 5ms fade-in and fade-out to prevent audible click
        val rampSamples = (config.sampleRate * 0.005).toInt().coerceAtMost(guardSamples)
        for (i in 0 until rampSamples) {
            val factor = i.toDouble() / rampSamples
            val idxIn = guardSamples + i
            if (idxIn < pcm.size) {
                pcm[idxIn] = (pcm[idxIn] * factor).toInt().toShort()
            }
            val idxOut = writeIdx - 1 - i
            if (idxOut >= 0 && idxOut < pcm.size) {
                pcm[idxOut] = (pcm[idxOut] * factor).toInt().toShort()
            }
        }

        return pcm
    }
}
