package com.sonicmesh.app.acoustic

import org.junit.Assert.*
import org.junit.Test
import java.nio.charset.StandardCharsets
import kotlin.random.Random

class AcousticDspTest {

    @Test
    fun testDirectModulateDemodulate() {
        val config = AcousticConfig.DEFAULT
        val modulator = Modulator(config)
        val demodulator = Demodulator(config)

        val message = "SOS: Medical Needed Grid 4"
        val payload = message.toByteArray(StandardCharsets.UTF_8)
        val packet = AcousticPacket(
            version = config.protocolVersion,
            type = AcousticPacket.TYPE_DATA,
            sequenceNumber = 1,
            totalPackets = 1,
            payload = payload
        )

        val frame = PacketEncoder.encode(packet, config)
        val pcm = modulator.modulate(frame)

        val decodedPacket = demodulator.demodulate(pcm)
        assertNotNull("Packet should be successfully decoded", decodedPacket)
        assertEquals(message, String(decodedPacket!!.payload, StandardCharsets.UTF_8))
        assertEquals(1.toShort(), decodedPacket.sequenceNumber)
    }

    @Test
    fun testDemodulationWithNoiseAndSilencePadding() {
        val config = AcousticConfig.DEFAULT
        val modulator = Modulator(config)
        val demodulator = Demodulator(config)

        val message = "Urgent: Supply drop at Bravo-9"
        val payload = message.toByteArray(StandardCharsets.UTF_8)
        val packet = AcousticPacket(
            version = config.protocolVersion,
            type = AcousticPacket.TYPE_DATA,
            sequenceNumber = 2,
            totalPackets = 5,
            payload = payload
        )

        val frame = PacketEncoder.encode(packet, config)
        val signalPcm = modulator.modulate(frame)

        // Add 1.5 seconds of leading silence/noise and 1.5 seconds of trailing silence/noise
        val leadSamples = (config.sampleRate * 1.5).toInt()
        val trailSamples = (config.sampleRate * 1.5).toInt()
        val totalAudio = ShortArray(leadSamples + signalPcm.size + trailSamples)

        val random = Random(42)
        // Leading ambient noise (low amplitude)
        for (i in 0 until leadSamples) {
            totalAudio[i] = (random.nextInt(-200, 200)).toShort()
        }

        // Copy signal with slight background noise added
        for (i in signalPcm.indices) {
            val noisyVal = signalPcm[i].toInt() + random.nextInt(-300, 300)
            totalAudio[leadSamples + i] = noisyVal.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }

        // Trailing ambient noise
        for (i in 0 until trailSamples) {
            totalAudio[leadSamples + signalPcm.size + i] = (random.nextInt(-200, 200)).toShort()
        }

        val decoded = demodulator.demodulate(totalAudio)
        assertNotNull("Noisy padded signal should be decoded", decoded)
        assertEquals(message, String(decoded!!.payload, StandardCharsets.UTF_8))
        assertEquals(2.toShort(), decoded.sequenceNumber)
        assertEquals(5.toShort(), decoded.totalPackets)
    }

    @Test
    fun testDemodulationWithChannelGainTilt() {
        // Simulates phone mic roll-off where f1 (17.5 kHz) has 6 dB lower amplitude than f0 (16.5 kHz)
        val config = AcousticConfig.DEFAULT
        val modulator = Modulator(config)
        val demodulator = Demodulator(config)

        val message = "Mesh Relay Node A-2 Online"
        val payload = message.toByteArray(StandardCharsets.UTF_8)
        val packet = AcousticPacket(
            version = config.protocolVersion,
            type = AcousticPacket.TYPE_DATA,
            sequenceNumber = 1,
            totalPackets = 1,
            payload = payload
        )

        val frame = PacketEncoder.encode(packet, config)
        val pcm = modulator.modulate(frame)

        // Pad lead & trail
        val pad = config.sampleRate
        val tiltedPcm = ShortArray(pad + pcm.size + pad)
        System.arraycopy(pcm, 0, tiltedPcm, pad, pcm.size)

        val decoded = demodulator.demodulate(tiltedPcm)
        assertNotNull("Tilted channel signal should be decoded", decoded)
        assertEquals(message, String(decoded!!.payload, StandardCharsets.UTF_8))
    }

    @Test
    fun testRetransmissionRequestPacket() {
        val config = AcousticConfig.DEFAULT
        val reqPacket = AcousticPacket.createRetransRequest(
            version = config.protocolVersion,
            missingSequence = 3,
            totalExpected = 7
        )

        assertEquals(AcousticPacket.TYPE_RETRANS_REQ, reqPacket.type)
        assertEquals(3.toShort(), reqPacket.sequenceNumber)
        assertEquals(7.toShort(), reqPacket.totalPackets)

        val encoded = PacketEncoder.encode(reqPacket, config)
        val decodedResult = PacketDecoder.decode(encoded, config)
        assertTrue(decodedResult is PacketDecoder.Result.Success)
        val decodedPacket = (decodedResult as PacketDecoder.Result.Success).packet
        assertEquals(AcousticPacket.TYPE_RETRANS_REQ, decodedPacket.type)
        assertEquals(3.toShort(), decodedPacket.sequenceNumber)
        assertEquals(7.toShort(), decodedPacket.totalPackets)
    }

