import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'broker_subscription_service.dart';

/// Shown when a broker hits the free limit. Returns true if they tapped
/// "View plans".
Future<bool?> showSubscriptionRequiredDialog(BuildContext context, BrokerSubscription sub) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(sub.expired ? 'Your plan has expired' : 'Free limit reached'),
      content: Text(
        sub.expired
            ? 'Renew your monthly or yearly plan to add more listings.'
            : "You've used ${sub.listingsUsed} of ${sub.listingsLimit} free listings. "
                'Subscribe to a monthly or yearly plan to add more.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('View plans')),
      ],
    ),
  );
}

class SubscriptionPlansScreen extends StatefulWidget {
  const SubscriptionPlansScreen({super.key});

  @override
  State<SubscriptionPlansScreen> createState() => _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  BrokerSubscriptionData? _data;
  String? _error;
  String _selected = 'yearly';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await BrokerSubscriptionService.instance.getMine();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    try {
      // TODO: run the payment (Cashfree / UPI) here and pass its reference.
      final d = await BrokerSubscriptionService.instance.subscribe(_selected);
      if (!mounted) return;
      setState(() {
        _data = d;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${d.subscription.planName} active till ${d.subscription.expiryLabel ?? ''}')),
      );
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Broker Plans', style: AppTextStyles.h3),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(data),
    );
  }

  Widget _buildBody(BrokerSubscriptionData data) {
    final sub = data.subscription;
    final plans = data.plans;
    final monthly = plans.where((p) => p.id == 'monthly').firstOrNull;
    final yearly = plans.where((p) => p.id == 'yearly').firstOrNull;
    final savePct = (monthly != null && yearly != null && monthly.price > 0)
        ? (100 - (yearly.price * 100 / (monthly.price * 12))).round()
        : 0;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Current plan
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_outlined, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.planName, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      sub.isActive
                          ? '${sub.usageLabel} • valid till ${sub.expiryLabel}'
                          : sub.expired
                              ? 'Expired on ${sub.expiryLabel} • ${sub.listingsUsed} listings'
                              : sub.usageLabel,
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'First ${sub.listingsLimit} listings are free. Subscribe for unlimited listings.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final p in plans)
          _PlanTile(
            plan: p,
            selected: _selected == p.id,
            badge: p.id == 'yearly' && savePct > 0 ? 'Save $savePct%' : null,
            onTap: () => setState(() => _selected = p.id),
          ),
        const SizedBox(height: AppSpacing.md),
        const _Feature('Unlimited property listings'),
        const _Feature('Add listings for all your clients'),
        const _Feature('Plan renews by adding time on top of what is left'),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _busy || plans.isEmpty ? null : _subscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
            ),
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(sub.isActive ? 'Renew / Extend' : 'Subscribe'),
          ),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;
  const _PlanTile({required this.plan, required this.selected, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    final isYear = plan.months >= 12;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppColors.primary : AppColors.textHint),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(isYear ? 'Yearly' : 'Monthly',
                            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(badge!,
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    Text(isYear ? 'Billed for 12 months' : 'Billed for 1 month',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text('₹${plan.price}', style: AppTextStyles.h3),
              Text(isYear ? '/yr' : '/mo', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final String text;
  const _Feature(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
          ],
        ),
      );
}