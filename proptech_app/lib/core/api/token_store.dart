import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage for the few pieces of session data we
/// need to persist across app restarts: the JWT, and the logged-in
/// user's id (since several backend endpoints need it as a query param
/// until the backend derives it from the token itself).
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  final _storage = const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> saveUserId(String userId) => _storage.write(key: _userIdKey, value: userId);
  Future<String?> getUserId() => _storage.read(key: _userIdKey);

  /// Never throws and never hangs: Android Keystore can get corrupted
  /// (reinstall / backup restore) and then secure-storage reads throw
  /// BadPaddingException or stall. In that case treat the user as logged
  /// out and wipe the unreadable data so the next login works cleanly.
  Future<bool> isLoggedIn() async {
    try {
      final token = await getToken().timeout(const Duration(seconds: 5));
      return token != null;
    } on TimeoutException {
      debugPrint('TokenStore: secure storage read timed out');
      return false;
    } catch (e) {
      debugPrint('TokenStore: secure storage unreadable, resetting: $e');
      try {
        await _storage.deleteAll().timeout(const Duration(seconds: 5));
      } catch (_) {}
      return false;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
  }
}