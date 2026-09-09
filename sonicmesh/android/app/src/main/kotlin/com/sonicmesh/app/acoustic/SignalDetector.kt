package com.sonicmesh.app.acoustic

import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sqrt

data class SignalMetrics(
    val hasSignal: Boolean,
    val signalLevel: Double,
    val rms: Double,
    val estimatedDistanceMeters: Double,
    val proximityZone: String,
    val snrDb: Double,
    val peakPower: Double
)

class SignalDetector(private val config: AcousticConfig = AcousticConfig.DEFAULT) {

    private var smoothedDistance: Double = 3.0
    private var ambientNoiseFloor: Double = 0.001

    fun computeRms(samples: ShortArray, offset: Int, length: Int): Double {
        if (length <= 0 || offset + length > samples.size) return 0.0
        var sumSquares = 0.0
        for (i in 0 until length) {
            val v = samples[offset + i].toDouble() / 32768.0
            sumSquares += v * v
        }
        return sqrt(sumSquares / length)
    }

    /**
     * Checks if acoustic energy around the FSK frequencies exceeds noise floor
     * and calculates estimated distance, proximity zone, and SNR in real time.
     */
    fun detectSignal(samples: ShortArray, offset: Int, length: Int): SignalMetrics {
        val p0 = Goertzel.computePower(samples, offset, length, config.f0, config.sampleRate)
        val p1 = Goertzel.computePower(samples, offset, length, config.f1, config.sampleRate)
        val maxPower = maxOf(p0, p1)
        val rms = computeRms(samples, offset, length)

        val threshold = 0.25 // Sensitivity threshold for carrier presence
        val hasSignal = maxPower > threshold
        val score = (maxPower * 25.0).coerceIn(0.0, 100.0)

        // Track ambient noise floor when no signal is present (slow exponential moving average)
        if (!hasSignal) {
            ambientNoiseFloor = (ambientNoiseFloor * 0.95 + maxPower * 0.05).coerceAtLeast(0.0001)
        }

        // Compute SNR (dB)
        val snrDb = (10.0 * log10((maxPower + 1e-6) / (ambientNoiseFloor + 1e-6))).coerceIn(-10.0, 45.0)

        // Range Meter: Log-distance path loss acoustic model
        // P(d) = P(1m) * (1 / d)^gamma  =>  d = (P(1m) / P(d))^(1 / gamma)
        val rawDistance = if (hasSignal) {
            val ratio = config.referenceRssi1m / (maxPower.coerceAtLeast(0.005))
            ratio.pow(1.0 / config.pathLossExponent).coerceIn(0.2, 15.0)
        } else {
            10.0 // Far default when idle
        }

        // Apply low-pass smoothing filter (alpha = 0.3) to prevent erratic distance jumps from room flutter
        smoothedDistance = if (hasSignal) {
            smoothedDistance * 0.7 + rawDistance * 0.3
        } else {
            smoothedDistance * 0.9 + 8.0 * 0.1
        }
        val distance = (smoothedDistance * 10.0).toInt() / 10.0 // 1 decimal place

        val proximityZone = when {
            distance < 1.0 -> "IMMEDIATE (< 1m)"
            distance < 3.0 -> "NEAR (1-3m)"
            distance < 7.0 -> "MID-RANGE (3-7m)"
            else -> "FAR (> 7m)"
        }

        return SignalMetrics(
            hasSignal = hasSignal,
            signalLevel = score,
            rms = rms,
            estimatedDistanceMeters = distance,
            proximityZone = proximityZone,
            snrDb = (snrDb * 10.0).toInt() / 10.0,
            peakPower = maxPower
        )
    }
}
