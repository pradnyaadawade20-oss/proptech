import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../properties/property_store.dart';
import 'landlord_service.dart';

/// Broker side. After posting a listing the broker enters the owner's phone or email and sends
/// them a link (WhatsApp / SMS). The link opens the app; the listing goes live for tenants only
/// after the owner approves it. Until then only the broker can see it.
class PropertyOwnerLinkScreen extends StatefulWidget {
  final String propertyId;
  final String propertyTitle;

  const PropertyOwnerLinkScreen({super.key, required this.propertyId, this.propertyTitle = ''});

  @override
  State<PropertyOwnerLinkScreen> createState() => _PropertyOwnerLinkScreenState();
}

class _PropertyOwnerLinkScreenState extends State<PropertyOwnerLinkScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  LandlordInvite? _invite;
  bool _loading = true;
  bool _busy = false;
  bool _editing = false; // pending invite: re-enter owner details
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final inv = await LandlordService.instance.getPropertyInvite(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _invite = inv;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createLink() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (name.length < 2) {
      _toast("Enter the owner's full name.");
      return;
    }
    if (phone.isEmpty && email.isEmpty) {
      _toast("Enter the owner's phone number or email.");
      return;
    }
    if (phone.isNotEmpty && (digits.length < 10 || digits.length > 15)) {
      _toast("Enter a valid phone number.");
      return;
    }
    if (email.isNotEmpty && (!email.contains('@') || !email.contains('.'))) {
      _toast("Enter a valid email address.");
      return;
    }
    setState(() => _busy = true);
    try {
      final inv = await LandlordService.instance.createInvite(widget.propertyId, name: name, phone: phone, email: email);
      if (!mounted) return;
      setState(() {
        _invite = inv;
        _editing = false;
        _busy = false;
      });
      _toast('Link ready. Send it to the owner.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.toString());
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel the link?'),
        content: const Text('The link will stop working. You can create a new one any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel link')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await LandlordService.instance.cancelInvite(widget.propertyId);
      await _load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
    if (mounted) setState(() => _busy = false);
  }

  // ---- sharing ----

  String _message(LandlordInvite inv) {
    final title = widget.propertyTitle.isNotEmpty ? widget.propertyTitle : inv.propertyTitle;
    return 'Hi ${inv.landlordName}, I would like to list your property "$title" on PropTech to find tenants. '
        'Please open this link, log in or sign up, check the details and approve: ${inv.shareUrl}\n'
        'The listing goes live only after you approve.';
  }

  String _waNumber(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    return d.length == 10 ? '91$d' : d; // bare 10-digit number = India
  }

  Future<void> _open(Uri uri, String fallbackText) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      _toast('Could not open that app. Choose another way to share.');
      await Share.share(fallbackText);
    }
  }

  Future<void> _whatsapp(LandlordInvite inv) {
    final msg = _message(inv);
    return _open(Uri.parse('https://wa.me/${_waNumber(inv.landlordPhone)}?text=${Uri.encodeComponent(msg)}'), msg);
  }

  Future<void> _sms(LandlordInvite inv) {
    final msg = _message(inv);
    return _open(Uri.parse('sms:${inv.landlordPhone}?body=${Uri.encodeComponent(msg)}'), msg);
  }

  Future<void> _shareOther(LandlordInvite inv) => Share.share(_message(inv));

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Send to owner for approval'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      if (widget.propertyTitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Text(widget.propertyTitle, style: AppTextStyles.h3),
                        ),
                      _body(),
                    ],
                  ),
      ),
    );
  }

  Widget _body() {
    final inv = _invite;
    if (inv != null && inv.isAccepted) return _liveCard(inv);
    if (inv != null && inv.isPending && !_editing) return _pendingCard(inv);
    return _form(previous: inv);
  }

  Widget _box({required Widget child, Color? color}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _explain() => _box(
        color: AppColors.primaryLight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Your listing is saved but NOT live. Send the link to the real owner. '
                'It goes live for tenants only after the owner opens it in the app, logs in and approves. '
                'Until then only you can see it.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
      );

  Widget _form({LandlordInvite? previous}) {
    final note = previous == null
        ? null
        : switch (previous.status) {
            'declined' => 'The owner declined the last link. You can send a new one.',
            'cancelled' => 'The last link was cancelled.',
            'expired' => 'The last link expired. Create a new one.',
            _ => null,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _explain(),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(note, style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning)),
          ),
        Text('Owner details', style: AppTextStyles.h3.copyWith(fontSize: 16)),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: "Owner's full name"),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: "Owner's phone number", hintText: '+91 98765 43210'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: "Owner's email", hintText: 'owner@gmail.com'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Enter the phone number or the email (one is enough). The owner must log in or sign up to approve.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(label: 'Create link', loading: _busy, onPressed: _busy ? null : _createLink),
        if (_editing)
          TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Back')),
      ],
    );
  }

  Widget _pendingCard(LandlordInvite inv) {
    final until = inv.expiresAt;
    final hasPhone = inv.landlordPhone.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _explain(),
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hourglass_top, size: 18, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Waiting for ${inv.landlordName} to approve',
                        style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [if (hasPhone) inv.landlordPhone, if (inv.landlordEmail.isNotEmpty) inv.landlordEmail].join('  |  '),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Link', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inv.shareUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy link',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inv.shareUrl));
                      _toast('Link copied');
                    },
                  ),
                ],
              ),
              if (until != null)
                Text(
                  'Valid until ${until.day.toString().padLeft(2, '0')}/${until.month.toString().padLeft(2, '0')}/${until.year}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
        AppButton(label: 'Share on WhatsApp', onPressed: () => _whatsapp(inv)),
        if (hasPhone) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'Send by SMS', outlined: true, onPressed: () => _sms(inv)),
        ],
        const SizedBox(height: AppSpacing.sm),
        AppButton(label: 'Share another way', outlined: true, onPressed: () => _shareOther(inv)),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _editing = true;
                          _name.text = inv.landlordName;
                          _phone.text = inv.landlordPhone;
                          _email.text = inv.landlordEmail;
                        }),
                child: const Text('Change details'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _cancel,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Cancel link'),
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: () async {
            await PropertyStore.instance.load();
            await _load();
          },
          child: const Text('Check if the owner approved'),
        ),
      ],
    );
  }

  Widget _liveCard(LandlordInvite inv) {
    final name = inv.landlordUserName.isNotEmpty ? inv.landlordUserName : inv.landlordName;
    return _box(
      color: AppColors.success.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Approved by $name. Your listing is live.',
                    style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tenants can now see it and request an online agreement. The owner signs it, and rent and deposit '
            'are paid online through the app. You appear on the agreement as the agent.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}