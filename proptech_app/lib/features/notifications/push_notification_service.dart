import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/api/token_store.dart';
import 'device_token_service.dart';

/// Must be a top-level (or static) function — FCM calls this in a separate
/// isolate when a data/notification message arrives while the app is fully
/// killed or in the background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing to do here for now: when the app is backgrounded/killed, FCM
  // shows the notification itself using the payload's `notification` block.
  // Hook DB writes or badge updates here later if needed.
}

/// Sets up Firebase Cloud Messaging: permission prompt, token registration
/// with the backend, foreground notification display, and token-refresh
/// handling. Call `PushNotificationService.instance.init()` once, after
/// Firebase.initializeApp() and after the user is logged in.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'proptech_default_channel', // must match AndroidManifest meta-data
    'General notifications',
    description: 'Visit updates, messages, agreements, listings and offers.',
    importance: Importance.high,
  );

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // App is in the foreground: FCM does NOT auto-show a system notification,
    // so we display one ourselves via flutter_local_notifications.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    await _registerCurrentToken();
    _messaging.onTokenRefresh.listen((newToken) => _registerToken(newToken));
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    final userId = await TokenStore.instance.getUserId();
    if (userId == null) return; // not logged in yet — register() is retried after login instead

    await DeviceTokenService.instance.register(
      userId: userId,
      token: token,
      platform: kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
    );
  }

  /// Call on logout so this device stops receiving pushes for the user who
  /// just signed out.
  Future<void> unregisterCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) await DeviceTokenService.instance.unregister(token);
  }
}