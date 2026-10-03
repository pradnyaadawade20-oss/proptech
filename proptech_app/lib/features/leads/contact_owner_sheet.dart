import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../profile/profile_service.dart';
import '../properties/property.dart';
import 'lead.dart';
import 'lead_service.dart';

/// "Contact Owner" bottom sheet: collects name / phone / message, saves the
/// enquiry as a lead, then shows Call + Chat buttons for the owner.
Future<void> showContactOwnerSheet(BuildContext context, Property property) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _ContactOwnerSheet(property: property),
  );
}

class _ContactOwnerSheet extends StatefulWidget {
  final Property property;
  const _ContactOwnerSheet({required this.property});

  @override
  State<_ContactOwnerSheet> createState() => _ContactOwnerSheetState();
}

class _ContactOwnerSheetState extends State<_ContactOwnerSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  late final TextEditingController _message;

  bool _sending = false;
  String? _error;
  LeadResult? _result;

  @override
  void initState() {
    super.initState();
    _message = TextEditingController(text: "Hi, I'm interested in \"${widget.property.title}\". Is it still available?");
    _prefill();
  }

  /// Pre-fill name/phone from the logged-in user's profile.
  Future<void> _prefill() async {
    try {
      final me = await ProfileService.instance.getMyProfile();
      if (!mounted) return;
      if (_name.text.isEmpty) _name.text = me.name;
      if (_phone.text.isEmpty) _phone.text = me.phone;
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = _phone.text.trim();
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    if (phone.length < 10) {
      setState(() => _error = 'Please enter a valid 10-digit phone number');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await LeadService.instance.create(
        propertyId: widget.property.id,
        name: _name.text.trim(),
        phone: phone,
        message: _message.text.trim(),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open dialer for $phone')));
    }
  }

  void _chat() {
    final p = widget.property;
    final router = GoRouter.of(context); // grab before the sheet closes
    Navigator.of(context).pop();
    router.push('/chats/${p.ownerId}?propertyId=${p.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _result == null ? _form() : _success(_result!),
      ),
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contact Owner', style: AppTextStyles.h3),
        const SizedBox(height: 4),
        Text(widget.property.title, style: AppTextStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(15)],
          decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _message,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
        ],
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send Enquiry'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Your name and number will be shared with the owner.', style: AppTextStyles.caption),
      ],
    );
  }

  Widget _success(LeadResult r) {
    final hasPhone = r.ownerPhone.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 48),
        const SizedBox(height: AppSpacing.sm),
        Text('Enquiry sent!', style: AppTextStyles.h3),
        const SizedBox(height: 4),
        Text(
          '${r.ownerName.isNotEmpty ? r.ownerName : 'The owner'} will get back to you soon.',
          style: AppTextStyles.bodyMedium,
          textAlign: TextAlign.center,
        ),
        if (hasPhone) ...[
          const SizedBox(height: AppSpacing.md),
          Text(r.ownerPhone, style: AppTextStyles.h3),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasPhone ? () => _call(r.ownerPhone) : null,
                icon: const Icon(Icons.call_outlined, size: 20),
                label: const Text('Call'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _chat,
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                label: const Text('Chat'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}