import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../properties/property.dart';
import 'property_filters.dart';
import 'advanced_filter_sheet.dart';
import 'map_search_screen.dart';

class CategoryScreen extends StatefulWidget {
  final String title;
  final String filterType; // 'buy', 'rent', 'commercial', 'plot', 'pg'

  const CategoryScreen({super.key, required this.title, required this.filterType});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  String _sortOption = 'default'; // default, price_low, price_high, rating
  bool _verifiedOnly = false;
  PropertyFilters _advancedFilters = PropertyFilters();

  List<Property> get _filtered {
    List<Property> results;
    switch (widget.filterType) {
      case 'rent':
        results = dummyProperties
            .where((p) => p.category == 'Residential' && p.priceUnit == '/month' && p.bhk != 'PG')
            .toList();
        break;
      case 'buy':
        results = dummyProperties
            .where((p) => p.category == 'Residential' && p.priceUnit != '/month')
            .toList();
        break;
      case 'pg':
        results = dummyProperties.where((p) => p.bhk == 'PG').toList();
        break;
      case 'commercial':
        results = dummyProperties.where((p) => p.category == 'Commercial').toList();
        break;
      case 'plot':
        results = dummyProperties.where((p) => p.category == 'Plot/Land').toList();
        break;
      case '1bhk':
        results = dummyProperties.where((p) => p.bhk == '1 BHK').toList();
        break;
      case '2bhk':
        results = dummyProperties.where((p) => p.bhk == '2 BHK').toList();
        break;
      case 'rooms':
        results = dummyProperties.where((p) => p.bhk == 'PG' || p.bhk == '1 BHK').toList();
        break;
      case 'villa':
        results = dummyProperties.where((p) => p.bhk == '4 BHK' || p.title.toLowerCase().contains('bungalow') || p.title.toLowerCase().contains('villa')).toList();
        break;
      case 'owner':
        // Heuristic: individually rented-out residential homes are typically owner-posted
        results = dummyProperties.where((p) => p.category == 'Residential' && p.priceUnit == '/month').toList();
        break;
      case 'dealer':
        // Everything else (buy, commercial, plot) is typically posted by dealers/builders
        results = dummyProperties.where((p) => !(p.category == 'Residential' && p.priceUnit == '/month')).toList();
        break;
      case 'furnished':
        results = dummyProperties
            .where((p) => p.furnishing == 'Furnished' || p.furnishing == 'Fully Furnished')
            .toList();
        break;
      case 'semifurnished':
        results = dummyProperties.where((p) => p.furnishing == 'Semi Furnished').toList();
        break;
      case 'unfurnished':
        results = dummyProperties.where((p) => p.furnishing == 'Unfurnished').toList();
        break;
      case 'family':
        results = dummyProperties
            .where((p) => p.category == 'Residential' && (p.bhk == '2 BHK' || p.bhk == '3 BHK' || p.bhk == '4 BHK'))
            .toList();
        break;
      case 'singles':
        results = dummyProperties
            .where((p) => p.category == 'Residential' && (p.bhk == '1 BHK' || p.bhk == '1 RK' || p.bhk == 'PG'))
            .toList();
        break;
      case 'petfriendly':
        results = dummyProperties.where((p) => p.category == 'Residential').toList();
        break;
      default:
        results = List.of(dummyProperties);
    }

    if (_verifiedOnly) {
      results = results.where((p) => p.isVerified).toList();
    }

    results = _advancedFilters.apply(results);

    return sortProperties(results, _sortOption);
  }

