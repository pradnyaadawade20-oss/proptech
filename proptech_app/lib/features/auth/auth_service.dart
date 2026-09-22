import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';

class AuthResult {
  final bool success;
  final String? errorMessage;
  AuthResult.success() : success = true, errorMessage = null;
  AuthResult.failure(this.errorMessage) : success = false;
}

/// Talks to /api/auth/send-otp and /api/auth/verify-otp. On successful
/// verification, persists the JWT + user id via TokenStore so the rest
/// of the app (ApiClient interceptor, screens needing user_id) can use
/// them without re-fetching.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final Dio _dio = ApiClient.instance.dio;

  /// Returns the OTP for convenience during development (backend currently
  /// echoes it back since there's no real SMS gateway wired up yet).
  Future<String?> sendOtp(String phone) async {
    try {
      final response = await _dio.post('/api/auth/send-otp', data: {'phone': phone});
      return response.data['otp'] as String?;
    } on DioException catch (e) {
      throw Exception(_extractError(e));
    }
  }

  Future<AuthResult> verifyOtp({
    required String phone,
    required String name,
    required String otp,
    String role = 'tenant',
  }) async {
    try {
      final response = await _dio.post('/api/auth/verify-otp', data: {
        'phone': phone,
        'name': name,
        'otp': otp,
        'role': role,
      });

      final token = response.data['token'] as String;
      final user = response.data['user'] as Map<String, dynamic>;

      await TokenStore.instance.saveToken(token);
      await TokenStore.instance.saveUserId(user['id'] as String);

      return AuthResult.success();
    } on DioException catch (e) {
      return AuthResult.failure(_extractError(e));
    }
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? 'Something went wrong. Please try again.';
  }

  Future<void> logout() => TokenStore.instance.clear();
}