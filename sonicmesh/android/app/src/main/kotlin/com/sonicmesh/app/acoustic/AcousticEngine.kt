package com.sonicmesh.app.acoustic

import android.content.Context
import kotlinx.coroutines.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import kotlin.random.Random

class AcousticEngine(
    val config: AcousticConfig = AcousticConfig.DEFAULT,
    val context: Context? = null,
    private val onEvent: (Map<String, Any?>) -> Unit
) {
    enum class State {
        IDLE,
        TRANSMITTING,
        LISTENING,
        RECEIVING,
        RECOVERING,
        ERROR
    }

    val identityManager = IdentityManager(context)
    val myIdentity get() = identityManager.identity

    var currentState: State = State.IDLE
        private set(value) {
            field = value
            emitState()
        }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val modulator = Modulator(config)
    private val demodulator = Demodulator(config)
    private val signalDetector = SignalDetector(config)
    private val audioPlayer = AudioPlayer(config)
    private val audioCapture = AudioCapture(config)

    // Rolling ring buffer for incoming audio stream (30 seconds buffer, ~2.6MB)
    private val ringBufferSize = config.sampleRate * 30
    private val ringBuffer = ShortArray(ringBufferSize)
    private var ringWritePos = 0
    private var totalSamplesCaptured = 0L

    // Signal telemetry tracking for discovered peers & Range Meter
    @Volatile var lastEstimatedDistance: Double = 1.0
    @Volatile var lastSignalLevel: Double = 0.0

    // Burst reception tracking
    private var isBurstActive = false
    private var burstStartSample = 0L
    private var lastSignalSample = 0L
    private var lastDemodAttemptSample = 0L
    private var isDemodulating = false

    // ARQ & Reassembly Cache
    private class FragmentSession(
        val totalExpected: Int,
        val receivedFragments: MutableMap<Int, ByteArray> = mutableMapOf(),
        var lastReceivedTimestamp: Long = System.currentTimeMillis()
    )

    private var activeSession: FragmentSession? = null
    private val broadcastCache = mutableListOf<AcousticPacket>() // Last transmitted packets for auto-relay

    private var broadcastJob: Job? = null

    private fun emitState() {
        onEvent(
            mapOf(
                "type" to "STATE_CHANGED",
                "state" to currentState.name
            )
        )
    }

    /**
     * Encodes a string message into packet(s), modulates to PCM, and plays through speaker.
     * Supports proactive redundancy repetitions for high-noise acoustic environments.
     */
    fun broadcast(message: String, redundancyCount: Int = 1) {
        if (currentState == State.TRANSMITTING) return

        broadcastJob?.cancel()
        broadcastJob = scope.launch {
            try {
                currentState = State.TRANSMITTING
                val payload = message.toByteArray(StandardCharsets.UTF_8)
                val packet = AcousticPacket(
                    version = config.protocolVersion,
                    type = AcousticPacket.TYPE_DATA,
                    sequenceNumber = 1,
                    totalPackets = 1,
                    payload = payload
                )

                // Save to local cache so we can autonomously answer NACK / retransmission requests
                synchronized(broadcastCache) {
                    if (broadcastCache.size >= 10) broadcastCache.removeAt(0)
                    broadcastCache.add(packet)
                }

                val encodedFrame = PacketEncoder.encode(packet, config)
                val pcm = modulator.modulate(encodedFrame)

                val repetitions = redundancyCount.coerceIn(1, 3)
                onEvent(
                    mapOf(
                        "type" to "TX_STARTED",
                        "message" to message,
                        "bytes" to payload.size,
                        "repetitions" to repetitions,
                        "durationMs" to (pcm.size * 1000L / config.sampleRate) * repetitions
                    )
                )

                for (rep in 1..repetitions) {
                    audioPlayer.play(pcm) { progress ->
                        val overallProgress = ((rep - 1).toDouble() + progress) / repetitions
                        onEvent(
                            mapOf(
                                "type" to "TX_PROGRESS",
                                "progress" to overallProgress,
                                "repetition" to rep
                            )
                        )
                    }
                    if (rep < repetitions) {
                        delay(250) // Inter-frame guard pause
                    }
                }

                onEvent(
                    mapOf(
                        "type" to "TX_COMPLETED",
                        "message" to message
                    )
                )
            } catch (e: Exception) {
                currentState = State.ERROR
                onEvent(
                    mapOf(
                        "type" to "ERROR",
                        "message" to "Transmission failed: ${e.message}"
                    )
                )
            } finally {
                currentState = if (audioCapture.isCapturing) State.LISTENING else State.IDLE
            }
        }
    }

    /**
     * Broadcasts an acoustic NACK requesting retransmission of a missing chunk.
     */
    fun sendRetransmissionRequest(missingSeq: Short, total: Short) {
        scope.launch {
            try {
                val nackPacket = AcousticPacket.createRetransRequest(
                    version = config.protocolVersion,
                    missingSequence = missingSeq,
                    totalExpected = total
                )
                val frame = PacketEncoder.encode(nackPacket, config)
                val pcm = modulator.modulate(frame, amplitude = 0.90)

                onEvent(
                    mapOf(
                        "type" to "RETRANS_REQUEST_SENT",
                        "missingSequence" to missingSeq.toInt(),
                        "totalExpected" to total.toInt()
                    )
                )

                audioPlayer.play(pcm) {}
            } catch (e: Exception) {
                // Log and ignore
            }
        }
    }

    /**
     * Broadcasts an acoustic PING packet to discover nearby receivers before sending private messages.
     */
    fun sendPing(enableLoopbackSimulation: Boolean = false) {
        if (currentState == State.TRANSMITTING) return

        broadcastJob?.cancel()
        broadcastJob = scope.launch {
            try {
                currentState = State.TRANSMITTING
                val pingPacket = AcousticPacket.createPingPacket(
                    senderId = myIdentity.deviceId,
                    version = config.protocolVersion
                )
                val frame = PacketEncoder.encode(pingPacket, config)
                val pcm = modulator.modulate(frame)

                onEvent(
                    mapOf(
                        "type" to "PING_STARTED",
                        "senderId" to myIdentity.deviceId,
                        "senderHex" to myIdentity.deviceIdHex,
                        "durationMs" to (pcm.size * 1000L / config.sampleRate)
                    )
                )

                audioPlayer.play(pcm) {}

                onEvent(
                    mapOf(
                        "type" to "PING_SENT",
                        "senderId" to myIdentity.deviceId,
                        "senderHex" to myIdentity.deviceIdHex
                    )
                )

                if (enableLoopbackSimulation) {
                    delay(350)
                    val simId = 0x4B219E10
                    val simHex = "4B21-9E10"
                    onEvent(
                        mapOf(
                            "type" to "PEER_DISCOVERED",
                            "deviceId" to simId,
                            "deviceIdHex" to simHex,
                            "deviceName" to "Sonic-Echo",
                            "fingerprint" to "7A3F-C091",
                            "estimatedDistanceMeters" to 1.4,
                            "signalLevel" to 0.82
                        )
                    )
                }
            } catch (e: Exception) {
                currentState = State.ERROR
                onEvent(mapOf("type" to "ERROR", "message" to "Ping transmission failed: ${e.message}"))
            } finally {
                currentState = if (audioCapture.isCapturing) State.LISTENING else State.IDLE
            }
        }
    }

    /**
     * Sends a targeted private message addressed to a specific receiver device ID.
     */
    fun sendPrivateMessage(receiverId: Int, message: String) {
        if (currentState == State.TRANSMITTING) return

        broadcastJob?.cancel()
        broadcastJob = scope.launch {
            try {
                currentState = State.TRANSMITTING
                val msgId = (Random.nextInt(1, 32767)).toShort()
                val packet = AcousticPacket.createPrivateMessage(
                    senderId = myIdentity.deviceId,
                    receiverId = receiverId,
                    msgId = msgId,
                    textPayload = message,
                    version = config.protocolVersion
                )

                val frame = PacketEncoder.encode(packet, config)
                val pcm = modulator.modulate(frame)

                onEvent(
                    mapOf(
                        "type" to "TX_PRIVATE_STARTED",
                        "senderId" to myIdentity.deviceId,
                        "receiverId" to receiverId,
                        "msgId" to msgId.toInt(),
                        "message" to message,
                        "durationMs" to (pcm.size * 1000L / config.sampleRate)
                    )
                )

                audioPlayer.play(pcm) { progress ->
                    onEvent(
                        mapOf(
                            "type" to "TX_PROGRESS",
                            "progress" to progress
                        )
                    )
                }

                onEvent(
                    mapOf(
                        "type" to "TX_PRIVATE_SENT",
                        "senderId" to myIdentity.deviceId,
                        "receiverId" to receiverId,
                        "msgId" to msgId.toInt(),
                        "status" to "Awaiting Receiver ACK..."
                    )
                )

                // If sending to simulated test receiver (0x4B219E10), generate simulated ACK response
                if (receiverId == 0x4B219E10) {
                    delay(500)
                    onEvent(
                        mapOf(
                            "type" to "MESSAGE_DELIVERED",
                            "senderId" to myIdentity.deviceId,
                            "senderHex" to myIdentity.deviceIdHex,
                            "receiverId" to receiverId,
                            "msgId" to msgId.toInt()
                        )
                    )
                }
            } catch (e: Exception) {
                currentState = State.ERROR
                onEvent(mapOf("type" to "ERROR", "message" to "Private message transmission failed: ${e.message}"))
            } finally {
                currentState = if (audioCapture.isCapturing) State.LISTENING else State.IDLE
            }
        }
    }

    /**
     * Starts listening on the microphone and demodulates incoming FSK acoustic signals.
     */
    fun startListening() {
        if (currentState == State.LISTENING || currentState == State.RECEIVING) return

        currentState = State.LISTENING
        ringWritePos = 0
        totalSamplesCaptured = 0L
        isBurstActive = false
        burstStartSample = 0L
        lastSignalSample = 0L
        lastDemodAttemptSample = 0L
        isDemodulating = false

        audioCapture.start(
            scope,
            onAudioData = { chunk, count ->
                if (currentState == State.TRANSMITTING) {
                    return@start
                }
                val samplePosBeforeChunk = totalSamplesCaptured
                // Write into rolling ring buffer
                for (i in 0 until count) {
                    ringBuffer[ringWritePos] = chunk[i]
                    ringWritePos = (ringWritePos + 1) % ringBufferSize
                }
                totalSamplesCaptured += count

                // Continuous carrier telemetry & Range Meter
                val metrics = signalDetector.detectSignal(chunk, 0, count)
                if (metrics.hasSignal) {
                    lastEstimatedDistance = metrics.estimatedDistanceMeters
                    lastSignalLevel = metrics.signalLevel
                }

                onEvent(
                    mapOf(
                        "type" to "SIGNAL_METRICS",
                        "signalLevel" to metrics.signalLevel,
                        "rms" to metrics.rms,
                        "hasSignal" to metrics.hasSignal,
                        "estimatedDistanceMeters" to metrics.estimatedDistanceMeters,
                        "proximityZone" to metrics.proximityZone,
                        "snrDb" to metrics.snrDb,
                        "peakPower" to metrics.peakPower
                    )
                )

                // Track carrier burst lifecycle
                if (metrics.hasSignal) {
                    lastSignalSample = totalSamplesCaptured
                    if (!isBurstActive) {
                        isBurstActive = true
                        burstStartSample = (samplePosBeforeChunk - (config.sampleRate * 1.5).toLong()).coerceAtLeast(0L)
                        currentState = State.RECEIVING
                    }
                }

                if (isBurstActive) {
                    val burstDurationSamples = totalSamplesCaptured - burstStartSample
                    val silenceSamples = totalSamplesCaptured - lastSignalSample
                    val minPacketSamples = config.samplesPerSymbol * 40L

                    val carrierEnded = (silenceSamples >= (config.sampleRate * 1.0).toLong())
                    val periodicScan = (burstDurationSamples >= minPacketSamples &&
                            totalSamplesCaptured - lastDemodAttemptSample >= (config.sampleRate * 2.5).toLong())

                    if ((carrierEnded || periodicScan) && !isDemodulating) {
                        lastDemodAttemptSample = totalSamplesCaptured
                        val samplesToExtract = burstDurationSamples.coerceAtMost(ringBufferSize.toLong()).toInt()
                        val burstAudio = extractAudioWindow(samplesToExtract)

                        scope.launch(Dispatchers.Default) {
                            isDemodulating = true
                            try {
                                val packet = demodulator.demodulate(burstAudio)
                                if (packet != null) {
                                    handleReceivedPacket(packet)
                                    isBurstActive = false
                                    currentState = State.LISTENING
                                } else if (carrierEnded) {
                                    // Burst ended without valid CRC decode -> Check if partial recovery needed
                                    checkIncompleteSessionTimeout()
                                    isBurstActive = false
                                    currentState = State.LISTENING
                                }
                            } finally {
                                isDemodulating = false
                            }
                        }
                    }
                }
            },
            onError = { err ->
                currentState = State.ERROR
                onEvent(
                    mapOf(
                        "type" to "ERROR",
                        "message" to err
                    )
                )
            }
        )
    }

    private fun handleReceivedPacket(packet: AcousticPacket) {
        when (packet.type) {
            AcousticPacket.TYPE_DATA, AcousticPacket.TYPE_RETRANS_RESP -> {
                val seq = packet.sequenceNumber.toInt()
                val total = packet.totalPackets.toInt()

                if (total <= 1) {
                    // Single complete frame
                    val decodedText = String(packet.payload, StandardCharsets.UTF_8)
                    onEvent(
                        mapOf(
                            "type" to "RX_PACKET",
                            "payloadText" to decodedText,
                            "sequence" to seq,
                            "total" to total,
                            "bytes" to packet.payload.size,
                            "crcValid" to true
                        )
                    )
                } else {
                    // Multi-fragment session
                    var session = activeSession
                    if (session == null || session.totalExpected != total) {
                        session = FragmentSession(totalExpected = total)
                        activeSession = session
                    }
                    session.receivedFragments[seq] = packet.payload
                    session.lastReceivedTimestamp = System.currentTimeMillis()

                    val receivedCount = session.receivedFragments.size
                    if (receivedCount == total) {
                        // All fragments received: assemble complete message in order!
                        val totalBytes = session.receivedFragments.values.sumOf { it.size }
                        val fullPayload = ByteArray(totalBytes)
                        var destPos = 0
                        for (i in 1..total) {
                            val frag = session.receivedFragments[i] ?: ByteArray(0)
                            System.arraycopy(frag, 0, fullPayload, destPos, frag.size)
                            destPos += frag.size
                        }
                        val decodedText = String(fullPayload, StandardCharsets.UTF_8)
                        onEvent(
                            mapOf(
                                "type" to "RX_PACKET",
                                "payloadText" to decodedText,
                                "sequence" to total,
                                "total" to total,
                                "bytes" to fullPayload.size,
                                "crcValid" to true,
                                "wasReassembled" to true
                            )
                        )
                        activeSession = null
                    } else {
                        // Incomplete reception detected!
                        val missingList = (1..total).filter { !session.receivedFragments.containsKey(it) }
                        onEvent(
                            mapOf(
                                "type" to "RX_INCOMPLETE",
                                "receivedCount" to receivedCount,
                                "totalCount" to total,
                                "missingSequence" to (missingList.firstOrNull() ?: 1),
                                "allMissing" to missingList,
                                "status" to "Incomplete: $receivedCount/$total chunks received"
                            )
                        )

                        // If auto-recovery enabled, autonomously broadcast acoustic NACK
                        if (config.autoRecoveryEnabled && missingList.isNotEmpty()) {
                            val firstMissing = missingList.first().toShort()
                            scope.launch {
                                delay(350) // Backoff to avoid collision with sender tail
                                sendRetransmissionRequest(firstMissing, total.toShort())
                            }
                        }
                    }
                }
            }

            AcousticPacket.TYPE_RETRANS_REQ -> {
                // An acoustic NACK arrived from a nearby device requesting retransmission!
                if (packet.payload.size >= 4) {
                    val buf = ByteBuffer.wrap(packet.payload).order(ByteOrder.BIG_ENDIAN)
                    val missingSeq = buf.short.toInt()
                    val totalExpected = buf.short.toInt()

                    onEvent(
                        mapOf(
                            "type" to "RETRANS_REQUESTED",
                            "missingSequence" to missingSeq,
                            "totalExpected" to totalExpected
                        )
                    )

                    // Autonomously serve the retransmission if we have the packet in cache
                    synchronized(broadcastCache) {
                        val matchingPacket = broadcastCache.firstOrNull { it.sequenceNumber.toInt() == missingSeq }
                            ?: broadcastCache.firstOrNull()

                        if (matchingPacket != null) {
                            scope.launch {
                                delay(400) // Acoustic collision avoidance backoff
                                try {
                                    val respPacket = AcousticPacket(
                                        version = matchingPacket.version,
                                        type = AcousticPacket.TYPE_RETRANS_RESP,
                                        sequenceNumber = matchingPacket.sequenceNumber,
                                        totalPackets = matchingPacket.totalPackets,
                                        payload = matchingPacket.payload
                                    )
                                    val frame = PacketEncoder.encode(respPacket, config)
                                    val pcm = modulator.modulate(frame)
                                    audioPlayer.play(pcm) {}

                                    onEvent(
                                        mapOf(
                                            "type" to "RETRANS_SERVED",
                                            "sequence" to respPacket.sequenceNumber.toInt(),
                                            "bytes" to respPacket.payload.size
                                        )
                                    )
                                } catch (_: Exception) {}
                            }
                        }
                    }
                }
            }

            AcousticPacket.TYPE_PING -> {
                val pingSenderId = AcousticPacket.parsePing(packet)
                if (pingSenderId != null && pingSenderId != myIdentity.deviceId) {
                    onEvent(
                        mapOf(
                            "type" to "PING_RECEIVED",
                            "senderId" to pingSenderId,
                            "senderHex" to String.format("%08X", pingSenderId).let { it.substring(0, 4) + "-" + it.substring(4) }
                        )
                    )

                    // Autonomously respond with PONG containing identity and key fingerprint
                    scope.launch {
                        delay(250L + Random.nextLong(200)) // Acoustic collision backoff
                        try {
                            val pongPacket = AcousticPacket.createPongPacket(
                                targetSenderId = pingSenderId,
                                responderId = myIdentity.deviceId,
                                fingerprint = myIdentity.fingerprintInt,
                                deviceName = myIdentity.deviceName,
                                version = config.protocolVersion
                            )
                            val frame = PacketEncoder.encode(pongPacket, config)
                            val pcm = modulator.modulate(frame)
                            audioPlayer.play(pcm) {}

                            onEvent(
                                mapOf(
                                    "type" to "PONG_SENT",
                                    "targetSenderId" to pingSenderId,
                                    "responderId" to myIdentity.deviceId
                                )
                            )
                        } catch (_: Exception) {}
                    }
                }
            }

            AcousticPacket.TYPE_PONG -> {
                val pongData = AcousticPacket.parsePong(packet)
                if (pongData != null) {
                    // Only process if addressed to me or general discovery
                    if (pongData.targetSenderId == myIdentity.deviceId || pongData.targetSenderId == 0) {
                        onEvent(
                            mapOf(
                                "type" to "PEER_DISCOVERED",
                                "deviceId" to pongData.responderId,
                                "deviceIdHex" to pongData.responderHex,
                                "deviceName" to pongData.deviceName,
                                "fingerprint" to pongData.fingerprintHex,
                                "estimatedDistanceMeters" to lastEstimatedDistance,
                                "signalLevel" to lastSignalLevel
                            )
                        )
                    }
                }
            }

            AcousticPacket.TYPE_PRIVATE_MESSAGE -> {
                val msgData = AcousticPacket.parsePrivateMessage(packet)
                if (msgData != null) {
                    if (msgData.receiverId == myIdentity.deviceId) {
                        // Targeted to ME! Decrypt and display
                        val senderHex = String.format("%08X", msgData.senderId).let { it.substring(0, 4) + "-" + it.substring(4) }
                        onEvent(
                            mapOf(
                                "type" to "RX_PRIVATE_MESSAGE",
                                "senderId" to msgData.senderId,
                                "senderHex" to senderHex,
                                "receiverId" to msgData.receiverId,
                                "msgId" to msgData.msgId.toInt(),
                                "payloadText" to msgData.text,
                                "crcValid" to true
                            )
                        )

                        // Autonomously reply with signed acoustic ACK
                        scope.launch {
                            delay(300L + Random.nextLong(150)) // Backoff to allow sender to release mic
                            try {
                                val ackPacket = AcousticPacket.createAckPacket(
                                    senderId = myIdentity.deviceId,
                                    receiverId = msgData.senderId,
                                    msgId = msgData.msgId,
                                    version = config.protocolVersion
                                )
                                val frame = PacketEncoder.encode(ackPacket, config)
                                val pcm = modulator.modulate(frame)
                                audioPlayer.play(pcm) {}

                                onEvent(
                                    mapOf(
                                        "type" to "ACK_SENT",
                                        "senderId" to myIdentity.deviceId,
                                        "receiverId" to msgData.senderId,
                                        "msgId" to msgData.msgId.toInt()
                                    )
                                )
                            } catch (_: Exception) {}
                        }
                    } else {
                        // Unicast message addressed to another device: IGNORE
                        onEvent(
                            mapOf(
                                "type" to "RX_PRIVATE_IGNORED",
                                "receiverId" to msgData.receiverId,
                                "myId" to myIdentity.deviceId,
                                "reason" to "Unicast target mismatch (intended for another device)"
                            )
                        )
                    }
                }
            }

            AcousticPacket.TYPE_ACK -> {
                val ackData = AcousticPacket.parseAck(packet)
                if (ackData != null) {
                    // Check if this ACK is addressed to me (I was the sender)
                    if (ackData.receiverId == myIdentity.deviceId) {
                        val responderHex = String.format("%08X", ackData.senderId).let { it.substring(0, 4) + "-" + it.substring(4) }
                        onEvent(
                            mapOf(
                                "type" to "MESSAGE_DELIVERED",
                                "senderId" to ackData.senderId,
                                "senderHex" to responderHex,
                                "receiverId" to ackData.receiverId,
                                "msgId" to ackData.msgId.toInt(),
                                "status" to "DELIVERED [VERIFIED ACK]"
                            )
                        )
                    }
                }
            }
        }
    }

    private fun checkIncompleteSessionTimeout() {
        val session = activeSession ?: return
        if (System.currentTimeMillis() - session.lastReceivedTimestamp > config.retransmissionTimeoutMs) {
            val missingList = (1..session.totalExpected).filter { !session.receivedFragments.containsKey(it) }
            if (missingList.isNotEmpty()) {
                onEvent(
                    mapOf(
                        "type" to "RX_INCOMPLETE_TIMEOUT",
                        "missingSequence" to missingList.first(),
                        "receivedCount" to session.receivedFragments.size,
                        "totalCount" to session.totalExpected
                    )
                )
            }
        }
    }

    private fun extractAudioWindow(samplesToRead: Int): ShortArray {
        val windowSize = samplesToRead.coerceAtMost(ringBufferSize).coerceAtMost(totalSamplesCaptured.toInt())
        val linear = ShortArray(windowSize)
        var readPos = (ringWritePos - windowSize + ringBufferSize) % ringBufferSize
        for (i in 0 until windowSize) {
            linear[i] = ringBuffer[readPos]
            readPos = (readPos + 1) % ringBufferSize
        }
        return linear
    }

    fun stopListening() {
        audioCapture.stop()
        isBurstActive = false
        if (currentState == State.LISTENING || currentState == State.RECEIVING || currentState == State.RECOVERING) {
            currentState = State.IDLE
        }
    }

    fun stopAll() {
        broadcastJob?.cancel()
        audioPlayer.stop()
        audioCapture.stop()
        isBurstActive = false
        currentState = State.IDLE
    }

    fun runLoopbackTest(testMessage: String = "SonicMesh Offline Acoustic Test 001"): Map<String, Any> {
        val startTime = System.currentTimeMillis()
        val payload = testMessage.toByteArray(StandardCharsets.UTF_8)
        val packet = AcousticPacket(
            version = config.protocolVersion,
            type = AcousticPacket.TYPE_DATA,
            sequenceNumber = 1,
            totalPackets = 1,
            payload = payload
        )

        val frame = PacketEncoder.encode(packet, config)
        val pcm = modulator.modulate(frame)
        val demodPacket = demodulator.demodulate(pcm)

        val endTime = System.currentTimeMillis()
        val durationMs = endTime - startTime

        val decodedText = demodPacket?.let { String(it.payload, StandardCharsets.UTF_8) } ?: ""
        val success = (decodedText == testMessage)

        return mapOf(
            "success" to success,
            "original" to testMessage,
            "decoded" to decodedText,
            "pcmSamples" to pcm.size,
            "elapsedMs" to durationMs,
            "f0" to config.f0,
            "f1" to config.f1,
            "symbolDurationMs" to config.symbolDurationMs,
            "baud" to (1000 / config.symbolDurationMs)
        )
    }

    fun getDiagnostics(): Map<String, Any> {
        return mapOf(
            "deviceId" to myIdentity.deviceId,
            "deviceIdHex" to myIdentity.deviceIdHex,
            "deviceName" to myIdentity.deviceName,
            "fingerprint" to myIdentity.publicKeyFingerprint,
            "sampleRate" to config.sampleRate,
            "f0" to config.f0,
            "f1" to config.f1,
            "symbolDurationMs" to config.symbolDurationMs,
            "baudRate" to (1000 / config.symbolDurationMs),
            "preambleCount" to config.preambleCount,
            "state" to currentState.name,
            "totalSamplesCaptured" to totalSamplesCaptured,
            "autoRecoveryEnabled" to config.autoRecoveryEnabled,
            "cachedPacketsCount" to broadcastCache.size
        )
    }
}
