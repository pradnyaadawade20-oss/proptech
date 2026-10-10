import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/session/user_session.dart';
import '../auth/auth_service.dart';
import 'profile_avatar.dart';
import 'profile_service.dart';
import 'kyc_store.dart';
import '../lease/upi_pay_sheet.dart';
import '../notifications/push_notification_service.dart';

class _Ui {
  _Ui._();
  static const Color bg = Color(0xFFF3F6FC);
  static const Color ink = Color(0xFF0F2A5C);
  static const Color chevron = Color(0xFF7B879E);
  static const Color divider = Color(0xFFE6EBF5);
  static const Color red = Color(0xFFE5484D);
  static const Color mutedOnNavy = Color(0xFFA9B6D3);
  static const LinearGradient header = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF081A45), Color(0xFF0F2C63)],
  );
}

enum _PhotoAction { gallery, camera, remove }

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  bool _uploadingAvatar = false;
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

  Future<void> _changePhoto() async {
    final profile = _profile;
    if (profile == null || _uploadingAvatar) return;

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PhotoSheet(hasPhoto: profile.avatarUrl.isNotEmpty),
    );
    if (action == null || !mounted) return;

    try {
      final UserProfile updated;
      if (action == _PhotoAction.remove) {
        setState(() => _uploadingAvatar = true);
        updated = await ProfileService.instance.removeAvatar(profile.id);
      } else {
        final file = await ImagePicker().pickImage(
          source: action == _PhotoAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1080,
          maxHeight: 1080,
        );
        if (file == null || !mounted) return;
        setState(() => _uploadingAvatar = true);
        updated = await ProfileService.instance
            .uploadAvatar(userId: profile.id, file: file);
      }
      if (!mounted) return;
      setState(() { _profile = updated; _uploadingAvatar = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _logout() async {
    // Push token ko JWT clear karne se PEHLE unregister karo (endpoint ko auth chahiye).
    // Warna logout ke baad bhi is phone par purane user ki notifications aati rahengi.
    try {
      await PushNotificationService.instance
          .unregisterCurrentToken()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Logout ko kabhi network/FCM error par mat rokho.
    }
    await AuthService.instance.logout();
    UserSession.instance.reset();
    KycStore.instance.clear();
    if (mounted) context.go(RouteNames.login);
  }

  // ---------------------------------------------------------------- header

  Widget _buildUserCard() {
    final profile = _profile;
    final Widget content;

    if (_loading) {
      content = const SizedBox(
        height: 76,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    } else if (profile == null) {
      content = Row(
        children: [
          Expanded(
            child: Text(
              _error ?? 'Could not load your profile.',
              style: const TextStyle(color: _Ui.mutedOnNavy, fontSize: 14),
            ),
          ),
          TextButton(onPressed: _loadProfile, child: const Text('Retry')),
        ],
      );
    } else {
      content = Row(
        children: [
          ProfileAvatar(
            name: profile.name,
            avatarUrl: profile.avatarUrl,
            size: 76,
            uploading: _uploadingAvatar,
            onTap: _changePhoto,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.email.isNotEmpty ? profile.email : 'Add your email',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _Ui.mutedOnNavy, fontSize: 14),
                ),
                if (profile.phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.phone,
                    style: const TextStyle(color: _Ui.mutedOnNavy, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkResponse(
            onTap: _editProfile,
            radius: 28,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: const Color(0xFF2B5FA8)),
              ),
              child: const Icon(Icons.edit_outlined,
                  size: 21, color: Color(0xFF4A90FF)),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: content,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 20, 16, 26),
      decoration: const BoxDecoration(
        gradient: _Ui.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildUserCard(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _Ui.bg,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                24,
                16,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              child: Column(
                children: [
                  _MenuGroup(
                    children: [
                      _ProfileMenuTile(
                        icon: Icons.home_outlined,
                        title: 'My Properties',
                        onTap: () => context.push(RouteNames.myProperties),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.calendar_today_outlined,
                        title: 'My Visits',
                        onTap: () => context.push(RouteNames.myVisits),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.vpn_key_outlined,
                        title: 'My Leases & Rent',
                        onTap: () => context.push(RouteNames.leases),
                      ),
                      // Anyone who posts a property (owner or broker) adds the UPI ID
                      // that receives rent and deposit here.
                      _ProfileMenuTile(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'My UPI ID (receive rent)',
                        onTap: () => editOwnerUpi(context),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.favorite_border,
                        title: 'Favorites',
                        onTap: () => context.push(RouteNames.favorites),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.mode_comment_outlined,
                        title: 'Chats',
                        onTap: () => context.go(RouteNames.chatList),
                      ),
                      _ProfileMenuTile(
                        icon: Icons.verified_user_outlined,
                        title: 'KYC Verification',
                        onTap: () => context.push(RouteNames.kycVerification),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _MenuGroup(
                    children: [
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
                      _ProfileMenuTile(
                        icon: Icons.logout_rounded,
                        title: 'Logout',
                        iconColor: _Ui.red,
                        textColor: _Ui.red,
                        onTap: _logout,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White rounded card that stacks menu tiles with inset dividers.
class _MenuGroup extends StatelessWidget {
  final List<Widget> children;
  const _MenuGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(const Padding(
          padding: EdgeInsets.only(left: 68, right: 16),
          child: Divider(height: 1, thickness: 1, color: _Ui.divider),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1F4B).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: Column(children: items),
        ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Icon(icon, size: 28, color: iconColor ?? _Ui.ink),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor ?? _Ui.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 26, color: _Ui.chevron),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: gallery / camera / remove.
class _PhotoSheet extends StatelessWidget {
  final bool hasPhoto;
  const _PhotoSheet({required this.hasPhoto});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _Ui.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Profile photo',
            style: TextStyle(
              color: _Ui.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: _Ui.ink),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, _PhotoAction.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: _Ui.ink),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, _PhotoAction.camera),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _Ui.red),
              title: const Text('Remove photo',
                  style: TextStyle(color: _Ui.red)),
              onTap: () => Navigator.pop(context, _PhotoAction.remove),
            ),
          const SizedBox(height: 8),
        ],
      ),
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