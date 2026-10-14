import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'landlord_service.dart';

/// Owner side: invitations from brokers who want to list your property.
/// Accepting makes YOU the landlord: you sign the agreement. Needs Aadhaar KYC first.
class LandlordInvitesScreen extends StatefulWidget {
  const LandlordInvitesScreen({super.key});

  @override
  State<LandlordInvitesScreen> createState() => _LandlordInvitesScreenState();
}

class _LandlordInvitesScreenState extends State<LandlordInvitesScreen> {
  final _codeController = TextEditingController();

  List<LandlordInvite> _invites = const [];
  LandlordInvite? _byCode; // invite found with a code (not listed in "mine")
  String? _byCodeValue;
  bool _loading = true;
  bool _lookingUp = false;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await LandlordService.instance.myInvites();
      if (!mounted) return;
      setState(() {
        _invites = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _lookUpCode() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      _toast('Enter the invite code the broker shared with you.');
      return;
    }
    setState(() => _lookingUp = true);
    try {
      final inv = await LandlordService.instance.byCode(code);
      if (!mounted) return;
      setState(() {
        _byCode = inv;
        _byCodeValue = code;
        _lookingUp = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _byCode = null;
        _lookingUp = false;
      });
      _toast(e.toString());
    }
  }

  Future<void> _accept(LandlordInvite inv, {String? code, bool retried = false}) async {
    setState(() => _busyId = inv.id);
    try {
      await LandlordService.instance.accept(inviteId: code == null ? inv.id : null, code: code);
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _byCode = null;
        _codeController.clear();
      });
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('You are now the owner'),
          content: Text(
            '"${inv.propertyTitle}" is linked to your account. Tenants can now request an agreement, you sign it, '
            'and rent and deposit are paid online through the app.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } on LandlordApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      if (e.code == 'kyc_required') {
        await _needKyc();
      } else {
        _toast(e.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      _toast(e.toString());
    }
  }

  Future<void> _needKyc() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('KYC required'),
        content: const Text(
          'As the owner you are the landlord on the agreement, so Aadhaar KYC is needed first. '
          'After it is verified, come back here and tap Accept again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verify now')),
        ],
      ),
    );
    if (go == true && mounted) await context.push(RouteNames.kycVerification);
  }

  Future<void> _decline(LandlordInvite inv, {String? code}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline invitation?'),
        content: Text('${inv.brokerName} will be told you declined.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Decline')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = inv.id);
    try {
      await LandlordService.instance.decline(inviteId: code == null ? inv.id : null, code: code);
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _byCode = null;
        _codeController.clear();
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Broker invitations'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'A broker may want to list your property on PropTech. If you accept, you become the landlord: '
                'you sign the agreement and rent and deposit are paid online through the app. '
                'You need Aadhaar KYC.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              _codeBox(),
              if (_byCode != null) _inviteCard(_byCode!, code: _byCodeValue),
              const SizedBox(height: AppSpacing.sm),
              Text('Invitations for you', style: AppTextStyles.h3.copyWith(fontSize: 16)),
              const SizedBox(height: AppSpacing.sm),
              if (_loading)
                const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))
              else if (_invites.isEmpty)
                Text(
                  'No invitations right now. If a broker gave you a code, enter it above.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                )
              else
                for (final inv in _invites) _inviteCard(inv),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeBox() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Have an invite code?', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 -]')),
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(hintText: 'e.g. K7M2Q9XA', isDense: true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(
                onPressed: _lookingUp ? null : _lookUpCode,
                child: _lookingUp
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Find'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inviteCard(LandlordInvite inv, {String? code}) {
    final busy = _busyId == inv.id;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.handshake_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${inv.brokerName.isEmpty ? 'A broker' : inv.brokerName} wants to list your property',
                  style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(inv.propertyTitle, style: AppTextStyles.h3.copyWith(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'If you accept: tenants can request an agreement, you are the landlord and sign it, and rent and deposit '
            'are paid online through the app. Any commission is settled between you and the broker.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decline(inv, code: code),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _accept(inv, code: code),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}