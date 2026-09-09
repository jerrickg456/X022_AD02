# SonicMesh — Acoustic One-to-Many Communication for Android

> **Turn the air into the network.**
>
> A real-device Android application for sending short messages and URLs from one smartphone to many nearby smartphones using only built-in speakers and microphones — without Internet, Wi-Fi, Bluetooth, GPS, mobile data, pairing, or external hardware.

---

## 0. Hackathon Context

This project is designed for the problem statement:

**PS02 — Acoustic One-to-Many Communication**

The application must enable short information to be broadcast from one Android smartphone to multiple nearby Android devices through acoustic communication.

### Mandatory constraints

The implementation must be:

- independent of Internet connectivity
- independent of Wi-Fi
- independent of Bluetooth
- independent of location services/GPS
- reliable when some receivers fail to receive individual packets
- capable of confirming successful receivers where feasible
- simple for receivers to join
- free from traditional file-transfer pairing/acceptance workflows
- efficient using only built-in phone hardware
- installable and testable as a real Android APK/AAB

The final system must work when network connectivity is disabled.

---

# 1. Product Vision

SonicMesh is intentionally broader than a simple "send text over sound" application.

The core product is an **infrastructure-free acoustic communication layer** that turns ordinary Android phones into temporary communication nodes.

### Basic communication

```text
                         Sender
                       Android Phone
                            |
                         Speaker
                            |
                            v
                    ~~~~~~~~ AIR ~~~~~~~~
                    /        |          \
                   /         |           \
                  v          v            v
              Receiver A Receiver B  Receiver C
                Mic         Mic          Mic
```

### Advanced communication

Receivers can optionally become acoustic relay nodes:

```text
                    Sender
                       |
                       v
                    Node A
                       |
                       v
                    Node B
                       |
                       v
                 Destination
```

This enables an experimental **self-forming, self-healing, multi-hop acoustic network** without conventional networking infrastructure.

---

# 2. What Makes SonicMesh Different

A basic solution would implement:

```text
Text
  ↓
FSK
  ↓
Speaker
  ↓
Air
  ↓
Microphone
  ↓
FSK decoder
  ↓
Text
```

SonicMesh should go further.

### Differentiating capabilities

1. One-to-many acoustic broadcast
2. Packetized protocol
3. Synchronization/preamble detection
4. CRC32 integrity checking
5. Forward Error Correction
6. Packet repetition
7. Duplicate suppression
8. Receiver session IDs
9. Acoustic acknowledgements
10. Adaptive acoustic profiles
11. Ambient-noise analysis
12. Fast and robust transmission modes
13. Optional acoustic relay
14. Multi-hop forwarding
15. TTL-based loop prevention
16. Store-and-forward for short messages
17. Message priority
18. Replay protection
19. Message authentication
20. Real-time diagnostics
21. Privacy-preserving local microphone processing
22. Real-device compatibility testing
23. No-network verification mode

The advanced features must never be allowed to break the mandatory core functionality.

---

# 3. Core Principle

The actual data path must be:

```text
Flutter UI
   |
   v
Kotlin Acoustic Engine
   |
   v
Message Encoder
   |
   v
Packetizer
   |
   v
CRC + FEC
   |
   v
Modulator
   |
   v
Android AudioTrack
   |
   v
PHONE SPEAKER
   |
   v
~~~~~~~~~~~~ AIR ~~~~~~~~~~~~
   |
   v
PHONE MICROPHONE
   |
   v
Android AudioRecord
   |
   v
Signal Detector
   |
   v
Synchronizer
   |
   v
Demodulator
   |
   v
CRC + FEC Decoder
   |
   v
Packet Reassembler
   |
   v
Flutter UI
```

### Forbidden as the core transport

Do not use:

- HTTP
- REST
- WebSocket
- Firebase
- MQTT
- Bluetooth
- Wi-Fi Direct
- Nearby Share
- QR code
- mobile data
- cloud APIs

The acoustic channel must carry the actual application data.

---

# 4. Technology Stack

## Frontend

Use:

- Flutter
- Dart
- Material 3
- feature-based architecture
- Riverpod or an equivalent lightweight state-management solution

Flutter handles:

- UI
- navigation
- message entry
- broadcast controls
- receiver controls
- progress
- diagnostics
- settings
- history
- calibration UI
- accessibility

## Native Android

Use:

- Kotlin
- Android SDK
- AudioRecord
- AudioTrack
- Coroutines
- MethodChannel/EventChannel or equivalent platform-channel architecture

Kotlin handles:

- real-time audio capture
- audio playback
- signal processing
- modulation
- demodulation
- synchronization
- packet processing
- CRC
- FEC
- acoustic session state
- relay logic

---

# 5. Why Flutter + Kotlin

The acoustic engine is timing-sensitive.

Real-time processing requires:

- PCM buffers
- low-latency capture
- precise symbol timing
- frequency analysis
- controlled waveform generation
- continuous microphone processing
- efficient memory use
- minimal allocations

Therefore:

```text
Flutter = Product/UI Layer
Kotlin  = Real-Time Acoustic Layer
```

Do not perform the main DSP/audio loop on the Flutter UI isolate.

---

# 6. Recommended Project Structure

