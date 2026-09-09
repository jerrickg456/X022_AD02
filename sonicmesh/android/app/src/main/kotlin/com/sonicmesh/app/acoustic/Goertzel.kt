package com.sonicmesh.app.acoustic

import kotlin.math.cos
import kotlin.math.PI

object Goertzel {
    /**
     * Calculates the power of a specific target frequency in a block of PCM samples.
     */
    fun computePower(samples: ShortArray, offset: Int, length: Int, targetFreq: Double, sampleRate: Int): Double {
        if (length <= 0 || offset + length > samples.size) return 0.0

        val omega = 2.0 * PI * targetFreq / sampleRate
        val coeff = 2.0 * cos(omega)

        var s0: Double
        var s1 = 0.0
        var s2 = 0.0

        for (i in 0 until length) {
            val sampleNorm = samples[offset + i].toDouble() / 32768.0
            s0 = sampleNorm + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }

        val power = s1 * s1 + s2 * s2 - s1 * s2 * coeff
        return if (power < 0.0) 0.0 else power
    }
}
