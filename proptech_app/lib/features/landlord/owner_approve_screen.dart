import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/api/token_store.dart';
import '../../core/session/user_session.dart';
import '../../core/utils/price_format.dart';
import '../../core/widgets/safe_network_image.dart';
import '../properties/property.dart';
import '../properties/property_store.dart';
import 'landlord_service.dart';
import 'pending_invite_store.dart';

enum _Stage { loading, needLogin, review, error }

/// Opened by the share link a broker sent (https://.../o/<token>).
/// The owner logs in / signs up, sees the full listing and approves it.
/// The listing becomes visible to tenants ONLY after the owner taps Approve.
class OwnerApproveScreen extends StatefulWidget {
  final String token;
  const OwnerApproveScreen({super.key, required this.token});

  @override
  State<OwnerApproveScreen> createState() => _OwnerApproveScreenState();
}

class _OwnerApproveScreenState extends State<OwnerApproveScreen> {
  _Stage _stage = _Stage.loading;
  InviteView? _view;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Remember the link first: login / sign-up / OTP happen in between and must come back here.
    await PendingInviteStore.save(widget.token);
    final loggedIn = await TokenStore.instance.isLoggedIn();
    if (!mounted) return;
    if (!loggedIn) {
      setState(() => _stage = _Stage.needLogin);
      return;
    }
    try {
      // Opened straight from the link (app was closed): the splash screen did not run.
      await UserSession.instance.restore();
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    try {
      final v = await LandlordService.instance.byToken(widget.token);
      if (!mounted) return;
      if (v.invite.status != 'pending') await PendingInviteStore.clear();
      setState(() {
        _view = v;
        _stage = _Stage.review;
      });
    } on LandlordApiException catch (e) {
      if (!mounted) return;
      await PendingInviteStore.clear();
      setState(() {
        _error = e.message;
        _stage = _Stage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _stage = _Stage.error;
      });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goHome() => context.go(RouteNames.home);

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await LandlordService.instance.accept(token: widget.token);
      await PendingInviteStore.clear();
      PropertyStore.instance.load();
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Property approved'),
          content: Text(
            '"${_view?.property.title ?? 'Your property'}" is now live. Tenants can see it and request an agreement. '
            'You sign the agreement, and rent and deposit are paid online through the app.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted) _goHome();
    } on LandlordApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'kyc_required') {
        await _needKyc();
      } else {
        _toast(e.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
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

  Future<void> _decline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline this listing?'),
        content: const Text('It will not go live, and the broker will be told you declined.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Decline')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await LandlordService.instance.decline(token: widget.token);
      await PendingInviteStore.clear();
      if (!mounted) return;
      _toast('Declined.');
      _goHome();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Approve your listing'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _goHome),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.loading:
        return const Center(child: CircularProgressIndicator());
      case _Stage.needLogin:
        return _message(
          icon: Icons.lock_outline,
          title: 'Log in to continue',
          text: 'A broker wants to list your property on PropTech. Log in or sign up to see the details and approve. '
              'It goes live only after you approve.',
          button: 'Log in / Sign up',
          onPressed: () => context.go(RouteNames.login),
        );
      case _Stage.error:
        return _message(
          icon: Icons.error_outline,
          title: 'Could not open this link',
          text: _error ?? 'Something went wrong.',
          button: 'Try again',
          onPressed: _load,
          secondary: 'Go home',
          onSecondary: _goHome,
        );
      case _Stage.review:
        final v = _view!;
        if (v.invite.status == 'accepted') {
          return _message(
            icon: Icons.check_circle_outline,
            title: 'Already approved',
            text: '"${v.property.title}" is live.',
            button: 'Go home',
            onPressed: _goHome,
          );
        }
        if (v.invite.status != 'pending') {
          return _message(
            icon: Icons.link_off,
            title: 'This invitation is no longer active',
            text: 'Ask the broker to send you a new link.',
            button: 'Go home',
            onPressed: _goHome,
          );
        }
        return _review(v);
    }
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String text,
    required String button,
    required VoidCallback onPressed,
    String? secondary,
    VoidCallback? onSecondary,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(text, textAlign: TextAlign.center, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(onPressed: onPressed, child: Text(button)),
            if (secondary != null) TextButton(onPressed: onSecondary, child: Text(secondary)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
      );

  Widget _review(InviteView v) {
    final Property p = v.property;
    final broker = v.invite.brokerName.isEmpty ? 'A broker' : v.invite.brokerName;
    final images = <String>[
      if (p.imageUrl.isNotEmpty) p.imageUrl,
      ...p.additionalImageUrls,
    ];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Text(
            '$broker wants to list this property for you. Check every detail. '
            'It goes live for tenants only after you approve.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (images.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: SafeNetworkImage(images[i], width: 280, height: 200, fit: BoxFit.cover),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(p.title, style: AppTextStyles.h3),
        const SizedBox(height: 4),
        Text(p.location, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Text(
          formatPrice(p.price, p.priceUnit),
          style: AppTextStyles.h3.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (p.bhk.isNotEmpty) _chip(p.bhk),
            if (p.furnishing.isNotEmpty) _chip(p.furnishing),
            if (p.area > 0) _chip('${p.area.toStringAsFixed(0)} sq ft'),
            if (p.bathrooms > 0) _chip('${p.bathrooms} bath'),
            if (p.securityDeposit > 0) _chip('Deposit ${formatPrice(p.securityDeposit)}'),
            if (p.category.isNotEmpty) _chip(p.category),
          ],
        ),
        if (p.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(p.description, style: AppTextStyles.bodySmall),
        ],
        if (p.amenities.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Amenities', style: AppTextStyles.h3.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final a in p.amenities) _chip(a)]),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'If you approve: tenants can request an agreement, you are the landlord and sign it, and rent and deposit '
          'are paid online through the app. Any commission is settled between you and the broker. Aadhaar KYC is needed.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _decline,
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _approve,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Approve'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}