```text
sonicmesh/
│
├── README.md
├── LICENSE
├── .gitignore
│
├── lib/
│   ├── main.dart
│   │
│   ├── app/
│   │   ├── app.dart
│   │   ├── routes.dart
│   │   └── theme.dart
│   │
│   ├── core/
│   │   ├── constants/
│   │   ├── errors/
│   │   ├── models/
│   │   ├── services/
│   │   └── utils/
│   │
│   ├── features/
│   │   ├── home/
│   │   ├── broadcast/
│   │   ├── receiver/
│   │   ├── diagnostics/
│   │   ├── calibration/
│   │   ├── history/
│   │   └── settings/
│   │
│   └── native/
│       └── acoustic_channel.dart
│
├── android/
│   └── app/
│       └── src/
│           └── main/
│               ├── AndroidManifest.xml
│               └── kotlin/
│                   └── com/
│                       └── sonicmesh/
│                           ├── MainActivity.kt
│                           │
│                           └── acoustic/
│                               ├── AcousticEngine.kt
│                               ├── AcousticConfig.kt
│                               ├── AudioCapture.kt
│                               ├── AudioPlayer.kt
│                               ├── SignalDetector.kt
│                               ├── Synchronizer.kt
│                               ├── Modulator.kt
│                               ├── Demodulator.kt
│                               ├── Packet.kt
│                               ├── PacketEncoder.kt
│                               ├── PacketDecoder.kt
│                               ├── Crc32.kt
│                               ├── FecEncoder.kt
│                               ├── FecDecoder.kt
│                               ├── SessionManager.kt
│                               ├── AckManager.kt
│                               ├── RelayManager.kt
│                               ├── ReplayProtection.kt
│                               └── DiagnosticsManager.kt
│
├── test/
│   ├── packet_test.dart
│   └── ...
│
├── docs/
│   ├── architecture.md
│   ├── protocol.md
│   ├── audio.md
│   ├── testing.md
│   └── security.md
│
└── assets/
    └── ...
```

---

# 7. Application Modes

The app has three major modes.

## 7.1 Broadcast

A user enters:

- text
- URL
- small JSON payload
- alert

and presses:

**BROADCAST**

The sender:

1. creates a session
2. encodes the message
3. packetizes it
4. adds integrity metadata
5. adds FEC
6. modulates the data
7. transmits acoustically
8. optionally repeats packets
9. optionally receives ACKs
10. displays statistics

---

## 7.2 Listen / Receive

The receiver opens the app and presses:

**LISTEN**

The app:

1. requests microphone permission only when needed
2. starts local microphone processing
3. waits for the SonicMesh preamble
4. detects synchronization
5. demodulates packets
6. validates CRC
7. performs FEC recovery
8. removes duplicates
9. reconstructs the message
10. displays only verified data

No pairing should be necessary.

---

## 7.3 Relay

Advanced mode.

A receiver can optionally become a relay node.

```text
Sender
  |
  v
Receiver / Relay
  |
  v
Receiver / Relay
  |
  v
Destination
```

A relay:

1. receives
2. verifies
3. checks session
4. checks duplicate cache
5. checks TTL
6. schedules a relay transmission
7. forwards the packet if allowed

Relay mode must be opt-in/configurable.

---

# 8. User Experience

## Home

```text
SONICMESH

Infrastructure-Free
Acoustic Communication

[ BROADCAST ]

[ LISTEN ]

[ CALIBRATE ]

[ DIAGNOSTICS ]
```

Keep the core workflow extremely simple.

---

# 9. Broadcast UI

```text
Broadcast

What would you like to share?

┌─────────────────────────────┐
│ Enter text or URL...        │
│                             │
└─────────────────────────────┘

82 bytes

Mode:
( ) Fast
(•) Robust

[ BROADCAST ]
```

During transmission:

```text
BROADCASTING

██████████████░░░░ 76%

Packets: 19 / 25

Receivers detected: 8
Verified: 7
Recovering: 1

Signal: STRONG
```

---

# 10. Receiver UI

```text
SONICMESH RECEIVER

             🎧

          LISTENING

No Internet required

Signal:
██████████░░

Packets:
12 / 12
```

After successful reception:

```text
✓ MESSAGE VERIFIED

"Meeting moved to Hall B"

CRC: VALID
FEC: NOT REQUIRED

[ COPY ]

[ OPEN ]
```

URLs should require explicit user action before opening.

---

# 11. Acoustic Protocol

The acoustic protocol is the core engineering component.

The protocol should be versioned.

Conceptual packet:

```text
+----------+---------+--------+---------+----------+-------+
| PREAMBLE | VERSION | TYPE   | SESSION | SEQUENCE | TTL   |
+----------+---------+--------+---------+----------+-------+
| PRIORITY | FLAGS   | LENGTH | PAYLOAD | FEC META | CRC32 |
+----------+---------+--------+---------+----------+-------+
```

The exact binary representation should be documented in `docs/protocol.md`.

---

# 12. Protocol Fields

## Preamble

A known sequence for signal detection and timing acquisition.

Example concept:

```text
SYNC SYNC SYNC SYNC START
```

The exact acoustic pattern should be configurable.

---

## Version

Protocol version.

Example:

```text
0x01
```

Allows future compatibility.

---

## Type

Supported message types:

```text
TEXT
URL
ALERT
JSON
ACK
NACK
RELAY
```

---

## Session ID

A random ephemeral identifier for the current broadcast.

Do not use:

- phone number
- IMEI
- Android ID
- Google account
- permanent device identifier

---

## Sequence Number

Identifies packet order.

Example:

```text
0000
0001
0002
0003
```

The receiver uses sequence numbers to identify:

- missing packets
- duplicates
- ordering

---

## TTL

Time-to-live / hop limit for relaying.

Example:

```text
TTL = 3
```

Relay sequence:

```text
3 -> 2 -> 1 -> 0
```

At zero, the packet cannot be relayed again.

---

## Priority

Example:

```text
NORMAL
HIGH
CRITICAL
```

Critical messages can use more redundancy/repetition.

---

## Flags

Possible flags:

```text
FEC_PRESENT
RETRANSMISSION
ACK_REQUEST
RELAY_ALLOWED
SIGNED
FINAL_PACKET
```

---

## Payload

Short application data.

Initial target:

```text
256–1024 bytes
```

Do not promise large-file transfer unless extensive real-device testing proves it reliable.

---

## CRC32

CRC32 is used for packet integrity.

Receiver:

```text
received CRC
       |
calculate CRC
       |
       +---- equal ----> ACCEPT
       |
       +---- different -> RECOVERY
```

