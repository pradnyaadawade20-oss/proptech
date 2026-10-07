import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../properties/property_store.dart';
import 'review.dart';
import 'review_service.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _star = Color(0xFFF5A623);

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

class _Stars extends StatelessWidget {
  final int rating;
  final double size;
  const _Stars({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: _star),
      ],
    );
  }
}

/// Reviews block for the property detail page: average rating, the reviews
/// and — only for visitors with a completed visit — a "Write a review" button.
class PropertyReviewsSection extends StatefulWidget {
  final String propertyId;
  const PropertyReviewsSection({super.key, required this.propertyId});

  @override
  State<PropertyReviewsSection> createState() => _PropertyReviewsSectionState();
}

class _PropertyReviewsSectionState extends State<PropertyReviewsSection> {
  static const _previewCount = 3;

  List<Review> _reviews = const [];
  ReviewEligibility? _eligibility;
  bool _loading = true;
  bool _showAll = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ReviewService.instance.getReviews(widget.propertyId),
        ReviewService.instance.getEligibility(widget.propertyId),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0] as List<Review>;
        _eligibility = results[1] as ReviewEligibility?;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _write() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (_) => _WriteReviewSheet(propertyId: widget.propertyId),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
      await _load();
      // Refresh the average rating shown at the top of the page.
      try {
        await PropertyStore.instance.load();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _reviews.length;
    final avg = count == 0 ? 0.0 : _reviews.fold<int>(0, (s, r) => s + r.rating) / count;
    final shown = _showAll ? _reviews : _reviews.take(_previewCount).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Reviews', style: AppTextStyles.h3)),
              if (count > 0) ...[
                const Icon(Icons.star_rounded, size: 18, color: _star),
                const SizedBox(width: 4),
                Text('${avg.toStringAsFixed(1)} ($count)',
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_error != null)
            Row(
              children: [
                Expanded(child: Text(_error!, style: AppTextStyles.bodySmall)),
                TextButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _load();
                  },
                  child: const Text('Retry'),
                ),
              ],
            )
          else ...[
            if (count == 0)
              Text('No reviews yet.', style: AppTextStyles.bodyMedium)
            else
              for (final r in shown) _ReviewTile(review: r),
            if (count > _previewCount)
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? 'Show less' : 'Show all $count reviews'),
              ),
            const SizedBox(height: AppSpacing.xs),
            _footer(),
          ],
        ],
      ),
    );
  }

  Widget _footer() {
    final e = _eligibility;
    if (e == null) return const SizedBox.shrink();
    if (e.canReview) {
      return OutlinedButton.icon(
        onPressed: _write,
        icon: const Icon(Icons.rate_review_outlined, size: 20),
        label: const Text('Write a review'),
      );
    }
    final text = e.reason == 'already_reviewed'
        ? 'You have already reviewed this property.'
        : 'Only visitors with a completed visit can write a review.';
    return Text(text, style: AppTextStyles.bodySmall);
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final name = review.userName.isEmpty ? 'User' : review.userName;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: review.userAvatarUrl.isEmpty ? null : NetworkImage(review.userAvatarUrl),
            child: review.userAvatarUrl.isEmpty
                ? Text(name[0].toUpperCase(),
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600))
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Text(_date(review.createdAt), style: AppTextStyles.caption),
                  ],
                ),
                const SizedBox(height: 2),
                _Stars(rating: review.rating),
                if (review.comment.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(review.comment, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WriteReviewSheet extends StatefulWidget {
  final String propertyId;
  const _WriteReviewSheet({required this.propertyId});

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Please tap a star rating');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ReviewService.instance.create(widget.propertyId, rating: _rating, comment: _comment.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rate this property', style: AppTextStyles.h3),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: _saving ? null : () => setState(() => _rating = i),
                      icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 36, color: _star),
                    ),
                ],
              ),
              TextField(
                controller: _comment,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(hintText: 'Share your experience (optional)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                ),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Review'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}