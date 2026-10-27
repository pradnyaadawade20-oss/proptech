import 'dart:async';
import 'dart:convert';
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

  // In-memory copy so a slow/flaky Keystore read can't log the user out
  // mid-session. Persisted copy in secure storage survives app restarts.
  String? _cachedToken;

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    // Android Keystore can be slow / fail transiently right after launch,
    // so retry once before giving up.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final t = await _storage.read(key: _tokenKey).timeout(const Duration(seconds: 8));
        _cachedToken = t;
        return t;
      } on TimeoutException {
        if (attempt == 1) rethrow;
      }
    }
    return null;
  }

  // In-memory copy, like the token: a flaky Keystore read must not make a
  // logged-in user look "logged out" (screens say "Please log in again.").
  String? _cachedUserId;

  Future<void> saveUserId(String userId) async {
    _cachedUserId = userId;
    await _storage.write(key: _userIdKey, value: userId);
  }

  Future<String?> getUserId() async {
    if (_cachedUserId != null && _cachedUserId!.isNotEmpty) return _cachedUserId;
    String? id;
    try {
      id = await _storage.read(key: _userIdKey).timeout(const Duration(seconds: 8));
    } catch (_) {}
    // Storage gave nothing: the login token itself carries the user id ("user_id" claim).
    if (id == null || id.isEmpty) {
      id = _userIdFromToken(await getToken());
    }
    _cachedUserId = id;
    return id;
  }

  /// Reads the "user_id" claim from the JWT (no signature check; the server does that).
  String? _userIdFromToken(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final id = (jsonDecode(payload) as Map)['user_id'];
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Never throws and never hangs: Android Keystore can get corrupted
  /// (reinstall / backup restore) and then secure-storage reads throw
  /// BadPaddingException or stall. In that case treat the user as logged
  /// out and wipe the unreadable data so the next login works cleanly.
  Future<bool> isLoggedIn() async {
    try {
      final token = await getToken();
      return token != null && token.isNotEmpty;
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
    _cachedToken = null;
    _cachedUserId = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _rolesKey);
    await _storage.delete(key: _activeRoleKey);
  }
}