Corrupt packets must never crash the application.

---

# 13. Modulation

Initial modulation:

## FSK — Frequency Shift Keying

Concept:

```text
bit 0 -> F0
bit 1 -> F1
```

Example values must be experimentally selected.

Do not blindly assume that a specific ultrasonic frequency will work on every phone.

The configuration must support:

```text
frequency0
frequency1
sampleRate
symbolDuration
```

---

# 14. Frequency Strategy

Maintain multiple profiles.

Example:

```text
FAST
ROBUST
VERY_ROBUST
```

A profile may contain:

```text
F0
F1
symbolDuration
preambleDuration
packetSize
FEC ratio
repeat count
```

The actual frequency values should be determined through device testing.

---

# 15. Important Audio Hardware Reality

Different Android phones have different:

- speaker frequency responses
- microphone responses
- automatic gain control
- noise suppression
- audio resampling
- microphone hardware
- speaker volume limits

Therefore:

**Do not assume identical acoustic performance across all phones.**

The system should be calibrated and tested on multiple physical devices.

---

# 16. Signal Detection

The receiver should not attempt full decoding on all microphone samples.

Use a state machine:

```text
IDLE
  |
  v
LISTENING
  |
  | signal energy/frequency detected
  v
PREAMBLE_DETECTION
  |
  v
SYNCHRONIZED
  |
  v
RECEIVING
  |
  v
VALIDATING
  |
  +------ invalid ------> RECOVERY
  |
  v
REASSEMBLING
  |
  v
COMPLETE
```

---

# 17. Synchronization

Synchronization must account for:

- speaker latency
- microphone buffering
- clock differences
- environmental noise
- small timing drift

The preamble should be sufficiently distinctive to avoid false detections.

The receiver should establish:

- signal start
- symbol timing
- packet timing

before attempting payload decoding.

---

# 18. Demodulation

For FSK:

1. capture PCM
2. create symbol windows
3. measure energy near F0
4. measure energy near F1
5. select dominant frequency
6. produce bit
7. group bits into bytes
8. parse packet

Possible detection algorithms:

- Goertzel
- FFT
- correlation

Start with Goertzel for focused frequency detection and lower computational overhead.

The implementation should be modular enough to replace it with FFT later.

---

# 19. Audio Capture

Use `AudioRecord`.

Requirements:

- mono PCM
- configurable sample rate
- efficient buffer size
- continuous processing
- no raw recording to storage

Determine supported audio configurations where practical.

Do not hardcode assumptions without checking the actual device.

---

# 20. Audio Playback

Use `AudioTrack`.

Requirements:

- PCM
- mono
- controlled amplitude
- avoid clipping
- clean lifecycle management
- release resources after transmission

Do not make the waveform unnecessarily loud.

Provide a configurable safe volume.

---

# 21. Waveform Generation

The modulator should generate the acoustic waveform mathematically.

For FSK:

```text
bit = 0
     -> sine wave at F0

bit = 1
     -> sine wave at F1
```

Use appropriate windowing/ramping to reduce abrupt transitions and spectral artifacts.

Avoid clicks caused by discontinuous waveform boundaries.

---

# 22. Packetization

Do not send a long message as one continuous block.

Split:

```text
Message
   |
   +-- Packet 0
   +-- Packet 1
   +-- Packet 2
   +-- Packet 3
```

Every packet must be independently identifiable.

---

# 23. Packet Repetition

Acoustic channels can experience temporary interference.

Therefore the sender can transmit:

```text
ROUND 1
P0 P1 P2 P3 P4

ROUND 2
P0 P1 P2 P3 P4
```

The receiver:

- accepts valid packets
- ignores duplicates
- keeps missing packets pending

---

# 24. Forward Error Correction

Implement FEC as a separate layer.

Possible approaches:

- Reed-Solomon
- parity blocks
- XOR parity

Start with a practical FEC implementation that is easy to validate.

The FEC module must not be tightly coupled to the audio code.

---

# 25. Recovery Strategy

If:

```text
P0 ✓
P1 ✓
P2 ✗
P3 ✓
P4 ✓
```

the receiver should attempt:

1. FEC recovery
2. repeated packet reception
3. retransmission where supported
4. relay recovery where supported

The entire message should not be discarded merely because one packet failed.

---

# 26. One-to-Many Architecture

One sender broadcasts a common session.

```text
                       Sender
                          |
                     Acoustic
                          |
        +-----------------+----------------+
        |                 |                |
        v                 v                v
    Receiver A       Receiver B       Receiver C
```

Each receiver independently decodes the same broadcast.

The sender should not depend on every receiver responding before completing the broadcast.

---

# 27. Receiver Joining

Receivers should be able to open the app and listen without pairing.

Recommended workflow:

```text
OPEN APP
   |
LISTEN
   |
WAIT
   |
SIGNAL DETECTED
   |
VERIFY
   |
MESSAGE RECEIVED
```

No traditional file transfer acceptance screen.

---

# 28. Receiver Session IDs

Generate a random temporary ID:

```text
A7F2
B91C
D204
```

Use only for the current communication session.

Never expose permanent device identity.

---

# 29. Acoustic Acknowledgements

Optional advanced capability.

```text
Sender
  |
  | DATA
  v
Receivers
  |
  | ACK
  v
Sender
```

The sender can display:

```text
Receivers detected: 12
Successfully verified: 11
Recovering: 1
```

Do not rely on ACKs as the only reliability mechanism.

Broadcast repetition + FEC must still provide useful one-to-many reliability.

---

# 30. ACK Collision Avoidance

Multiple receivers may attempt to ACK simultaneously.

Use randomized/time-slotted response windows.

Example:

```text
ACK WINDOW

0–50 ms       Receiver A
50–100 ms     Receiver B
100–150 ms    Receiver C
...
```

A receiver chooses a randomized response slot.

For larger receiver counts, acknowledgement collection should be treated as an optimization rather than a mandatory guarantee.

