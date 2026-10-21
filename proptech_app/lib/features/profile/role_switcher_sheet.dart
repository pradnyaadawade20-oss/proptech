import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/session/user_session.dart';
import '../auth/auth_service.dart';

/// Profile -> tap the role badge: pick Buyer / Owner / Broker.
/// The choice is saved on the server first, so the profile shows the same
/// role after the next login too.
Future<void> showRoleSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => const _RoleSwitcherSheet(),
  );
}

class _RoleSwitcherSheet extends StatefulWidget {
  const _RoleSwitcherSheet();

  @override
  State<_RoleSwitcherSheet> createState() => _RoleSwitcherSheetState();
}

class _RoleSwitcherSheetState extends State<_RoleSwitcherSheet> {
  UserRole? _busy; // role currently being saved
  String? _error;

  static IconData _icon(UserRole role) {
    switch (role) {
      case UserRole.buyerTenant:
        return Icons.person_search_outlined;
      case UserRole.owner:
        return Icons.apartment_outlined;
      case UserRole.broker:
        return Icons.badge_outlined;
    }
  }

  Future<void> _pick(UserRole role) async {
    if (_busy != null) return;
    if (role == UserSession.instance.currentRole.value) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = role;
      _error = null;
    });
    final error = await AuthService.instance.switchRole(role);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = null;
        _error = error;
      });
      return;
    }
    UserSession.instance.switchTo(role);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('Switched to ${role.label}')));
  }

  @override
  Widget build(BuildContext context) {
    final current = UserSession.instance.currentRole.value;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Switch role', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('Choose how you want to use the app.', style: AppTextStyles.bodySmall),
          const SizedBox(height: AppSpacing.md),
          for (final role in UserRole.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: _busy == null ? () => _pick(role) : null,
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                child: Icon(_icon(role), color: AppColors.primary),
              ),
              title: Text(role.label, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(role.subtitle, style: AppTextStyles.bodySmall),
              trailing: _busy == role
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : (role == current ? const Icon(Icons.check_circle, color: AppColors.primary) : null),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}