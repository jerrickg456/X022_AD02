# SonicMesh: Product Requirements Document (PRD)

### Infrastructure-Free Acoustic Communication Network for Android
**Version:** 1.4.0  
**Status:** Implemented & Verified Live on Hardware  
**Repository:** [github.com/jerrickg456/X022_AD02](https://github.com/jerrickg456/X022_AD02)  

---

## 1. Executive Summary & Vision

**SonicMesh** transforms standard Android smartphones into an ad-hoc, peer-to-peer acoustic mesh communication network using **only built-in loudspeakers and microphones**. 

Operating entirely in the near-ultrasound spectrum ($16.5\text{ kHz} - 17.5\text{ kHz}$), SonicMesh requires **zero Wi-Fi, zero Bluetooth, zero cellular data, zero internet, and zero external hardware**. It is designed for mission-critical emergency disaster relief, battlefield stealth operations, underground subway tunnels, and deep air-gapped environments where conventional radiofrequency (RF) channels are jammed, monitored, or unavailable.

---

## 2. Infrastructure-Free Compliance Policy

| Channel | Status | Compliance Verification |
| :--- | :--- | :--- |
| **Wi-Fi** | **STRICTLY PROHIBITED** | No network permissions (`INTERNET`, `ACCESS_WIFI_STATE`) in AndroidManifest. |
| **Bluetooth / BLE** | **STRICTLY PROHIBITED** | No Bluetooth permissions (`BLUETOOTH`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`). |
| **Cellular Data / GSM / 5G**| **STRICTLY PROHIBITED** | Functions 100% in Airplane Mode. |
| **Cloud / External Servers**| **STRICTLY PROHIBITED** | Pure device-to-device physical acoustic waves and local on-device processing. |
| **Required Permissions** | **MICROPHONE ONLY** | `android.permission.RECORD_AUDIO` strictly for acoustic demodulation and local offline voice transcription. |

---

## 3. Acoustic Physical Layer (PHY) Specifications

The physical layer modulates binary data into continuous acoustic sound waves using **Continuous-Phase Frequency Shift Keying (2-CPFSK)** at a standard $44.1\text{ kHz}$ 16-bit mono PCM sample rate.

```
+-----------------------------------------------------------------------+
|  GUARD (50ms) | PREAMBLE (4x 0xAA) | SYNC (0x7E) | FRAME BODY | CRC32 |
+-----------------------------------------------------------------------+
```

### 3.1 Modulation Parameters
* **Mark Frequency ($f_0$ - Binary 0):** $16,500\text{ Hz}$ ($16.5\text{ kHz}$)
* **Space Frequency ($f_1$ - Binary 1):** $17,500\text{ Hz}$ ($17.5\text{ kHz}$)
* **Channel Separation ($\Delta f$):** $1,000\text{ Hz}$ (well above the minimum orthogonal threshold)
* **Symbol Duration ($T_s$):** $40\text{ ms}$
* **Baud Rate:** $25\text{ Baud}$ ($25\text{ bits/second}$)
* **Samples Per Symbol ($N$):** $1,764\text{ samples}$ at $44,100\text{ Hz}$
* **Continuous Phase Guarantee:** Phase continuity ($\Delta \theta = 0$) maintained across bit transitions to eliminate audio clicks and spectral splatter.
* **Envelope Shaping:** Raised cosine edge ramp ($5\text{ ms}$) on transmission burst start and end.

### 3.2 Human Audibility & Stealth
* **Near-Ultrasound Profile:** Operating at $16.5\text{ kHz} - 17.5\text{ kHz}$ places the signal at the upper threshold of human adult hearing, ensuring silent or near-imperceptible operation in public rooms.
* **Audible Profile Fallback:** Diagnostic mode capable of running at $1.8\text{ kHz} / 2.4\text{ kHz}$ for extreme acoustic environments through dense partitions.

---

## 4. Data Link & Packet Architecture

### 4.1 Frame Structure
```
+----------------+----------------+----------------+----------------+
| Preamble (4 B) | Sync Word (1B) | Header (8 B)   | Payload (N B)  | CRC32 (4 B)
| 0xAA 0xAA...   | 0x7E (01111110)| Ver/Type/Seq.. | Binary/Text    | IEEE 802.3
+----------------+----------------+----------------+----------------+
```

### 4.2 Packet Types & Opcodes
| Opcode | Packet Type | Description |
| :--- | :--- | :--- |
| `0x01` | `TYPE_DATA` | Standard broadcast text payload. |
| `0x02` | `TYPE_PING` | Ultrasonic beacon heartbeat query. |
| `0x03` | `TYPE_ACK` | Signed delivery receipt acknowledgment. |
| `0x04` | `TYPE_RETRANS_REQ` | Acoustic NACK requesting missing packet chunks. |
| `0x05` | `TYPE_RETRANS_RESP` | Autonomous retransmission chunk response. |
| `0x06` | `TYPE_PONG` | Discovery response with device ID, name, and ECDSA fingerprint. |
| `0x07` | `TYPE_PRIVATE_MESSAGE` | Targeted unicast payload addressed to specific recipient. |
| `0x10` | `TYPE_IMAGE_START` | Image transfer initiation (dimensions, byte size, format, total chunks). |
| `0x11` | `TYPE_IMAGE_CHUNK` | 48-byte sliced binary image payload with chunk sequence index. |
| `0x12` | `TYPE_IMAGE_END` | Image transfer termination with full-file CRC-32 integrity seal. |

### 4.3 Error Detection: CRC-32
* **Polynomial:** IEEE 802.3 standard (`0xEDB88320` reversed).
* Computed strictly over Header + Payload. Frames failing CRC-32 are rejected or flagged for retransmission.

---

## 5. Persistent Broadcast Timer

For search-and-rescue beacons, automated SOS alerts, and emergency area status broadcasts, SonicMesh provides an automated persistent transmission engine:

* **Configurable Durations:** Presets for 30 seconds, 1 minute, 2 minutes, 5 minutes, or custom timer windows.
* **In-Memory Caching:** Automatically caches the latest message payload in native RAM.
* **Configurable Repeat Interval:** Automatically retransmits the cached acoustic packet every configurable interval (default: 5 seconds) until the timer expires.
* **Live Telemetry & Cancellation:** Real-time countdown timer, live repeat counter, animated transmission waves, and a single-tap **Stop Broadcast** button that instantly halts the hardware synthesizer.
* **100% Offline:** Operates entirely over the existing 2-CPFSK physical pipeline without any network calls.

---

## 6. Acoustic Store-and-Forward Relay Node

To bridge communication gaps when transmitters and receivers are separated by distance or acoustic barriers ($\text{Phone A} \to \text{Phone B} \to \text{Phone C}$):

```
[Phone A] ──(Weak 16.5-17.5 kHz FSK)──> [Phone B Mic]
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       │ 1. AudioRecord captures weak PCM stream   │
                       │ 2. SignalDetector tracks carrier power    │
                       │ 3. Goertzel/Demodulator decodes symbols   │
                       │ 4. Frame Parser extracts packet bytes     │
                       │ 5. CRC32 Checksum verifies 100% integrity │
                       │ 6. Deduplication Cache prevents loops     │
                       │ 7. 500ms Turnaround Guard Delay pauses    │
                       │ 8. Modulator synthesizes BRAND-NEW CPFSK  │
                       │ 9. AudioTrack plays full-power signal     │
                       └─────────────────────┬─────────────────────┘
                                             │
                                   [Phone B Speaker]
                                             │
                    ──(Fresh, Strong 100% Acoustic Signal)──> [Phone C]
```

### 6.1 Zero Analog Amplification Rule
Phone B strictly **never amplifies or echoes microphone audio**. The weak audio signal is fully demodulated to its raw digital bytes, verified for 100% CRC-32 integrity, and re-synthesized as a pristine, brand-new CPFSK carrier at full amplitude.

### 6.2 Echo & Loop Suppression
1. **60-Second Signature Deduplication:** Packets are hashed by type, sequence, and payload CRC32. Repeated packets heard within 60 seconds are suppressed (`LOOP SUPPRESSED`).
2. **Turnaround Guard Delay:** Configurable 500ms delay between reception and relay re-broadcast allows room reverberations to clear.
3. **Half-Duplex Silencing:** Microphone capture is ignored during transmitter playback to prevent self-triggering.

---

## 7. Offline Microphone Voice Input (Speech-to-Text)

To facilitate rapid hands-free broadcast creation during emergency or tactical operations:

* **Engine:** Android native `SpeechRecognizer` configured with `EXTRA_PREFER_OFFLINE = true` and offline fallback service binding.
* **API Compatibility:** Declared `<queries>` for `RecognitionService` in `AndroidManifest.xml` for full Android 11+ (API 30+) compliance.
* **User Workflow:**
  1. User taps the **VOICE** badge or microphone icon in the Broadcast Console.
  2. Offline recognizer activates with live RMS level audio wave feedback.
  3. Spoken words are transcribed into text in real-time.
  4. Transcribed text auto-fills the message payload field, allowing the user to review, edit, or append text prior to acoustic transmission.

---

## 8. Offline Read Aloud Speaker (Text-to-Speech)

To support eyes-free situation awareness and auditory alert dispatch:

* **Engine:** Android native `TextToSpeech` engine (`com.google.android.tts` / local voice synthesis engine).
* **API Compatibility:** Declared `<queries>` for `android.intent.action.TTS_SERVICE` in `AndroidManifest.xml`.
* **Controls & Lifecycle:**
  * Interactive `READ`, `PAUSE`, `RESUME`, and `STOP` controls.
  * Real-time `UtteranceProgressListener` tracking (`TTS_STARTED`, `TTS_COMPLETED`, `TTS_STOPPED`, `TTS_ERROR`).
* **Placement:**
  * **Receiver Console:** Speaker controls on every decoded message card.
  * **Private Messaging:** Quick read-aloud speaker icon on all received incoming chat bubbles.

---

## 9. Complete Offline Acoustic Image Transfer

Enables transmission of compressed visual data across the acoustic channel without any RF connectivity:

```
[Gallery / Camera Image]
          │
          ▼
[Intelligent Scaler]
   • Thumbnail Mode: 64×64 pixels (ultra-fast transmission)
   • Standard Mode: 128×128 pixels (detailed visual data)
          │
          ▼
[WebP Binary Compression (Quality 50-70)]
   • Compress to compact binary stream (300 - 1500 bytes)
          │
          ▼
[Packet Fragmentation (48-Byte Payload Frames)]
   • Frame 0: TYPE_IMAGE_START (Dimensions, Size, Format, Chunks)
   • Frame 1..N: TYPE_IMAGE_CHUNK (Chunk Index, Payload, Chunk CRC32)
   • Frame N+1: TYPE_IMAGE_END (Total Chunks, Full-File CRC32)
          │
          ▼
[2-CPFSK Acoustic Synthesizer (25 Baud)]
          │
     AIR LINK (Speaker ──> Microphone)
          │
          ▼
[Receiver Demodulator & Chunk Store]
   • Per-chunk CRC32 validation
   • Sequential buffer reassembly
   • Full-file CRC32 verification
   • Persisted to local storage (`filesDir/sonic_images/img_{id}.webp`)
   • Verified Image Preview Card with dimensions and byte badges
```

### 9.1 Pre-Transmission Telemetry
Before transmission begins, the sender UI calculates and displays:
* WebP compressed byte count.
* Total required acoustic chunk frames.
* Precise estimated transmission duration in seconds ($\approx \text{chunks} \times 17.5\text{s}$).

---

## 10. Acoustic Range & Distance Estimator (Range Meter)

SonicMesh implements a real-time **Acoustic Range Meter** estimating physical distance between transmitter and receiver using the **Log-Distance Acoustic Path Loss Model**:

$$d = \left(\frac{P_{1\text{m}}}{\max(P_0, P_1) + \epsilon}\right)^{\frac{1}{\gamma}}$$

* **$P_{1\text{m}}$:** Calibrated reference carrier power at $1\text{ meter}$ ($0.50$).
* **$\gamma$:** Indoor acoustic path loss exponent ($1.9$ nominal).
* **Zones:** `IMMEDIATE (< 1.0m)`, `NEAR (1.0m - 3.0m)`, `MID-RANGE (3.0m - 7.0m)`, `FAR (> 7.0m)`.

---

## 11. Receiver Validation & Targeted Private Unicast Protocol

Guarantees confidential point-to-point delivery prior to message dispatch:

1. **PING Discovery (`0x02`):** Broadcasts acoustic ping to discover nearby active receivers.
2. **PONG Response (`0x06`):** Receivers respond with device ID, friendly name, and synthetic ECDSA P-256 public key fingerprint.
3. **Targeted Selection:** Sender selects recipient; non-target devices discard unaddressed packets.
4. **Signed Acoustic ACK (`0x03`):** Target recipient autonomously replies with an acoustic delivery receipt, updating sender status to `DELIVERED [VERIFIED ACK]`.

---

## 12. System Architecture & Component Mapping

```
+-------------------------------------------------------------+
|                      FLUTTER UI LAYER                       |
|   (Broadcast / Receiver / Private / Relay / Persistent)     |
+-------------------------------------------------------------+
                              │
    MethodChannel ("control") │ EventChannel ("events")
                              │
+-------------------------------------------------------------+
|                     ANDROID KOTLIN NATIVE                   |
|  +--------------------+  +--------------------+  +-------+  |
|  | SpeechRecognizer   |  | TextToSpeech       |  | Packet|  |
|  | Manager.kt         |  | Manager.kt         |  | .kt   |  |
|  +--------------------+  +--------------------+  +-------+  |
|  +--------------------+  +--------------------+  +-------+  |
|  | ImageTransfer      |  | IdentityManager    |  | FSK   |  |
|  | Manager.kt         |  | .kt                |  | Mod.kt|  |
|  +--------------------+  +--------------------+  +-------+  |
|  +--------------------+  +--------------------+  +-------+  |
|  | AcousticEngine.kt  |  | AudioCapture.kt    |  | Goert.|  |
|  +--------------------+  +--------------------+  +-------+  |
+-------------------------------------------------------------+
```

---

## 13. Verification Matrix

| Test Suite | Target Capability | Status |
| :--- | :--- | :--- |
| `testDirectModulateDemodulate` | In-memory encode $\to$ modulate $\to$ demodulate $\to$ decode | **PASSED** |
| `testDemodulationWithNoiseAndSilencePadding` | Signal resilience under background noise & jitter | **PASSED** |
| `testDemodulationWithChannelGainTilt` | Phone mic high-frequency roll-off (6 dB tilt) | **PASSED** |
| `testRangeMeterDistanceEstimation` | Log-distance path loss distance estimation | **PASSED** |
| `testPingPongPacketEncodingAndParsing` | Ultrasonic PING discovery & PONG response parsing | **PASSED** |
| `testPrivateMessageTargetingAndAck` | Targeted unicast filtering & signed acoustic ACK | **PASSED** |
| `testPersistentBroadcastTimer` | Duration countdown, cached retransmission, cancel | **PASSED** |
| `testAcousticRelayPipeline` | Store-and-forward digital reconstruction & deduplication | **PASSED** |
| `testOfflineSpeechRecognition` | Offline voice capture & auto-fill text integration | **PASSED** |
| `testOfflineTextToSpeech` | Local TTS engine binding, play/pause/stop lifecycle | **PASSED** |
| `testAcousticImageTransfer` | WebP compression, chunk framing, CRC-32 reassembly | **PASSED** |
| `flutter test` (8 test suites) | Full widget hierarchy, UI state, and channel mocks | **PASSED** |
| `Live Hardware Deployment` | Physical Android device (`10BD5H1XDZ0003N`) verification | **PASSED** |
| `Git Synchronization` | Remote push to `origin main` on GitHub | **PASSED** |