---

# 31. Adaptive Acoustic Communication

SonicMesh should be able to inspect the environment.

Concept:

```text
Microphone
    |
Ambient analysis
    |
Frequency spectrum
    |
Find suitable frequency pair
    |
Select acoustic profile
```

Possible behavior:

### Quiet environment

```text
FAST MODE
Shorter symbols
Less redundancy
Higher throughput
```

### Noisy environment

```text
ROBUST MODE
Longer symbols
More FEC
More repetitions
Lower throughput
```

---

# 32. Signal Quality

Expose a simple signal quality metric.

Example:

```text
Signal: STRONG
██████████░░
```

Possible internal measurements:

- energy ratio
- F0/F1 separation
- noise floor
- estimated SNR
- symbol confidence

Avoid presenting scientifically precise values unless they are properly calibrated.

---

# 33. Confidence-Based Decoding

For every decoded symbol, calculate a confidence score where practical.

Concept:

```text
F0 energy = 80
F1 energy = 20

confidence = HIGH
```

versus:

```text
F0 energy = 52
F1 energy = 48

confidence = LOW
```

Low-confidence symbols can trigger:

- FEC
- packet rejection
- repetition request/recovery

---

# 34. Multi-Hop Acoustic Relay

This is the major advanced differentiator.

```text
                 Sender
                   |
                   v
                Node A
                   |
                   v
                Node B
                   |
                   v
             Destination
```

A relay forwards only after validation.

Relay rules:

```text
CRC valid?
Session valid?
Not duplicate?
TTL > 0?
Relay allowed?
```

If all are true:

```text
TTL = TTL - 1
Relay packet
```

---

# 35. Relay Scheduling

Multiple nodes may hear the same packet.

They must not all immediately retransmit.

Use randomized relay delay:

```text
Node A -> 80 ms
Node B -> 130 ms
Node C -> 210 ms
```

If a node hears another valid relay before its scheduled transmission, it may cancel its own relay.

This reduces unnecessary duplicate transmissions.

---

# 36. Relay Deduplication

Maintain a small cache:

```text
sessionId + sequenceNumber
```

If already seen:

```text
IGNORE
```

This prevents relay storms.

The cache should expire after the session ends.

---

# 37. Store-and-Forward

Advanced mode:

```text
RECEIVE
   |
VERIFY
   |
TEMPORARILY STORE
   |
WAIT
   |
RELAY
```

Only short messages should be stored.

Stored messages must expire automatically.

Do not persist sensitive data indefinitely.

---

# 38. Message Priority

Support:

```text
NORMAL
HIGH
CRITICAL
```

Priority can affect:

- repetition count
- FEC ratio
- relay priority
- queue ordering

Example:

```text
CRITICAL
"EVACUATE THROUGH EXIT B"
```

gets stronger redundancy than:

```text
NORMAL
"Event starts at 4 PM"
```

---

# 39. Security

Acoustic transmission is not inherently trustworthy.

The application should support message authentication where practical.

Possible protected message:

```text
MESSAGE
SESSION
TIMESTAMP
NONCE
AUTHENTICATION TAG
```

The receiver validates before displaying sensitive/critical messages.

---

# 40. Replay Protection

A recorded acoustic signal should not remain valid forever.

Use:

- session ID
- nonce
- timestamp/expiry where appropriate

Example:

```text
Old session
     |
     v
Expired
     |
     v
REJECT
```

Do not claim perfect security unless the cryptographic implementation has been properly reviewed.

---

# 41. Privacy

Raw microphone audio must not be stored.

Correct:

```text
Microphone
   |
PCM buffer in memory
   |
Signal processing
   |
Decoded packet
   |
Discard audio buffer
```

Do not create:

```text
recording.wav
recording.mp3
microphone_history
```

Do not upload microphone data to a server.

---

# 42. Permissions

Request only required permissions.

Expected:

```text
RECORD_AUDIO
```

Do not request unnecessary permissions such as:

- location
- contacts
- camera
- storage
- Bluetooth

unless a clearly justified future feature requires them.

---

# 43. Android Lifecycle

Handle:

- app backgrounding
- app foregrounding
- screen rotation
- microphone interruptions
- audio focus changes
- phone calls
- another application taking audio focus
- permission denial
- process recreation

Always release:

```text
AudioRecord
AudioTrack
coroutines
buffers
```

when no longer needed.

---

# 44. Threading Model

Recommended:

```text
Flutter UI
    |
MethodChannel
    |
Kotlin Acoustic Engine
    |
    +------------------+
    |                  |
Audio Thread       Protocol Worker
    |                  |
AudioRecord        Decoder
AudioTrack         CRC
DSP                FEC
                   Session
```

Do not block the UI thread.

---

# 45. Method Channel API

Flutter-to-Kotlin methods:

```text
initializeEngine()
startListening()
stopListening()
startBroadcast(message, config)
stopBroadcast()
startCalibration()
stopCalibration()
getDiagnostics()
setConfig(config)
setVolume(volume)
enableRelay(enabled)
```

Kotlin-to-Flutter events:

```text
engineReady
signalDetected
syncAcquired
packetReceived
packetRejected
packetRecovered
packetDuplicate
messageProgress
messageReceived
receiverDetected
broadcastProgress
relayScheduled
relayCompleted
diagnosticUpdate
error
```

---

# 46. Acoustic Engine State Machine

Use explicit states.

```text
IDLE

INITIALIZING

CALIBRATING

LISTENING

SIGNAL_DETECTED

SYNCHRONIZING

RECEIVING

VALIDATING

RECOVERING

COMPLETE

BROADCASTING

WAITING_FOR_ACK

RELAYING

ERROR
```

Avoid large numbers of unrelated boolean flags.

---

# 47. Error Handling

Handle:

