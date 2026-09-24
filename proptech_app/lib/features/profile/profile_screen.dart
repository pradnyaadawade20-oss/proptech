import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/session/user_session.dart';
import '../auth/auth_service.dart';
import '../auth/role_switcher_sheet.dart';
import '../chat/chat_avatar.dart';
import 'profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() { _loading = true; _error = null; });
    try {
      final profile = await ProfileService.instance.getMyProfile();
      if (!mounted) return;
      setState(() { _profile = profile; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _editProfile() async {
    final profile = _profile;
    if (profile == null) return;

    final updated = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
    if (updated != null && mounted) setState(() => _profile = updated);
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    UserSession.instance.reset();
    if (mounted) context.go(RouteNames.login);
  }

  Widget _buildHeader() {
    if (_loading) {
      return const SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _error ?? 'Could not load your profile.',
              style: AppTextStyles.bodySmall,
            ),
          ),
          TextButton(onPressed: _loadProfile, child: const Text('Retry')),
        ],
      );
    }

    return Row(
      children: [
        ChatAvatar(name: profile.name, avatarUrl: profile.avatarUrl, radius: 36),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.name, style: AppTextStyles.h3),
              const SizedBox(height: 2),
              Text(
                profile.email.isNotEmpty ? profile.email : 'Add your email',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(profile.phone, style: AppTextStyles.bodySmall),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: _editProfile,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _buildHeader(),
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
            onTap: () => context.push(RouteNames.settings),
          ),
          _ProfileMenuTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            onTap: () => context.push(RouteNames.helpSupport),
          ),
          _ProfileMenuTile(
            icon: Icons.info_outline,
            title: 'About',
            onTap: () => context.push(RouteNames.about),
          ),
          const SizedBox(height: AppSpacing.md),
          _ProfileMenuTile(
            icon: Icons.logout,
            title: 'Logout',
            iconColor: Colors.red,
            textColor: Colors.red,
            onTap: _logout,
          ),
        ],
      ),
    );
  }
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

class _EditProfileSheet extends StatefulWidget {
  final UserProfile profile;
  const _EditProfileSheet({required this.profile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.profile.name);
  late final TextEditingController _email = TextEditingController(text: widget.profile.email);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty.');
      return;
    }
    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      final updated = await ProfileService.instance.updateProfile(
        userId: widget.profile.id,
        name: name,
        email: email,
        avatarUrl: widget.profile.avatarUrl, // backend overwrites it, so send it back unchanged
      );
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit Profile', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: Colors.red)),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}