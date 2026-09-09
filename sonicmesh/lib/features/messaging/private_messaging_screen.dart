import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../native/acoustic_channel.dart';

class DiscoveredPeer {
  final int deviceId;
  final String deviceIdHex;
  final String deviceName;
  final String fingerprint;
  double estimatedDistanceMeters;
  double signalLevel;
  DateTime lastSeen;

  DiscoveredPeer({
    required this.deviceId,
    required this.deviceIdHex,
    required this.deviceName,
    required this.fingerprint,
    required this.estimatedDistanceMeters,
    required this.signalLevel,
    required this.lastSeen,
  });
}

class PrivateMessageEntry {
  final bool isOutgoing;
  final String peerName;
  final String peerHex;
  final String text;
  final DateTime timestamp;
  String status; // 'AWAITING_ACK', 'DELIVERED [VERIFIED ACK]', 'RECEIVED'
  final int? msgId;

  PrivateMessageEntry({
    required this.isOutgoing,
    required this.peerName,
    required this.peerHex,
    required this.text,
    required this.timestamp,
    required this.status,
    this.msgId,
  });
}

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

  // Peer Discovery & Selection
  bool _isPinging = false;
  final Map<int, DiscoveredPeer> _discoveredPeers = {};
  DiscoveredPeer? _selectedPeer;

  // Messaging & Delivery Status
  final TextEditingController _textController = TextEditingController();
  final List<PrivateMessageEntry> _messages = [];
  bool _isTransmitting = false;
  double _txProgress = 0.0;
  int _ignoredCount = 0;

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
          );
          if (_selectedPeer == null || _selectedPeer!.deviceId == id) {
            _selectedPeer = _discoveredPeers[id];
          }
          _isPinging = false;
          _radarController.stop();
        });
      } else if (type == 'PING_STARTED') {
        setState(() {
          _isPinging = true;
          _radarController.repeat();
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
        final msgId = (event['msgId'] as num?)?.toInt();
        setState(() {
          _isTransmitting = false;
          _txProgress = 1.0;
          // Add to local message history awaiting ACK
          _messages.insert(
            0,
            PrivateMessageEntry(
              isOutgoing: true,
              peerName: _selectedPeer?.deviceName ?? 'Recipient',
              peerHex: _selectedPeer?.deviceIdHex ?? '',
              text: _textController.text.trim(),
              timestamp: DateTime.now(),
              status: 'AWAITING_ACK',
              msgId: msgId,
            ),
          );
          _textController.clear();
        });
      } else if (type == 'MESSAGE_DELIVERED') {
        final msgId = (event['msgId'] as num?)?.toInt();
        final senderHex = event['senderHex'] as String? ?? '';
        setState(() {
          for (final msg in _messages) {
            if (msg.isOutgoing && (msgId == null || msg.msgId == msgId)) {
              msg.status = 'DELIVERED [VERIFIED ACK]';
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF065F46),
            content: Row(
              children: [
                const Icon(Icons.verified, color: SonicTheme.teal, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Acoustic ACK received from $senderHex! Message Delivered.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (type == 'RX_PRIVATE_MESSAGE') {
        final senderHex = event['senderHex'] as String? ?? 'Peer';
        final payloadText = event['payloadText'] as String? ?? '';
        final msgId = (event['msgId'] as num?)?.toInt();
        setState(() {
          _messages.insert(
            0,
            PrivateMessageEntry(
              isOutgoing: false,
              peerName: 'Sender-$senderHex',
              peerHex: senderHex,
              text: payloadText,
              timestamp: DateTime.now(),
              status: 'RECEIVED & ACK SENT',
              msgId: msgId,
            ),
          );
        });
      } else if (type == 'RX_PRIVATE_IGNORED') {
        setState(() {
          _ignoredCount++;
        });
      }
    });
  }

  Future<void> _pingNearbyDevices() async {
    setState(() {
      _isPinging = true;
      _radarController.repeat();
    });
    await _channel.startPing();
    // Stop radar after 5s if no response
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isPinging) {
        setState(() {
          _isPinging = false;
          _radarController.stop();
        });
      }
    });
  }

  Future<void> _sendPrivateMessage() async {
    if (_selectedPeer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select and validate a receiver first!'),
          backgroundColor: SonicTheme.coral,
        ),
      );
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty) return;

    await _channel.sendPrivateMessage(
      receiverId: _selectedPeer!.deviceId,
      message: text,
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
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
            tooltip: 'Ping Nearby Receivers',
            onPressed: _pingNearbyDevices,
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
                    Text(
                      _isLoadingIdentity ? 'Generating...' : _myDeviceName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: SonicTheme.textPrimary,
                      ),
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
                children: [
                  const Icon(Icons.shield_outlined, size: 14, color: SonicTheme.teal),
                  const SizedBox(width: 4),
                  const Text(
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
              ElevatedButton.icon(
                onPressed: _isPinging ? null : _pingNearbyDevices,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_discoveredPeers.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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
                        : 'No validated receivers yet. Tap "PING RECEIVERS" to discover nearby devices via acoustics.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: SonicTheme.textSecondary),
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
                              Row(
                                children: [
                                  Text(
                                    peer.deviceName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: SonicTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: SonicTheme.surfaceElevated,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      peer.deviceIdHex,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: SonicTheme.cyan,
                                      ),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: SonicTheme.teal.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.straighten,
                                      size: 12, color: SonicTheme.teal),
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
                              'VERIFIED PEER',
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
                Text(
                  'Only this device will decrypt the message. Other devices will ignore.',
                  style: TextStyle(fontSize: 11, color: SonicTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: SonicTheme.teal, size: 20),
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
            children: const [
              Icon(Icons.send_outlined, color: SonicTheme.cyan, size: 18),
              SizedBox(width: 8),
              Text(
                'PRIVATE MESSAGE COMPOSER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: SonicTheme.textPrimary,
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
                  ? 'Select a nearby receiver first...'
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
            onPressed: (_isTransmitting || _selectedPeer == null)
                ? null
                : _sendPrivateMessage,
            icon: const Icon(Icons.shield_outlined),
            label: const Text('TRANSMIT PRIVATE MESSAGE (ACOUSTIC)'),
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
            if (_ignoredCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_ignoredCount unaddressed packets ignored',
                  style: const TextStyle(fontSize: 10, color: SonicTheme.textMuted),
                ),
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
                    Text(
                      '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}:${msg.timestamp.second.toString().padLeft(2, '0')} • Acoustic CPFSK Unicast',
                      style: const TextStyle(fontSize: 10, color: SonicTheme.textMuted),
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
