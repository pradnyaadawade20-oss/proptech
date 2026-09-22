import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/property_card.dart';
import '../properties/property.dart';

class AllCategoriesScreen extends StatefulWidget {
  const AllCategoriesScreen({super.key});

  @override
  State<AllCategoriesScreen> createState() => _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends State<AllCategoriesScreen> {
  int _selectedIndex = 0;

  final List<Map<String, dynamic>> _sidebarItems = const [
    {'label': 'For you', 'icon': Icons.explore_outlined},
    {'label': 'Sell/Rent', 'icon': Icons.sell_outlined},
    {'label': 'Buy Residential', 'icon': Icons.home_outlined},
    {'label': 'Rent / PG', 'icon': Icons.vpn_key_outlined},
    {'label': 'Buy Commercial', 'icon': Icons.storefront_outlined},
    {'label': 'Lease Commercial', 'icon': Icons.business_center_outlined},
    {'label': 'Price & Insights', 'icon': Icons.currency_rupee},
    {'label': 'Activity & Support', 'icon': Icons.support_agent_outlined},
  ];

  void _onSidebarTap(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('All Categories')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left sidebar
          SizedBox(
            width: 110,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              itemCount: _sidebarItems.length,
              itemBuilder: (context, index) {
                final item = _sidebarItems[index];
                final isSelected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () => _onSidebarTap(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.background : AppColors.surfaceSoft,
                      border: Border(
                        left: BorderSide(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 3,
                        ),
                        bottom: const BorderSide(color: AppColors.divider, width: 1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          item['icon'] as IconData,
                          size: 24,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['label'] as String,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption.copyWith(
                            color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Right content panel — switches with the selected sidebar item
          Expanded(
            child: _buildRightPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(BuildContext context) {
    switch (_selectedIndex) {
      case 1: // Sell/Rent
        return _buildActionPanel(
          context,
          title: 'Sell or Rent your property',
          subtitle: 'List your property in a few quick steps and reach genuine buyers/tenants.',
          actions: [
            _CategoryTile(
              icon: Icons.sell_outlined,
              label: 'Sell my Property',
              onTap: () => context.push(RouteNames.addProperty),
              fullWidth: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _CategoryTile(
              icon: Icons.vpn_key_outlined,
              label: 'Rent out my Property',
              onTap: () => context.push(RouteNames.addProperty),
              fullWidth: true,
            ),
          ],
        );
      case 2: // Buy Residential
        return _buildListingPanel(
          context,
          title: 'Buy Residential',
          properties: dummyProperties
              .where((p) => p.category == 'Residential' && p.priceUnit != '/month')
              .toList(),
        );
      case 3: // Rent / PG
        return _buildListingPanel(
          context,
          title: 'Rent / PG',
          properties: dummyProperties
              .where((p) => p.category == 'Residential' && p.priceUnit == '/month')
              .toList(),
        );
      case 4: // Buy Commercial
        return _buildListingPanel(
          context,
          title: 'Buy Commercial',
          properties: dummyProperties
              .where((p) => p.category == 'Commercial' && p.priceUnit != '/month')
              .toList(),
        );
      case 5: // Lease Commercial
        return _buildListingPanel(
          context,
          title: 'Lease Commercial',
          properties: dummyProperties
              .where((p) => p.category == 'Commercial' && p.priceUnit == '/month')
              .toList(),
        );
      case 6: // Price & Insights
        return _buildActionPanel(
          context,
          title: 'Price & Insights',
          subtitle: 'Market trends, price heatmaps, and locality insights will appear here once available.',
          actions: const [],
        );
      case 7: // Activity & Support
        return _buildActionPanel(
          context,
          title: 'Activity & Support',
          subtitle: 'Track your visits, chats, and get help — all in one place.',
          actions: [
            _CategoryTile(
              icon: Icons.event_available_outlined,
              label: 'My Visits',
              onTap: () => context.push(RouteNames.myVisits),
              fullWidth: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _CategoryTile(
              icon: Icons.chat_bubble_outline,
              label: 'My Chats',
              onTap: () => context.go(RouteNames.chatList),
              fullWidth: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _CategoryTile(
              icon: Icons.support_agent_outlined,
              label: 'Help & Support',
              onTap: () => _showComingSoon(context, 'Help & Support'),
              fullWidth: true,
            ),
          ],
        );
      case 0:
      default:
        return _buildForYouPanel(context);
    }
  }

  Widget _buildForYouPanel(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Manage your property', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _CategoryTile(
                icon: Icons.people_outline,
                label: 'View Responses',
                onTap: () => _showComingSoon(context, 'View Responses'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _CategoryTile(
                icon: Icons.edit_note_outlined,
                label: 'Manage / Edit Listings',
                onTap: () => context.push(RouteNames.myProperties),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _CategoryTile(
          icon: Icons.verified_outlined,
          label: 'Self Verify Property',
          onTap: () => _showComingSoon(context, 'Self Verify Property'),
          fullWidth: true,
        ),
        const SizedBox(height: AppSpacing.lg),

        Text('Plans & Services', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        _CategoryTile(
          icon: Icons.workspace_premium_outlined,
          label: 'Owner Plans',
          onTap: () => _showComingSoon(context, 'Owner Plans'),
          fullWidth: true,
        ),
        const SizedBox(height: AppSpacing.lg),

        Text('Subscription & Payments', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        _CategoryTile(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Manage Payments',
          onTap: () => _showComingSoon(context, 'Manage Payments'),
          fullWidth: true,
        ),
        const SizedBox(height: AppSpacing.lg),

        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            const Icon(Icons.call_outlined, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text('Call ', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            Text(
              '1800-41-99099',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
            Text(' for support', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _buildActionPanel(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> actions,
  }) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(title, style: AppTextStyles.h3),
        const SizedBox(height: 4),
        Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.lg),
        ...actions,
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _buildListingPanel(
    BuildContext context, {
    required String title,
    required List<Property> properties,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Text('$title • ${properties.length} Properties', style: AppTextStyles.h3.copyWith(fontSize: 15)),
        ),
        Expanded(
          child: properties.isEmpty
              ? Center(
                  child: Text('No properties yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
                  itemCount: properties.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisExtent: 352,
                  ),
                  itemBuilder: (context, index) {
                    final property = properties[index];
                    return PropertyCard(
                      property: property,
                      onTap: () => context.push('/property/${property.id}'),
                      onFavoriteTap: () {
                        final i = dummyProperties.indexWhere((p) => p.id == property.id);
                        if (i != -1) {
                          dummyProperties[i] = property.copyWith(isFavorite: !property.isFavorite);
                          notifyPropertiesChanged();
                          setState(() {});
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool fullWidth;

  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

void _showComingSoon(BuildContext context, String feature) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(feature),
      content: const Text('This feature will be available once the owner backend is connected.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    ),
  );
}