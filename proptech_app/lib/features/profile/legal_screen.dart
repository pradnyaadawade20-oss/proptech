import 'package:flutter/material.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'support_links.dart';

/// Simple scrolling text page used for both Privacy Policy and Terms.
class LegalScreen extends StatelessWidget {
  final String title;
  final List<(String, String)> sections;

  const LegalScreen({super.key, required this.title, required this.sections});

  factory LegalScreen.privacy() => const LegalScreen(
        title: 'Privacy Policy',
        sections: _privacySections,
      );

  factory LegalScreen.terms() => const LegalScreen(
        title: 'Terms of Service',
        sections: _termsSections,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Last updated: September 2026', style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.md),
          for (final s in sections) ...[
            Text(s.$1, style: AppTextStyles.h3.copyWith(fontSize: 16)),
            const SizedBox(height: AppSpacing.xs),
            Text(s.$2, style: AppTextStyles.bodySmall.copyWith(height: 1.5)),
            const SizedBox(height: AppSpacing.md),
          ],
          Text('Questions? Write to $supportEmail', style: AppTextStyles.bodySmall),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

const List<(String, String)> _privacySections = [
  (
    'Information we collect',
    'When you use PropTech we collect the details you give us: your name, mobile number, '
        'email address and profile photo; the properties you list, save or view; your chat '
        'messages, visit requests and rental agreements; and any documents you upload for '
        'verification.',
  ),
  (
    'How we use it',
    'We use your information to create and secure your account, show relevant properties, '
        'connect you with owners, buyers and tenants, arrange visits, prepare agreements, '
        'and improve the app.',
  ),
  (
    'What other users can see',
    'To make a deal possible, some details are shared with the other party: your name and '
        'profile photo are visible in chats, and your phone number may be visible to an '
        'owner or tenant you are dealing with. Messages are visible only to you and the '
        'person you are chatting with.',
  ),
  (
    'Sharing',
    'We do not sell your personal information. We share it only with service providers '
        'that help us run the app (such as hosting and messaging) or when required by law.',
  ),
  (
    'Security',
    'Your login is protected with an OTP and your session is stored securely on your '
        'device. No system is perfectly secure, so please keep your phone and OTPs private.',
  ),
  (
    'Your choices',
    'You can edit your name and email from Profile at any time. To request deletion of '
        'your account and data, contact us using the email below.',
  ),
];

const List<(String, String)> _termsSections = [
  (
    'Using PropTech',
    'By creating an account you agree to these terms. You must be at least 18 years old '
        'and provide accurate information. You are responsible for activity on your account.',
  ),
  (
    'Listings',
    'Owners and brokers are responsible for the accuracy of their listings, including '
        'price, photos, availability and ownership documents. Do not post properties you '
        'are not authorised to list.',
  ),
  (
    'Deals between users',
    'PropTech is a platform that connects users. Unless stated otherwise, we are not a '
        'party to any sale, rental or agreement between users. Please verify the property '
        'and documents yourself before paying any money.',
  ),
  (
    'Agreements',
    'Agreements prepared in the app are drafts based on the details entered by the owner '
        'and tenant. Review them carefully; you may wish to get independent legal advice.',
  ),
  (
    'Acceptable use',
    'Do not post false or misleading content, harass other users, misuse chat for spam or '
        'fraud, or attempt to access other accounts or disrupt the service.',
  ),
  (
    'Suspension',
    'We may remove content or suspend accounts that break these terms or put other users '
        'at risk.',
  ),
  (
    'Liability',
    'We work to keep the app reliable but do not guarantee it will always be available or '
        'error-free. To the extent permitted by law, we are not liable for losses arising '
        'from dealings between users.',
  ),
  (
    'Changes',
    'We may update these terms from time to time. Continuing to use the app after an update '
        'means you accept the new terms.',
  ),
];