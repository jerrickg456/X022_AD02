import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../native/acoustic_channel.dart';

/// A single discovered acoustic mesh peer.
class MeshPeer {
  final int deviceId;
  final String deviceIdHex;
  String deviceName;
  final String fingerprint;
  double estimatedDistanceMeters;
  double signalLevel;
  DateTime lastSeen;
  final bool isSimulated;

  MeshPeer({
    required this.deviceId,
    required this.deviceIdHex,
    required this.deviceName,
    required this.fingerprint,
    required this.estimatedDistanceMeters,
    required this.signalLevel,
    required this.lastSeen,
    this.isSimulated = false,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceIdHex': deviceIdHex,
    'deviceName': deviceName,
    'fingerprint': fingerprint,
    'estimatedDistanceMeters': estimatedDistanceMeters,
    'signalLevel': signalLevel,
    'lastSeen': lastSeen.toIso8601String(),
    'isSimulated': isSimulated,
  };

  factory MeshPeer.fromJson(Map<String, dynamic> json) => MeshPeer(
    deviceId: (json['deviceId'] as num).toInt(),
    deviceIdHex: json['deviceIdHex'] as String? ?? '',
    deviceName: json['deviceName'] as String? ?? 'Sonic-Peer',
    fingerprint: json['fingerprint'] as String? ?? '',
    estimatedDistanceMeters: (json['estimatedDistanceMeters'] as num?)?.toDouble() ?? 1.0,
    signalLevel: (json['signalLevel'] as num?)?.toDouble() ?? 0.0,
    lastSeen: json['lastSeen'] != null ? DateTime.parse(json['lastSeen'] as String) : DateTime.now(),
    isSimulated: json['isSimulated'] as bool? ?? false,
  );
}

/// A single incoming or outgoing private message record.
class PrivateMsg {
  final bool isOutgoing;
  final String peerName;
  final String peerHex;
  final String text;
  final DateTime timestamp;
  String status;
  final int? msgId;
  final int? senderId;
  final int? receiverId;

  PrivateMsg({
    required this.isOutgoing,
    required this.peerName,
    required this.peerHex,
    required this.text,
    required this.timestamp,
    required this.status,
    this.msgId,
    this.senderId,
    this.receiverId,
  });

  Map<String, dynamic> toJson() => {
    'isOutgoing': isOutgoing,
    'peerName': peerName,
    'peerHex': peerHex,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'status': status,
    'msgId': msgId,
    'senderId': senderId,
    'receiverId': receiverId,
  };

  factory PrivateMsg.fromJson(Map<String, dynamic> json) => PrivateMsg(
    isOutgoing: json['isOutgoing'] as bool? ?? false,
    peerName: json['peerName'] as String? ?? 'Peer',
    peerHex: json['peerHex'] as String? ?? '',
    text: json['text'] as String? ?? '',
    timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : DateTime.now(),
    status: json['status'] as String? ?? 'DELIVERED',
    msgId: (json['msgId'] as num?)?.toInt(),
    senderId: (json['senderId'] as num?)?.toInt(),
    receiverId: (json['receiverId'] as num?)?.toInt(),
  );
}

/// Global singleton that persists messages and discovered peers to device storage
/// (SharedPreferences), and captures incoming/outgoing acoustic events regardless
/// of which screen is currently visible.
class MessageStore {
  static final MessageStore instance = MessageStore._();
  MessageStore._();

  static const String _messagesKey = 'sonicmesh_message_history_v1';
  static const String _peersKey = 'sonicmesh_discovered_peers_v1';

  final List<PrivateMsg> messages = [];
  final Map<int, MeshPeer> peers = {};
  MeshPeer? selectedPeer;

  StreamSubscription? _sub;
  final StreamController<void> _onChange = StreamController<void>.broadcast();
  Stream<void> get onChange => _onChange.stream;

  int ignoredCount = 0;
  bool _isInitialized = false;

