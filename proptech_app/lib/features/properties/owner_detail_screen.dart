import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../chat/chat_message.dart';
import 'property.dart';

/// Simple derived "owner" record for a property. Real data will come from
/// the backend once properties carry an actual ownerId — for now every
/// property is deterministically mapped to one of the dummy people so the
/// same property always shows the same owner.
class OwnerInfo {
  final String name;
  final String avatarUrl;
  final String phone;
  final double rating;
  final int propertiesListed;
  final String memberSince;

  const OwnerInfo({
    required this.name,
    required this.avatarUrl,
    required this.phone,
    required this.rating,
    required this.propertiesListed,
    required this.memberSince,
  });
}

OwnerInfo ownerForProperty(Property property) {
  final convo = dummyConversations[property.id.hashCode.abs() % dummyConversations.length];
  return OwnerInfo(
    name: convo.name,
    avatarUrl: convo.avatarUrl,
    phone: '+91 98${(property.id.hashCode.abs() % 90000000 + 10000000)}',
    rating: property.rating,
    propertiesListed: 2 + (property.id.hashCode.abs() % 6),
    memberSince: '${2019 + (property.id.hashCode.abs() % 5)}',
  );
}

class OwnerDetailScreen extends StatelessWidget {
  final Property property;
  const OwnerDetailScreen({super.key, required this.property});

  @override
  Widget build(BuildContext context) {
    final owner = ownerForProperty(property);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Owner Details')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Owner card
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                CircleAvatar(radius: 40, backgroundImage: NetworkImage(owner.avatarUrl)),
                const SizedBox(height: AppSpacing.md),
                Text(owner.name, style: AppTextStyles.h2),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    Text('${owner.rating.toStringAsFixed(1)} • Property Owner', style: AppTextStyles.bodyMedium),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatColumn(label: 'Listed', value: '${owner.propertiesListed} properties'),
                    Container(width: 1, height: 32, color: AppColors.border),
                    _StatColumn(label: 'Member since', value: owner.memberSince),
                    Container(width: 1, height: 32, color: AppColors.border),
                    const _StatColumn(label: 'Response', value: '~1 hour'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Property this owner is being contacted about
          Text('About this listing', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Image.network(property.imageUrl, width: 56, height: 56, fit: BoxFit.cover),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                      Text(property.location, style: AppTextStyles.caption),
                      Text(
                        '₹${property.price.toStringAsFixed(0)}${property.priceUnit}',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Contact options
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Call',
                  outlined: true,
                  onPressed: () => _callOwner(context, owner.phone),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Message',
                  onPressed: () => context.push('/chats/${property.id}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _callOwner(BuildContext context, String phone) async {
  final cleanNumber = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  final uri = Uri(scheme: 'tel', path: cleanNumber);
  final launched = await launchUrl(uri);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open dialer for $phone')),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}