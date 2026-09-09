import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import '../features/broadcast/broadcast_screen.dart';
import '../features/receiver/receiver_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/messaging/private_messaging_screen.dart';

class Routes {
  static const String home = '/';
  static const String broadcast = '/broadcast';
  static const String receiver = '/receiver';
  static const String diagnostics = '/diagnostics';
  static const String privateMessaging = '/private_messaging';

  static Map<String, WidgetBuilder> get routes => {
        home: (context) => const HomeScreen(),
        broadcast: (context) => const BroadcastScreen(),
        receiver: (context) => const ReceiverScreen(),
        diagnostics: (context) => const DiagnosticsScreen(),
        privateMessaging: (context) => const PrivateMessagingScreen(),
      };
}
