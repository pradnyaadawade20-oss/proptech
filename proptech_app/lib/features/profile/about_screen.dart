import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'support_links.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const List<(IconData, String, String)> _features = [
    (Icons.home_work_outlined, 'Buy, rent or sell', 'Residential, commercial, plots and PG listings in one place.'),
    (Icons.verified_outlined, 'Verified listings', 'View ownership documents before you decide.'),
    (Icons.chat_bubble_outline, 'Talk to owners directly', 'Chat or call owners without a middleman.'),
    (Icons.event_available_outlined, 'Schedule visits', 'Request and track property visits.'),
    (Icons.description_outlined, 'Digital agreements', 'Draft, review and sign rental agreements in the app.'),
    (Icons.swap_horiz, 'One account, many roles', 'Switch between Buyer / Tenant, Owner and Broker anytime.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const SizedBox(height: AppSpacing.md),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              child: Image.asset(
                'assets/images/logo.png',
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 88,
                  height: 88,
                  color: AppColors.primary,
                  child: const Icon(Icons.home_work, color: Colors.white, size: 44),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(child: Text('PropTech', style: AppTextStyles.h2)),
          const SizedBox(height: 2),
          Center(child: Text('Version $appVersion', style: AppTextStyles.caption)),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              'Buy, Rent or Sell verified properties with complete trust.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('What PropTech does', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'PropTech connects property owners, brokers, buyers and tenants on one platform, '
            'so finding or listing a property is transparent and simple — from the first '
            'search to the signed agreement.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          ..._features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(f.$1, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.$2, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(f.$3, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.textPrimary),
            title: Text('Privacy Policy', style: AppTextStyles.bodyMedium),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
            onTap: () => context.push(RouteNames.privacy),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.gavel_outlined, color: AppColors.textPrimary),
            title: Text('Terms of Service', style: AppTextStyles.bodyMedium),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
            onTap: () => context.push(RouteNames.terms),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.email_outlined, color: AppColors.textPrimary),
            title: Text('Contact us', style: AppTextStyles.bodyMedium),
            subtitle: Text(supportEmail, style: AppTextStyles.caption),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
            onTap: () => launchSupportEmail(context),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text('© 2026 PropTech. All rights reserved.', style: AppTextStyles.caption),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}