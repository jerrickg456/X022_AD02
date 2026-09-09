import 'dart:async';
import 'dart:typed_data';
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

  // Offline Voice Input (Speech-to-Text)
  bool _isVoiceRecording = false;
  String _sttStatus = '';

  // Offline Acoustic Image Transfer
  Map<String, dynamic>? _preparedImage;
  bool _isTransmittingImage = false;
  double _imageTxProgress = 0.0;
  int _imageTxCurrentChunk = 0;
  bool _isThumbnailMode = true; // true = 64x64 thumbnail, false = 128x128 standard

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
      } else if (type == 'STT_LISTENING') {
        setState(() {
          _isVoiceRecording = true;
          _sttStatus = 'Listening offline... Speak now';
        });
      } else if (type == 'STT_SPEECH_STARTED') {
        setState(() {
          _sttStatus = 'Recognizing speech offline...';
        });
      } else if (type == 'STT_PARTIAL') {
        final text = event['text'] as String? ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _textController.text = text;
            _textController.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
          });
        }
      } else if (type == 'STT_RESULT') {
        final text = event['text'] as String? ?? '';
        setState(() {
          _isVoiceRecording = false;
          _sttStatus = '';
          if (text.isNotEmpty) {
            _textController.text = text;
            _textController.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
          }
        });
        if (text.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: SonicTheme.teal,
              content: Text('Voice transcribed offline: "$text"'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (type == 'STT_SPEECH_ENDED') {
        setState(() {
          _sttStatus = 'Processing speech...';
        });
      } else if (type == 'STT_ERROR') {
        setState(() {
          _isVoiceRecording = false;
          _sttStatus = '';
        });
        final err = event['error'] as String? ?? 'Offline speech recognition error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SonicTheme.coral,
            content: Text(err),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (type == 'IMAGE_TX_PROGRESS') {
        setState(() {
          _isTransmittingImage = true;
          _imageTxProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
          _imageTxCurrentChunk = (event['chunkIndex'] as num?)?.toInt() ?? 0;
        });
      } else if (type == 'IMAGE_TX_COMPLETED') {
        setState(() {
          _isTransmittingImage = false;
          _imageTxProgress = 1.0;
          _statusText = 'Image #${event['imageId']} acoustic broadcast completed!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: SonicTheme.teal,
            content: Text('Acoustic Image transmission complete!'),
            duration: Duration(seconds: 3),
          ),
        );
      } else if (type == 'ERROR') {
        setState(() {
          _isTransmitting = false;
          _isTransmittingImage = false;
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

  Future<void> _toggleVoiceRecording() async {
    if (_isVoiceRecording) {
      await AcousticChannel.instance.stopSpeechRecognition();
      setState(() {
        _isVoiceRecording = false;
        _sttStatus = '';
      });
    } else {
      final hasPerm = await AcousticChannel.instance.hasAudioPermission();
      if (!hasPerm) {
        final granted = await AcousticChannel.instance.requestAudioPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Microphone permission required for voice recording')),
            );
          }
          return;
        }
      }
      setState(() {
        _isVoiceRecording = true;
        _sttStatus = 'Initializing offline speech engine...';
      });
      final ok = await AcousticChannel.instance.startSpeechRecognition();
      if (!ok && mounted) {
        setState(() {
          _isVoiceRecording = false;
          _sttStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline speech recognizer not available on this device')),
        );
      }
    }
  }

  Future<void> _pickImage(bool isThumbnail) async {
    try {
      final res = await AcousticChannel.instance.pickImage(isThumbnail: isThumbnail);
      if (!mounted) return;
      if (res != null) {
        setState(() {
          _preparedImage = res;
          _isThumbnailMode = isThumbnail;
          _imageTxProgress = 0.0;
          _imageTxCurrentChunk = 0;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  Future<void> _transmitPreparedImage() async {
    if (_preparedImage == null) return;
    setState(() {
      _isTransmittingImage = true;
      _imageTxProgress = 0.0;
      _imageTxCurrentChunk = 0;
      _statusText = 'Synthesizing FSK tones for image chunks...';
    });
    final ok = await AcousticChannel.instance.transmitImage();
    if (!ok && mounted) {
      setState(() {
        _isTransmittingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to transmit image')),
      );
    }
  }

  void _discardPreparedImage() {
    setState(() {
      _preparedImage = null;
      _isTransmittingImage = false;
      _imageTxProgress = 0.0;
      _imageTxCurrentChunk = 0;
    });
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
      _isTransmittingImage = false;
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
              _buildImageTransferCard(),
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
        border: Border.all(
          color: _isVoiceRecording ? SonicTheme.coral : SonicTheme.border,
          width: _isVoiceRecording ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
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
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _toggleVoiceRecording,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (_isVoiceRecording ? SonicTheme.coral : SonicTheme.cyan).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (_isVoiceRecording ? SonicTheme.coral : SonicTheme.cyan).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isVoiceRecording ? Icons.mic : Icons.mic_none,
                              size: 13,
                              color: _isVoiceRecording ? SonicTheme.coral : SonicTheme.cyan,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isVoiceRecording ? 'REC' : 'VOICE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: _isVoiceRecording ? SonicTheme.coral : SonicTheme.cyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$byteCount B • ~${estimatedDurationSec}s',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: SonicTheme.teal,
                ),
              ),
            ],
          ),
          if (_isVoiceRecording || _sttStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SonicTheme.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SonicTheme.coral.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2, color: SonicTheme.coral),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sttStatus.isNotEmpty ? _sttStatus : 'Listening offline... Speak now to transcribe into input',
                      style: const TextStyle(fontSize: 11, color: SonicTheme.coral, fontWeight: FontWeight.bold),
                    ),
                  ),
                  InkWell(
                    onTap: _toggleVoiceRecording,
                    child: const Text('STOP', style: TextStyle(fontSize: 10, color: SonicTheme.coral, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
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
            decoration: InputDecoration(
              hintText: 'Enter text to broadcast or tap MIC for offline speech...',
              counterStyle: const TextStyle(color: SonicTheme.textMuted),
              suffixIcon: IconButton(
                icon: Icon(
                  _isVoiceRecording ? Icons.mic : Icons.mic_none,
                  color: _isVoiceRecording ? SonicTheme.coral : SonicTheme.cyan,
                ),
                tooltip: _isVoiceRecording ? 'Stop Offline Speech Input' : 'Offline Voice Input (Speech-to-Text)',
                onPressed: _toggleVoiceRecording,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTransferCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SonicTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isTransmittingImage ? SonicTheme.cyan : SonicTheme.border,
          width: _isTransmittingImage ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Icon(Icons.image_outlined, size: 16, color: SonicTheme.cyan),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'ACOUSTIC IMAGE TRANSFER',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: SonicTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SonicTheme.teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'WEBP CPFSK',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: SonicTheme.teal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Thumbnail vs Standard mode selector
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _isTransmittingImage ? null : () => setState(() => _isThumbnailMode = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _isThumbnailMode ? SonicTheme.cyan.withValues(alpha: 0.15) : SonicTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isThumbnailMode ? SonicTheme.cyan : SonicTheme.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Thumbnail (64×64)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _isThumbnailMode ? FontWeight.w800 : FontWeight.w500,
                          color: _isThumbnailMode ? SonicTheme.cyan : SonicTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _isTransmittingImage ? null : () => setState(() => _isThumbnailMode = false),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !_isThumbnailMode ? SonicTheme.cyan.withValues(alpha: 0.15) : SonicTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !_isThumbnailMode ? SonicTheme.cyan : SonicTheme.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Standard (128×128)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: !_isThumbnailMode ? FontWeight.w800 : FontWeight.w500,
                          color: !_isThumbnailMode ? SonicTheme.cyan : SonicTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_preparedImage == null) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isTransmittingImage ? null : () => _pickImage(_isThumbnailMode),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text(
                  'SELECT IMAGE FROM STORAGE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SonicTheme.cyan,
                  side: const BorderSide(color: SonicTheme.cyan),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ] else ...[
            // Prepared Image Preview & Transmission details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SonicTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SonicTheme.cyan.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _preparedImage!['webpBytes'] != null
                        ? Image.memory(
                            _preparedImage!['webpBytes'] as Uint8List,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : Container(width: 64, height: 64, color: Colors.black26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_preparedImage!['width']}×${_preparedImage!['height']} WebP',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: SonicTheme.textPrimary),
                            ),
                            Text(
                              '${_preparedImage!['fileSize']} B',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SonicTheme.teal, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_preparedImage!['totalChunks']} Chunks • 48 B/chunk',
                          style: const TextStyle(fontSize: 11, color: SonicTheme.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Est. Acoustic Duration: ~${_preparedImage!['estimatedDurationSec']}s',
                          style: const TextStyle(fontSize: 11, color: SonicTheme.cyan, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (_isTransmittingImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _imageTxProgress,
                  backgroundColor: SonicTheme.surfaceElevated,
                  color: SonicTheme.cyan,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transmitting Chunk $_imageTxCurrentChunk/${_preparedImage!['totalChunks']}',
                    style: const TextStyle(fontSize: 10, color: SonicTheme.cyan, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${(_imageTxProgress * 100).toInt()}%',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: SonicTheme.cyan),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTransmittingImage ? null : _transmitPreparedImage,
                    icon: _isTransmittingImage
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.send, size: 16),
                    label: Text(_isTransmittingImage ? 'TRANSMITTING...' : 'TRANSMIT ACOUSTIC IMAGE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SonicTheme.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: SonicTheme.coral),
                  tooltip: 'Discard image',
                  onPressed: _isTransmittingImage ? null : _discardPreparedImage,
                ),
              ],
            ),
          ],
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
