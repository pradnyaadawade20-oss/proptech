import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import 'property.dart';
import 'property_store.dart';
import 'verify_property_flow.dart';

class MyPropertiesScreen extends StatefulWidget {
  const MyPropertiesScreen({super.key});

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}

class _MyPropertiesScreenState extends State<MyPropertiesScreen> with PropertyStoreListener<MyPropertiesScreen> {
  String? _myId;

  @override
  void initState() {
    super.initState();
    TokenStore.instance.getUserId().then((id) {
      if (mounted) setState(() => _myId = id);
    });
    if (!PropertyStore.instance.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => PropertyStore.instance.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only the logged-in user's own listings (not everyone's).
    final properties = PropertyStore.instance.all.where((p) => _myId != null && p.ownerId == _myId).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My Properties')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RouteNames.addProperty),
        icon: const Icon(Icons.add),
        label: const Text('Add Property'),
      ),
      body: properties.isEmpty
          ? const Center(child: Text('No properties listed yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: properties.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final property = properties[index];
                return _PropertyManageCard(property: property);
              },
            ),
    );
  }
}

class _PropertyManageCard extends StatelessWidget {
  final Property property;
  const _PropertyManageCard({required this.property});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/property/${property.id}'),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Image.network(
                    property.imageUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(property.title, style: AppTextStyles.h3.copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(property.location, style: AppTextStyles.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        '₹${property.price.toStringAsFixed(0)}${property.priceUnit}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'edit') {
                      // TODO: navigate to edit property screen
                    } else if (value == 'delete') {
                      // TODO: delete property logic
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (property.isVerified)
              const Row(
                children: [
                  Icon(Icons.verified, size: 16, color: AppColors.success),
                  SizedBox(width: 4),
                  Text('Verified', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => runVerifyNowFlow(context, property),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Verify Now'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}