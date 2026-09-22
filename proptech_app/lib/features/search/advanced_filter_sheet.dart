import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'property_filters.dart';

/// Opens the advanced-filter bottom sheet. Returns the updated
/// [PropertyFilters] if the user taps Apply, or null if dismissed/cleared
/// without changes propagating (caller decides what to do with null).
Future<PropertyFilters?> showAdvancedFilterSheet(
  BuildContext context,
  PropertyFilters current,
) {
  return showModalBottomSheet<PropertyFilters>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
    ),
    builder: (_) => _AdvancedFilterSheet(initial: current),
  );
}

class _AdvancedFilterSheet extends StatefulWidget {
  final PropertyFilters initial;
  const _AdvancedFilterSheet({required this.initial});

  @override
  State<_AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<_AdvancedFilterSheet> {
  late PropertyFilters _filters;

  static const _possessionOptions = ['Ready to Move', 'Under Construction'];
  static const _ageOptions = [1, 5, 10, 20];
  static const _facingOptions = [
    'North', 'South', 'East', 'West', 'North-East', 'North-West', 'South-East', 'South-West',
  ];

  @override
  void initState() {
    super.initState();
    _filters = widget.initial.copy();
  }

  String _formatPrice(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Advanced Filters', style: AppTextStyles.h3),
                    TextButton(
                      onPressed: () => setState(() => _filters.reset()),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      _sectionTitle(
                        'Price Range',
                        '${_formatPrice(_filters.priceRange.start)} - ${_formatPrice(_filters.priceRange.end)}',
                      ),
                      RangeSlider(
                        values: _filters.priceRange,
                        min: 0,
                        max: 50000000,
                        divisions: 50,
                        activeColor: AppColors.primary,
                        labels: RangeLabels(
                          _formatPrice(_filters.priceRange.start),
                          _formatPrice(_filters.priceRange.end),
                        ),
                        onChanged: (v) => setState(() => _filters.priceRange = v),
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      _sectionTitle(
                        'Area (sqft)',
                        '${_filters.areaRange.start.toStringAsFixed(0)} - ${_filters.areaRange.end.toStringAsFixed(0)} sqft',
                      ),
                      RangeSlider(
                        values: _filters.areaRange,
                        min: 0,
                        max: 5000,
                        divisions: 50,
                        activeColor: AppColors.primary,
                        labels: RangeLabels(
                          _filters.areaRange.start.toStringAsFixed(0),
                          _filters.areaRange.end.toStringAsFixed(0),
                        ),
                        onChanged: (v) => setState(() => _filters.areaRange = v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      _sectionTitle('Possession Status', null),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: _possessionOptions.map((option) {
                          final selected = _filters.possessionStatus == option;
                          return ChoiceChip(
                            label: Text(option),
                            selected: selected,
                            selectedColor: AppColors.primaryLight,
                            onSelected: (_) => setState(() {
                              _filters.possessionStatus = selected ? null : option;
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      _sectionTitle('Age of Property', null),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: _ageOptions.map((years) {
                          final selected = _filters.maxAgeYears == years;
                          return ChoiceChip(
                            label: Text('Under $years yrs'),
                            selected: selected,
                            selectedColor: AppColors.primaryLight,
                            onSelected: (_) => setState(() {
                              _filters.maxAgeYears = selected ? null : years;
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      _sectionTitle(
                        'Floor Number',
                        '${_filters.floorRange.start.toStringAsFixed(0)} - ${_filters.floorRange.end.toStringAsFixed(0)}',
                      ),
                      RangeSlider(
                        values: _filters.floorRange,
                        min: 0,
                        max: 50,
                        divisions: 50,
                        activeColor: AppColors.primary,
                        labels: RangeLabels(
                          _filters.floorRange.start.toStringAsFixed(0),
                          _filters.floorRange.end.toStringAsFixed(0),
                        ),
                        onChanged: (v) => setState(() => _filters.floorRange = v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      _sectionTitle('Facing Direction', null),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: _facingOptions.map((option) {
                          final selected = _filters.facing == option;
                          return ChoiceChip(
                            label: Text(option),
                            selected: selected,
                            selectedColor: AppColors.primaryLight,
                            onSelected: (_) => setState(() {
                              _filters.facing = selected ? null : option;
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _filters),
                    child: Text(
                      _filters.isActive
                          ? 'Apply Filters (${_filters.activeCount})'
                          : 'Apply Filters',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title, String? valueLabel) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
          if (valueLabel != null)
            Text(valueLabel, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
        ],
      ),
    );
  }
}