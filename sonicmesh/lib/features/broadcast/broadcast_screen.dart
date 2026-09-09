import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../native/acoustic_channel.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController(text: 'HELLO MESH');
  StreamSubscription? _eventSubscription;
  
  bool _isTransmitting = false;
  double _progress = 0.0;
  String _statusText = 'Ready to broadcast';
  int _audioDurationMs = 0;
  int _audioSamples = 0;
  int _currentRepetition = 1;
  int _repetitions = 1; // 1x, 2x, or 3x proactive redundancy

  // Relay activity notification
  String? _relayStatus;

  late AnimationController _waveController;

  final List<String> _quickMessages = [
    'HELLO MESH',
    'SOS: Medical Needed Grid 4',
    'Rendezvous Point Alpha',
    'Grid Sector Clear',
    'Ping: Acoustic Beacon',
  ];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _eventSubscription = AcousticChannel.instance.events.listen((event) {
      if (!mounted) return;
      final type = event['type'] as String?;

      if (type == 'TX_STARTED') {
        setState(() {
          _isTransmitting = true;
          _progress = 0.0;
          _statusText = 'Transmitting audio tones...';
          _audioDurationMs = (event['durationMs'] as num?)?.toInt() ?? 0;
          _audioSamples = (event['totalAudioSamples'] as num?)?.toInt() ?? 0;
        });
      } else if (type == 'TX_PROGRESS') {
        setState(() {
          _progress = (event['progress'] as num?)?.toDouble() ?? 0.0;
          _currentRepetition = (event['repetition'] as num?)?.toInt() ?? 1;
        });
      } else if (type == 'TX_COMPLETED') {
        setState(() {
          _isTransmitting = false;
          _progress = 1.0;
          _statusText = 'Transmission completed successfully';
        });
      } else if (type == 'RETRANS_REQUESTED') {
        setState(() {
          _relayStatus = 'Peer requested missing chunk #${event['missingSequence']}. Autonomously re-broadcasting...';
        });
      } else if (type == 'RETRANS_SERVED') {
        setState(() {
          _relayStatus = 'Served autonomous retransmission for chunk #${event['sequence']} (${event['bytes']} B)';
        });
      } else if (type == 'ERROR') {
        setState(() {
          _isTransmitting = false;
          _statusText = 'Error: ${event['message']}';
        });
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _eventSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _startBroadcast() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message to broadcast')),
      );
      return;
    }

    setState(() {
      _isTransmitting = true;
      _progress = 0.0;
      _statusText = 'Encoding packet & synthesizing FSK waveform...';
    });

    await AcousticChannel.instance.startBroadcast(text, repetitions: _repetitions);
  }

  Future<void> _stopBroadcast() async {
    await AcousticChannel.instance.stopBroadcast();
    setState(() {
      _isTransmitting = false;
      _progress = 0.0;
      _statusText = 'Broadcast aborted';
    });
  }

  @override
  Widget build(BuildContext context) {
    final byteCount = _textController.text.codeUnits.length;
    final estimatedDurationSec = (((17 + byteCount) * 8 * 0.04 + 0.1) * _repetitions).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ACOUSTIC TRANSMITTER'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusHeader(),
              if (_relayStatus != null) ...[
                const SizedBox(height: 14),
                _buildRelayCard(),
              ],
              const SizedBox(height: 18),
              _buildMessageInputCard(byteCount, estimatedDurationSec),
              const SizedBox(height: 16),
              _buildRedundancySelector(),
              const SizedBox(height: 16),
              _buildQuickPresets(),
              const SizedBox(height: 18),
              _buildProtocolCard(),
              const SizedBox(height: 24),
              _buildActionButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isTransmitting ? SonicTheme.cyan : SonicTheme.border,
          width: _isTransmitting ? 1.5 : 1.0,
        ),
      ),
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
                  color: _isTransmitting ? SonicTheme.cyan : SonicTheme.teal,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isTransmitting
                    ? 'TRANSMITTING (BURST $_currentRepetition/$_repetitions)'
                    : 'TRANSMITTER IDLE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: _isTransmitting ? SonicTheme.cyan : SonicTheme.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _statusText,
            style: const TextStyle(
              fontSize: 14,
              color: SonicTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_isTransmitting) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: SonicTheme.surfaceElevated,
                color: SonicTheme.cyan,
                minHeight: 6,
              ),
            ),
            if (_audioDurationMs > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Acoustic Frame: ~${(_audioDurationMs / 1000).toStringAsFixed(1)}s ($_audioSamples samples)',
                style: const TextStyle(fontSize: 10, color: SonicTheme.textMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRelayCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SonicTheme.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SonicTheme.teal.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.autorenew, color: SonicTheme.teal, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _relayStatus!,
              style: const TextStyle(fontSize: 12, color: SonicTheme.teal, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: SonicTheme.teal),
            onPressed: () => setState(() => _relayStatus = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInputCard(int byteCount, String estimatedDurationSec) {
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
              const Text(
                'PAYLOAD MESSAGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
              Text(
                '$byteCount Bytes • ~$estimatedDurationSec s',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: SonicTheme.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 3,
            maxLength: 128,
            style: const TextStyle(
              fontSize: 16,
              color: SonicTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: 'Enter text to broadcast...',
              counterStyle: TextStyle(color: SonicTheme.textMuted),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildRedundancySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, size: 15, color: SonicTheme.cyan),
              SizedBox(width: 6),
              Text(
                'PROACTIVE RELIABILITY & REDUNDANCY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: SonicTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildRepetitionOption(1, '1x Standard'),
              const SizedBox(width: 8),
              _buildRepetitionOption(2, '2x Robust (ARQ)'),
              const SizedBox(width: 8),
              _buildRepetitionOption(3, '3x High-Noise'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRepetitionOption(int count, String label) {
    final isSelected = _repetitions == count;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _repetitions = count),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? SonicTheme.cyan.withValues(alpha: 0.15) : SonicTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? SonicTheme.cyan : SonicTheme.border,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? SonicTheme.cyan : SonicTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK DISPATCH PRESETS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: SonicTheme.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickMessages.map((msg) {
            final isSelected = _textController.text == msg;
            return ChoiceChip(
              label: Text(
                msg,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.black : SonicTheme.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: SonicTheme.teal,
              backgroundColor: SonicTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? SonicTheme.teal : SonicTheme.border,
                ),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _textController.text = msg;
                  });
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildProtocolCard() {
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
          const Text(
            'SYNTHESIS PARAMETERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: SonicTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          _buildParamRow('Carrier Mark (0):', '16,500 Hz'),
          const SizedBox(height: 6),
          _buildParamRow('Carrier Space (1):', '17,500 Hz'),
          const SizedBox(height: 6),
          _buildParamRow('Baud Rate:', '25 Baud (40ms / symbol)'),
        ],
      ),
    );
  }

  Widget _buildParamRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: SonicTheme.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: SonicTheme.cyan)),
      ],
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _isTransmitting ? _stopBroadcast : _startBroadcast,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isTransmitting ? SonicTheme.coral : SonicTheme.cyan,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(_isTransmitting ? Icons.stop : Icons.volume_up),
        label: Text(
          _isTransmitting ? 'ABORT TRANSMISSION' : 'BROADCAST OVER SPEAKER',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
