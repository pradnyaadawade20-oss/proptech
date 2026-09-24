import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'support_links.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const List<(String, String)> _faqs = [
    (
      'How do I list my property?',
      'Go to Profile → Switch role and choose Property Owner (or Broker / Agent). '
          'Then open your dashboard and tap Add Property. Fill in the details and photos '
          'and submit. Your listing will appear under My Properties.',
    ),
    (
      'How do I contact an owner?',
      'Open any property and tap the owner details. You can Call the owner directly or '
          'send a Message. All your conversations are saved in the Messages tab.',
    ),
    (
      'How do I schedule a visit?',
      'Open the property you like and choose Schedule Visit. Pick a date and time, and '
          'you can track the request under Profile → My Visits.',
    ),
    (
      'What does "Verified" mean on a listing?',
      'Verified listings have ownership documents attached. Open the property page to '
          'view the documents and check them yourself before you decide.',
    ),
    (
      'How does the rental agreement work?',
      'From a property page, request an agreement. The owner fills in the rent, deposit '
          'and terms, and a draft is prepared. Both the owner and the tenant then sign it '
          'digitally, and you can follow the progress on the agreement status screen.',
    ),
    (
      'Can I be a buyer and an owner at the same time?',
      'Yes. One account can have several roles. Use Profile → Switch role to move between '
          'Buyer / Tenant, Property Owner and Broker / Agent without logging out.',
    ),
    (
      'How do I edit my name or email?',
      'Go to Profile and tap the pencil icon next to your name. Update your details and '
          'tap Save.',
    ),
    (
      'I am not receiving the OTP or cannot log in',
      'Check that you entered the correct 10-digit mobile number, wait a few seconds and '
          'request the OTP again. If it still does not work, email us and mention your '
          'mobile number.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Intro card
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(Icons.support_agent, size: 36, color: AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How can we help?', style: AppTextStyles.h3),
                      const SizedBox(height: 2),
                      Text(
                        'Find quick answers below or write to us.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Contact us', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.sm),
          _ContactCard(
            icon: Icons.email_outlined,
            title: 'Email support',
            subtitle: supportEmail,
            onTap: () => launchSupportEmail(context, subject: 'PropTech support (v$appVersion)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ContactCard(
            icon: Icons.bug_report_outlined,
            title: 'Report a problem',
            subtitle: 'Tell us what went wrong',
            onTap: () => launchSupportEmail(
              context,
              subject: 'PropTech problem report (v$appVersion)',
              body: 'What happened:\n\n\nWhat I expected:\n\n\nScreen / steps:\n',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Frequently asked questions', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.sm),
          ..._faqs.map((faq) => _FaqTile(question: faq.$1, answer: faq.$2)),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: AppTextStyles.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(question, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
          children: [Text(answer, style: AppTextStyles.bodySmall)],
        ),
      ),
    );
  }
}