import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/session/user_session.dart';
import '../auth/auth_service.dart';

/// Wraps the "Add property" screen. First time someone posts, ask
/// Owner or Broker, remember it, then show the real form.
class PostRoleGate extends StatelessWidget {
  final Widget child;
  const PostRoleGate({super.key, required this.child});

  static bool _canPost(Set<UserRole> roles) =>
      roles.contains(UserRole.owner) || roles.contains(UserRole.broker);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<UserRole>>(
      valueListenable: UserSession.instance.activeRoles,
      builder: (context, roles, _) =>
          _canPost(roles) ? child : const _PostRolePicker(),
    );
  }
}

class _PostRolePicker extends StatelessWidget {
  const _PostRolePicker();

  void _choose(UserRole role) {
    UserSession.instance.switchTo(role);
    AuthService.instance.saveRole(role); // best-effort, saves on server
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post property')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Who is posting this property?', style: AppTextStyles.h2),
            const SizedBox(height: AppSpacing.xs),
            Text('You can switch this later from your profile.',
                style: AppTextStyles.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            _PickTile(
              icon: Icons.apartment_outlined,
              role: UserRole.owner,
              onTap: () => _choose(UserRole.owner),
            ),
            const SizedBox(height: AppSpacing.md),
            _PickTile(
              icon: Icons.badge_outlined,
              role: UserRole.broker,
              onTap: () => _choose(UserRole.broker),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  final IconData icon;
  final UserRole role;
  final VoidCallback onTap;

  const _PickTile({required this.icon, required this.role, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label,
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(role.subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}