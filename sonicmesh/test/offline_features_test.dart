import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmesh/features/broadcast/broadcast_screen.dart';
import 'package:sonicmesh/features/receiver/receiver_screen.dart';
import 'package:sonicmesh/native/acoustic_channel.dart';

// Valid 1x1 transparent PNG bytes
final Uint8List validPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('com.sonicmesh/control');
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      switch (call.method) {
        case 'hasAudioPermission':
          return true;
        case 'requestAudioPermission':
          return true;
        case 'startSpeechRecognition':
          return true;
        case 'stopSpeechRecognition':
          return true;
        case 'ttsSpeak':
          return true;
        case 'ttsStop':
          return true;
        case 'ttsPause':
          return true;
        case 'pickImage':
          return {
            'imageId': 42,
            'width': 64,
            'height': 64,
            'fileSize': validPngBytes.length,
            'totalChunks': 8,
            'estimatedDurationSec': 25.6,
            'webpBytes': validPngBytes,
          };
        case 'transmitImage':
          return true;
        case 'stopListening':
          return true;
        case 'startListening':
          return true;
        default:
          return true;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('BroadcastScreen displays offline mic and image transfer components', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BroadcastScreen(),
      ),
    );
    await tester.pump();

    // Verify OFFLINE MIC badge is visible
    expect(find.text('OFFLINE MIC'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsWidgets);

    // Verify Offline Acoustic Image Transfer card
    expect(find.text('ACOUSTIC IMAGE TRANSFER (OFFLINE)'), findsOneWidget);
    expect(find.text('Thumbnail (64×64)'), findsOneWidget);
    expect(find.text('Standard (128×128)'), findsOneWidget);
    expect(find.text('SELECT IMAGE FROM STORAGE'), findsOneWidget);

    // Tap Offline Mic
    await tester.tap(find.text('OFFLINE MIC'));
    await tester.pump();
    expect(methodCalls.any((c) => c.method == 'startSpeechRecognition'), isTrue);

    // Tap Select Image From Storage
    await tester.ensureVisible(find.text('SELECT IMAGE FROM STORAGE'));
    await tester.tap(find.text('SELECT IMAGE FROM STORAGE'));
    await tester.pump();
    expect(methodCalls.any((c) => c.method == 'pickImage'), isTrue);

    // Verify prepared image preview is rendered
    expect(find.text('64×64 WebP'), findsOneWidget);
    expect(find.text('8 Chunks • 48 B/chunk'), findsOneWidget);
    expect(find.text('TRANSMIT ACOUSTIC IMAGE'), findsOneWidget);

    // Tap Transmit Image
    await tester.ensureVisible(find.text('TRANSMIT ACOUSTIC IMAGE'));
    await tester.tap(find.text('TRANSMIT ACOUSTIC IMAGE'));
    await tester.pump();
    expect(methodCalls.any((c) => c.method == 'transmitImage'), isTrue);
  });

  testWidgets('ReceiverScreen displays empty state and controls', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReceiverScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('No Packets Received Yet'), findsOneWidget);
    expect(find.text('START ACOUSTIC LISTENER'), findsOneWidget);
  });

  test('AcousticChannel invokes STT, TTS, and Image methods correctly', () async {
    final channelInstance = AcousticChannel.instance;

    final sttStarted = await channelInstance.startSpeechRecognition();
    expect(sttStarted, isTrue);

    final sttStopped = await channelInstance.stopSpeechRecognition();
    expect(sttStopped, isTrue);

    final spoke = await channelInstance.speakText('Test voice read aloud');
    expect(spoke, isTrue);

    final paused = await channelInstance.pauseSpeaking();
    expect(paused, isTrue);

    final stopped = await channelInstance.stopSpeaking();
    expect(stopped, isTrue);

    final img = await channelInstance.pickImage(isThumbnail: true);
    expect(img, isNotNull);
    expect(img!['imageId'], 42);

    final txImg = await channelInstance.transmitImage();
    expect(txImg, isTrue);
  });
}
