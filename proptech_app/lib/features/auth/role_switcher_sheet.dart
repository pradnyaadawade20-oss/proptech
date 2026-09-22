import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/session/user_session.dart';

/// Opens a bottom sheet listing every role, letting the person switch to
/// a role they already have, or add a new one on the spot (e.g. a Tenant
/// who now also wants to list a property they own). Call this from the
/// profile screen or an app-bar action — it's the entry point that makes
/// multi-role accounts feel like switching modes rather than logging out.
void showRoleSwitcherSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
    ),
    builder: (sheetContext) => const _RoleSwitcherSheet(),
  );
}

class _RoleSwitcherSheet extends StatelessWidget {
  const _RoleSwitcherSheet();

  void _goToRoleHome(GoRouter router, UserRole role) {
    switch (role) {
      case UserRole.owner:
        // Push (not go) so Home stays underneath in the stack — otherwise
        // Owner Dashboard becomes the only route and back-press exits the app.
        router.go(RouteNames.home);
        router.push(RouteNames.ownerDashboard);
        break;
      case UserRole.broker:
        router.go(RouteNames.home);
        router.push(RouteNames.brokerDashboard);
        break;
      case UserRole.buyerTenant:
        router.go(RouteNames.home);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Switch role', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Text('You can be more than one — pick what you want to do right now.', style: AppTextStyles.bodySmall),
            const SizedBox(height: AppSpacing.md),
            ValueListenableBuilder<Set<UserRole>>(
              valueListenable: UserSession.instance.activeRoles,
              builder: (context, activeRoles, _) {
                return ValueListenableBuilder<UserRole?>(
                  valueListenable: UserSession.instance.currentRole,
                  builder: (context, current, _) {
                    return Column(
                      children: UserRole.values.map((role) {
                        final isActive = activeRoles.contains(role);
                        final isCurrent = current == role;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            onTap: () {
                              // Capture the router BEFORE popping the sheet —
                              // navigating with `context` right after
                              // Navigator.pop() uses a context whose widget
                              // is mid-unmount, which can produce a blank
                              // pushed screen.
                              final router = GoRouter.of(context);
                              UserSession.instance.switchTo(role);
                              Navigator.pop(context);
                              _goToRoleHome(router, role);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isCurrent ? AppColors.primary : AppColors.border,
                                  width: isCurrent ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _iconFor(role),
                                    color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(role.label, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                                        Text(
                                          isActive ? 'Already set up on your account' : 'Add this role to your account',
                                          style: AppTextStyles.caption,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent)
                                    const Icon(Icons.check_circle, color: AppColors.primary)
                                  else if (!isActive)
                                    const Icon(Icons.add_circle_outline, color: AppColors.textHint),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(UserRole role) {
    switch (role) {
      case UserRole.buyerTenant:
        return Icons.home_work_outlined;
      case UserRole.owner:
        return Icons.apartment_outlined;
      case UserRole.broker:
        return Icons.badge_outlined;
    }
  }
}