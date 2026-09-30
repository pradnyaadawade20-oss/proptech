import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';

class AppNotification {
  final String id;
  final String type; // property | visit | agreement | message | offer | account
  final String title;
  final String body;
  final String route;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.route,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: (j['type'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        route: (j['route'] as String?) ?? '',
        isRead: (j['is_read'] as bool?) ?? false,
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal() ??
            DateTime.now(),
      );

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        route: route,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}

/// Talks to /api/notifications (in-app notification feed).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final Dio _dio = ApiClient.instance.dio;

  /// Unread count shown on the home bell.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  Future<List<AppNotification>> getAll() async {
    final userId = await TokenStore.instance.getUserId();
    if (userId == null) return [];
    final response = await _dio.get('/api/notifications', queryParameters: {'user_id': userId});
    final list = response.data['notifications'] as List<dynamic>? ?? [];
    final items =
        list.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
    unread.value = items.where((n) => !n.isRead).length;
    return items;
  }

  Future<void> refreshUnread() async {
    try {
      await getAll();
    } catch (_) {
      // Best-effort: the badge just stays as it was.
    }
  }

  Future<void> markRead(String id) async {
    await _dio.patch('/api/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    final userId = await TokenStore.instance.getUserId();
    if (userId == null) return;
    await _dio.post('/api/notifications/read-all', data: {'user_id': userId});
    unread.value = 0;
  }

  Future<void> delete(String id) async {
    await _dio.delete('/api/notifications/$id');
  }
}