import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import 'moderation_service.dart';

/// Shows the duplicate-check result. Returns true only when the user chose
/// to "List anyway" (possible duplicate of someone else's listing). If the
/// user already listed this property, it just informs them and returns false.
Future<bool> showDuplicateListingDialog(BuildContext context, DuplicateCheck check) async {
  final list = check.duplicates
      .map((d) => '• ${d.title}${d.location.isEmpty ? '' : ' (${d.location})'}')
      .join('\n');

  if (check.blocked) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already listed'),
        content: Text('You have already listed this property:\n\n$list\n\nEdit the existing listing instead of adding it again.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return false;
  }

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Similar listing found'),
      content: Text(
        'A listing that looks like this one already exists:\n\n$list\n\n'
        'If this is a different property, you can still list it. Our team will review it.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('List anyway', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    ),
  );
  return proceed == true;
}