# SonicMesh: Product Requirements Document (PRD)

### Infrastructure-Free Acoustic Communication Network for Android
**Version:** 1.2.0  
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
| **Cloud / External Servers**| **STRICTLY PROHIBITED** | Pure device-to-device physical acoustic waves. |
| **Required Permissions** | **MICROPHONE ONLY** | `android.permission.RECORD_AUDIO` strictly for acoustic demodulation. |

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
* **Continuous Phase Guarantee:** Phase continuity ($\Delta \theta = 0$) maintained across bit transitions to eliminate audio pops and spectral splatter.
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
| 0xAA 0xAA...   | 0x7E (01111110)| Ver/Type/Seq.. | UTF-8 Data     | IEEE 802.3
+----------------+----------------+----------------+----------------+
```

### 4.2 Header Fields (8 Bytes Big-Endian)
1. **Protocol Version (1 Byte):** Default `0x01`.
2. **Packet Type (1 Byte):**
   * `0x01` — `TYPE_DATA` (Standard text payload)
   * `0x02` — `TYPE_PING` (Beacon heartbeat)
   * `0x03` — `TYPE_ACK` (Receipt acknowledgment)
   * `0x04` — `TYPE_RETRANS_REQ` (Acoustic NACK requesting missing packet chunk)
   * `0x05` — `TYPE_RETRANS_RESP` (Autonomous retransmission chunk response)
3. **Sequence Number (2 Bytes):** Index of current fragment ($1 \le seq \le total$).
4. **Total Packets (2 Bytes):** Total fragments in current transmission session.
5. **Payload Length (2 Bytes):** Byte length of payload ($0 \le len \le 1024$).

### 4.3 Error Detection: CRC-32
* **Polynomial:** IEEE 802.3 standard (`0xEDB88320` reversed).
* Computed strictly over Header + Payload. Frames failing CRC-32 are rejected or flagged for retransmission.

---

## 5. Incomplete Reception Recovery & Autonomous ARQ

Due to room reverberation, distance attenuation, or transient noise, receivers may miss frames or receive partial fragments. SonicMesh incorporates a dual-tier recovery system:

```mermaid
sequenceDiagram
    participant TX as Transmitter
    participant RX as Receiver
    TX->>RX: Chunks 1/2 Transmitted
    Note over RX: Fading causes Chunk 2/2 dropped
    Note over RX: Incomplete reception detected (Missing #2)
    RX->>TX: Acoustic NACK: TYPE_RETRANS_REQ(missing=2, total=2)
    Note over TX: Cache hit: Chunk #2 found in memory
    TX->>RX: Autonomous Re-broadcast: TYPE_RETRANS_RESP(seq=2)
    Note over RX: Reassembly complete & CRC-32 verified!
```

### 5.1 Multi-Chunk Fragmentation & Reassembly
* Long messages or multi-hop relays are automatically fragmented into indexed chunks ($seq / total$).
* The receiver tracks arrived sequence indices in a sliding reassembly window.
* When all fragments arrive, the complete message is reassembled in order and verified against CRC-32.

### 5.2 Reactive Acoustic ARQ (NACK)
* When a receiver detects a partial session (e.g., received Chunk 1, missing Chunk 2) or a burst terminates without valid CRC:
  * Emits an ultra-compact acoustic NACK beacon (`TYPE_RETRANS_REQ`, 4-byte payload).
  * Any nearby mesh peer or the original transmitter holding the message in cache autonomously serves the missing chunk (`TYPE_RETRANS_RESP`).
  * Eliminates the need for the sender to manually coordinate with each receiver.

### 5.3 Proactive Redundancy Profiles
Transmitters can operate in one of three reliability profiles:
1. **1x Standard:** Single transmission burst for normal acoustic channels.
2. **2x Robust (ARQ):** Dual burst repetition with $250\text{ ms}$ guard silence.
3. **3x High-Noise:** Triple burst repetition for distant or noisy environments.

---

## 6. Acoustic Range & Distance Estimator (Range Meter)

SonicMesh implements a real-time **Acoustic Range Meter** estimating physical distance between transmitter and receiver without GPS, Wi-Fi RTT, or Bluetooth RSSI.

### 6.1 Mathematical Model: Log-Distance Acoustic Path Loss
Acoustic wave intensity decreases geometrically in an indoor room:
$$P(d) = P(d_0) \cdot \left(\frac{d_0}{d}\right)^\gamma$$

Solving for distance $d$ with reference distance $d_0 = 1.0\text{ m}$:
$$d = \left(\frac{P_{1\text{m}}}{\max(P_0, P_1) + \epsilon}\right)^{\frac{1}{\gamma}}$$

* **$P_{1\text{m}}$:** Reference carrier power at $1\text{ meter}$ ($0.50$ calibrated).
* **$\gamma$:** Indoor acoustic path loss exponent ($1.9$ nominal).
* **Smoothing Filter:** $\bar{d}_t = 0.7 \cdot \bar{d}_{t-1} + 0.3 \cdot d_t$ to dampen air turbulence and room reflections.

### 6.2 Proximity Classification Zones
| Zone | Distance Range | Physical Context |
| :--- | :--- | :--- |
| **IMMEDIATE** | $< 1.0\text{ m}$ | Direct table contact, handheld proximity. |
| **NEAR** | $1.0\text{ m} - 3.0\text{ m}$ | Same desk or workstation area. |
| **MID-RANGE** | $3.0\text{ m} - 7.0\text{ m}$ | Across the room. |
| **FAR** | $> 7.0\text{ m}$ | Long-range indoor link, threshold of SNR. |

---

## 7. System Architecture & Native DSP Implementation

```
+-------------------------------------------------------------+
|                      FLUTTER UI LAYER                       |
|   (Theme / Routes / Broadcast / Receiver / Range / Diag)    |
+-------------------------------------------------------------+
                              |
    MethodChannel ("control") | EventChannel ("events")
                              |
+-------------------------------------------------------------+
|                     ANDROID KOTLIN NATIVE                   |
|                   com.sonicmesh.app.acoustic                |
|                                                             |
|  +----------------+  +----------------+  +---------------+  |
|  | Modulator.kt   |  | AudioPlayer.kt |  | Packet.kt     |  |
|  +----------------+  +----------------+  +---------------+  |
|                                                             |
|  +----------------+  +----------------+  +---------------+  |
|  | Demodulator.kt |  | AudioCapture.kt|  | Goertzel.kt   |  |
|  +----------------+  +----------------+  +---------------+  |
|                                                             |
|  +----------------+  +----------------+  +---------------+  |
|  | SignalDetector |  | AcousticEngine |  | Crc32.kt      |  |
|  +----------------+  +----------------+  +---------------+  |
+-------------------------------------------------------------+
```

### 7.1 Native Kotlin DSP Components
* **`AcousticEngine.kt`:** Finite state machine (`IDLE`, `TRANSMITTING`, `LISTENING`, `RECEIVING`, `RECOVERING`). Manages $30\text{-second}$ circular audio history, burst lifecycle, ARQ reassembly, and telemetry dispatch.
* **`Modulator.kt`:** Converts byte frames into continuous-phase sine wave PCM samples with raised-cosine envelopes.
* **`Demodulator.kt`:** Over-the-air demodulator with:
  * Automatic frequency response gain balancing (compensating for $17.5\text{ kHz}$ microphone attenuation).
  * Center 50% symbol windowing in Goertzel DFT to eliminate inter-symbol interference and edge multipath.
  * 8-phase clock synchronization.
  * Hamming distance $\le 1$ tolerant sync word matching with CRC-32 validation.
* **`Goertzel.kt`:** Second-order IIR filter computing discrete Fourier transform power at specific target frequencies with $O(N)$ efficiency.
* **`SignalDetector.kt`:** Real-time carrier energy detection, RMS level measurement, SNR estimation, and acoustic distance computation.
* **`AudioCapture.kt`:** Non-blocking PCM capture using `AudioRecord` (`VOICE_RECOGNITION` source fallback).
* **`AudioPlayer.kt`:** Low-latency PCM playback using `AudioTrack`.

---

## 8. User Interface & Experience Design

* **Design Philosophy:** Cyberpunk military-grade tactical dark mode with glassmorphic cards, glowing cyan/teal accents, and monospace telemetry.
* **Haptic Feedback:** Tactile impact on carrier lock and successful packet arrival.
* **Interactive Consoles:**
  * **Broadcast Console:** Text entry, payload byte count, dynamic duration estimation, quick dispatch presets (`HELLO MESH`, `SOS: Medical Needed Grid 4`), proactive redundancy selector (`1x`, `2x`, `3x`), and live autonomous relay activity log.
  * **Receiver & Range Console:** Animated radar ring indicator, real-time Acoustic Range Meter ($2.1\text{ m}$ readout, proximity zone badge, SNR in dB), live carrier intensity bar, Incomplete Reception Recovery banner with manual/auto-NACK trigger, and verified message cards with copy actions.
  * **DSP Diagnostics Console:** Complete compliance policy review, in-memory encode-modulate-demodulate loopback testing, and live PHY parameters display.

---

## 9. Hardware & Operating Environment

* **Target OS:** Android 7.0+ (API Level 24 through 35+).
* **Validated Device:** `iQOO I2223` (Android 15, API 35, ARM64-v8a).
* **Audio Hardware:** Built-in mono/stereo speakers and microphones.
* **Memory Footprint:** $\approx 45\text{ MB}$ runtime heap; ring buffer consumes only $2.6\text{ MB}$ RAM.
* **Battery Impact:** Low; Goertzel evaluation runs only over short symbol windows on native coroutines.

---

## 10. Verification Matrix

| Test Suite | Target | Status |
| :--- | :--- | :--- |
| `testDirectModulateDemodulate` | In-memory encode $\to$ modulate $\to$ demodulate $\to$ decode | **PASSED** |
| `testDemodulationWithNoiseAndSilencePadding` | Signal with leading/trailing noise & ambient jitter | **PASSED** |
| `testDemodulationWithChannelGainTilt` | Phone mic high-frequency roll-off (6 dB tilt) | **PASSED** |
| `testRetransmissionRequestPacket` | NACK packet encoding, parsing, and CRC verification | **PASSED** |
| `testRangeMeterDistanceEstimation` | Log-distance path loss distance calculation | **PASSED** |
| `flutter test` | Flutter widget hierarchy and routing test suite | **PASSED** |
| `Live Hardware Validation` | Live Carrier Lock, 2.1m Range Meter, UI telemetry on real phone | **PASSED** |
| `Git Synchronization` | Remote push to `origin main` on GitHub | **PASSED** |
