package com.sonicmesh.app.acoustic

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets

data class AcousticPacket(
    val version: Byte = 1,
    val type: Byte = TYPE_DATA,
    val sequenceNumber: Short = 1,
    val totalPackets: Short = 1,
    val payload: ByteArray
) {
    data class ImageStartData(
        val imageId: Int,
        val width: Short,
        val height: Short,
        val fileSize: Int,
        val format: Byte,
        val totalChunks: Short,
        val chunkSize: Short
    )

    data class ImageChunkData(
        val imageId: Int,
        val chunkIndex: Short,
        val totalChunks: Short,
        val chunkData: ByteArray
    )

    data class ImageEndData(
        val imageId: Int,
        val totalChunks: Short,
        val imageCrc32: Int
    )

    companion object {
        const val TYPE_DATA: Byte = 0x01
        const val TYPE_PING: Byte = 0x02
        const val TYPE_ACK: Byte = 0x03
        const val TYPE_RETRANS_REQ: Byte = 0x04   // NACK: requesting retransmission
        const val TYPE_RETRANS_RESP: Byte = 0x05  // ARQ response
        const val TYPE_PONG: Byte = 0x06          // Peer discovery response
        const val TYPE_PRIVATE_MESSAGE: Byte = 0x07 // Targeted unicast message
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

        /**
         * Creates an acoustic PING packet broadcasted to discover nearby receivers.
         */
        fun createPingPacket(senderId: Int, version: Byte = 1): AcousticPacket {
            val payload = ByteArray(6)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(senderId)
            buf.putShort(1.toShort()) // Nonce / Ping seq
            return AcousticPacket(
                version = version,
                type = TYPE_PING,
                sequenceNumber = 1,
                totalPackets = 1,
                payload = payload
            )
        }

        fun parsePing(packet: AcousticPacket): Int? {
            if (packet.type != TYPE_PING || packet.payload.size < 4) return null
            val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
            return buf.int
        }

        /**
         * Creates an acoustic PONG response containing device identity, key fingerprint, and name.
         */
        fun createPongPacket(
            targetSenderId: Int,
            responderId: Int,
            fingerprint: Int,
            deviceName: String,
            version: Byte = 1
        ): AcousticPacket {
            val nameBytes = deviceName.toByteArray(StandardCharsets.UTF_8).let {
                if (it.size > 12) it.copyOfRange(0, 12) else it
            }
            val payload = ByteArray(4 + 4 + 4 + 1 + nameBytes.size)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(targetSenderId)
            buf.putInt(responderId)
            buf.putInt(fingerprint)
            buf.put(nameBytes.size.toByte())
            buf.put(nameBytes)

            return AcousticPacket(
                version = version,
                type = TYPE_PONG,
                sequenceNumber = 1,
                totalPackets = 1,
                payload = payload
            )
        }

        data class PongData(
            val targetSenderId: Int,
            val responderId: Int,
            val responderHex: String,
            val fingerprintHex: String,
            val deviceName: String
        )

        fun parsePong(packet: AcousticPacket): PongData? {
            if (packet.type != TYPE_PONG || packet.payload.size < 13) return null
            val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
            val targetSenderId = buf.int
            val responderId = buf.int
            val fingerprint = buf.int
            val nameLen = buf.get().toInt() and 0xFF
            if (buf.remaining() < nameLen) return null
            val nameBytes = ByteArray(nameLen)
            buf.get(nameBytes)
            val name = String(nameBytes, StandardCharsets.UTF_8)

            val hex = String.format("%08X", responderId)
            val shortHex = hex.substring(0, 4) + "-" + hex.substring(4)
            val fp = String.format("%08X", fingerprint)
            val fpFormatted = fp.substring(0, 4) + "-" + fp.substring(4)

            return PongData(
                targetSenderId = targetSenderId,
                responderId = responderId,
                responderHex = shortHex,
                fingerprintHex = fpFormatted,
                deviceName = name
            )
        }

        /**
         * Creates a targeted private message addressed to a specific Receiver Device ID.
         */
        fun createPrivateMessage(
            senderId: Int,
            receiverId: Int,
            msgId: Short,
            textPayload: String,
            version: Byte = 1
        ): AcousticPacket {
            val textBytes = textPayload.toByteArray(StandardCharsets.UTF_8)
            val payload = ByteArray(4 + 4 + 2 + textBytes.size)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(senderId)
            buf.putInt(receiverId)
            buf.putShort(msgId)
            buf.put(textBytes)

            return AcousticPacket(
                version = version,
                type = TYPE_PRIVATE_MESSAGE,
                sequenceNumber = 1,
                totalPackets = 1,
                payload = payload
            )
        }

        data class PrivateMessageData(
            val senderId: Int,
            val receiverId: Int,
            val msgId: Short,
            val text: String
        )

        fun parsePrivateMessage(packet: AcousticPacket): PrivateMessageData? {
            if (packet.type != TYPE_PRIVATE_MESSAGE || packet.payload.size < 10) return null
            val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
            val senderId = buf.int
            val receiverId = buf.int
            val msgId = buf.short
            val textBytes = ByteArray(buf.remaining())
            buf.get(textBytes)
            val text = String(textBytes, StandardCharsets.UTF_8)

            return PrivateMessageData(
                senderId = senderId,
                receiverId = receiverId,
                msgId = msgId,
                text = text
            )
        }

        /**
         * Creates an acoustic delivery ACK packet confirming receipt and decryption.
         */
        fun createAckPacket(
            senderId: Int,
            receiverId: Int,
            msgId: Short,
            version: Byte = 1
        ): AcousticPacket {
            val payload = ByteArray(4 + 4 + 2)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(senderId)
            buf.putInt(receiverId)
            buf.putShort(msgId)

            return AcousticPacket(
                version = version,
                type = TYPE_ACK,
                sequenceNumber = 1,
                totalPackets = 1,
                payload = payload
            )
        }

        data class AckData(
            val senderId: Int,
            val receiverId: Int,
            val msgId: Short
        )

        fun parseAck(packet: AcousticPacket): AckData? {
            if (packet.type != TYPE_ACK || packet.payload.size < 10) return null
            val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
            val senderId = buf.int
            val receiverId = buf.int
            val msgId = buf.short
            return AckData(
                senderId = senderId,
                receiverId = receiverId,
                msgId = msgId
            )
        }

        const val TYPE_IMAGE_START: Byte = 0x10
        const val TYPE_IMAGE_CHUNK: Byte = 0x11
        const val TYPE_IMAGE_END: Byte = 0x12

        const val FORMAT_WEBP: Byte = 0x01
        const val FORMAT_JPEG: Byte = 0x02
        const val FORMAT_PNG: Byte = 0x03


        fun createImageStartPacket(
            imageId: Int,
            width: Short,
            height: Short,
            fileSize: Int,
            format: Byte = FORMAT_WEBP,
            totalChunks: Short,
            chunkSize: Short = 48,
            version: Byte = 1
        ): AcousticPacket {
            val payload = ByteArray(4 + 2 + 2 + 4 + 1 + 2 + 2)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(imageId)
            buf.putShort(width)
            buf.putShort(height)
            buf.putInt(fileSize)
            buf.put(format)
            buf.putShort(totalChunks)
            buf.putShort(chunkSize)

            return AcousticPacket(
                version = version,
                type = TYPE_IMAGE_START,
                sequenceNumber = 1,
                totalPackets = totalChunks,
                payload = payload
            )
        }

        fun parseImageStart(packet: AcousticPacket): ImageStartData? {
            if (packet.type != TYPE_IMAGE_START || packet.payload.size < 17) return null
            val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
            val imageId = buf.int
            val width = buf.short
            val height = buf.short
            val fileSize = buf.int
            val format = buf.get()
            val totalChunks = buf.short
            val chunkSize = buf.short
            return ImageStartData(
                imageId = imageId,
                width = width,
                height = height,
                fileSize = fileSize,
                format = format,
                totalChunks = totalChunks,
                chunkSize = chunkSize
            )
        }

        fun createImageChunkPacket(
            imageId: Int,
            chunkIndex: Short,
            totalChunks: Short,
            chunkData: ByteArray,
            version: Byte = 1
        ): AcousticPacket {
            val payload = ByteArray(4 + 2 + 2 + chunkData.size)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(imageId)
            buf.putShort(chunkIndex)
            buf.putShort(chunkData.size.toShort())
            buf.put(chunkData)

            return AcousticPacket(
                version = version,
                type = TYPE_IMAGE_CHUNK,
                sequenceNumber = chunkIndex,
                totalPackets = totalChunks,
                payload = payload
            )
        }

        fun parseImageChunk(packet: AcousticPacket): ImageChunkData? {
            if (packet.type != TYPE_IMAGE_CHUNK || packet.payload.size < 8) return null
            val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
            val imageId = buf.int
            val chunkIndex = buf.short
            val len = buf.short.toInt() and 0xFFFF
            if (buf.remaining() < len) return null
            val data = ByteArray(len)
            buf.get(data)
            return ImageChunkData(
                imageId = imageId,
                chunkIndex = chunkIndex,
                totalChunks = packet.totalPackets,
                chunkData = data
            )
        }

        fun createImageEndPacket(
            imageId: Int,
            totalChunks: Short,
            imageCrc32: Int,
            version: Byte = 1
        ): AcousticPacket {
            val payload = ByteArray(4 + 2 + 4)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(imageId)
            buf.putShort(totalChunks)
            buf.putInt(imageCrc32)

            return AcousticPacket(
                version = version,
                type = TYPE_IMAGE_END,
                sequenceNumber = totalChunks,
                totalPackets = totalChunks,
                payload = payload
            )
        }

        fun parseImageEnd(packet: AcousticPacket): ImageEndData? {
            if (packet.type != TYPE_IMAGE_END || packet.payload.size < 10) return null
            val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
            val imageId = buf.int
            val totalChunks = buf.short
            val imageCrc32 = buf.int
            return ImageEndData(
                imageId = imageId,
                totalChunks = totalChunks,
                imageCrc32 = imageCrc32
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