  /// Call at app start (e.g. in main.dart)
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _loadFromStorage();
    _sub = AcousticChannel.instance.events.listen(_handleEvent);
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load messages
      final msgJson = prefs.getString(_messagesKey);
      if (msgJson != null && msgJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(msgJson) as List<dynamic>;
        messages.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            messages.add(PrivateMsg.fromJson(item));
          }
        }
      }

      // 2. Load discovered peers
      final peerJson = prefs.getString(_peersKey);
      if (peerJson != null && peerJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(peerJson) as List<dynamic>;
        peers.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final peer = MeshPeer.fromJson(item);
            peers[peer.deviceId] = peer;
          }
        }
      }

      // Default demo peer if none saved
      if (!peers.containsKey(0x4B219E10)) {
        peers[0x4B219E10] = MeshPeer(
          deviceId: 0x4B219E10,
          deviceIdHex: '4B21-9E10',
          deviceName: 'Sonic-Echo',
          fingerprint: '7A3F-C091',
          estimatedDistanceMeters: 1.4,
          signalLevel: 0.85,
          lastSeen: DateTime.now(),
          isSimulated: true,
        );
      }

      if (peers.isNotEmpty) {
        selectedPeer = peers.values.first;
      }
      _notify();
    } catch (_) {
      // Best-effort storage recovery
    }
  }

  Future<void> _saveMessagesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep up to 200 most recent messages
      final toSave = messages.take(200).map((m) => m.toJson()).toList();
      await prefs.setString(_messagesKey, jsonEncode(toSave));
    } catch (_) {}
  }

  Future<void> _savePeersToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = peers.values.map((p) => p.toJson()).toList();
      await prefs.setString(_peersKey, jsonEncode(toSave));
    } catch (_) {}
  }

  void _notify() {
    if (!_onChange.isClosed) {
      _onChange.add(null);
    }
  }

  void selectPeer(MeshPeer peer) {
    selectedPeer = peer;
    _notify();
  }

  void addOrUpdatePeer(MeshPeer peer) {
    peers[peer.deviceId] = peer;
    if (selectedPeer == null || selectedPeer!.deviceId == peer.deviceId) {
      selectedPeer = peer;
    }
    _savePeersToStorage();
    _notify();
  }

  Future<void> clearMessageHistory() async {
    messages.clear();
    await _saveMessagesToStorage();
    _notify();
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;

    if (type == 'PEER_DISCOVERED') {
      final id = (event['deviceId'] as num?)?.toInt() ?? 0;
      final hex = event['deviceIdHex'] as String? ?? '';
      final name = event['deviceName'] as String? ?? 'Sonic-Peer';
      final fp = event['fingerprint'] as String? ?? '';
      final dist = (event['estimatedDistanceMeters'] as num?)?.toDouble() ?? 1.0;
      final sig = (event['signalLevel'] as num?)?.toDouble() ?? 0.0;

      if (id != 0) {
        peers[id] = MeshPeer(
          deviceId: id,
          deviceIdHex: hex,
          deviceName: name,
          fingerprint: fp,
          estimatedDistanceMeters: dist,
          signalLevel: sig,
          lastSeen: DateTime.now(),
          isSimulated: id == 0x4B219E10,
        );
        if (selectedPeer == null || selectedPeer!.deviceId == id) {
          selectedPeer = peers[id];
        }
        _savePeersToStorage();
        _notify();
      }
    } else if (type == 'RX_PRIVATE_MESSAGE') {
      final senderHex = event['senderHex'] as String? ?? 'Peer';
      final payloadText = event['payloadText'] as String? ?? '';
      final msgId = (event['msgId'] as num?)?.toInt();
      final senderId = (event['senderId'] as num?)?.toInt();
      final receiverId = (event['receiverId'] as num?)?.toInt();

      // Look up peer name if we have it
      final peerName = senderId != null && peers.containsKey(senderId)
          ? peers[senderId]!.deviceName
          : 'Sender-$senderHex';

      // Insert message
      messages.insert(
        0,
        PrivateMsg(
          isOutgoing: false,
          peerName: peerName,
          peerHex: senderHex,
          text: payloadText,
          timestamp: DateTime.now(),
          status: 'RECEIVED & ACK SENT',
          msgId: msgId,
          senderId: senderId,
          receiverId: receiverId,
        ),
      );

      _saveMessagesToStorage();
      _notify();
    } else if (type == 'TX_PRIVATE_STARTED') {
      // Optional pre-registration if needed
    } else if (type == 'TX_PRIVATE_SENT') {
      final msgId = (event['msgId'] as num?)?.toInt();
      final receiverId = (event['receiverId'] as num?)?.toInt();
      final senderId = (event['senderId'] as num?)?.toInt();
      final text = event['message'] as String? ?? '';

      final peerName = receiverId != null && peers.containsKey(receiverId)
          ? peers[receiverId]!.deviceName
          : (selectedPeer?.deviceName ?? 'Recipient');
      final peerHex = receiverId != null && peers.containsKey(receiverId)
          ? peers[receiverId]!.deviceIdHex
          : (selectedPeer?.deviceIdHex ?? '');

      messages.insert(
        0,
        PrivateMsg(
          isOutgoing: true,
          peerName: peerName,
          peerHex: peerHex,
          text: text,
          timestamp: DateTime.now(),
          status: 'AWAITING AIR-GAP ACK...',
          msgId: msgId,
          senderId: senderId,
          receiverId: receiverId,
        ),
      );

      _saveMessagesToStorage();
      _notify();
    } else if (type == 'MESSAGE_DELIVERED') {
      final msgId = (event['msgId'] as num?)?.toInt();
      for (final msg in messages) {
        if (msg.isOutgoing && (msgId == null || msg.msgId == msgId)) {
          msg.status = 'DELIVERED [VERIFIED ACK]';
        }
      }
      _saveMessagesToStorage();
      _notify();
    } else if (type == 'RX_PRIVATE_IGNORED') {
      ignoredCount++;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _onChange.close();
  }
}
