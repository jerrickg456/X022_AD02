package com.sonicmesh.app.acoustic

data class AcousticConfig(
    val sampleRate: Int = 44100,
    val f0: Double = 16500.0, // Binary 0
    val f1: Double = 17500.0, // Binary 1
    val symbolDurationMs: Int = 40, // 40ms per bit -> 25 baud
    val preambleByte: Byte = 0xAA.toByte(),
    val preambleCount: Int = 4,
    val syncByte: Byte = 0x7E.toByte(),
    val protocolVersion: Byte = 0x01.toByte(),
    // Acoustic Range Meter calibration constants
    val referenceRssi1m: Double = 0.50, // Reference carrier power at 1 meter
    val pathLossExponent: Double = 1.9, // Indoor acoustic propagation exponent
    // Auto-Recovery and Retransmission
    val autoRecoveryEnabled: Boolean = true,
    val maxRetransmissions: Int = 3,
    val retransmissionTimeoutMs: Long = 5000L
) {
    val samplesPerSymbol: Int
        get() = (sampleRate * symbolDurationMs) / 1000

    companion object {
        val DEFAULT = AcousticConfig()
    }
}
