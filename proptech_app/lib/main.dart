import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';
import 'features/notifications/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Show the app immediately. Push setup must never block (or crash) startup:
  // if Firebase isn't configured for this platform (web/desktop), or the
  // device has no Google Play services, the UI still has to appear.
  runApp(
    const ProviderScope(
      child: ProptechApp(),
    ),
  );

  _initPush();
}

Future<void> _initPush() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    await PushNotificationService.instance
        .init()
        .timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('Push notifications disabled: $e');
  }
}