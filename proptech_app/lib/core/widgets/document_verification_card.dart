
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../features/properties/property.dart';

/// Shows which ownership/legal documents have been verified for this
/// listing (RERA, Sale Deed / Title Deed, etc). Real verification data
/// isn't wired up yet, so this derives a plausible checklist from
/// [property.isVerified] and [property.category] — swap for real backend
/// verification records once that exists.
class DocumentVerificationCard extends StatelessWidget {
  final Property property;
  const DocumentVerificationCard({super.key, required this.property});

  List<_DocItem> get _docs {
    final isPlot = property.category.toLowerCase().contains('plot');
    return [
      _DocItem('RERA Registration', property.isVerified),
      _DocItem(isPlot ? 'Title Deed' : 'Sale Deed', property.isVerified),
      _DocItem('Encumbrance Certificate', property.isVerified),
      const _DocItem('Property Tax Receipt', false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            children: [
              Icon(
                property.isVerified ? Icons.verified : Icons.pending_outlined,
                color: property.isVerified ? AppColors.verifiedBadge : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                property.isVerified ? 'Documents Verified' : 'Verification Pending',
                style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._docs.map(
            (doc) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    doc.verified ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: doc.verified ? AppColors.verifiedBadge : AppColors.textHint,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(doc.label, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocItem {
  final String label;
  final bool verified;
  const _DocItem(this.label, this.verified);
}