- microphone unavailable
- unsupported sample rate
- audio initialization failure
- permission denied
- buffer underrun
- buffer overrun
- corrupted packets
- invalid protocol version
- malformed packet
- memory pressure
- audio interruption
- lifecycle interruption

Example:

```text
Microphone unavailable.

Close other applications using the microphone
and try again.
```

Never crash on malformed acoustic input.

---

# 48. Diagnostics Screen

Create a judge-friendly technical screen.

Example:

```text
SONICMESH DIAGNOSTICS

AUDIO
--------------------------------
Sample rate:       48 kHz
Channels:          Mono
Input:             Available
Output:            Available

ACOUSTIC
--------------------------------
Modulation:        FSK
F0:                XXXX Hz
F1:                XXXX Hz
Symbol duration:   XX ms
Profile:           ROBUST

TRANSMISSION
--------------------------------
Packets sent:      32
Packets received:  31
CRC failures:       2
FEC recovered:      2
Duplicates:         4

RECEIVERS
--------------------------------
Detected:          12
Verified:          11
Recovering:         1

PERFORMANCE
--------------------------------
Latency:            XXX ms
CPU:                XX %
Memory:             XX MB

CONNECTIVITY
--------------------------------
Internet:           OFF
Wi-Fi:              OFF
Bluetooth:          OFF
GPS:                OFF
```

Values must be measured, not fabricated.

---

# 49. No-Network Demonstration Mode

Add a visible diagnostics indicator:

```text
INTERNET       OFF
WI-FI          OFF
BLUETOOTH      OFF
MOBILE DATA    OFF
```

The actual acoustic communication must continue to function.

For the strongest demo, test devices in airplane mode with Wi-Fi/Bluetooth disabled.

---

# 50. Performance Requirements

The application should be:

- responsive
- stable
- memory efficient
- CPU efficient
- battery conscious

Avoid allocations inside high-frequency audio loops.

Do not log every audio sample.

Do not continuously create large temporary arrays.

Use reusable buffers where appropriate.

---

# 51. Battery Optimization

While listening:

- detect signal efficiently
- avoid unnecessary FFT calculations
- use focused frequency detection when possible
- stop processing when listening ends

After broadcast:

```text
stop AudioTrack
release buffers
release audio resources
stop workers
```

---

# 52. Audio Robustness

The implementation must consider:

- volume changes
- background speech
- music
- fan noise
- echo
- reverberation
- microphone distance
- speaker distance
- different phone models

Do not assume laboratory conditions.

---

# 53. Real-Device Compatibility

Test on several Android phones.

At minimum:

```text
Phone A -> Phone B
Phone A -> Phone C
Phone A -> Phone B + C
```

Then:

```text
1 sender -> 5 receivers
1 sender -> 10 receivers
```

If possible:

```text
1 sender -> 15+ receivers
```

Record actual results.

---

# 54. Test Environments

Test:

### Quiet

```text
Office/classroom
Low background noise
```

### Moderate noise

```text
People talking
```

### High noise

```text
Crowded hall
```

### Distance

Test several realistic distances.

Do not claim a maximum range until measured.

---

# 55. Real Device Test Matrix

Maintain a table:

```text
Device | Android | Speaker | Mic | Profile | Distance | Result
----------------------------------------------------------------
A      | XX       | OK      | OK  | Robust  | X m      | PASS
B      | XX       | OK      | OK  | Robust  | X m      | PASS
C      | XX       | OK      | OK  | Fast    | X m      | FAIL
```

This will help diagnose hardware-specific failures.

---

# 56. Unit Testing

Test:

- packet encoding
- packet decoding
- CRC
- FEC
- sequence handling
- duplicate detection
- TTL
- relay rules
- session handling
- replay protection
- message reassembly

---

# 57. Protocol Integration Testing

Test:

```text
Message
   |
Encoder
   |
Packetizer
   |
CRC
   |
FEC
   |
Modulator
   |
Demodulator
   |
Decoder
   |
CRC
   |
FEC
   |
Reassembler
   |
Original Message
```

The final output must exactly match the original input.

---

# 58. Fault Injection Testing

Artificially simulate:

- missing packet
- corrupted packet
- duplicate packet
- out-of-order packet
- invalid CRC
- invalid version
- expired session
- TTL = 0
- invalid authentication
- incomplete message

The system should recover or fail gracefully.

---

# 59. Required Demo Scenarios

## Demo 1 — Basic

```text
Phone A
   |
Speaker
   |
Air
   |
Phone B
   |
Microphone

"HELLO WORLD"
```

---

## Demo 2 — One-to-Many

```text
             Sender
          /     |     \
         /      |      \
        A       B       C
```

All receivers decode the same message.

---

## Demo 3 — No Network

Disable:

```text
Internet
Wi-Fi
Bluetooth
Mobile data
```

Then transmit.

---

## Demo 4 — Noise

Introduce realistic background noise.

Show:

```text
CRC errors
FEC recovery
successful final message
```

---

## Demo 5 — Receiver Joins Mid-Broadcast

Sender repeats the broadcast.

A receiver starts listening after the transmission has already started.

The receiver should eventually reconstruct the message.

---

## Demo 6 — Relay

If relay mode is implemented:

```text
Sender
   |
Node A
   |
Node B
   |
Destination
```

Destination receives the message through relay nodes.

---

# 60. Surprise Challenge Strategy

The organizers may change:

- device
- environment
- distance
- number of receivers
- message size
- noise
- speaker volume

Therefore make the following configurable:

```text
sampleRate
frequency0
frequency1
symbolDuration
packetSize
preambleLength
retryCount
fecRatio
relayDelay
maxHops
profile
```

Do not scatter these values throughout the code.

Use:

```text
AcousticConfig
```

as the single configuration model.

---

# 61. Adaptive Profiles

Provide:

## FAST

```text
Higher data rate
Lower redundancy
Shorter symbols
```

## ROBUST

```text
Moderate data rate
Higher redundancy
More repetition
```

## EMERGENCY

