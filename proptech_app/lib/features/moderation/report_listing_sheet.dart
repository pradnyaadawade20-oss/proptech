import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'moderation_service.dart';

/// Bottom sheet to report a listing:
///   ReportListingSheet.show(context, property.id);
class ReportListingSheet extends StatefulWidget {
  final String propertyId;
  const ReportListingSheet({super.key, required this.propertyId});

  static Future<void> show(BuildContext context, String propertyId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReportListingSheet(propertyId: propertyId),
    );
  }

  @override
  State<ReportListingSheet> createState() => _ReportListingSheetState();
}

class _ReportListingSheetState extends State<ReportListingSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    try {
      await ModerationService.instance.report(
        propertyId: widget.propertyId,
        reason: reason,
        details: _details.text,
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Thanks, we will review this listing.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Report this listing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Why are you reporting it?', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            for (final r in reportReasons)
              RadioListTile<String>(
                value: r.$1,
                groupValue: _reason,
                title: Text(r.$2),
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: _sending ? null : (v) => setState(() => _reason = v),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _details,
              maxLines: 3,
              maxLength: 500,
              enabled: !_sending,
              decoration: const InputDecoration(
                hintText: 'Add details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_reason == null || _sending) ? null : _submit,
                child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}