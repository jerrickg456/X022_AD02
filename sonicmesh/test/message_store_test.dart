import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonicmesh/services/message_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MessageStore initializes with default demo peer and empty messages', () async {
    final store = MessageStore.instance;
    await store.init();

    expect(store.peers.containsKey(0x4B219E10), isTrue);
    expect(store.peers[0x4B219E10]?.deviceName, 'Sonic-Echo');
    expect(store.selectedPeer?.deviceName, 'Sonic-Echo');
  });

  test('MeshPeer serialization and deserialization', () {
    final peer = MeshPeer(
      deviceId: 0x12345678,
      deviceIdHex: '1234-5678',
      deviceName: 'Sonic-Alpha',
      fingerprint: 'A1B2-C3D4',
      estimatedDistanceMeters: 2.5,
      signalLevel: 0.92,
      lastSeen: DateTime(2026, 9, 9, 12, 0, 0),
      isSimulated: false,
    );

    final jsonMap = peer.toJson();
    final reconstructed = MeshPeer.fromJson(jsonMap);

    expect(reconstructed.deviceId, 0x12345678);
    expect(reconstructed.deviceIdHex, '1234-5678');
    expect(reconstructed.deviceName, 'Sonic-Alpha');
    expect(reconstructed.fingerprint, 'A1B2-C3D4');
    expect(reconstructed.estimatedDistanceMeters, 2.5);
    expect(reconstructed.signalLevel, 0.92);
    expect(reconstructed.isSimulated, isFalse);
  });

  test('PrivateMsg serialization and deserialization', () {
    final msg = PrivateMsg(
      isOutgoing: true,
      peerName: 'Sonic-Echo',
      peerHex: '4B21-9E10',
      text: 'Test private message payload',
      timestamp: DateTime(2026, 9, 9, 12, 30, 0),
      status: 'DELIVERED [VERIFIED ACK]',
      msgId: 42,
      senderId: 0x11112222,
      receiverId: 0x4B219E10,
    );

    final jsonMap = msg.toJson();
    final reconstructed = PrivateMsg.fromJson(jsonMap);

    expect(reconstructed.isOutgoing, isTrue);
    expect(reconstructed.peerName, 'Sonic-Echo');
    expect(reconstructed.peerHex, '4B21-9E10');
    expect(reconstructed.text, 'Test private message payload');
    expect(reconstructed.status, 'DELIVERED [VERIFIED ACK]');
    expect(reconstructed.msgId, 42);
    expect(reconstructed.senderId, 0x11112222);
    expect(reconstructed.receiverId, 0x4B219E10);
  });

  test('Add and select peer in MessageStore', () {
    final store = MessageStore.instance;
    final newPeer = MeshPeer(
      deviceId: 0x7B3A1C92,
      deviceIdHex: '7B3A-1C92',
      deviceName: 'Sonic-Beta',
      fingerprint: 'E5F6-0708',
      estimatedDistanceMeters: 1.8,
      signalLevel: 0.75,
      lastSeen: DateTime.now(),
    );

    store.addOrUpdatePeer(newPeer);
    expect(store.peers.containsKey(0x7B3A1C92), isTrue);
    expect(store.peers[0x7B3A1C92]?.deviceName, 'Sonic-Beta');

    store.selectPeer(newPeer);
    expect(store.selectedPeer?.deviceId, 0x7B3A1C92);
  });
}
