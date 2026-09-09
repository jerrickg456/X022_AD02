package com.sonicmesh.app.acoustic

import android.content.Context
import kotlinx.coroutines.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
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
    val imageTransferManager: ImageTransferManager? = context?.let { ImageTransferManager(it, onEvent) }

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

    // Acoustic Relay Mode & Deduplication state
    var isRelayMode: Boolean = false
        private set
    var relayGuardDelayMs: Long = 500L
    var relayRepetitions: Int = 1
    var relayPrivateEnabled: Boolean = true

    data class RelayStats(
        var packetsCaptured: Int = 0,
        var packetsVerified: Int = 0,
        var packetsRetransmitted: Int = 0,
        var duplicatesSuppressed: Int = 0
    )
    val relayStats = RelayStats()

    // Signatures of packets recently transmitted or relayed to prevent acoustic feedback/loops
    private val seenPacketSignatures = ConcurrentHashMap<Long, Long>()

    private fun computePacketSignature(packet: AcousticPacket): Long {
        val payloadCrc = Crc32.compute(packet.payload)
        return (packet.type.toLong() and 0xFFL shl 48) or
               (packet.sequenceNumber.toLong() and 0xFFFFL shl 32) or
               (payloadCrc and 0xFFFFFFFFL)
    }

    private fun markSignatureSeen(sig: Long) {
        val now = System.currentTimeMillis()
        seenPacketSignatures[sig] = now
        if (seenPacketSignatures.size > 300) {
            val cutoff = now - 60_000L
            seenPacketSignatures.entries.removeIf { it.value < cutoff }
        }
    }

    private fun isSignatureRecentlySeen(sig: Long, windowMs: Long = 45_000L): Boolean {
        val now = System.currentTimeMillis()
        val lastSeen = seenPacketSignatures[sig] ?: return false
        return (now - lastSeen) < windowMs
    }

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

                // Track signature so this node never relays its own broadcast
                val sig = computePacketSignature(packet)
                markSignatureSeen(sig)

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

                // Track signature so this node never relays its own private message
                val sig = computePacketSignature(packet)
                markSignatureSeen(sig)

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
                        "message" to message,
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

                    // If Relay Mode is active, forward the verified message
                    if (isRelayMode) {
                        triggerRelay(packet, decodedText)
                    }
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
                    val pingSenderHex = String.format("%08X", pingSenderId).let { it.substring(0, 4) + "-" + it.substring(4) }
                    val pingSenderName = "Sonic-" + String.format("%08X", pingSenderId).substring(0, 4)

                    onEvent(
                        mapOf(
                            "type" to "PING_RECEIVED",
                            "senderId" to pingSenderId,
                            "senderHex" to pingSenderHex
                        )
                    )

                    // Autonomously register the transmitter as a discovered peer!
                    onEvent(
                        mapOf(
                            "type" to "PEER_DISCOVERED",
                            "deviceId" to pingSenderId,
                            "deviceIdHex" to pingSenderHex,
                            "deviceName" to pingSenderName,
                            "fingerprint" to "Acoustic-Ping",
                            "estimatedDistanceMeters" to lastEstimatedDistance,
                            "signalLevel" to lastSignalLevel
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
                if (pongData != null && pongData.responderId != myIdentity.deviceId) {
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

            AcousticPacket.TYPE_PRIVATE_MESSAGE -> {
                val msgData = AcousticPacket.parsePrivateMessage(packet)
                if (msgData != null) {
                    val senderHex = String.format("%08X", msgData.senderId).let { it.substring(0, 4) + "-" + it.substring(4) }
                    val senderName = "Sonic-" + String.format("%08X", msgData.senderId).substring(0, 4)

                    // Register sender as a peer
                    onEvent(
                        mapOf(
                            "type" to "PEER_DISCOVERED",
                            "deviceId" to msgData.senderId,
                            "deviceIdHex" to senderHex,
                            "deviceName" to senderName,
                            "fingerprint" to "Air-Gap",
                            "estimatedDistanceMeters" to lastEstimatedDistance,
                            "signalLevel" to lastSignalLevel
                        )
                    )

                    if (msgData.receiverId == myIdentity.deviceId) {
                        // Targeted to ME! Decrypt and display
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
                        // Unicast message addressed to another device
                        onEvent(
                            mapOf(
                                "type" to "RX_PRIVATE_IGNORED",
                                "receiverId" to msgData.receiverId,
                                "myId" to myIdentity.deviceId,
                                "reason" to "Unicast target mismatch (intended for another device)"
                            )
                        )

                        // If relay is active, relay the private message towards target
                        if (isRelayMode && relayPrivateEnabled) {
                            triggerRelay(packet, "[Private to ${String.format("%08X", msgData.receiverId)}]: ${msgData.text}")
                        }
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
                    } else if (isRelayMode && relayPrivateEnabled) {
                        // Relay delivery ACK back towards original sender
                        triggerRelay(packet, "[ACK for ${String.format("%08X", ackData.receiverId)}]")
                    }
                }
            }

            AcousticPacket.TYPE_IMAGE_START -> {
                val startData = AcousticPacket.parseImageStart(packet)
                if (startData != null) {
                    imageTransferManager?.handleImageStart(startData)
                    if (isRelayMode) {
                        triggerRelay(packet, "[Image #${startData.imageId} Start: ${startData.width}x${startData.height}]")
                    }
                }
            }

            AcousticPacket.TYPE_IMAGE_CHUNK -> {
                val chunkData = AcousticPacket.parseImageChunk(packet)
                if (chunkData != null) {
                    imageTransferManager?.handleImageChunk(chunkData)
                    if (isRelayMode) {
                        triggerRelay(packet, "[Image #${chunkData.imageId} Chunk ${chunkData.chunkIndex}/${chunkData.totalChunks}]")
                    }
                }
            }

            AcousticPacket.TYPE_IMAGE_END -> {
                val endData = AcousticPacket.parseImageEnd(packet)
                if (endData != null) {
                    imageTransferManager?.handleImageEnd(endData)
                    if (isRelayMode) {
                        triggerRelay(packet, "[Image #${endData.imageId} End]")
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

    /**
     * Acoustic Relay core pipeline:
     * Receives verified packet -> Checks deduplication cache -> Waits turnaround guard delay
     * -> Synthesizes fresh CPFSK audio waveform -> Transmits through speaker.
     */
    fun triggerRelay(packet: AcousticPacket, decodedSummary: String) {
        if (!isRelayMode) return
        relayStats.packetsCaptured++
        relayStats.packetsVerified++

        val sig = computePacketSignature(packet)
        if (isSignatureRecentlySeen(sig)) {
            relayStats.duplicatesSuppressed++
            onEvent(
                mapOf(
                    "type" to "RELAY_DUPLICATE_SUPPRESSED",
                    "payloadText" to decodedSummary,
                    "reason" to "Recently seen or locally originated (loop prevented)",
                    "stats" to getRelayStats()
                )
            )
            return
        }

        markSignatureSeen(sig)

        onEvent(
            mapOf(
                "type" to "RELAY_PACKET_QUEUED",
                "payloadText" to decodedSummary,
                "bytes" to packet.payload.size,
                "guardDelayMs" to relayGuardDelayMs,
                "signalLevel" to lastSignalLevel,
                "estimatedDistanceMeters" to lastEstimatedDistance,
                "stats" to getRelayStats()
            )
        )

        scope.launch {
            try {
                // Guard pause to allow channel clearance and prevent self-interference
                delay(relayGuardDelayMs)

                // Wait if another audio burst is playing
                while (currentState == State.TRANSMITTING) {
                    delay(100)
                }

                currentState = State.TRANSMITTING

                // Synthesize fresh CPFSK audio waveform from scratch (NEVER amplify/replay mic audio!)
                val frame = PacketEncoder.encode(packet, config)
                val pcm = modulator.modulate(frame, amplitude = 1.0)
                val durationMs = pcm.size * 1000L / config.sampleRate

                onEvent(
                    mapOf(
                        "type" to "RELAY_TX_STARTED",
                        "payloadText" to decodedSummary,
                        "bytes" to packet.payload.size,
                        "durationMs" to durationMs,
                        "repetitions" to relayRepetitions,
                        "stats" to getRelayStats()
                    )
                )

                for (rep in 1..relayRepetitions) {
                    audioPlayer.play(pcm) { progress ->
                        onEvent(
                            mapOf(
                                "type" to "RELAY_TX_PROGRESS",
                                "progress" to progress,
                                "repetition" to rep
                            )
                        )
                    }
                    if (rep < relayRepetitions) {
                        delay(250)
                    }
                }

                relayStats.packetsRetransmitted++
                onEvent(
                    mapOf(
                        "type" to "RELAY_TX_COMPLETED",
                        "payloadText" to decodedSummary,
                        "stats" to getRelayStats()
                    )
                )
            } catch (e: Exception) {
                onEvent(
                    mapOf(
                        "type" to "ERROR",
                        "message" to "Relay transmission failed: ${e.message}"
                    )
                )
            } finally {
                currentState = if (audioCapture.isCapturing) State.LISTENING else State.IDLE
            }
        }
    }

    fun startRelayMode(guardDelayMs: Long = 500L, repetitions: Int = 1, relayPrivate: Boolean = true) {
        isRelayMode = true
        relayGuardDelayMs = guardDelayMs.coerceIn(200L, 2000L)
        relayRepetitions = repetitions.coerceIn(1, 3)
        relayPrivateEnabled = relayPrivate
        startListening()
        onEvent(
            mapOf(
                "type" to "RELAY_MODE_CHANGED",
                "isRelayMode" to true,
                "guardDelayMs" to relayGuardDelayMs,
                "repetitions" to relayRepetitions,
                "stats" to getRelayStats()
            )
        )
    }

    fun stopRelayMode() {
        isRelayMode = false
        onEvent(
            mapOf(
                "type" to "RELAY_MODE_CHANGED",
                "isRelayMode" to false,
                "stats" to getRelayStats()
            )
        )
    }

    fun getRelayStats(): Map<String, Any> {
        return mapOf(
            "packetsCaptured" to relayStats.packetsCaptured,
            "packetsVerified" to relayStats.packetsVerified,
            "packetsRetransmitted" to relayStats.packetsRetransmitted,
            "duplicatesSuppressed" to relayStats.duplicatesSuppressed,
            "isRelayMode" to isRelayMode
        )
    }

    fun testRelayPipeline(testMessage: String = "Relay Node B Test Signal"): Map<String, Any> {
        val payload = testMessage.toByteArray(StandardCharsets.UTF_8)
        val testPacket = AcousticPacket(
            version = config.protocolVersion,
            type = AcousticPacket.TYPE_DATA,
            sequenceNumber = 1,
            totalPackets = 1,
            payload = payload
        )

        val encodedFrame = PacketEncoder.encode(testPacket, config)
        val decodeResult = PacketDecoder.decode(encodedFrame, config)

        return if (decodeResult is PacketDecoder.Result.Success) {
            val decodedPacket = decodeResult.packet
            val decodedText = String(decodedPacket.payload, StandardCharsets.UTF_8)
            triggerRelay(decodedPacket, decodedText)
            mapOf(
                "success" to true,
                "decodedText" to decodedText,
                "crcValid" to true,
                "bytes" to decodedPacket.payload.size
            )
        } else {
            mapOf(
                "success" to false,
                "error" to "Test decode verification failed"
            )
        }
    }

    /**
     * Transmits a prepared image through acoustic CPFSK:
     * 1. TYPE_IMAGE_START (Dimensions, Size, Chunks)
     * 2. Sequenced TYPE_IMAGE_CHUNK packets with guard intervals
     * 3. TYPE_IMAGE_END (Verification checksum)
     */
    fun sendImage(prepared: ImageTransferManager.PreparedImage) {
        if (currentState == State.TRANSMITTING) return

        broadcastJob?.cancel()
        broadcastJob = scope.launch {
            try {
                currentState = State.TRANSMITTING

                onEvent(mapOf(
                    "type" to "IMAGE_TX_STARTED",
                    "imageId" to prepared.imageId,
                    "totalChunks" to prepared.totalChunks,
                    "fileSize" to prepared.fileSize,
                    "estimatedDurationSec" to prepared.estimatedDurationSec
                ))

                // 1. TYPE_IMAGE_START
                val startPacket = AcousticPacket.createImageStartPacket(
                    imageId = prepared.imageId,
                    width = prepared.width.toShort(),
                    height = prepared.height.toShort(),
                    fileSize = prepared.fileSize,
                    format = AcousticPacket.FORMAT_WEBP,
                    totalChunks = prepared.totalChunks.toShort(),
                    chunkSize = 48,
                    version = config.protocolVersion
                )
                val startFrame = PacketEncoder.encode(startPacket, config)
                val startPcm = modulator.modulate(startFrame)
                audioPlayer.play(startPcm) {}
                delay(350)

                // 2. Chunks
                for ((index, chunkBytes) in prepared.chunks.withIndex()) {
                    val chunkIndex = (index + 1).toShort()
                    val chunkPacket = AcousticPacket.createImageChunkPacket(
                        imageId = prepared.imageId,
                        chunkIndex = chunkIndex,
                        totalChunks = prepared.totalChunks.toShort(),
                        chunkData = chunkBytes,
                        version = config.protocolVersion
                    )
                    val chunkFrame = PacketEncoder.encode(chunkPacket, config)
                    val chunkPcm = modulator.modulate(chunkFrame)

                    audioPlayer.play(chunkPcm) {}

                    val progress = (index + 1).toFloat() / prepared.totalChunks.toFloat()
                    onEvent(mapOf(
                        "type" to "IMAGE_TX_PROGRESS",
                        "imageId" to prepared.imageId,
                        "chunkIndex" to chunkIndex.toInt(),
                        "totalChunks" to prepared.totalChunks,
                        "progress" to progress
                    ))

                    delay(250) // Inter-packet guard silence
                }

                // 3. TYPE_IMAGE_END
                val endPacket = AcousticPacket.createImageEndPacket(
                    imageId = prepared.imageId,
                    totalChunks = prepared.totalChunks.toShort(),
                    imageCrc32 = prepared.imageCrc32,
                    version = config.protocolVersion
                )
                val endFrame = PacketEncoder.encode(endPacket, config)
                val endPcm = modulator.modulate(endFrame)
                audioPlayer.play(endPcm) {}

                onEvent(mapOf(
                    "type" to "IMAGE_TX_COMPLETED",
                    "imageId" to prepared.imageId,
                    "totalChunks" to prepared.totalChunks
                ))
            } catch (e: Exception) {
                currentState = State.ERROR
                onEvent(mapOf(
                    "type" to "ERROR",
                    "message" to "Image transmission failed: ${e.message}"
                ))
            } finally {
                currentState = if (audioCapture.isCapturing) State.LISTENING else State.IDLE
            }
        }
    }
}
