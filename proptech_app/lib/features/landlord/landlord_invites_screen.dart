import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'landlord_service.dart';

/// Owner side: invitations from brokers who want to list your property.
/// (Owners who open the broker's share link go to OwnerApproveScreen; this list is for invitations
/// that match your account's email / phone.) Approving needs Aadhaar KYC first.
class LandlordInvitesScreen extends StatefulWidget {
  const LandlordInvitesScreen({super.key});

  @override
  State<LandlordInvitesScreen> createState() => _LandlordInvitesScreenState();
}

class _LandlordInvitesScreenState extends State<LandlordInvitesScreen> {
  List<LandlordInvite> _invites = const [];
  bool _loading = true;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _accept(LandlordInvite inv) async {
    setState(() => _busyId = inv.id);
    try {
      await LandlordService.instance.accept(inviteId: inv.id);
      if (!mounted) return;
      setState(() => _busyId = null);
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Approved'),
          content: Text(
            '"${inv.propertyTitle}" is now live and linked to your account. Tenants can request an agreement, '
            'you sign it, and rent and deposit are paid online through the app.',
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
          'After it is verified, come back here and tap Approve again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verify now')),
        ],
      ),
    );
    if (go == true && mounted) await context.push(RouteNames.kycVerification);
  }

  Future<void> _decline(LandlordInvite inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline invitation?'),
        content: Text('${inv.brokerName.isEmpty ? 'The broker' : inv.brokerName} will be told you declined.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Decline')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = inv.id);
    try {
      await LandlordService.instance.decline(inviteId: inv.id);
      if (!mounted) return;
      setState(() => _busyId = null);
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
                'A broker may want to list your property on PropTech. The listing goes live for tenants only '
                'after you approve it. If you approve, you become the landlord: you sign the agreement, and rent and '
                'deposit are paid online through the app. You need Aadhaar KYC.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))
              else if (_invites.isEmpty)
                Text(
                  'No invitations right now. If a broker sent you a link, just open it and this app will show the property.',
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

  Widget _inviteCard(LandlordInvite inv) {
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
            'If you approve: the listing goes live, tenants can request an agreement, you are the landlord and sign it, '
            'and rent and deposit are paid online through the app. Any commission is settled between you and the broker.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          if (inv.propertyId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => context.push('/property/${inv.propertyId}'),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View property details'),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decline(inv),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _accept(inv),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}