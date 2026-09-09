package com.sonicmesh.app.acoustic

class Demodulator(private val config: AcousticConfig = AcousticConfig.DEFAULT) {

    /**
     * Decodes a complete or segmented PCM ShortArray buffer into AcousticPacket,
     * or returns null if no valid frame with matching CRC-32 is found.
     */
    fun demodulate(pcm: ShortArray): AcousticPacket? {
        val samplesPerSymbol = config.samplesPerSymbol
        // Minimum packet: preamble (4B) + sync (1B) + header (8B) + payload (1B) + crc (4B) = 18B = 144 symbols
        if (pcm.size < samplesPerSymbol * 40) {
            return null
        }

        // 1. Scan across the audio to measure the peak power of f0 and f1.
        // This dynamically balances hardware frequency response asymmetry (e.g. 17.5 kHz attenuation on phone mics).
        var maxP0 = 1e-9
        var maxP1 = 1e-9
        val evalLen = samplesPerSymbol / 2 // Middle 50% window
        val scanStep = (samplesPerSymbol * 2).coerceAtLeast(1)

        var scanPos = 0
        while (scanPos + evalLen <= pcm.size) {
            val p0 = Goertzel.computePower(pcm, scanPos, evalLen, config.f0, config.sampleRate)
            val p1 = Goertzel.computePower(pcm, scanPos, evalLen, config.f1, config.sampleRate)
            if (p0 > maxP0) maxP0 = p0
            if (p1 > maxP1) maxP1 = p1
            scanPos += scanStep
        }

        // If overall carrier power is below minimum acoustic floor, skip
        if (maxOf(maxP0, maxP1) < 0.01) {
            return null
        }

        // Gain balancing multipliers
        val norm0 = 1.0 / maxP0
        val norm1 = 1.0 / maxP1

        // 2. Evaluate candidate symbol clock alignments (8 sub-symbol phases)
        val phaseCount = 8
        val phaseStep = (samplesPerSymbol / phaseCount).coerceAtLeast(1)
        val syncBits = intArrayOf(0, 1, 1, 1, 1, 1, 1, 0) // 0x7E

        for (phaseIdx in 0 until phaseCount) {
            val phaseOffset = phaseIdx * phaseStep
            if (phaseOffset + samplesPerSymbol * 30 > pcm.size) continue

            val totalSymbols = (pcm.size - phaseOffset) / samplesPerSymbol
            if (totalSymbols < 30) continue

            val bits = IntArray(totalSymbols)

            // Demodulate bit stream using center-window Goertzel
            for (s in 0 until totalSymbols) {
                val symStart = phaseOffset + s * samplesPerSymbol
                // Evaluate middle 50% of symbol to reject inter-symbol interference and multipath edges
                val centerOffset = symStart + samplesPerSymbol / 4
                val p0 = Goertzel.computePower(pcm, centerOffset, evalLen, config.f0, config.sampleRate) * norm0
                val p1 = Goertzel.computePower(pcm, centerOffset, evalLen, config.f1, config.sampleRate) * norm1
                bits[s] = if (p1 > p0) 1 else 0
            }

            // 3. Search for sync word 0x7E with Hamming distance tolerance <= 1
            val maxBitCheck = totalSymbols - syncBits.size - (AcousticPacket.HEADER_SIZE + AcousticPacket.CRC_SIZE) * 8
            for (b in 0..maxBitCheck) {
                var distance = 0
                for (k in syncBits.indices) {
                    if (bits[b + k] != syncBits[k]) {
                        distance++
                        if (distance > 1) break
                    }
                }

                if (distance <= 1) {
                    // Potential sync word detected at bit index b!
                    // Verify if packet frame decodes with valid CRC-32
                    val candidatePacket = tryExtractPacket(
                        pcm,
                        phaseOffset,
                        b + syncBits.size,
                        samplesPerSymbol,
                        evalLen,
                        norm0,
                        norm1
                    )
                    if (candidatePacket != null) {
                        return candidatePacket
                    }
                }
            }
        }

        return null
    }

