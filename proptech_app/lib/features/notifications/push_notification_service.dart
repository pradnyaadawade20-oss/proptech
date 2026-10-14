import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../app/router/app_router.dart';
import '../../app/router/route_names.dart';
import '../../core/api/token_store.dart';
import '../call/call_service.dart';
import 'device_token_service.dart';
import 'notification_service.dart';

/// Must be a top-level (or static) function — FCM calls this in a separate
/// isolate when a data/notification message arrives while the app is fully
/// killed or in the background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Incoming calls are sent data-only (no `notification` block) so WE show a
  // ringing, full-screen-intent notification. Everything else is shown by FCM.
  if (PushNotificationService.isIncomingCall(message.data)) {
    await PushNotificationService.showIncomingCallNotification(message.data);
  }
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
    'proptech_alerts', // must match AndroidManifest meta-data + backend ChannelID
    'PropTech alerts',
    description: 'Visit updates, messages, agreements, listings and offers.',
    importance: Importance.max,
    playSound: true, // ringer normal  -> notification tune
    enableVibration: true, // vibrate mode -> vibrates (silent mode stays silent)
    showBadge: true,
  );

  /// Rings like a phone call (device ringtone, loops until answered/dismissed).
  static const _callChannel = AndroidNotificationChannel(
    'proptech_calls',
    'Incoming calls',
    description: 'Rings when someone calls you in the app.',
    importance: Importance.max,
    playSound: true,
    sound: UriAndroidNotificationSound('content://settings/system/ringtone'),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    enableVibration: true,
  );

  static bool isIncomingCall(Map<String, dynamic> d) =>
      d['type'] == 'call' && ((d['route'] as String?) ?? '').startsWith('/call/');

  static int _callNotifId(String route) => route.hashCode & 0x7fffffff;

  /// Works from the background isolate too (creates its own plugin instance).
  static Future<void> showIncomingCallNotification(Map<String, dynamic> data) async {
    final route = (data['route'] as String?) ?? '';
    if (!route.startsWith('/call/')) return;
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_callChannel);
    await plugin.show(
      _callNotifId(route),
      (data['title'] as String?) ?? 'Incoming call',
      (data['body'] as String?) ?? 'Someone is calling you',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannel.id,
          _callChannel.name,
          channelDescription: _callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
          timeoutAfter: 45000, // same as the server's ring timeout
          playSound: true,
          sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT: keep ringing
          visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      payload: route,
    );
  }

  /// Stops the ringing notification once the call is answered / ended.
  Future<void> cancelCallNotification(String? callId) async {
    if (callId == null) return;
    try {
      await _localNotifications.cancel(_callNotifId('/call/$callId'));
    } catch (_) {}
  }

  bool _initialized = false;

  // Route from the push that cold-started the app (null if none). SplashScreen
  // awaits this so it can skip onboarding and open the right screen.
  final Completer<String?> _launchRoute = Completer<String?>();
  Future<String?> get launchRoute => _launchRoute.future;
  void completeLaunchRoute([String? route]) {
    if (!_launchRoute.isCompleted) _launchRoute.complete(route);
  }

  static final Set<String> _tabRoutes = {
    RouteNames.home,
    RouteNames.search,
    RouteNames.favorites,
    RouteNames.chatList,
    RouteNames.profile,
  };

  /// Screen to open for a push: backend sends `route`; falls back to `type`.
  String? _routeFrom(Map<String, dynamic> data) {
    final route = data['route'];
    if (route is String && route.startsWith('/')) return route;
    switch (data['type']) {
      case 'message':
        return RouteNames.chatList;
      case 'visit':
        return RouteNames.myVisits;
      case 'property':
      case 'account':
        return RouteNames.home;
    }
    return null;
  }

  /// Opens [route] with Home underneath, so Back returns to the app.
  Future<void> openRoute(String? route) async {
    if (route == null || route.isEmpty) return;
    if (!await TokenStore.instance.isLoggedIn()) return;
    if (_tabRoutes.contains(route)) {
      appRouter.go(route);
      return;
    }
    appRouter.go(RouteNames.home);
    WidgetsBinding.instance.addPostFrameCallback((_) => appRouter.push(route));
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Killed -> user tapped the notification. Do this BEFORE the permission
    // prompt, which can block for a long time.
    try {
      final initial = await _messaging.getInitialMessage();
      // Data-only call push: the app was opened by tapping our local notification.
      String? localRoute;
      try {
        final d = await _localNotifications.getNotificationAppLaunchDetails();
        if (d?.didNotificationLaunchApp == true) localRoute = d!.notificationResponse?.payload;
      } catch (_) {}
      completeLaunchRoute(initial == null ? localRoute : (_routeFrom(initial.data) ?? localRoute));
    } catch (_) {
      completeLaunchRoute();
    }

    // Background -> user tapped the notification.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => openRoute(_routeFrom(m.data)));

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_callChannel);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      // Foreground notification (shown by us) was tapped.
      onDidReceiveNotificationResponse: (r) => openRoute(r.payload),
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // App is in the foreground: FCM does NOT auto-show a system notification,
    // so we display one ourselves via flutter_local_notifications.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    await _registerCurrentToken();
    _messaging.onTokenRefresh.listen((newToken) => _registerToken(newToken));
  }

  void _showForegroundNotification(RemoteMessage message) {
    NotificationService.instance.refreshUnread(); // bell badge
    // Incoming call: if the call socket is up it already opened the call screen;
    // otherwise show the ringing call notification.
    if (isIncomingCall(message.data)) {
      if (!CallService.instance.isConnected) showIncomingCallNotification(message.data);
      return;
    }
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
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      payload: _routeFrom(message.data),
    );
  }

  /// Call right after a successful login (email OTP or Google) so this device
  /// gets registered for the user who just signed in. init() runs at app start,
  /// when nobody is logged in yet, so it cannot do this itself.
  Future<void> registerForCurrentUser() async {
    try {
      await _registerCurrentToken();
    } catch (_) {
      // Firebase not ready / no Play services: push just stays off.
    }
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