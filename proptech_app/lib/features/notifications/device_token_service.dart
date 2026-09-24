import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';

/// Registers/unregisters this device's FCM token against the backend so the
/// server knows where to push notifications for the logged-in user.
class DeviceTokenService {
  DeviceTokenService._();
  static final DeviceTokenService instance = DeviceTokenService._();

  final Dio _dio = ApiClient.instance.dio;

  Future<void> register({
    required String userId,
    required String token,
    required String platform, // 'android' | 'ios' | 'web'
  }) async {
    try {
      await _dio.post('/api/device-tokens', data: {
        'user_id': userId,
        'token': token,
        'platform': platform,
      });
    } catch (_) {
      // Best-effort — a failed registration just means this device won't
      // get pushes until the next successful attempt (e.g. next app open).
    }
  }

  Future<void> unregister(String token) async {
    try {
      await _dio.delete('/api/device-tokens', data: {'token': token});
    } catch (_) {
      // Best-effort, e.g. called during logout.
    }
  }
}