    private fun tryExtractPacket(
        pcm: ShortArray,
        phaseOffset: Int,
        startBitIndex: Int,
        samplesPerSymbol: Int,
        evalLen: Int,
        norm0: Double,
        norm1: Double
    ): AcousticPacket? {
        val bitStep = samplesPerSymbol
        var currentSample = phaseOffset + startBitIndex * bitStep

        // 1. Read Header (8 bytes)
        val headerBytes = ByteArray(AcousticPacket.HEADER_SIZE)
        for (i in 0 until AcousticPacket.HEADER_SIZE) {
            val b = readByte(pcm, currentSample, bitStep, evalLen, norm0, norm1) ?: return null
            headerBytes[i] = b
            currentSample += bitStep * 8
        }

        val version = headerBytes[0]
        val type = headerBytes[1]
        val seq = (((headerBytes[2].toInt() and 0xFF) shl 8) or (headerBytes[3].toInt() and 0xFF)).toShort()
        val total = (((headerBytes[4].toInt() and 0xFF) shl 8) or (headerBytes[5].toInt() and 0xFF)).toShort()
        val payloadLen = ((headerBytes[6].toInt() and 0xFF) shl 8) or (headerBytes[7].toInt() and 0xFF)

        // Strict protocol sanity checks
        if (version != config.protocolVersion || payloadLen < 0 || payloadLen > 1024) {
            return null
        }
        if (total < 1 || seq < 1 || seq > total) {
            return null
        }

        // 2. Read Payload (payloadLen bytes)
        val payloadBytes = ByteArray(payloadLen)
        for (i in 0 until payloadLen) {
            val b = readByte(pcm, currentSample, bitStep, evalLen, norm0, norm1) ?: return null
            payloadBytes[i] = b
            currentSample += bitStep * 8
        }

        // 3. Read CRC-32 (4 bytes)
        val crcBytes = ByteArray(AcousticPacket.CRC_SIZE)
        for (i in 0 until AcousticPacket.CRC_SIZE) {
            val b = readByte(pcm, currentSample, bitStep, evalLen, norm0, norm1) ?: return null
            crcBytes[i] = b
            currentSample += bitStep * 8
        }

        val expectedCrc = (((crcBytes[0].toLong() and 0xFF) shl 24) or
                ((crcBytes[1].toLong() and 0xFF) shl 16) or
                ((crcBytes[2].toLong() and 0xFF) shl 8) or
                (crcBytes[3].toLong() and 0xFF)) and 0xFFFFFFFFL

        // Compute actual CRC-32 over Header + Payload
        val bodyBytes = ByteArray(AcousticPacket.HEADER_SIZE + payloadLen)
        System.arraycopy(headerBytes, 0, bodyBytes, 0, AcousticPacket.HEADER_SIZE)
        System.arraycopy(payloadBytes, 0, bodyBytes, AcousticPacket.HEADER_SIZE, payloadLen)

        val actualCrc = Crc32.compute(bodyBytes)
        if (actualCrc == expectedCrc) {
            return AcousticPacket(
                version = version,
                type = type,
                sequenceNumber = seq,
                totalPackets = total,
                payload = payloadBytes
            )
        }

        return null
    }

    private fun readByte(
        pcm: ShortArray,
        startSample: Int,
        samplesPerSymbol: Int,
        evalLen: Int,
        norm0: Double,
        norm1: Double
    ): Byte? {
        var byteVal = 0
        var offset = startSample
        for (bit in 7 downTo 0) {
            if (offset + samplesPerSymbol > pcm.size) return null
            val center = offset + samplesPerSymbol / 4
            val p0 = Goertzel.computePower(pcm, center, evalLen, config.f0, config.sampleRate) * norm0
            val p1 = Goertzel.computePower(pcm, center, evalLen, config.f1, config.sampleRate) * norm1
            val bitVal = if (p1 > p0) 1 else 0
            byteVal = byteVal or (bitVal shl bit)
            offset += samplesPerSymbol
        }
        return byteVal.toByte()
    }
}
