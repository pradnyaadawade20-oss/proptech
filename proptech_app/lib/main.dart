import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';
import 'features/notifications/push_notification_service.dart';
import 'features/properties/property_store.dart';
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
  _loadProperties();
}

/// Fetches real listings from the backend right after the UI appears.
/// HomeScreen/SearchScreen etc. already rebuild on propertiesVersion
/// changes, so they'll pick this up automatically once it lands — no need
/// to block the splash/home screen waiting for it.
Future<void> _loadProperties() async {
  try {
    await PropertyStore.instance.load().timeout(const Duration(seconds: 60));
  } catch (e) {
    debugPrint('Failed to load properties from backend: $e');
  }
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