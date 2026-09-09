import 'dart:async';
import 'package:flutter/services.dart';

class AcousticChannel {
  static const MethodChannel _methodChannel = MethodChannel('com.sonicmesh/control');
  static const EventChannel _eventChannel = EventChannel('com.sonicmesh/events');

  static final AcousticChannel instance = AcousticChannel._();
  AcousticChannel._();

  Stream<Map<String, dynamic>>? _eventStream;

  Stream<Map<String, dynamic>> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _eventStream!;
  }

  Future<bool> hasAudioPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('hasAudioPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestAudioPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestAudioPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startBroadcast(String message, {int repetitions = 1}) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('startBroadcast', {
        'message': message,
        'repetitions': repetitions,
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestRetransmission({required int missingSequence, required int totalExpected}) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestRetransmission', {
        'missingSequence': missingSequence,
        'totalExpected': totalExpected,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopBroadcast() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopBroadcast');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startListening() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('startListening');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopListening() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopListening');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> runLoopbackTest([String message = 'SonicMesh DSP Loopback 001']) async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('runLoopbackTest', {
        'message': message,
      });
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> getIdentity() async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('getIdentity');
      return Map<String, dynamic>.from(res ?? {});
    } catch (_) {
      return {};
    }
  }

  Future<bool> startPing({bool loopback = false}) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('startPing', {
        'loopback': loopback,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendPrivateMessage({required int receiverId, required String message}) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('sendPrivateMessage', {
        'receiverId': receiverId,
        'message': message,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getDiagnostics() async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('getDiagnostics');
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, dynamic>?> renameDevice(String newName) async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('renameDevice', {
        'name': newName,
      });
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> startRelayMode({int guardDelayMs = 500, int repetitions = 1, bool relayPrivate = true}) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('startRelayMode', {
        'guardDelayMs': guardDelayMs,
        'repetitions': repetitions,
        'relayPrivate': relayPrivate,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopRelayMode() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopRelayMode');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getRelayStats() async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('getRelayStats');
      return Map<String, dynamic>.from(res ?? {});
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> testRelayPipeline([String message = 'Relay Node B Test Signal']) async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('testRelayPipeline', {
        'message': message,
      });
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Offline Speech-to-Text (STT)
  Future<bool> startSpeechRecognition() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('startSpeechRecognition');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopSpeechRecognition() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopSpeechRecognition');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // Offline Text-to-Speech (TTS)
  Future<bool> speakText(String text) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('ttsSpeak', {'text': text});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopSpeaking() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('ttsStop');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pauseSpeaking() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('ttsPause');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // Offline Acoustic Image Transfer
  Future<Map<String, dynamic>?> pickImage({bool isThumbnail = true}) async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('pickImage', {
        'isThumbnail': isThumbnail,
      });
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> prepareImageFromBytes(Uint8List bytes, {bool isThumbnail = true}) async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('prepareImageFromBytes', {
        'bytes': bytes,
        'isThumbnail': isThumbnail,
      });
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> transmitImage() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('transmitImage');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

