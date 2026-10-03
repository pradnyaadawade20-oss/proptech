import 'package:flutter/foundation.dart';
import '../api/token_store.dart';

/// The roles a person can operate as inside the app. A single account
/// can hold more than one — e.g. someone who owns a flat (Owner) but is
/// also hunting for a bigger place to rent (Tenant/Buyer).
enum UserRole { buyerTenant, owner, broker }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.buyerTenant:
        return 'Buyer / Tenant';
      case UserRole.owner:
        return 'Property Owner';
      case UserRole.broker:
        return 'Broker / Agent';
    }
  }

  String get subtitle {
    switch (this) {
      case UserRole.buyerTenant:
        return 'Browse & shortlist properties to buy or rent';
      case UserRole.owner:
        return 'List and manage your own properties';
      case UserRole.broker:
        return "List clients' properties, manage leads";
    }
  }
}

/// App-wide session holding which roles this account has opted into and
/// which one is currently active. Screens read [currentRole] to decide
/// what dashboard/navigation to show, and can call [switchTo] to change
/// it without logging out — this is what makes roles feel like "modes"
/// rather than separate accounts.
class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  final ValueNotifier<Set<UserRole>> activeRoles = ValueNotifier({});
  final ValueNotifier<UserRole?> currentRole = ValueNotifier(null);

  bool get hasAnyRole => activeRoles.value.isNotEmpty;

  void setInitialRoles(Set<UserRole> roles, {UserRole? startWith}) {
    activeRoles.value = roles;
    currentRole.value = startWith ?? (roles.isNotEmpty ? roles.first : null);
    _persist();
  }

  /// Adds a role the user didn't originally sign up with (e.g. a Tenant
  /// later decides to list a property they own) without touching the rest
  /// of their session/login state.
  void addRole(UserRole role) {
    activeRoles.value = {...activeRoles.value, role};
    _persist();
  }

  void switchTo(UserRole role) {
    if (!activeRoles.value.contains(role)) {
      addRole(role);
    }
    currentRole.value = role;
    _persist();
  }

  /// Saves roles so they survive an app restart (login is kept on device).
  Future<void> _persist() async {
    try {
      await TokenStore.instance.saveRoles(
        activeRoles.value.map((r) => r.name).join(','),
        currentRole.value?.name ?? '',
      );
    } catch (_) {}
  }

  /// Restores roles after a cold start when the user is still logged in.
  Future<void> restore() async {
    try {
      final saved = (await TokenStore.instance.getRoles()) ?? '';
      final roles = <UserRole>{
        for (final n in saved.split(',').where((e) => e.isNotEmpty))
          UserRole.values.firstWhere((r) => r.name == n, orElse: () => UserRole.buyerTenant),
      };
      if (roles.isEmpty) return;
      final activeName = await TokenStore.instance.getActiveRole();
      final active = UserRole.values.where((r) => r.name == activeName);
      activeRoles.value = roles;
      currentRole.value = active.isNotEmpty && roles.contains(active.first)
          ? active.first
          : roles.first;
    } catch (_) {}
  }

  void reset() {
    activeRoles.value = {};
    currentRole.value = null;
  }
}