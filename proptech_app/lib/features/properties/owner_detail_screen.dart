import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/api/token_store.dart';
import '../chat/chat_avatar.dart';
import '../profile/profile_service.dart';
import 'property_service.dart';
import 'property.dart';

class OwnerDetailScreen extends StatefulWidget {
  final Property property;
  const OwnerDetailScreen({super.key, required this.property});

  @override
  State<OwnerDetailScreen> createState() => _OwnerDetailScreenState();
}

class _OwnerDetailScreenState extends State<OwnerDetailScreen> {
  UserProfile? _owner;
  int? _listedCount;
  bool _loading = true;

  Property get property => widget.property;

  @override
  void initState() {
    super.initState();
    _loadOwner();
  }

  Future<void> _loadOwner() async {
    if (property.ownerId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    // Profile and listing count load independently — one failing shouldn't
    // hide the other.
    final results = await Future.wait([
      ProfileService.instance.getProfile(property.ownerId).then<UserProfile?>((v) => v).catchError((_) => null),
      PropertyService.instance.getByOwner(property.ownerId).then<int?>((v) => v.length).catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _owner = results[0] as UserProfile?;
      _listedCount = results[1] as int?;
      _loading = false;
    });
  }

  Future<void> _messageOwner() async {
    if (property.ownerId.isEmpty) return;
    final myId = await TokenStore.instance.getUserId();
    if (!mounted) return;
    if (myId == property.ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is your own listing.')),
      );
      return;
    }
    context.push('/chats/${property.ownerId}?propertyId=${property.id}');
  }

  @override
  Widget build(BuildContext context) {
    final ownerName = (_owner?.name.isNotEmpty == true) ? _owner!.name : property.ownerName;
    final ownerPhone = _owner?.phone ?? '';
    final memberSince = _owner?.createdAt != null ? '${_owner!.createdAt!.year}' : '—';
    final listed = _listedCount != null ? '$_listedCount properties' : '—';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Owner Details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(context, ownerName, ownerPhone, memberSince, listed),
    );
  }

  Widget _buildContent(BuildContext context, String ownerName, String ownerPhone,
      String memberSince, String listed) {
    return ListView(
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
                ChatAvatar(name: ownerName, avatarUrl: _owner?.avatarUrl ?? '', radius: 40),
                const SizedBox(height: AppSpacing.md),
                Text(ownerName, style: AppTextStyles.h2),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    Text('${property.rating.toStringAsFixed(1)} • Property Owner', style: AppTextStyles.bodyMedium),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatColumn(label: 'Listed', value: listed),
                    Container(width: 1, height: 32, color: AppColors.border),
                    _StatColumn(label: 'Member since', value: memberSince),
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
                  onPressed: ownerPhone.isEmpty ? null : () => _callOwner(context, ownerPhone),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Message',
                  onPressed: property.ownerId.isEmpty ? null : _messageOwner,
                ),
              ),
            ],
          ),
        ],
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