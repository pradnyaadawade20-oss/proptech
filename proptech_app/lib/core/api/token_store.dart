import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps flutter_secure_storage for the few pieces of session data we
/// need to persist across app restarts: the JWT, and the logged-in
/// user's id (since several backend endpoints need it as a query param
/// until the backend derives it from the token itself).
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  // resetOnError: if stored data can't be decrypted (e.g. restored after a
  // reinstall) it is wiped instead of throwing -> user just logs in again.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _rolesKey = 'auth_roles';
  static const _activeRoleKey = 'auth_active_role';
  static const _installedFlag = 'proptech_installed_once';

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

  Future<void> saveRoles(String roles, String activeRole) async {
    await _storage.write(key: _rolesKey, value: roles);
    await _storage.write(key: _activeRoleKey, value: activeRole);
  }

  Future<String?> getRoles() => _storage.read(key: _rolesKey);
  Future<String?> getActiveRole() => _storage.read(key: _activeRoleKey);

  /// Call once at startup. SharedPreferences is wiped when the app is
  /// uninstalled, but Keychain (iOS) / restored backups can keep the old
  /// session. So: flag missing => fresh install => drop any leftover login.
  Future<void> clearIfFreshInstall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_installedFlag) != true) {
        await clear();
        await prefs.setBool(_installedFlag, true);
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _rolesKey);
    await _storage.delete(key: _activeRoleKey);
  }
}