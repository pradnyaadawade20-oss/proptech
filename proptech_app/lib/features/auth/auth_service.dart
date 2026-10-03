import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';
import '../properties/property_store.dart';
import '../notifications/push_notification_service.dart';
import '../../core/session/user_session.dart';
import '../favorites/favorite_service.dart';
class AuthResult {
  final bool success;
  final String? errorMessage;

  /// From send-otp: false when the server could not deliver the email
  /// (only possible while the backend runs with DEV_SKIP_OTP=true).
  final bool emailSent;

  /// From send-otp: true when the backend allows skipping OTP (testing only).
  final bool skipAvailable;

  AuthResult.success({this.emailSent = true, this.skipAvailable = false})
      : success = true,
        errorMessage = null;
  AuthResult.failure(this.errorMessage)
      : success = false,
        emailSent = false,
        skipAvailable = false;
}

/// Talks to /api/auth/send-otp and /api/auth/verify-otp.
///
/// Flow: email + password (+ name for first-time signup) -> backend emails a
/// 6-digit OTP -> verify -> JWT + user id are persisted via TokenStore so the
/// rest of the app (ApiClient interceptor, screens needing user_id) can use
/// them without re-fetching.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final Dio _dio = ApiClient.instance.dio;

  /// Validates the credentials server-side and emails an OTP.
  /// The OTP itself is never returned to the app.
  Future<AuthResult> sendOtp({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/api/auth/send-otp', data: {
        'name': name,
        'phone': phone,
        'email': email,
        'password': password,
      });
      final data = response.data;
      return AuthResult.success(
        emailSent: !(data is Map && data['email_sent'] == false),
        skipAvailable: data is Map && data['skip_available'] == true,
      );
    } on DioException catch (e) {
      return AuthResult.failure(_extractError(e));
    }
  }

  Future<AuthResult> verifyOtp({
    required String email,
    required String otp,
    String role = 'tenant',
  }) async {
    try {
      final response = await _dio.post('/api/auth/verify-otp', data: {
        'email': email,
        'otp': otp,
        'role': role,
      });
      await _saveSession(response.data);
      return AuthResult.success();
    } on DioException catch (e) {
      return AuthResult.failure(_extractError(e));
    }
  }

  /// TESTING ONLY: logs in without an OTP. The backend rejects this (404)
  /// unless it runs with DEV_SKIP_OTP=true, and it needs a prior successful
  /// sendOtp for the same email (which already checked the password).
  Future<AuthResult> skipOtp({
    required String email,
    String role = 'tenant',
  }) async {
    try {
      final response = await _dio.post('/api/auth/skip-otp', data: {
        'email': email,
        'role': role,
      });
      await _saveSession(response.data);
      return AuthResult.success();
    } on DioException catch (e) {
      return AuthResult.failure(_extractError(e));
    }
  }

  Future<void> _saveSession(dynamic data) async {
    final token = data['token'] as String;
    final user = data['user'] as Map<String, dynamic>;

    await TokenStore.instance.saveToken(token);
    await TokenStore.instance.saveUserId(user['id'] as String);
    await PropertyStore.instance.load();
    PushNotificationService.instance.registerForCurrentUser();

    final roles = <UserRole>{
      for (final r in (user['roles'] as List? ?? const []))
        _roleFromServer(r.toString()),
    };
    if (roles.isEmpty) roles.add(UserRole.buyerTenant);
    final active = _roleFromServer((user['active_role'] ?? '').toString());
    UserSession.instance.setInitialRoles(
      roles,
      startWith: roles.contains(active) ? active : roles.first,
    );

    FavoriteService.instance.syncFavoriteFlags();
  }

  UserRole _roleFromServer(String role) {
    switch (role) {
      case 'owner':
        return UserRole.owner;
      case 'broker':
        return UserRole.broker;
      default:
        return UserRole.buyerTenant;
    }
  }

  String _roleToServer(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'owner';
      case UserRole.broker:
        return 'broker';
      case UserRole.buyerTenant:
        return 'buyer_tenant';
    }
  }

  Future<void> saveRole(UserRole role) async {
    try {
      final id = await TokenStore.instance.getUserId();
      if (id == null) return;
      await _dio.patch('/api/auth/users/$id/role',
          data: {'role': _roleToServer(role)});
    } on DioException catch (_) {}
  }
  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? 'Something went wrong. Please try again.';
  }

  Future<void> logout() => TokenStore.instance.clear();
}