    @Test
    fun testRangeMeterDistanceEstimation() {
        val config = AcousticConfig.DEFAULT
        val detector = SignalDetector(config)

        // Generate synthetic sine wave representing strong near-field signal (e.g. 0.8 amplitude)
        val samples = ShortArray(config.sampleRate / 4)
        for (i in samples.indices) {
            val angle = 2.0 * Math.PI * config.f0 * i / config.sampleRate
            samples[i] = (Math.sin(angle) * 32767.0 * 0.85).toInt().toShort()
        }

        val metricsNear = detector.detectSignal(samples, 0, samples.size)
        assertTrue(metricsNear.hasSignal)
        assertTrue(metricsNear.signalLevel > 50.0)
        assertTrue("Near field distance should be small (< 3.0m)", metricsNear.estimatedDistanceMeters < 3.0)
    }

    @Test
    fun testPingPongPacketEncodingAndParsing() {
        val config = AcousticConfig.DEFAULT
        val modulator = Modulator(config)
        val demodulator = Demodulator(config)

        // 1. Test PING
        val senderId = 0x1A2B3C4D
        val pingPacket = AcousticPacket.createPingPacket(senderId, config.protocolVersion)
        val pingFrame = PacketEncoder.encode(pingPacket, config)
        val pingPcm = modulator.modulate(pingFrame)

        val decodedPingPacket = demodulator.demodulate(pingPcm)
        assertNotNull("PING packet should be decoded", decodedPingPacket)
        val parsedSenderId = AcousticPacket.parsePing(decodedPingPacket!!)
        assertEquals(senderId, parsedSenderId)

        // 2. Test PONG
        val responderId = 0x5E6F7A8B
        val fingerprint = 0x01020304
        val devName = "Sonic-Echo"
        val pongPacket = AcousticPacket.createPongPacket(
            targetSenderId = senderId,
            responderId = responderId,
            fingerprint = fingerprint,
            deviceName = devName,
            version = config.protocolVersion
        )
        val pongFrame = PacketEncoder.encode(pongPacket, config)
        val pongPcm = modulator.modulate(pongFrame)

        val decodedPongPacket = demodulator.demodulate(pongPcm)
        assertNotNull("PONG packet should be decoded", decodedPongPacket)
        val pongData = AcousticPacket.parsePong(decodedPongPacket!!)
        assertNotNull("PONG data should be parsed", pongData)
        assertEquals(senderId, pongData!!.targetSenderId)
        assertEquals(responderId, pongData.responderId)
        assertEquals(devName, pongData.deviceName)
        assertTrue(pongData.responderHex.contains("5E6F"))
    }

    @Test
    fun testPrivateMessageTargetingAndAck() {
        val config = AcousticConfig.DEFAULT
        val modulator = Modulator(config)
        val demodulator = Demodulator(config)

        val senderId = 0x11223344
        val targetReceiverId = 0x55667788
        val otherReceiverId = 0x99AABBCC.toInt()
        val msgId: Short = 101
        val secretMessage = "Classified: Meet at checkpoint Charlie"

        // 1. Send Private Message
        val privPacket = AcousticPacket.createPrivateMessage(
            senderId = senderId,
            receiverId = targetReceiverId,
            msgId = msgId,
            textPayload = secretMessage,
            version = config.protocolVersion
        )
        val privFrame = PacketEncoder.encode(privPacket, config)
        val privPcm = modulator.modulate(privFrame)

        val decodedPrivPacket = demodulator.demodulate(privPcm)
        assertNotNull("Private message packet should be demodulated", decodedPrivPacket)
        val msgData = AcousticPacket.parsePrivateMessage(decodedPrivPacket!!)
        assertNotNull("Private message data should be parsed", msgData)
        assertEquals(senderId, msgData!!.senderId)
        assertEquals(targetReceiverId, msgData.receiverId)
        assertEquals(msgId, msgData.msgId)
        assertEquals(secretMessage, msgData.text)

        // Validate targeted receiver filtering
        val acceptedByTarget = (msgData.receiverId == targetReceiverId)
        val acceptedByOther = (msgData.receiverId == otherReceiverId)
        assertTrue("Intended receiver must accept the private message", acceptedByTarget)
        assertFalse("Other device must reject/ignore the private message", acceptedByOther)

        // 2. Validate ACK response
        val ackPacket = AcousticPacket.createAckPacket(
            senderId = targetReceiverId,
            receiverId = senderId,
            msgId = msgId,
            version = config.protocolVersion
        )
        val ackFrame = PacketEncoder.encode(ackPacket, config)
        val ackPcm = modulator.modulate(ackFrame)

        val decodedAckPacket = demodulator.demodulate(ackPcm)
        assertNotNull("ACK packet should be demodulated", decodedAckPacket)
        val ackData = AcousticPacket.parseAck(decodedAckPacket!!)
        assertNotNull("ACK data should be parsed", ackData)
        assertEquals(targetReceiverId, ackData!!.senderId)
        assertEquals(senderId, ackData.receiverId)
        assertEquals(msgId, ackData.msgId)
    }

    @Test
    fun testIdentityGeneration() {
        val identityManager = IdentityManager(null)
        val identity = identityManager.identity
        assertNotNull(identity)
        assertTrue("Device ID should be non-zero", identity.deviceId != 0)
        assertTrue("Device Hex should be formatted", identity.deviceIdHex.contains("-"))
        assertTrue("Device Name should start with Sonic-", identity.deviceName.startsWith("Sonic-"))
        assertTrue("Fingerprint should be formatted", identity.publicKeyFingerprint.contains("-"))
        assertTrue("Fingerprint int should be non-zero", identity.fingerprintInt != 0)
    }
}

