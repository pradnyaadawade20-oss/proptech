import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import '../chat/chat_avatar.dart';
import '../leads/lead_service.dart';
import '../profile/profile_service.dart';
import 'property_service.dart';
import 'property.dart';
import '../../core/utils/price_format.dart';
import '../../core/widgets/safe_network_image.dart';

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
    LeadService.instance.track(property.id, 'chat');
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
      appBar: AppBar(
        title: Text(
          'Owner Details',
          style: AppTextStyles.h3.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(context, ownerName, ownerPhone, memberSince, listed),
    );
  }

  Widget _buildOwnerCard(String ownerName, String memberSince, String listed) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceSoft, Colors.white],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 1),
        child: Stack(
          children: [
            // Soft decorative circles (top-left / bottom-right).
            Positioned(
              top: -50,
              left: -40,
              child: _softCircle(140),
            ),
            Positioned(
              bottom: -60,
              right: -50,
              child: _softCircle(170),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ChatAvatar(
                      name: ownerName,
                      avatarUrl: _owner?.avatarUrl ?? '',
                      radius: 48,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    ownerName,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h2.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Property Owner',
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(child: _StatColumn(label: 'Listed', value: listed)),
                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: AppColors.border,
                        ),
                        Expanded(child: _StatColumn(label: 'Member since', value: memberSince)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _softCircle(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.05),
        ),
      );

  Widget _buildListingCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: SafeNetworkImage(property.imageUrl, width: 88, height: 80, fit: BoxFit.cover),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        property.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatPrice(property.price, property.priceUnit),
                  style: AppTextStyles.h3.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, String ownerName, String ownerPhone,
      String memberSince, String listed) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _buildOwnerCard(ownerName, memberSince, listed),
        const SizedBox(height: AppSpacing.lg),

        // Property this owner is being contacted about
        Text(
          'About this listing',
          style: AppTextStyles.h2.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildListingCard(),
        const SizedBox(height: AppSpacing.lg),

        // Contact options
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                icon: const Icon(Icons.phone_outlined),
                label: Text(
                  'Call',
                  style: AppTextStyles.button.copyWith(color: AppColors.primary),
                ),
                onPressed: ownerPhone.isEmpty
                    ? null
                    : () {
                        LeadService.instance.track(property.id, 'call');
                        _callOwner(context, ownerPhone);
                      },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Message'),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: AppTextStyles.h3.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}