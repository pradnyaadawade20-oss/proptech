import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import 'landlord_service.dart';

/// Broker side: link a broker-posted listing to its REAL owner.
/// The broker enters the owner's details and shares an invite code. The owner accepts from
/// their own account (after Aadhaar KYC), and the agreement names them as the landlord.
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

  Future<void> _sendInvite() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    if (name.length < 2) {
      _toast("Enter the owner's full name.");
      return;
    }
    if (phone.isEmpty && email.isEmpty) {
      _toast("Enter the owner's phone number or email.");
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
      _toast('Invitation created. Share the code with the owner.');
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
        title: const Text('Cancel invitation?'),
        content: const Text('The code will stop working. You can invite the owner again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel invite')),
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

  void _share(LandlordInvite inv) {
    final title = widget.propertyTitle.isNotEmpty ? widget.propertyTitle : inv.propertyTitle;
    Share.share(
      'Hi ${inv.landlordName}, I would like to list your property "$title" on PropTech to find tenants. '
      'Please install the PropTech app, sign up, and open Profile > Broker invitations. '
      'Invite code: ${inv.code} (valid for 14 days). '
      'Rent and deposit will be paid directly to you.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Owner & agreement'),
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
    if (inv != null && inv.isAccepted) return _acceptedCard(inv);
    if (inv != null && inv.isPending && !_editing) return _pendingCard(inv);
    return _form(previous: inv);
  }

  // ---- states ----

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
                'Tenants can request an online agreement only after the real owner joins. '
                'The owner signs the agreement, and rent and deposit are paid online through the app. '
                'You stay on the agreement as the agent.',
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
            'declined' => 'The owner declined the last invitation. You can invite again.',
            'cancelled' => 'The last invitation was cancelled.',
            'expired' => 'The last invitation expired. Create a new one.',
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
          decoration: const InputDecoration(labelText: "Owner's email (optional)"),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'If the owner already has a PropTech account with this phone or email, they get a notification. '
          'Otherwise share the invite code with them.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(label: 'Create invitation', loading: _busy, onPressed: _busy ? null : _sendInvite),
        if (_editing)
          TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Back')),
      ],
    );
  }

  Widget _pendingCard(LandlordInvite inv) {
    final until = inv.expiresAt;
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
                  Text('Waiting for ${inv.landlordName}', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [if (inv.landlordPhone.isNotEmpty) inv.landlordPhone, if (inv.landlordEmail.isNotEmpty) inv.landlordEmail].join('  |  '),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Invite code', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inv.code,
                      style: AppTextStyles.h2.copyWith(letterSpacing: 4, color: AppColors.primary),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy code',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inv.code));
                      _toast('Code copied');
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
        AppButton(label: 'Share invite (WhatsApp, SMS...)', onPressed: () => _share(inv)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => setState(() {
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
                child: const Text('Cancel invite'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _acceptedCard(LandlordInvite inv) {
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
                child: Text('Owner linked: $name', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tenants can now request an online agreement for this listing. The owner signs it, and rent and deposit '
            "are paid online through the app. You appear on the agreement as the agent.",
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}