import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/route_names.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/session/user_session.dart';

/// Shown right after login/signup. Unlike a traditional single-role
/// picker, this lets the person select every role that applies to them —
/// they can be a Buyer/Tenant AND an Owner AND a Broker on one account,
/// and switch between those "modes" later from their profile.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final Set<UserRole> _selected = {};

  void _continue() {
    if (_selected.isEmpty) return;

    UserSession.instance.setInitialRoles(_selected, startWith: _selected.first);

    // Always land on Home first so it sits underneath in the stack.
    // Owner/Broker dashboards are pushed on top of it — otherwise they'd
    // be the only route in the stack and back-press would exit the app.
    context.go(RouteNames.home);
    switch (_selected.first) {
      case UserRole.owner:
        context.push(RouteNames.ownerDashboard);
        break;
      case UserRole.broker:
        context.push(RouteNames.brokerDashboard);
        break;
      case UserRole.buyerTenant:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text('Tell us about yourself', style: AppTextStyles.h2),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Select all that apply — you can switch between these anytime from your profile.',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              _RoleTile(
                icon: Icons.home_work_outlined,
                role: UserRole.buyerTenant,
                selected: _selected.contains(UserRole.buyerTenant),
                onTap: () => setState(() {
                  _selected.contains(UserRole.buyerTenant)
                      ? _selected.remove(UserRole.buyerTenant)
                      : _selected.add(UserRole.buyerTenant);
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              _RoleTile(
                icon: Icons.apartment_outlined,
                role: UserRole.owner,
                selected: _selected.contains(UserRole.owner),
                onTap: () => setState(() {
                  _selected.contains(UserRole.owner)
                      ? _selected.remove(UserRole.owner)
                      : _selected.add(UserRole.owner);
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              _RoleTile(
                icon: Icons.badge_outlined,
                role: UserRole.broker,
                selected: _selected.contains(UserRole.broker),
                onTap: () => setState(() {
                  _selected.contains(UserRole.broker)
                      ? _selected.remove(UserRole.broker)
                      : _selected.add(UserRole.broker);
                }),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected.isEmpty ? null : _continue,
                  child: Text(_selected.length > 1 ? 'Continue with ${_selected.length} roles' : 'Continue'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final IconData icon;
  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          color: selected ? AppColors.primaryLight.withValues(alpha: 0.3) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label, style: AppTextStyles.h3),
                  const SizedBox(height: 2),
                  Text(role.subtitle, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? AppColors.primary : AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}