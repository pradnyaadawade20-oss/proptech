import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'visit.dart';
import 'visit_service.dart';

String feedbackLabel(String interest) {
  switch (interest) {
    case 'interested':
      return 'Interested';
    case 'maybe':
      return 'Thinking about it';
    case 'not_interested':
      return 'Not interested';
  }
  return '';
}

Color feedbackColor(String interest) {
  switch (interest) {
    case 'interested':
      return AppColors.success;
    case 'maybe':
      return AppColors.warning;
    case 'not_interested':
      return AppColors.error;
  }
  return AppColors.textSecondary;
}

IconData feedbackIcon(String interest) {
  switch (interest) {
    case 'interested':
      return Icons.thumb_up_alt_outlined;
    case 'maybe':
      return Icons.schedule;
    case 'not_interested':
      return Icons.thumb_down_alt_outlined;
  }
  return Icons.rate_review_outlined;
}

/// Bottom sheet: visitor picks Interested / Thinking / Not interested and
/// optionally leaves a note. Pops `true` once the feedback is saved.
class VisitFeedbackSheet extends StatefulWidget {
  final Visit visit;
  const VisitFeedbackSheet({super.key, required this.visit});

  @override
  State<VisitFeedbackSheet> createState() => _VisitFeedbackSheetState();
}

class _VisitFeedbackSheetState extends State<VisitFeedbackSheet> {
  static const _options = ['interested', 'maybe', 'not_interested'];

  late String _interest = widget.visit.feedbackInterest;
  late final TextEditingController _note = TextEditingController(text: widget.visit.feedbackNote);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_interest.isEmpty) {
      setState(() => _error = 'Please choose one option');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await VisitService.instance.submitFeedback(
        widget.visit.id,
        interest: _interest,
        note: _note.text.trim(),
      );
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
              Text('How was the visit?', style: AppTextStyles.h3),
              const SizedBox(height: 2),
              Text(widget.visit.propertyTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
              const SizedBox(height: AppSpacing.md),
              for (final o in _options) ...[
                _OptionTile(
                  interest: o,
                  selected: _interest == o,
                  onTap: () => setState(() {
                    _interest = o;
                    _error = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(hintText: 'Add a note for the owner (optional)'),
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
                    : const Text('Send Feedback'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String interest;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({required this.interest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = feedbackColor(interest);
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: selected ? color : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(feedbackIcon(interest), color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(feedbackLabel(interest),
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (selected) Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }
}