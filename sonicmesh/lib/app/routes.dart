import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import '../features/broadcast/broadcast_screen.dart';
import '../features/broadcast/persistent_broadcast_screen.dart';
import '../features/receiver/receiver_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/messaging/private_messaging_screen.dart';
import '../features/relay/acoustic_relay_screen.dart';

class Routes {
  static const String home = '/';
  static const String broadcast = '/broadcast';
  static const String persistentBroadcast = '/persistent_broadcast';
  static const String receiver = '/receiver';
  static const String diagnostics = '/diagnostics';
  static const String privateMessaging = '/private_messaging';
  static const String relay = '/relay';

  static Map<String, WidgetBuilder> get routes => {
        home: (context) => const HomeScreen(),
        broadcast: (context) => const BroadcastScreen(),
        persistentBroadcast: (context) => const PersistentBroadcastScreen(),
        receiver: (context) => const ReceiverScreen(),
        diagnostics: (context) => const DiagnosticsScreen(),
        privateMessaging: (context) => const PrivateMessagingScreen(),
        relay: (context) => const AcousticRelayScreen(),
      };
}
