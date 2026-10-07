import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/price_format.dart';
import '../../core/widgets/safe_network_image.dart';
import '../properties/property.dart';
import '../properties/property_store.dart';
import 'compare_store.dart';

class CompareScreen extends StatelessWidget {
  const CompareScreen({super.key});

  static const double _labelWidth = 86;

  @override
  Widget build(BuildContext context) {
    final store = CompareStore.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Compare Properties', style: AppTextStyles.h3),
        actions: [
          AnimatedBuilder(
            animation: store,
            builder: (_, __) => store.count == 0
                ? const SizedBox.shrink()
                : TextButton(onPressed: store.clear, child: const Text('Clear')),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final props = <Property>[
            for (final id in store.ids)
              if (PropertyStore.instance.byId(id) != null) PropertyStore.instance.byId(id)!,
          ];
          if (props.length < 2) return _empty(context, props.length);
          return _table(context, props);
        },
      ),
    );
  }

  Widget _empty(BuildContext context, int n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.compare_arrows, size: 56, color: AppColors.textHint),
            const SizedBox(height: AppSpacing.md),
            Text(
              n == 0
                  ? 'Add 2 or 3 properties to compare.'
                  : 'Add at least one more property to compare.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Open a listing and tap the compare icon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── table ─────────────────────────

  Widget _table(BuildContext context, List<Property> props) {
    final amenities = <String>{for (final p in props) ...p.amenities}.toList()..sort();
    final sameUnit = props.every((p) => p.priceUnit == props.first.priceUnit);

    // Lowest price and lowest price/sqft are highlighted (only when comparable).
    int? bestIndex(List<double?> v) {
      if (!sameUnit) return null;
      double? best;
      int? idx;
      for (var i = 0; i < v.length; i++) {
        final x = v[i];
        if (x == null || x <= 0) continue;
        if (best == null || x < best) {
          best = x;
          idx = i;
        }
      }
      final distinct = v.where((x) => x != null && x > 0).toSet().length;
      return distinct > 1 ? idx : null;
    }

    final ppsf = props.map<double?>((p) => p.area > 0 ? p.price / p.area : null).toList();
    final bestPrice = bestIndex(props.map<double?>((p) => p.price).toList());
    final bestPpsf = bestIndex(ppsf);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
      child: Column(
        children: [
          _header(context, props),
          const SizedBox(height: AppSpacing.sm),
          _section('Price'),
          _row('Price', [for (final p in props) formatPrice(p.price, p.priceUnit)], best: bestPrice),
          _row('Per sqft', [
            for (final v in ppsf) v == null ? '—' : '${formatPrice(v)}/sqft',
          ], best: bestPpsf),
          _row('Negotiable', [for (final p in props) p.isPriceNegotiable ? 'Yes' : 'No']),
          if (props.any((p) => p.securityDeposit > 0))
            _row('Deposit', [for (final p in props) p.securityDeposit > 0 ? formatPrice(p.securityDeposit) : '—']),
          if (props.any((p) => p.maintenanceCharges > 0))
            _row('Maintenance', [for (final p in props) p.maintenanceCharges > 0 ? '${formatPrice(p.maintenanceCharges)}/mo' : '—']),
          _section('Details'),
          _row('Location', [for (final p in props) _or(p.locality.isNotEmpty ? '${p.locality}, ${p.city}' : p.location)]),
          _row('BHK', [for (final p in props) _or(p.bhk)]),
          _row('Area', [for (final p in props) p.area > 0 ? '${p.area.round()} sqft' : '—']),
          _row('Bathrooms', [for (final p in props) p.bathrooms > 0 ? '${p.bathrooms}' : '—']),
          _row('Balconies', [for (final p in props) p.balconies > 0 ? '${p.balconies}' : '—']),
          _row('Furnishing', [for (final p in props) _or(p.furnishing)]),
          _row('Floor', [
            for (final p in props)
              p.totalFloors > 0 ? '${p.floorNumber} of ${p.totalFloors}' : (p.floorNumber > 0 ? '${p.floorNumber}' : '—'),
          ]),
          _row('Facing', [for (final p in props) _or(p.facing)]),
          _row('Possession', [for (final p in props) _or(p.possessionStatus)]),
          _row('Age', [
            for (final p in props)
              p.ageOfPropertyYears < 0 ? '—' : (p.ageOfPropertyYears == 0 ? 'New' : '${p.ageOfPropertyYears} yrs'),
          ]),
          _section('Trust'),
          _rowW('Verified', [for (final p in props) _tick(p.isVerified)]),
          _row('Posted by', [for (final p in props) p.postedBy == 'broker' ? 'Broker' : 'Owner']),
          _row('Rating', [
            for (final p in props) p.reviewCount > 0 ? '${p.rating.toStringAsFixed(1)} (${p.reviewCount})' : '—',
          ]),
          if (amenities.isNotEmpty) _section('Amenities'),
          for (final a in amenities) _rowW(a, [for (final p in props) _tick(p.amenities.contains(a))]),
        ],
      ),
    );
  }

  String _or(String s) => s.trim().isEmpty ? '—' : s;

  Widget _header(BuildContext context, List<Property> props) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: _labelWidth),
          for (final p in props)
            Expanded(
              child: GestureDetector(
                onTap: () => context.push('/property/${p.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                            child: SafeNetworkImage(p.imageUrl, width: double.infinity, height: 90),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => CompareStore.instance.remove(p.id),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.close, size: 14, color: AppColors.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(6)),
        child: Text(title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
      );

  Widget _row(String label, List<String> values, {int? best}) {
    return _rowW(label, [
      for (var i = 0; i < values.length; i++)
        Text(
          values[i],
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: best == i ? FontWeight.w700 : FontWeight.w500,
            color: best == i ? AppColors.success : AppColors.textPrimary,
          ),
        ),
    ]);
  }

  Widget _rowW(String label, List<Widget> cells) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          for (final c in cells) Expanded(child: Center(child: c)),
        ],
      ),
    );
  }

  Widget _tick(bool yes) => Icon(
        yes ? Icons.check_circle : Icons.remove_circle_outline,
        size: 18,
        color: yes ? AppColors.success : AppColors.textHint,
      );
}