```text
Lowest data rate
Highest reliability
Strong FEC
More repetition
Priority handling
```

---

# 62. Configuration Example

Conceptually:

```text
AcousticConfig(
    sampleRate = ...,
    frequency0 = ...,
    frequency1 = ...,
    symbolDurationMs = ...,
    packetSize = ...,
    repetitionCount = ...,
    fecEnabled = true,
    fecRatio = ...,
    preambleDurationMs = ...,
    maxHops = ...
)
```

Do not hardcode example values until verified on physical devices.

---

# 63. Accessibility

The app should support:

- large controls
- high contrast
- clear status indicators
- minimal text
- simple language
- vibration feedback where appropriate
- screen-reader-friendly labels

The receiver workflow should require minimal interaction.

---

# 64. Safety and Responsible Audio

Do not intentionally transmit dangerously loud audio.

Provide:

- safe default volume
- user volume control
- optional transmission test
- graceful shutdown

Avoid frequencies/volumes that could create uncomfortable or unsafe sound exposure.

---

# 65. Logging

Use structured logs:

```text
[ENGINE] initialized
[AUDIO] capture started
[DETECT] acoustic signal detected
[SYNC] preamble acquired
[PACKET] sequence=12 valid
[CRC] valid
[FEC] recovery not required
[REASSEMBLY] 12/12
[MESSAGE] complete
```

Never log:

- raw PCM
- sensitive message content unnecessarily
- permanent device identifiers
- personal data

---

# 66. Security Model

Security should be layered:

```text
Physical acoustic channel
        |
Packet integrity
        |
Session validation
        |
Replay protection
        |
Authentication
        |
Application validation
```

CRC provides integrity against accidental corruption.

CRC is NOT cryptographic security.

For security-sensitive messages, use a proper authentication mechanism.

---

# 67. Threat Model

Consider:

### Accidental noise

Handled by:

- synchronization
- confidence scoring
- CRC
- FEC

### Corrupted packet

Handled by:

- CRC
- repetition
- FEC

### Duplicate packet

Handled by:

- session + sequence cache

### Replay

Handled by:

- session expiry
- nonce
- timestamp

### Fake message

Handled by:

- message authentication

### Relay loop

Handled by:

- TTL
- deduplication

---

# 68. Core Data Models

Recommended models:

```text
AcousticConfig
AcousticSession
Packet
ReceiverInfo
TransmissionStats
ReceptionStats
SignalMetrics
MessageEnvelope
RelayMetadata
```

---

# 69. TransmissionStats

Example:

```text
packetsSent
packetsAcknowledged
packetsRepeated
crcFailures
fecRecoveries
receiverCount
verifiedReceiverCount
durationMs
estimatedThroughput
```

Only display metrics that are actually measured.

---

# 70. SignalMetrics

Example:

```text
noiseFloor
signalEnergy
f0Energy
f1Energy
confidence
estimatedSnr
profile
```

Do not claim calibrated SNR unless the measurement method supports it.

---

# 71. ReceiverInfo

Use temporary identifiers only:

```text
sessionReceiverId
status
lastSeen
packetsReceived
packetsMissing
signalQuality
```

Do not store permanent identity.

---

# 72. Message Lifecycle

```text
USER MESSAGE
     |
     v
VALIDATE
     |
     v
CREATE SESSION
     |
     v
ENCODE
     |
     v
PACKETIZE
     |
     v
CRC
     |
     v
FEC
     |
     v
MODULATE
     |
     v
TRANSMIT
     |
     v
RECEIVE
     |
     v
DEMODULATE
     |
     v
CRC
     |
     v
FEC
     |
     v
REASSEMBLE
     |
     v
VERIFY
     |
     v
DISPLAY
```

---

# 73. Relay Lifecycle

```text
RECEIVE PACKET
      |
      v
VALIDATE CRC
      |
      v
VALID SESSION?
      |
      v
DUPLICATE?
  /         \
YES         NO
 |           |
STOP       TTL > 0?
             |
             v
       RELAY ALLOWED?
             |
             v
       RANDOM DELAY
             |
             v
           RELAY
```

---

# 74. Recommended Development Order

Do not implement everything simultaneously.

## Phase 0 — Project Setup

Build:

- Flutter project
- Kotlin integration
- clean architecture
- basic UI
- MethodChannel

Do not implement advanced features yet.

---

## Phase 1 — Acoustic Hello World

Goal:

```text
Phone A -> sound -> Phone B

HELLO
```

Implement only:

- AudioTrack
- AudioRecord
- basic FSK
- basic detection
- basic decoding

This must work on real devices.

---

## Phase 2 — Protocol

Add:

- preamble
- packet structure
- sequence number
- CRC
- message reassembly

---

## Phase 3 — Reliability

Add:

- packet repetition
- duplicate handling
- FEC
- recovery

---

## Phase 4 — One-to-Many

Test:

```text
1 -> 5
1 -> 10
```

receivers.

---

## Phase 5 — ACK

Add:

- temporary receiver IDs
- ACK
- randomized ACK windows
- receiver statistics

---

## Phase 6 — Adaptive Communication

Add:

- calibration
- ambient noise analysis
- acoustic profiles
- confidence scoring

---

## Phase 7 — Relay

Add:

- relay mode
- TTL
- deduplication
- randomized forwarding
- multi-hop

---

## Phase 8 — Security

Add:

- nonce
- session expiry
- replay protection
- authentication

---

## Phase 9 — Product Polish

Add:

- polished Flutter UI
- diagnostics
- animations
- accessibility
- error states
- demo mode

---

# 75. MVP Definition

The minimum acceptable working system is:

```text
Android Phone A
      |
   Speaker
      |
      AIR
      |
   Microphone
      |
Android Phone B
```

with:

- FSK
- synchronization
- packetization
- CRC
- message reconstruction

and:

```text
Internet = OFF
Wi-Fi = OFF
Bluetooth = OFF
```