  void _openSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (sheetContext) {
        Widget option(String label, String value) {
          return RadioListTile<String>(
            title: Text(label),
            value: value,
            groupValue: _sortOption,
            activeColor: AppColors.primary,
            onChanged: (selected) {
              setState(() => _sortOption = selected!);
              Navigator.pop(sheetContext);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('Sort by', style: AppTextStyles.h3),
              ),
              option('Recommended', 'default'),
              option('Newest First', 'newest'),
              option('Price: Low to High', 'price_low'),
              option('Price: High to Low', 'price_high'),
              option('Rating: High to Low', 'rating'),
              option('Area: Largest First', 'area_large'),
            ],
          ),
        );
      },
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filter', style: AppTextStyles.h3),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Verified only'),
                      value: _verifiedOnly,
                      activeThumbColor: AppColors.primary,
                      onChanged: (value) {
                        setSheetState(() => _verifiedOnly = value);
                        setState(() {});
                      },
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tune, color: AppColors.primary),
                      title: const Text('Advanced Filters'),
                      subtitle: _advancedFilters.isActive
                          ? Text('${_advancedFilters.activeCount} filter(s) applied')
                          : const Text('Price, area, possession, floor & more'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final result = await showAdvancedFilterSheet(context, _advancedFilters);
                        if (result != null) {
                          setState(() => _advancedFilters = result);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sharePropertyList() async {
    final shareText =
        'Check out ${widget.title} on PropTech: https://proptech.app/category/${widget.filterType}';
    final whatsappUri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(shareText)}');
    final launched = await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp is not installed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Map View',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MapSearchScreen(properties: _filtered),
              ));
            },
          ),
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: _sharePropertyList),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${results.length} Properties', style: AppTextStyles.h3.copyWith(fontSize: 15)),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _openSortSheet,
                      icon: const Icon(Icons.swap_vert, size: 16),
                      label: const Text('Sort'),
                    ),
                    TextButton.icon(
                      onPressed: _openFilterSheet,
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('Filter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: results.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => _buildCard(context, results[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 48, color: AppColors.textHint),
          const SizedBox(height: AppSpacing.sm),
          Text('No ${widget.title} yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, Property property) {
    switch (widget.filterType) {
      case 'pg':
        return _PGCard(property: property);
      case 'commercial':
        return _CommercialCard(property: property);
      case 'plot':
        return _PlotCard(property: property);
      case 'rent':
        return _RentCard(property: property);
      case 'buy':
      default:
        return _BuyCard(property: property);
    }
  }
}

// ── Buy card: big box style, interior photo, price, beds/baths ─────────────
class _BuyCard extends StatelessWidget {
  final Property property;
  const _BuyCard({required this.property});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/property/${property.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(property.imageUrl, width: double.infinity, height: 150, fit: BoxFit.cover),
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white,
                    child: Icon(
                      property.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: property.isFavorite ? Colors.red : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Text('Verified', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${property.price.toStringAsFixed(0)}',
                    style: AppTextStyles.price,
                  ),
                  const SizedBox(height: 2),
                  Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  Text(property.location, style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Text('${property.bhk} • ${property.furnishing}', style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rent card: similar to buy but shows /month and Verified badge ─────────
class _RentCard extends StatelessWidget {
  final Property property;
  const _RentCard({required this.property});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/property/${property.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(property.imageUrl, width: double.infinity, height: 150, fit: BoxFit.cover),
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white,
                    child: Icon(
                      property.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: property.isFavorite ? Colors.red : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Text('Verified', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('₹${property.price.toStringAsFixed(0)}/mo', style: AppTextStyles.price),
                  const SizedBox(height: 2),
                  Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  Text(property.location, style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Text('${property.bhk} • ${property.furnishing}', style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PG card: big box style, name, tags, price ───────────────────────────────
class _PGCard extends StatelessWidget {
  final Property property;
  const _PGCard({required this.property});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/property/${property.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(property.imageUrl, width: double.infinity, height: 150, fit: BoxFit.cover),
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white,
                    child: Icon(
                      property.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: property.isFavorite ? Colors.red : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Text('Verified', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${property.price.toStringAsFixed(0)}/mo',
                    style: AppTextStyles.price,
                  ),
                  const SizedBox(height: 2),
                  Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  Text(property.location, style: AppTextStyles.caption),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _tag(property.furnishing.contains('Fully') ? 'Twin Sharing' : 'Single'),
                      _tag('AC'),
                      _tag('Wi-Fi'),
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

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.primaryDark)),
    );
  }
}

// ── Commercial card: big box style, sqft prominent, office/shop ────────────
class _CommercialCard extends StatelessWidget {
  final Property property;
  const _CommercialCard({required this.property});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/property/${property.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(property.imageUrl, width: double.infinity, height: 150, fit: BoxFit.cover),
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white,
                    child: Icon(
                      property.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: property.isFavorite ? Colors.red : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Text('Verified', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${property.price.toStringAsFixed(0)}${property.priceUnit}',
                    style: AppTextStyles.price,
                  ),
                  const SizedBox(height: 2),
                  Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  Text(property.location, style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.square_foot, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text('${property.bhk} sq.ft', style: AppTextStyles.caption),
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

// ── Plot card: big box style, area only, no bhk/furnishing ─────────────────
class _PlotCard extends StatelessWidget {
  final Property property;
  const _PlotCard({required this.property});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/property/${property.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(property.imageUrl, width: double.infinity, height: 150, fit: BoxFit.cover),
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white,
                    child: Icon(
                      property.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: property.isFavorite ? Colors.red : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Text('Verified', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${property.price.toStringAsFixed(0)}',
                    style: AppTextStyles.price,
                  ),
                  const SizedBox(height: 2),
                  Text(property.title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  Text(property.location, style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Text('${property.bhk} sq.ft • Plot', style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}