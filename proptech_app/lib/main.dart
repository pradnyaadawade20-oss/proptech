import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';
import 'features/notifications/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Requires `flutterfire configure` to have generated
  // lib/firebase_options.dart for this project (see PUSH_NOTIFICATIONS.md).
  await Firebase.initializeApp();
  await PushNotificationService.instance.init();

  runApp(
    const ProviderScope(
      child: ProptechApp(),
    ),
  );
}