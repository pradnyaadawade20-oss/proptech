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

  // Backup copy in SharedPreferences. Android Keystore reads can fail or stall on
  // a cold start (app killed in background), which used to look like "logged out".
  // SharedPreferences is wiped on uninstall, so a reinstall still starts logged out.
  Future<void> _mirrorWrite(String key, String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove('mirror_$key');
      } else {
        await prefs.setString('mirror_$key', value);
      }
    } catch (_) {}
  }

  Future<String?> _mirrorRead(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString('mirror_$key');
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _mirrorWrite(_tokenKey, token);
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('TokenStore: secure write failed, using backup copy: $e');
    }
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    String? t;
    // Android Keystore can be slow / fail transiently right after launch, so retry.
    for (var attempt = 0; attempt < 3 && (t == null || t.isEmpty); attempt++) {
      try {
        t = await _storage.read(key: _tokenKey).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('TokenStore: secure read failed (attempt ${attempt + 1}): $e');
      }
      if (t == null || t.isEmpty) await Future.delayed(const Duration(milliseconds: 300));
    }
    // Secure storage gave nothing: use the backup copy (and heal secure storage).
    if (t == null || t.isEmpty) {
      t = await _mirrorRead(_tokenKey);
      if (t != null && t.isNotEmpty) {
        try {
          await _storage.write(key: _tokenKey, value: t);
        } catch (_) {}
      }
    }
    if (t != null && t.isNotEmpty) _cachedToken = t;
    return (t == null || t.isEmpty) ? null : t;
  }

  // In-memory copy, like the token: a flaky Keystore read must not make a
  // logged-in user look "logged out" (screens say "Please log in again.").
  String? _cachedUserId;

  Future<void> saveUserId(String userId) async {
    _cachedUserId = userId;
    await _mirrorWrite(_userIdKey, userId);
    try {
      await _storage.write(key: _userIdKey, value: userId);
    } catch (_) {}
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

  /// Never throws. Only "no token anywhere" counts as logged out; a failing or
  /// slow secure-storage read must NOT wipe the login (that logged users out
  /// every time the app was reopened after being killed).
  Future<bool> isLoggedIn() async {
    try {
      final token = await getToken();
      return token != null && token.isNotEmpty;
    } catch (e) {
      debugPrint('TokenStore: isLoggedIn check failed: $e');
      return false;
    }
  }

  Future<void> saveRoles(String roles, String activeRole) async {
    await _mirrorWrite(_rolesKey, roles);
    await _mirrorWrite(_activeRoleKey, activeRole);
    try {
      await _storage.write(key: _rolesKey, value: roles);
      await _storage.write(key: _activeRoleKey, value: activeRole);
    } catch (_) {}
  }

  Future<String?> _readWithMirror(String key) async {
    try {
      final v = await _storage.read(key: key).timeout(const Duration(seconds: 8));
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return _mirrorRead(key);
  }

  Future<String?> getRoles() => _readWithMirror(_rolesKey);
  Future<String?> getActiveRole() => _readWithMirror(_activeRoleKey);

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
    for (final k in [_tokenKey, _userIdKey, _rolesKey, _activeRoleKey]) {
      await _mirrorWrite(k, null);
      try {
        await _storage.delete(key: k);
      } catch (_) {}
    }
  }
}