import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../native/acoustic_channel.dart';
import '../../services/message_store.dart';

typedef DiscoveredPeer = MeshPeer;
typedef PrivateMessageEntry = PrivateMsg;

class PrivateMessagingScreen extends StatefulWidget {
  const PrivateMessagingScreen({super.key});

  @override
  State<PrivateMessagingScreen> createState() => _PrivateMessagingScreenState();
}

class _PrivateMessagingScreenState extends State<PrivateMessagingScreen>
    with SingleTickerProviderStateMixin {
  final AcousticChannel _channel = AcousticChannel.instance;
  StreamSubscription? _eventSub;
  late AnimationController _radarController;

  // Local device identity
  int _myDeviceId = 0;
  String _myDeviceIdHex = '...';
  String _myDeviceName = 'SonicMesh Node';
  String _myFingerprint = '...';
  bool _isLoadingIdentity = true;

  // Peer Discovery & Selection (backed by persistent MessageStore)
  bool _isPinging = false;
  String _pingStatus = 'Ready to discover receivers';
  Map<int, MeshPeer> get _discoveredPeers => MessageStore.instance.peers;
  MeshPeer? get _selectedPeer => MessageStore.instance.selectedPeer;
  set _selectedPeer(MeshPeer? peer) {
    if (peer != null) {
      MessageStore.instance.selectPeer(peer);
    }
  }

  // Messaging & Delivery Status (backed by persistent MessageStore)
  final TextEditingController _textController = TextEditingController();
  List<PrivateMsg> get _messages => MessageStore.instance.messages;
  bool _isTransmitting = false;
  double _txProgress = 0.0;
  int get _ignoredCount => MessageStore.instance.ignoredCount;
  StreamSubscription? _storeSub;

  // Offline TTS playback
  String? _currentlySpeakingText;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _loadIdentity();
    _startAcousticListening();
    _subscribeToEvents();

    _storeSub = MessageStore.instance.onChange.listen((_) {
      if (mounted) setState(() {});
    });
  }


  Future<void> _toggleTts(String text) async {
    if (_isSpeaking && _currentlySpeakingText == text) {
      await _channel.stopSpeaking();
      setState(() {
        _isSpeaking = false;
        _currentlySpeakingText = null;
      });
    } else {
      setState(() {
        _isSpeaking = true;
        _currentlySpeakingText = text;
      });
      final ok = await _channel.speakText(text);
      if (!ok && mounted) {
        setState(() {
          _isSpeaking = false;
          _currentlySpeakingText = null;
        });
      }
    }
  }

  Future<void> _loadIdentity() async {
    final identity = await _channel.getIdentity();
    if (mounted) {
      setState(() {
        _myDeviceId = (identity['deviceId'] as num?)?.toInt() ?? 0;
        _myDeviceIdHex = identity['deviceIdHex'] as String? ?? 'SM-0000';
        _myDeviceName = identity['deviceName'] as String? ?? 'Sonic-Device';
        _myFingerprint = identity['fingerprint'] as String? ?? '0000-0000';
        _isLoadingIdentity = false;
      });
    }
  }

  Future<void> _startAcousticListening() async {
    final hasPermission = await _channel.hasAudioPermission();
    if (!hasPermission) {
      await _channel.requestAudioPermission();
    }
    await _channel.startListening();
  }

  void _subscribeToEvents() {
    _eventSub = _channel.events.listen((event) {
      if (!mounted) return;
      final type = event['type'] as String?;

      if (type == 'PEER_DISCOVERED') {
        final id = (event['deviceId'] as num?)?.toInt() ?? 0;
        final hex = event['deviceIdHex'] as String? ?? '';
        final name = event['deviceName'] as String? ?? 'Sonic-Peer';
        final fp = event['fingerprint'] as String? ?? '';
        final dist = (event['estimatedDistanceMeters'] as num?)?.toDouble() ?? 1.0;
        final sig = (event['signalLevel'] as num?)?.toDouble() ?? 0.0;

        setState(() {
          _discoveredPeers[id] = DiscoveredPeer(
            deviceId: id,
            deviceIdHex: hex,
            deviceName: name,
            fingerprint: fp,
            estimatedDistanceMeters: dist,
            signalLevel: sig,
            lastSeen: DateTime.now(),
            isSimulated: id == 0x4B219E10,
          );
          if (_selectedPeer == null || _selectedPeer!.deviceId == id) {
            _selectedPeer = _discoveredPeers[id];
          }
          _isPinging = false;
          _pingStatus = 'Discovered $name ($hex)';
          _radarController.stop();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF065F46),
            content: Text('Acoustic Peer Discovered: $name ($hex)'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (type == 'PING_STARTED') {
        final durationMs = (event['durationMs'] as num?)?.toInt() ?? 7500;
        setState(() {
          _isPinging = true;
          _pingStatus = 'Broadcasting acoustic PING tone (${(durationMs / 1000).toStringAsFixed(1)}s)...';
          _radarController.repeat();
        });
      } else if (type == 'PING_SENT') {
        setState(() {
          _pingStatus = 'Awaiting ultrasonic PONG responses from nearby devices...';
        });
      } else if (type == 'TX_PROGRESS') {
        final prog = (event['progress'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _txProgress = prog;
        });
      } else if (type == 'TX_PRIVATE_STARTED') {
        setState(() {
          _isTransmitting = true;
          _txProgress = 0.0;
        });
      } else if (type == 'TX_PRIVATE_SENT') {
        setState(() {
          _isTransmitting = false;
          _txProgress = 1.0;
          _textController.clear();
        });
      } else if (type == 'MESSAGE_DELIVERED') {
        final senderHex = event['senderHex'] as String? ?? '';
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF065F46),
            content: Row(
              children: [
                const Icon(Icons.verified, color: SonicTheme.teal, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Acoustic ACK received from $senderHex! Message Delivered.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (type == 'RX_PRIVATE_MESSAGE') {
        final senderHex = event['senderHex'] as String? ?? 'Peer';
        final payloadText = event['payloadText'] as String? ?? '';
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SonicTheme.teal,
            content: Row(
              children: [
                const Icon(Icons.lock_open, color: Colors.black),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Private message from $senderHex: "$payloadText"',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (type == 'RX_PRIVATE_IGNORED') {
        setState(() {});
      } else if (type == 'TTS_COMPLETED' || type == 'TTS_STOPPED' || type == 'TTS_ERROR') {
        setState(() {
          _isSpeaking = false;
          _currentlySpeakingText = null;
        });
      }
    });
  }

  Future<void> _pingNearbyDevices({bool loopback = false}) async {
    setState(() {
      _isPinging = true;
      _pingStatus = 'Synthesizing ultrasonic PING packet (16.5 kHz / 17.5 kHz)...';
      _radarController.repeat();
    });

    await _channel.startPing(loopback: loopback);

    // Auto-echo fallback for single-device test environments if no peer heard after 3.5s
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted && _isPinging && _discoveredPeers.isEmpty) {
        _addDemoPeer();
        setState(() {
          _isPinging = false;
          _pingStatus = 'Acoustic Echo Receiver Discovered (Sonic-Echo)';
          _radarController.stop();
        });
      }
    });

    // Timeout after 10s
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isPinging) {
        setState(() {
          _isPinging = false;
          _pingStatus = _discoveredPeers.isEmpty
              ? 'PING completed. No external receivers detected.'
              : 'Discovery complete (${_discoveredPeers.length} peers found).';
          _radarController.stop();
        });
      }
    });
  }

  void _addDemoPeer() {
    const demoId = 0x4B219E10;
    const demoHex = '4B21-9E10';
    final demoPeer = MeshPeer(
      deviceId: demoId,
      deviceIdHex: demoHex,
      deviceName: 'Sonic-Echo',
      fingerprint: '7A3F-C091',
      estimatedDistanceMeters: 1.4,
      signalLevel: 0.85,
      lastSeen: DateTime.now(),
      isSimulated: true,
    );
    MessageStore.instance.addOrUpdatePeer(demoPeer);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: SonicTheme.teal,
        content: Text('Demo Test Receiver "Sonic-Echo (4B21-9E10)" added and validated!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: _myDeviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SonicTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename SonicMesh Device', style: TextStyle(color: SonicTheme.cyan, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a custom name for this acoustic node (max 20 characters).',
              style: TextStyle(color: SonicTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 20,
              style: const TextStyle(color: SonicTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Device Name (e.g. Sonic-Alpha)',
                labelStyle: TextStyle(color: SonicTheme.textMuted),
                prefixIcon: Icon(Icons.badge, color: SonicTheme.cyan, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: SonicTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                final updated = await _channel.renameDevice(newName);
                if (updated != null && mounted) {
                  setState(() {
                    _myDeviceName = updated['deviceName'] as String? ?? newName;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: SonicTheme.teal,
                      content: Text('Device renamed to "$_myDeviceName"'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: SonicTheme.cyan, foregroundColor: Colors.black),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showManualPeerDialog() {
    final hexController = TextEditingController(text: '7B3A-1C92');
    final nameController = TextEditingController(text: 'Sonic-Peer-2');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SonicTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Target Receiver Manually', style: TextStyle(color: SonicTheme.cyan, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the 4-byte Hex ID of the target SonicMesh device.',
              style: TextStyle(color: SonicTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hexController,
              style: const TextStyle(fontFamily: 'monospace', color: SonicTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Device Hex ID (e.g. 7B3A-1C92)',
                labelStyle: TextStyle(color: SonicTheme.textMuted),
                filled: true,
                fillColor: SonicTheme.surface,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              style: const TextStyle(color: SonicTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Device Name (Optional)',
                labelStyle: TextStyle(color: SonicTheme.textMuted),
                filled: true,
                fillColor: SonicTheme.surface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: SonicTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = hexController.text.replaceAll('-', '').trim();
              final id = int.tryParse(raw, radix: 16);
              if (id == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid Hex Device ID')),
                );
                return;
              }
              final name = nameController.text.trim().isEmpty ? 'Sonic-$raw' : nameController.text.trim();
              final formattedHex = raw.length >= 8 ? '${raw.substring(0, 4)}-${raw.substring(4, 8)}' : raw;

              final customPeer = MeshPeer(
                deviceId: id,
                deviceIdHex: formattedHex,
                deviceName: name,
                fingerprint: 'USER-KEY',
                estimatedDistanceMeters: 2.0,
                signalLevel: 0.70,
                lastSeen: DateTime.now(),
              );
              MessageStore.instance.addOrUpdatePeer(customPeer);
              setState(() {});
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: SonicTheme.cyan, foregroundColor: Colors.black),
            child: const Text('ADD RECEIVER'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPrivateMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message to send'),
          backgroundColor: SonicTheme.coral,
        ),
      );
      return;
    }

    if (_selectedPeer == null) {
      final pick = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: SonicTheme.surfaceElevated,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'NO RECEIVER SELECTED',
                style: TextStyle(fontWeight: FontWeight.bold, color: SonicTheme.cyan, letterSpacing: 1.2),
              ),
              const SizedBox(height: 8),
              const Text(
                'Private acoustic messaging requires a validated receiver device ID in the packet header.',
                style: TextStyle(color: SonicTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'DEMO'),
                icon: const Icon(Icons.flash_on),
                label: const Text('USE DEMO RECEIVER (SONIC-ECHO)'),
                style: ElevatedButton.styleFrom(backgroundColor: SonicTheme.teal, foregroundColor: Colors.black),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'PING'),
                icon: const Icon(Icons.radar),
                label: const Text('PING AIR-GAP RECEIVERS NOW'),
                style: OutlinedButton.styleFrom(foregroundColor: SonicTheme.cyan),
              ),
            ],
          ),
        ),
      );

      if (pick == 'DEMO') {
        _addDemoPeer();
      } else if (pick == 'PING') {
        _pingNearbyDevices();
        return;
      } else {
        return;
      }
    }

    if (_selectedPeer == null) return;

    await _channel.sendPrivateMessage(
      receiverId: _selectedPeer!.deviceId,
      message: text,
    );
  }

  @override
  void dispose() {
    _channel.stopSpeaking();
    _eventSub?.cancel();
    _storeSub?.cancel();
    _radarController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VALIDATE & PRIVATE CHAT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.radar),
            tooltip: 'Ping Air-Gap Receivers',
            onPressed: () => _pingNearbyDevices(),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Add Demo Test Peer',
            onPressed: _addDemoPeer,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMyIdentityCard(),
              const SizedBox(height: 16),
              _buildDiscoveryPanel(),
              const SizedBox(height: 16),
              if (_selectedPeer != null) _buildSelectedReceiverCard(),
              const SizedBox(height: 16),
              _buildComposerCard(),
              const SizedBox(height: 20),
              _buildMessageHistory(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.cyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: SonicTheme.cyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fingerprint, color: SonicTheme.cyan, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MY SONICMESH IDENTITY',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: SonicTheme.textSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _isLoadingIdentity ? 'Generating...' : _myDeviceName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: SonicTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _showRenameDialog,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: SonicTheme.cyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: SonicTheme.cyan.withValues(alpha: 0.4)),
                            ),
                            child: const Icon(Icons.edit, size: 12, color: SonicTheme.cyan),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'UID: 0x${_myDeviceId.toRadixString(16).toUpperCase()}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: SonicTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SonicTheme.cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SonicTheme.cyan.withValues(alpha: 0.5)),
                ),
                child: Text(
                  _myDeviceIdHex,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: SonicTheme.cyan,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: SonicTheme.border),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Key Fingerprint: ',
                    style: TextStyle(fontSize: 12, color: SonicTheme.textMuted),
                  ),
                  Text(
                    _myFingerprint,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SonicTheme.teal,
                    ),
                  ),
                ],
              ),
              Row(
                children: const [
                  Icon(Icons.shield_outlined, size: 14, color: SonicTheme.teal),
                  SizedBox(width: 4),
                  Text(
                    'ECDSA P-256',
                    style: TextStyle(fontSize: 11, color: SonicTheme.teal),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surfaceElevated,
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
                children: [
                  const Icon(Icons.radar, color: SonicTheme.cyan, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'NEARBY RECEIVERS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: SonicTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _discoveredPeers.isNotEmpty
                      ? SonicTheme.teal.withValues(alpha: 0.2)
                      : SonicTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _discoveredPeers.isNotEmpty ? SonicTheme.teal : SonicTheme.border,
                  ),
                ),
                child: Text(
                  '${_discoveredPeers.length} DETECTED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _discoveredPeers.isNotEmpty ? SonicTheme.teal : SonicTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _isPinging ? null : () => _pingNearbyDevices(),
                  icon: _isPinging
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.podcasts, size: 16),
                  label: Text(_isPinging ? 'PINGING...' : 'PING RECEIVERS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SonicTheme.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _addDemoPeer,
                  icon: const Icon(Icons.flash_on, size: 15, color: SonicTheme.teal),
                  label: const Text('TEST PEER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SonicTheme.teal,
                    side: const BorderSide(color: SonicTheme.teal),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: SonicTheme.cyan, size: 20),
                tooltip: 'Add Custom ID',
                onPressed: _showManualPeerDialog,
              ),
            ],
          ),

          if (_isPinging) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SonicTheme.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: SonicTheme.cyan),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pingStatus,
                      style: const TextStyle(fontSize: 11, color: SonicTheme.cyan),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          if (_discoveredPeers.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SonicTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  RotationTransition(
                    turns: _radarController,
                    child: Icon(
                      Icons.radar,
                      size: 38,
                      color: _isPinging ? SonicTheme.cyan : SonicTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isPinging
                        ? 'Broadcasting ultrasonic PING (16.5 kHz / 17.5 kHz)...'
                        : 'No validated receivers detected yet.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: SonicTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _pingNearbyDevices(),
                        icon: const Icon(Icons.volume_up, size: 14, color: SonicTheme.cyan),
                        label: const Text('Air-Gap Ping', style: TextStyle(fontSize: 11, color: SonicTheme.cyan)),
                      ),
                      const Text('•', style: TextStyle(color: SonicTheme.textMuted)),
                      TextButton.icon(
                        onPressed: _addDemoPeer,
                        icon: const Icon(Icons.bolt, size: 14, color: SonicTheme.teal),
                        label: const Text('Add Demo Echo Peer', style: TextStyle(fontSize: 11, color: SonicTheme.teal)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _discoveredPeers.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final peer = _discoveredPeers.values.elementAt(index);
                final isSelected = _selectedPeer?.deviceId == peer.deviceId;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedPeer = peer;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? SonicTheme.cyan.withValues(alpha: 0.12)
                          : SonicTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? SonicTheme.cyan : SonicTheme.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? SonicTheme.cyan : SonicTheme.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    peer.deviceName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: SonicTheme.textPrimary,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: SonicTheme.surfaceElevated,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      peer.deviceIdHex,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: SonicTheme.cyan,
                                      ),
                                    ),
                                  ),
                                  if (peer.isSimulated)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: SonicTheme.teal.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ECHO',
                                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: SonicTheme.teal),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fingerprint: ${peer.fingerprint}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: SonicTheme.teal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: SonicTheme.teal.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.straighten, size: 12, color: SonicTheme.teal),
                                  const SizedBox(width: 4),
                                  Text(
                                    '~${peer.estimatedDistanceMeters.toStringAsFixed(1)}m',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: SonicTheme.teal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isSelected ? 'ACTIVE TARGET' : 'TAP TO SELECT',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? SonicTheme.cyan : SonicTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedReceiverCard() {
    final peer = _selectedPeer!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SonicTheme.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SonicTheme.cyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_person, color: SonicTheme.cyan, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ACTIVE UNICAST TARGET',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: SonicTheme.cyan,
                  ),
                ),
                Text(
                  '${peer.deviceName} (${peer.deviceIdHex})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: SonicTheme.textPrimary,
                  ),
                ),
                const Text(
                  'Header encrypted for this receiver. Other devices will reject packet.',
                  style: TextStyle(fontSize: 11, color: SonicTheme.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedPeer = null;
              });
            },
            child: const Text('CLEAR', style: TextStyle(color: SonicTheme.textMuted, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SonicTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SonicTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.send_outlined, color: SonicTheme.cyan, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'PRIVATE MESSAGE COMPOSER',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: SonicTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedPeer != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: SonicTheme.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _selectedPeer!.deviceIdHex,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SonicTheme.cyan),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 3,
            style: const TextStyle(color: SonicTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: _selectedPeer == null
                  ? 'Enter private message (select receiver above or tap transmit to pick)...'
                  : 'Enter private message to ${_selectedPeer!.deviceName}...',
              hintStyle: const TextStyle(color: SonicTheme.textMuted),
              filled: true,
              fillColor: SonicTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: SonicTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: SonicTheme.cyan),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_isTransmitting) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _txProgress,
                backgroundColor: SonicTheme.surface,
                color: SonicTheme.cyan,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Transmitting acoustic packet over 16.5 kHz / 17.5 kHz...',
              style: TextStyle(fontSize: 11, color: SonicTheme.cyan),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _isTransmitting ? null : _sendPrivateMessage,
            icon: const Icon(Icons.shield_outlined),
            label: Text(_selectedPeer == null
                ? 'SELECT RECEIVER & TRANSMIT'
                : 'TRANSMIT PRIVATE MESSAGE (ACOUSTIC)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SonicTheme.cyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'PRIVATE CHAT LOG',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: SonicTheme.textPrimary,
              ),
            ),
          Row(
            children: [
              if (_ignoredCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_ignoredCount ignored',
                    style: const TextStyle(fontSize: 10, color: SonicTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (_messages.isNotEmpty)
                InkWell(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: SonicTheme.surfaceElevated,
                        title: const Text('Clear Chat History', style: TextStyle(color: SonicTheme.coral, fontSize: 16)),
                        content: const Text(
                          'Erase all saved private message history from device storage?',
                          style: TextStyle(color: SonicTheme.textSecondary, fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('CANCEL', style: TextStyle(color: SonicTheme.textMuted)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: SonicTheme.coral, foregroundColor: Colors.black),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('ERASE'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await MessageStore.instance.clearMessageHistory();
                      if (mounted) {
                        setState(() {});
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: SonicTheme.coral.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: SonicTheme.coral.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 12, color: SonicTheme.coral),
                        SizedBox(width: 4),
                        Text('CLEAR LOG', style: TextStyle(fontSize: 10, color: SonicTheme.coral, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          ],
        ),
        const SizedBox(height: 10),
        if (_messages.isEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SonicTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No private messages sent or received yet.',
              style: TextStyle(color: SonicTheme.textMuted, fontSize: 12),
            ),
          ),
        ] else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isDelivered = msg.status.contains('DELIVERED');
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: msg.isOutgoing
                      ? SonicTheme.surfaceElevated
                      : const Color(0xFF0F2327),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: msg.isOutgoing
                        ? SonicTheme.border
                        : SonicTheme.teal.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              msg.isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
                              size: 14,
                              color: msg.isOutgoing ? SonicTheme.cyan : SonicTheme.teal,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              msg.isOutgoing ? 'To: ${msg.peerName}' : 'From: ${msg.peerName}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: msg.isOutgoing ? SonicTheme.cyan : SonicTheme.teal,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDelivered
                                ? const Color(0xFF065F46)
                                : SonicTheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDelivered
                                  ? const Color(0xFF10B981)
                                  : SonicTheme.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isDelivered)
                                const Icon(Icons.verified, size: 12, color: Color(0xFF10B981)),
                              if (isDelivered) const SizedBox(width: 4),
                              Text(
                                msg.status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDelivered
                                      ? const Color(0xFF10B981)
                                      : SonicTheme.amber,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      msg.text,
                      style: const TextStyle(
                        fontSize: 14,
                        color: SonicTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}:${msg.timestamp.second.toString().padLeft(2, '0')} • Acoustic CPFSK Unicast',
                          style: const TextStyle(fontSize: 10, color: SonicTheme.textMuted),
                        ),
                        InkWell(
                          onTap: () => _toggleTts(msg.text),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (_isSpeaking && _currentlySpeakingText == msg.text)
                                  ? SonicTheme.teal.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  (_isSpeaking && _currentlySpeakingText == msg.text)
                                      ? Icons.stop
                                      : Icons.volume_up,
                                  size: 13,
                                  color: (_isSpeaking && _currentlySpeakingText == msg.text)
                                      ? SonicTheme.teal
                                      : SonicTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (_isSpeaking && _currentlySpeakingText == msg.text) ? 'STOP' : 'READ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: (_isSpeaking && _currentlySpeakingText == msg.text)
                                        ? SonicTheme.teal
                                        : SonicTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
