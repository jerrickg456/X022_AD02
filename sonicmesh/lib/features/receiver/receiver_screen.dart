import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../native/acoustic_channel.dart';

class DecodedMessage {
  final String text;
  final int sequence;
  final int total;
  final int bytes;
  final bool crcValid;
  final bool wasReassembled;
  final DateTime timestamp;

  DecodedMessage({
    required this.text,
    required this.sequence,
    required this.total,
    required this.bytes,
    required this.crcValid,
    this.wasReassembled = false,
    required this.timestamp,
  });
}

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> with SingleTickerProviderStateMixin {
  StreamSubscription? _eventSubscription;
  bool _isListening = false;
  double _signalLevel = 0.0;
  bool _hasSignal = false;
  double _distanceMeters = 3.0;
  String _proximityZone = 'STANDBY';
  double _snrDb = 0.0;
  String _statusMessage = 'Microphone standby';

  // Incomplete frame tracking & recovery
  Map<String, dynamic>? _incompleteSession;
  bool _isRequestingRetrans = false;

  final List<DecodedMessage> _messages = [];
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _eventSubscription = AcousticChannel.instance.events.listen((event) {
      if (!mounted) return;
      final type = event['type'] as String?;

      if (type == 'SIGNAL_METRICS') {
        setState(() {
          _signalLevel = ((event['signalLevel'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0);
          _hasSignal = event['hasSignal'] as bool? ?? false;
          _distanceMeters = ((event['estimatedDistanceMeters'] as num?)?.toDouble() ?? 3.0);
          _proximityZone = event['proximityZone'] as String? ?? 'STANDBY';
          _snrDb = ((event['snrDb'] as num?)?.toDouble() ?? 0.0);
        });
      } else if (type == 'RX_PACKET') {
        final payloadText = event['payloadText'] as String? ?? '';
        final seq = (event['sequence'] as num?)?.toInt() ?? 1;
        final tot = (event['total'] as num?)?.toInt() ?? 1;
        final bytes = (event['bytes'] as num?)?.toInt() ?? payloadText.length;
        final crc = event['crcValid'] as bool? ?? true;
        final reassembled = event['wasReassembled'] as bool? ?? false;

        HapticFeedback.mediumImpact();
        setState(() {
          _incompleteSession = null;
          _messages.insert(
            0,
            DecodedMessage(
              text: payloadText,
              sequence: seq,
              total: tot,
              bytes: bytes,
              crcValid: crc,
              wasReassembled: reassembled,
              timestamp: DateTime.now(),
            ),
          );
          _statusMessage = 'Received: "$payloadText" ($bytes B, CRC OK)';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SonicTheme.teal,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.black),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Acoustic Packet Received: $payloadText',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (type == 'RX_INCOMPLETE') {
        setState(() {
          _incompleteSession = event;
          _statusMessage = 'Incomplete frame: ${event['receivedCount']}/${event['totalCount']} chunks. Auto-NACK recovering...';
        });
      } else if (type == 'RETRANS_REQUEST_SENT') {
        setState(() {
          _statusMessage = 'Acoustic NACK beacon broadcasted for chunk #${event['missingSequence']}';
        });
      } else if (type == 'STATE_CHANGED') {
        final state = event['state'] as String?;
        if (state == 'LISTENING') {
          setState(() {
            _isListening = true;
            _statusMessage = 'Listening on microphone for acoustic carrier...';
          });
          _radarController.repeat();
        } else if (state == 'RECEIVING') {
          setState(() {
            _isListening = true;
            _statusMessage = 'Carrier locked! Receiving & demodulating acoustic packet...';
          });
        } else if (state == 'IDLE') {
          setState(() {
            _isListening = false;
            _statusMessage = 'Microphone standby';
          });
          _radarController.stop();
        }
      } else if (type == 'ERROR') {
        setState(() {
          _statusMessage = 'Error: ${event['message']}';
        });
      }
    });
  }

  @override
  void dispose() {
    AcousticChannel.instance.stopListening();
    _radarController.dispose();
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _manualRetransmit() async {
    final session = _incompleteSession;
    if (session == null) return;
    setState(() => _isRequestingRetrans = true);

    final missingSeq = (session['missingSequence'] as num?)?.toInt() ?? 1;
    final total = (session['totalCount'] as num?)?.toInt() ?? 1;

    await AcousticChannel.instance.requestRetransmission(
      missingSequence: missingSeq,
      totalExpected: total,
    );

    if (mounted) {
      setState(() => _isRequestingRetrans = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SonicTheme.amber,
          content: Text('Acoustic NACK emitted for chunk #$missingSeq'),
        ),
      );
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await AcousticChannel.instance.stopListening();
      setState(() {
        _isListening = false;
        _radarController.stop();
        _statusMessage = 'Receiver stopped';
        _signalLevel = 0.0;
        _hasSignal = false;
        _proximityZone = 'STANDBY';
      });
    } else {
      final hasPerm = await AcousticChannel.instance.hasAudioPermission();
      if (!hasPerm) {
        final granted = await AcousticChannel.instance.requestAudioPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Microphone permission required to demodulate audio')),
            );
          }
          return;
        }
      }

      final success = await AcousticChannel.instance.startListening();
      if (success) {
        setState(() {
          _isListening = true;
          _statusMessage = 'Active: Listening for 16.5 / 17.5 kHz carrier...';
        });
        _radarController.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ACOUSTIC RECEIVER & RANGE'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: SonicTheme.textMuted),
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _incompleteSession = null;
                });
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildMonitorCard(),
                    const SizedBox(height: 14),
                    _buildRangeMeterCard(),
                    const SizedBox(height: 14),
                    _buildSignalLevelBar(),
                    if (_incompleteSession != null) ...[
                      const SizedBox(height: 14),
                      _buildIncompleteRecoveryCard(),
                    ],
                    const SizedBox(height: 20),
                    const Divider(color: SonicTheme.border, height: 1),
                    const SizedBox(height: 16),
                    _buildMessageSection(),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitorCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hasSignal ? SonicTheme.teal : SonicTheme.border,
          width: _hasSignal ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (_isListening)
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (context, child) {
                    final progress = _radarController.value;
                    return Container(
                      width: 54 + progress * 20,
                      height: 54 + progress * 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (_hasSignal ? SonicTheme.cyan : SonicTheme.teal)
                              .withValues(alpha: (1.0 - progress) * 0.5),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening
                      ? (_hasSignal ? SonicTheme.cyan.withValues(alpha: 0.2) : SonicTheme.teal.withValues(alpha: 0.15))
                      : SonicTheme.surfaceElevated,
                  border: Border.all(
                    color: _isListening
                        ? (_hasSignal ? SonicTheme.cyan : SonicTheme.teal)
                        : SonicTheme.textMuted,
                    width: 2,
                  ),
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_off,
                  color: _isListening
                      ? (_hasSignal ? SonicTheme.cyan : SonicTheme.teal)
                      : SonicTheme.textMuted,
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening
                            ? (_hasSignal ? SonicTheme.cyan : SonicTheme.teal)
                            : SonicTheme.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isListening
                          ? (_hasSignal ? 'CARRIER LOCK DETECTED' : 'LISTENING')
                          : 'STANDBY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: _isListening
                            ? (_hasSignal ? SonicTheme.cyan : SonicTheme.teal)
                            : SonicTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SonicTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeMeterCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.straighten, size: 16, color: SonicTheme.amber),
                  SizedBox(width: 6),
                  Text(
                    'ACOUSTIC RANGE METER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: SonicTheme.textMuted,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SonicTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _hasSignal ? _proximityZone : 'IDLE',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: SonicTheme.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _hasSignal ? _distanceMeters.toStringAsFixed(1) : '--',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: SonicTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'METERS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SonicTheme.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'SNR: ${_hasSignal ? '+${_snrDb.toStringAsFixed(1)} dB' : '--'}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _snrDb > 10 ? SonicTheme.teal : SonicTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Indoor Path Loss Model',
                    style: TextStyle(fontSize: 10, color: SonicTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _hasSignal ? (1.0 - (_distanceMeters / 12.0)).clamp(0.05, 1.0) : 0.0,
              backgroundColor: SonicTheme.surfaceElevated,
              color: _distanceMeters < 3.0 ? SonicTheme.teal : SonicTheme.amber,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Immediate (0.5m)', style: TextStyle(fontSize: 9, color: SonicTheme.textMuted)),
              Text('Near (2m)', style: TextStyle(fontSize: 9, color: SonicTheme.textMuted)),
              Text('Mid (5m)', style: TextStyle(fontSize: 9, color: SonicTheme.textMuted)),
              Text('Far (>10m)', style: TextStyle(fontSize: 9, color: SonicTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalLevelBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SonicTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ACOUSTIC CARRIER INTENSITY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
              Text(
                '${_signalLevel.toInt()}%',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _signalLevel > 30 ? SonicTheme.cyan : SonicTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_signalLevel / 100.0).clamp(0.0, 1.0),
              backgroundColor: SonicTheme.surface,
              color: _signalLevel > 50 ? SonicTheme.cyan : SonicTheme.teal,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncompleteRecoveryCard() {
    final session = _incompleteSession!;
    final rcv = session['receivedCount'] ?? 1;
    final tot = session['totalCount'] ?? 1;
    final missing = session['missingSequence'] ?? 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.coral.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.coral.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: SonicTheme.coral, size: 20),
              const SizedBox(width: 8),
              const Text(
                'INCOMPLETE RECEPTION DETECTED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: SonicTheme.coral,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SonicTheme.coral.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$rcv/$tot Chunks',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: SonicTheme.coral,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Received $rcv of $tot packet chunks. Missing sequence #$missing due to acoustic fading or noise.',
            style: const TextStyle(fontSize: 12, color: SonicTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _isRequestingRetrans ? null : _manualRetransmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: SonicTheme.coral,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isRequestingRetrans
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text(
                'REQUEST RETRANSMISSION (ACOUSTIC NACK)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageSection() {
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }
    return Column(
      children: _messages.map((msg) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildMessageCard(msg),
      )).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speaker_notes_off_outlined, color: SonicTheme.textMuted.withValues(alpha: 0.5), size: 48),
          const SizedBox(height: 14),
          const Text(
            'No Packets Received Yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: SonicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Transmissions from nearby SonicMesh devices will appear here in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: SonicTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(DecodedMessage msg) {
    final timeStr = '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}:${msg.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (msg.crcValid ? SonicTheme.teal : SonicTheme.coral).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (msg.crcValid ? SonicTheme.teal : SonicTheme.coral).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          msg.crcValid ? Icons.verified_outlined : Icons.error_outline,
                          size: 13,
                          color: msg.crcValid ? SonicTheme.teal : SonicTheme.coral,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          msg.crcValid ? 'CRC-32 VERIFIED' : 'CRC ERROR',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: msg.crcValid ? SonicTheme.teal : SonicTheme.coral,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (msg.wasReassembled) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: SonicTheme.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ARQ REASSEMBLED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: SonicTheme.cyan,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '$timeStr • ${msg.bytes} B',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: SonicTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            msg.text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: SonicTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Seq ${msg.sequence}/${msg.total}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: SonicTheme.textMuted,
                ),
              ),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied to clipboard')),
                  );
                },
                child: Row(
                  children: const [
                    Icon(Icons.copy, size: 14, color: SonicTheme.cyan),
                    SizedBox(width: 4),
                    Text(
                      'COPY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: SonicTheme.cyan,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: SonicTheme.surfaceElevated,
        border: Border(top: BorderSide(color: SonicTheme.border)),
      ),
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _toggleListening,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isListening ? SonicTheme.coral.withValues(alpha: 0.15) : SonicTheme.teal,
            foregroundColor: _isListening ? SonicTheme.coral : Colors.black,
            side: BorderSide(
              color: _isListening ? SonicTheme.coral : Colors.transparent,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(_isListening ? Icons.stop : Icons.hearing),
          label: Text(
            _isListening ? 'STOP LISTENING' : 'START ACOUSTIC LISTENER',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
