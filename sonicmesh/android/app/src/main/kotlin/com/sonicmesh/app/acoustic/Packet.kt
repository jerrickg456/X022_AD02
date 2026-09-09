package com.sonicmesh.app.acoustic

import java.nio.ByteBuffer
import java.nio.ByteOrder

data class AcousticPacket(
    val version: Byte = 1,
    val type: Byte = TYPE_DATA,
    val sequenceNumber: Short = 1,
    val totalPackets: Short = 1,
    val payload: ByteArray
) {
    companion object {
        const val TYPE_DATA: Byte = 0x01
        const val TYPE_PING: Byte = 0x02
        const val TYPE_ACK: Byte = 0x03
        const val TYPE_RETRANS_REQ: Byte = 0x04   // NACK: requesting retransmission of missing sequence
        const val TYPE_RETRANS_RESP: Byte = 0x05  // ARQ response with requested sequence
        const val HEADER_SIZE: Int = 8 // version(1) + type(1) + seq(2) + total(2) + length(2)
        const val CRC_SIZE: Int = 4
        const val SYNC_WORD: Byte = 0x7E

        /**
         * Creates a compact NACK packet requesting retransmission of a missing chunk.
         */
        fun createRetransRequest(
            version: Byte = 1,
            missingSequence: Short,
            totalExpected: Short
        ): AcousticPacket {
            val payload = ByteArray(4)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putShort(missingSequence)
            buf.putShort(totalExpected)
            return AcousticPacket(
                version = version,
                type = TYPE_RETRANS_REQ,
                sequenceNumber = missingSequence,
                totalPackets = totalExpected,
                payload = payload
            )
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as AcousticPacket
        if (version != other.version) return false
        if (type != other.type) return false
        if (sequenceNumber != other.sequenceNumber) return false
        if (totalPackets != other.totalPackets) return false
        if (!payload.contentEquals(other.payload)) return false
        return true
    }

    override fun hashCode(): Int {
        var result = version.toInt()
        result = 31 * result + type.toInt()
        result = 31 * result + sequenceNumber.toInt()
        result = 31 * result + totalPackets.toInt()
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

object PacketEncoder {
    fun encode(packet: AcousticPacket, config: AcousticConfig = AcousticConfig.DEFAULT): ByteArray {
        val payloadLen = packet.payload.size
        val frameBodySize = AcousticPacket.HEADER_SIZE + payloadLen
        val bodyBuffer = ByteBuffer.allocate(frameBodySize).order(ByteOrder.BIG_ENDIAN)

        bodyBuffer.put(packet.version)
        bodyBuffer.put(packet.type)
        bodyBuffer.putShort(packet.sequenceNumber)
        bodyBuffer.putShort(packet.totalPackets)
        bodyBuffer.putShort(payloadLen.toShort())
        bodyBuffer.put(packet.payload)

        val bodyBytes = bodyBuffer.array()
        val crc = Crc32.compute(bodyBytes)

        val totalFrameSize = config.preambleCount + 1 + frameBodySize + AcousticPacket.CRC_SIZE
        val frameBuffer = ByteBuffer.allocate(totalFrameSize).order(ByteOrder.BIG_ENDIAN)

        // Preamble (0xAA...)
        repeat(config.preambleCount) {
            frameBuffer.put(config.preambleByte)
        }
        // Sync word (0x7E)
        frameBuffer.put(AcousticPacket.SYNC_WORD)
        // Body (Header + Payload)
        frameBuffer.put(bodyBytes)
        // CRC32
        frameBuffer.putInt(crc.toInt())

        return frameBuffer.array()
    }
}

object PacketDecoder {
    sealed class Result {
        data class Success(val packet: AcousticPacket) : Result()
        data class Error(val message: String) : Result()
    }

    /**
     * Attempts to find preamble, sync word, and decode the frame from raw received bytes.
     */
    fun decode(rawBytes: ByteArray, config: AcousticConfig = AcousticConfig.DEFAULT): Result {
        if (rawBytes.size < config.preambleCount + 1 + AcousticPacket.HEADER_SIZE + AcousticPacket.CRC_SIZE) {
            return Result.Error("Data too short for valid packet frame: ${rawBytes.size} bytes")
        }

        // Search for sync word
        var syncIndex = -1
        for (i in 0 until rawBytes.size - (AcousticPacket.HEADER_SIZE + AcousticPacket.CRC_SIZE)) {
            if (rawBytes[i] == AcousticPacket.SYNC_WORD) {
                syncIndex = i
                break
            }
        }

        if (syncIndex == -1) {
            return Result.Error("Sync word 0x7E not found in byte stream")
        }

        val startIndex = syncIndex + 1
        val remaining = rawBytes.size - startIndex
        if (remaining < AcousticPacket.HEADER_SIZE + AcousticPacket.CRC_SIZE) {
            return Result.Error("Truncated frame after sync word: remaining $remaining bytes")
        }

        val buffer = ByteBuffer.wrap(rawBytes, startIndex, remaining).order(ByteOrder.BIG_ENDIAN)
        val version = buffer.get()
        val type = buffer.get()
        val seq = buffer.short
        val total = buffer.short
        val length = buffer.short.toInt() and 0xFFFF

        if (remaining < AcousticPacket.HEADER_SIZE + length + AcousticPacket.CRC_SIZE) {
            return Result.Error("Packet payload truncated. Expected $length bytes, available: ${remaining - AcousticPacket.HEADER_SIZE - AcousticPacket.CRC_SIZE}")
        }

        val payload = ByteArray(length)
        buffer.get(payload)

        val expectedCrc = buffer.int.toLong() and 0xFFFFFFFFL

        val bodyLength = AcousticPacket.HEADER_SIZE + length
        val actualCrc = Crc32.compute(rawBytes, startIndex, bodyLength)

        if (actualCrc != expectedCrc) {
            return Result.Error("CRC mismatch: computed 0x${actualCrc.toString(16)}, expected 0x${expectedCrc.toString(16)}")
        }

        return Result.Success(
            AcousticPacket(
                version = version,
                type = type,
                sequenceNumber = seq,
                totalPackets = total,
                payload = payload
            )
        )
    }
}