---

# 76. Advanced Definition of Done

### Core

- [ ] APK builds
- [ ] APK installs
- [ ] real Android devices tested
- [ ] speaker transmission works
- [ ] microphone reception works
- [ ] no network required
- [ ] synchronization works
- [ ] packetization works
- [ ] CRC works
- [ ] message reconstruction works
- [ ] one-to-many works

### Reliability

- [ ] packet repetition
- [ ] duplicate detection
- [ ] FEC
- [ ] recovery
- [ ] noise testing

### Advanced

- [ ] ACK
- [ ] adaptive profile
- [ ] calibration
- [ ] receiver statistics
- [ ] relay
- [ ] TTL
- [ ] multi-hop
- [ ] store-and-forward

### Security

- [ ] session nonce
- [ ] replay protection
- [ ] message authentication
- [ ] temporary receiver IDs

### Quality

- [ ] no raw microphone storage
- [ ] no unnecessary permissions
- [ ] no UI blocking
- [ ] lifecycle handling
- [ ] diagnostics
- [ ] crash handling
- [ ] performance testing

---

# 77. What NOT to Do

Do not:

1. build only a mock UI
2. fake received messages
3. use Firebase as the transport
4. use Wi-Fi as fallback
5. use Bluetooth as fallback
6. depend on Internet
7. depend on QR codes
8. store microphone recordings
9. assume ultrasonic transmission works on all phones
10. claim a range that has not been measured
11. claim 100% reliability without testing
12. implement advanced networking before basic acoustic transmission works

---

# 78. Engineering Principles

Follow these principles:

### Separation of concerns

```text
UI
 |
Protocol
 |
DSP
 |
Audio Hardware
```

Keep layers independent.

### Configuration over hardcoding

All acoustic parameters must be configurable.

### Measurement over assumptions

Measure:

- latency
- success rate
- packet loss
- CPU
- memory
- battery impact
- practical range

### Reliability over feature count

A reliable basic acoustic protocol is more valuable than ten unfinished features.

---

# 79. Hackathon Differentiation

The presentation should not say:

> "We send data through sound."

Instead:

> **"We created an infrastructure-free acoustic communication layer for Android devices."**

Then demonstrate:

```text
No Internet
No Wi-Fi
No Bluetooth
No pairing
No external hardware
```

followed by:

```text
One sender
     |
     +---- many receivers
     |
     +---- packet recovery
     |
     +---- adaptive communication
     |
     +---- optional relay
     |
     +---- self-healing forwarding
```

---

# 80. Suggested High-Impact Demonstration

Use several real Android phones.

### Step 1

Put devices into airplane mode.

### Step 2

Disable Wi-Fi and Bluetooth.

### Step 3

Open SonicMesh receiver mode on multiple phones.

### Step 4

On the sender enter:

```text
Emergency evacuation — use Exit B.
```

### Step 5

Broadcast.

### Step 6

Show several devices receiving simultaneously.

### Step 7

Introduce background noise.

### Step 8

Show diagnostics:

```text
Packets sent:       40
CRC errors:          3
FEC recovered:       3
Verified receivers: 10
```

### Step 9

If relay is implemented, demonstrate:

```text
Sender -> Relay -> Destination
```

---

# 81. Strong Pitch

Use this positioning:

> **"Traditional communication assumes infrastructure. SonicMesh doesn't."**

> **"We use the speaker and microphone already present in every Android phone to create a temporary communication layer through the air."**

> **"Our protocol adds synchronization, packetization, integrity checking, error recovery and optional relaying so the system can operate beyond a simple point-to-point sound experiment."**

Final line:

> **"No server. No router. No pairing. The air becomes the network."**

---

# 82. Antigravity Implementation Instructions

This README is the master technical specification.

When using an AI coding agent such as Antigravity:

### Rule 1

Do not generate the complete system in a single step.

### Rule 2

Implement one phase at a time.

### Rule 3

After each phase:

1. compile
2. install APK
3. test on physical Android devices
4. inspect logs
5. fix issues
6. only then proceed

### Rule 4

Never fake acoustic results.

### Rule 5

Never replace the acoustic transport with Internet/Wi-Fi/Bluetooth.

### Rule 6

Do not optimize for architecture diagrams before real acoustic transmission works.

### Rule 7

Keep all acoustic constants configurable.

### Rule 8

If an advanced feature causes the core protocol to become unreliable, disable/defer the advanced feature and preserve the reliable core.

### Rule 9

Before adding a new dependency, explain why it is needed and whether it works offline.

### Rule 10

The final build must be a real installable Android APK/AAB.

---

# 83. Antigravity Phase Prompt

Use this workflow with the coding agent:

```text
You are implementing SonicMesh according to README.md.

Do not implement the entire system at once.

Current phase: [PHASE NUMBER]

First inspect the existing project.

Then:

1. Explain the implementation plan.
2. Identify files that must be created/modified.
3. Implement only the current phase.
4. Keep the architecture modular.
5. Do not introduce Internet, Wi-Fi, Bluetooth or cloud transport.
6. Build the Android project.
7. Run available tests.
8. Report build errors.
9. Fix compile/runtime issues.
10. Provide exact instructions for testing on a physical Android device.
11. Do not claim that a feature works unless it has been verified.

Do not proceed to the next phase automatically.
```

---

# 84. Antigravity Phase 1 Prompt

```text
Implement Phase 1 of SonicMesh.

Goal:

Phone A must generate a simple acoustic signal using Android AudioTrack.

Phone B must capture microphone audio using AudioRecord and detect/decode a basic FSK message.

Start with a minimal "HELLO" payload.

Requirements:

- Kotlin native audio engine
- AudioTrack for transmission
- AudioRecord for reception
- PCM audio
- FSK modulation
- basic frequency detection
- basic synchronization
- no Internet
- no Wi-Fi
- no Bluetooth
- no cloud
- no fake data

Keep all frequency/sample-rate/symbol-duration values configurable.

Build the APK.

Do not implement packetization, FEC, relay, security or advanced UI yet.

The success criterion is actual Phone A -> speaker -> air -> Phone B -> microphone -> decoded HELLO.
```

