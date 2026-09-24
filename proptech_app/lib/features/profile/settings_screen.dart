import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'app_settings.dart';
import 'support_links.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  final Map<String, bool> _prefs = {
    AppSettings.notifMessages: true,
    AppSettings.notifVisits: true,
    AppSettings.notifAgreements: true,
    AppSettings.notifOffers: false,
  };

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    for (final key in _prefs.keys.toList()) {
      _prefs[key] = await AppSettings.instance.getBool(key, defaultValue: _prefs[key]!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs[key] = value);
    await AppSettings.instance.setBool(key, value);
  }

  Widget _switchTile(String key, IconData icon, String title, String subtitle) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: AppTextStyles.bodyMedium),
      subtitle: Text(subtitle, style: AppTextStyles.caption),
      value: _prefs[key] ?? false,
      onChanged: (v) => _toggle(key, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                const _SectionLabel('Notifications'),
                _switchTile(AppSettings.notifMessages, Icons.chat_bubble_outline,
                    'Messages', 'New chat messages from owners and buyers'),
                _switchTile(AppSettings.notifVisits, Icons.event_available_outlined,
                    'Visit updates', 'Requests, confirmations and reschedules'),
                _switchTile(AppSettings.notifAgreements, Icons.description_outlined,
                    'Agreement updates', 'Drafts ready, signatures and status changes'),
                _switchTile(AppSettings.notifOffers, Icons.local_offer_outlined,
                    'New listings & offers', 'Properties matching your saved searches'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.md),
                  child: Text(
                    'These choices are saved on this device.',
                    style: AppTextStyles.caption,
                  ),
                ),
                const Divider(),
                const _SectionLabel('Privacy & legal'),
                _NavTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => context.push(RouteNames.privacy),
                ),
                _NavTile(
                  icon: Icons.gavel_outlined,
                  title: 'Terms of Service',
                  onTap: () => context.push(RouteNames.terms),
                ),
                const Divider(),
                const _SectionLabel('App'),
                _NavTile(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () => context.push(RouteNames.helpSupport),
                ),
                _NavTile(
                  icon: Icons.info_outline,
                  title: 'About PropTech',
                  onTap: () => context.push(RouteNames.about),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_outlined, color: AppColors.textPrimary),
                  title: Text('Version', style: AppTextStyles.bodyMedium),
                  trailing: Text(appVersion, style: AppTextStyles.bodySmall),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _NavTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: AppTextStyles.bodyMedium),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}