import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/session/user_session.dart';
import '../auth/role_switcher_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 36,
                backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=8'),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Amit Kumar', style: AppTextStyles.h3),
                    const SizedBox(height: 2),
                    Text('amit.kumar@email.com', style: AppTextStyles.bodySmall),
                    const SizedBox(height: 2),
                    Text('+91 98765 43210', style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showInfoDialog(context, 'Edit Profile', 'Profile editing will be available once the backend is connected.'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ValueListenableBuilder<UserRole?>(
            valueListenable: UserSession.instance.currentRole,
            builder: (context, current, _) {
              return _ProfileMenuTile(
                icon: Icons.swap_horiz,
                title: current != null ? 'Switch role — currently ${current.label}' : 'Choose your role',
                onTap: () => showRoleSwitcherSheet(context),
              );
            },
          ),
          _ProfileMenuTile(
            icon: Icons.home_work_outlined,
            title: 'My Properties',
            onTap: () => context.push(RouteNames.myProperties),
          ),
          _ProfileMenuTile(
            icon: Icons.event_available_outlined,
            title: 'My Visits',
            onTap: () => context.push(RouteNames.myVisits),
          ),
          _ProfileMenuTile(
            icon: Icons.favorite_border,
            title: 'Favorites',
            onTap: () => context.push(RouteNames.favorites),
          ),
          _ProfileMenuTile(
            icon: Icons.chat_bubble_outline,
            title: 'Chats',
            onTap: () => context.go(RouteNames.chatList),
          ),
          const Divider(height: AppSpacing.lg * 2),
          _ProfileMenuTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () => _showInfoDialog(context, 'Settings', 'App settings screen is coming soon.'),
          ),
          _ProfileMenuTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            onTap: () => _showInfoDialog(context, 'Help & Support', 'For any queries, reach us at support@proptech.app'),
          ),
          _ProfileMenuTile(
            icon: Icons.info_outline,
            title: 'About',
            onTap: () => _showInfoDialog(context, 'About PropTech', 'PropTech v0.1.0\nBuy, Rent or Sell verified properties with complete trust.'),
          ),
          const SizedBox(height: AppSpacing.md),
          _ProfileMenuTile(
            icon: Icons.logout,
            title: 'Logout',
            iconColor: Colors.red,
            textColor: Colors.red,
            onTap: () {
              context.go(RouteNames.login);
            },
          ),
        ],
      ),
    );
  }
}

void _showInfoDialog(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    ),
  );
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: iconColor ?? AppColors.textPrimary),
      title: Text(
        title,
        style: AppTextStyles.bodyMedium.copyWith(color: textColor ?? AppColors.textPrimary),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}