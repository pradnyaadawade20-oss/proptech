import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/router/route_names.dart';

/// Remembers an owner-approval link (https://.../o/<token>) while the owner logs in or signs up,
/// so the approval screen opens by itself right after.
class PendingInviteStore {
  PendingInviteStore._();
  static const _key = 'pending_owner_invite_token';

  static Future<void> save(String token) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, token);
    } catch (e) {
      debugPrint('PendingInviteStore.save failed: $e');
    }
  }

  static Future<String?> peek() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString(_key);
      return (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}

/// Use this instead of `context.go(RouteNames.home)` after every successful login / sign-up.
/// Goes home, and if an owner-approval link is waiting, opens it on top.
Future<void> goHomeAfterAuth(BuildContext context) async {
  final router = GoRouter.of(context);
  final token = await PendingInviteStore.peek();
  router.go(RouteNames.home);
  if (token != null) {
    router.push(RouteNames.ownerApprove.replaceFirst(':token', token));
  }
}