---

# 85. Antigravity Phase 2 Prompt

```text
Implement Phase 2 of SonicMesh.

Build on the verified Phase 1 acoustic transmission.

Add:

- preamble
- protocol version
- packet type
- session ID
- sequence number
- payload length
- CRC32
- packet decoding
- message reassembly

Do not introduce networking.

Test:

Phone A -> acoustic channel -> Phone B

with a message longer than one packet.

Include unit tests for packet encoding/decoding and CRC.

Do not proceed to FEC or relay until packetized communication works on real devices.
```

---

# 86. Antigravity Phase 3 Prompt

```text
Implement Phase 3 reliability.

Add:

- packet repetition
- duplicate detection
- missing-packet tracking
- FEC
- recovery
- diagnostic counters

The receiver must recover from selected packet loss/corruption without crashing.

Do not introduce networking.

Create fault-injection tests for:

- missing packet
- corrupted packet
- duplicate packet
- out-of-order packet
```

---

# 87. Antigravity Phase 4 Prompt

```text
Implement one-to-many acoustic broadcasting.

One Android sender must broadcast the same session to multiple receivers.

Do not use pairing.

Test with at least several real Android devices.

Add receiver statistics using ephemeral session IDs.

The sender must not depend on receiving an ACK from every device to complete the base broadcast.

Maintain packet repetition and FEC.
```

---

# 88. Antigravity Phase 5 Prompt

```text
Implement optional acoustic ACK.

Add:

- temporary receiver IDs
- ACK packet type
- randomized ACK response windows
- sender-side receiver statistics
- collision avoidance

ACK must remain optional.

Do not make the core broadcast fail because an ACK was not received.
```

---

# 89. Antigravity Phase 6 Prompt

```text
Implement adaptive acoustic profiles.

Add:

- ambient noise analysis
- configurable frequency profiles
- FAST mode
- ROBUST mode
- EMERGENCY mode
- confidence scoring
- diagnostic signal metrics

Do not claim measured SNR/range unless actually measured.

Test across multiple physical Android devices.
```

---

# 90. Antigravity Phase 7 Prompt

```text
Implement optional multi-hop acoustic relay.

Add:

- relay mode
- TTL
- relay permission flag
- duplicate cache
- randomized relay delay
- relay cancellation when another node has already forwarded the packet
- relay diagnostics

Test:

Sender -> Relay A -> Relay B -> Destination

No Internet, Wi-Fi or Bluetooth.
```

---

# 91. Antigravity Phase 8 Prompt

```text
Implement security enhancements.

Add:

- session nonce
- expiry
- replay protection
- message authentication
- validation before displaying protected messages

Do not claim cryptographic security unless a standard, correctly implemented primitive is used.

Do not store permanent device identity.
```

---

# 92. Antigravity Phase 9 Prompt

```text
Polish SonicMesh into a hackathon-ready Android application.

Add:

- Material 3 UI
- broadcast screen
- receiver screen
- calibration screen
- diagnostics screen
- settings
- clear error states
- accessibility
- progress indicators
- signal indicators
- receiver statistics
- network-disabled indicator

Do not change the verified acoustic transport.

Prioritize stability over visual complexity.
```

---

# 93. Final Architecture

```text
                         SONICMESH
                             |
             +---------------+---------------+
             |                               |
        BROADCASTER                       RECEIVER
             |                               |
        Flutter UI                       Flutter UI
             |                               |
       Platform Channel                 Platform Channel
             |                               |
      Kotlin Acoustic Engine          Kotlin Acoustic Engine
             |                               |
       +-----+------+                  +-----+------+
       |            |                  |            |
   Packetizer    Security          AudioRecord     DSP
       |            |                  |            |
      CRC           |              Detector       Sync
       |            |                  |            |
      FEC           |              Demodulator      |
       |            |                  |            |
    Modulator       |                CRC/FEC        |
       |            |                  |            |
    AudioTrack      |              Reassembler      |
       |            |                  |            |
     Speaker        |                Message        |
       |            |                  |            |
       +------------+------ AIR ------+------------+
                                      |
                                Optional Relay
                                      |
                                      v
                                 Another Node
```

---

# 94. Final Product Statement

SonicMesh is not simply a file-transfer application.

It is an experimental **infrastructure-free acoustic networking layer for Android**.

Its core promise is:

```text
                 NO INTERNET
                     NO
                   WI-FI
                     NO
                 BLUETOOTH
                     NO
                  PAIRING
                     NO
                EXTERNAL HARDWARE

                       ↓

                 SPEAKER + AIR
                       ↓
                  MICROPHONE
                       ↓
              ACOUSTIC PROTOCOL
                       ↓
              VERIFIED MESSAGE
```

The system should demonstrate that ordinary smartphones can temporarily communicate and coordinate through sound when conventional communication infrastructure is unavailable.

---

# 95. Final Success Criteria

The project succeeds when a judge can take multiple real Android phones, disable conventional connectivity, open SonicMesh, and observe:

```text
                 ONE PHONE
                     |
                     v
               ACOUSTIC SIGNAL
                     |
              +------+------+------+
              |      |      |      |
              v      v      v      v
             📱     📱     📱     📱
              |      |      |      |
              +------+------+------+
                     |
              VERIFIED MESSAGE
```

with:

- no Internet
- no Wi-Fi
- no Bluetooth
- no external hardware
- no traditional pairing
- packet integrity
- error recovery
- real-device operation

and, when the advanced layer is enabled:

```text
Adaptive
   +
Reliable
   +
Secure
   +
Self-healing
   +
Multi-hop
```

---

## Core tagline

> **SonicMesh — No infrastructure. No pairing. Just sound.**

