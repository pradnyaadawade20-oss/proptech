import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../lease/online_payment.dart';
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
  List<SubscriptionReceipt> _history = [];
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
      _loadHistory();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadHistory() async {
    try {
      final h = await BrokerSubscriptionService.instance.getHistory();
      if (mounted) setState(() => _history = h);
    } catch (_) {}
  }

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    try {
      // Cashfree checkout (UPI / card / netbanking). The server activates the plan after payment.
      final paid = await payOnline(
        context,
        start: () => BrokerSubscriptionService.instance.checkout(_selected),
      );
      if (!mounted) return;
      if (!paid) {
        setState(() => _busy = false);
        return;
      }
      final d = await BrokerSubscriptionService.instance.getMine();
      if (!mounted) return;
      setState(() {
        _data = d;
        _busy = false;
      });
      _loadHistory();
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

  static String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  void _showReceipt(SubscriptionReceipt r) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(k, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary))),
              Expanded(child: Text(v, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600))),
            ],
          ),
        );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 8),
                Text('Payment receipt', style: AppTextStyles.h3),
              ]),
              const Divider(height: 24),
              row('Receipt no', r.receiptNo),
              row('Plan', r.planName),
              row('Amount paid', '₹${r.amount.toStringAsFixed(r.amount % 1 == 0 ? 0 : 2)}'),
              row('Paid on', _date(r.paidAt)),
              row('Valid', '${_date(r.startsAt)} - ${_date(r.expiresAt)}'),
              if (r.paymentMethod.isNotEmpty) row('Method', r.paymentMethod),
              row('Order id', r.paymentRef),
              if (r.transactionId.isNotEmpty) row('Transaction id', r.transactionId),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.maybePop(context),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            ),
          ),
        ),
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
        // Current plan (gradient hero card)
        Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0C3476), Color(0xFF1A4BA0)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -4,
                top: -6,
                child: Icon(Icons.workspace_premium, size: 72, color: Colors.white.withValues(alpha: 0.10)),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.verified, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sub.planName,
                            style: AppTextStyles.h3.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          (sub.isActive
                                  ? '${sub.usageLabel} • valid till ${sub.expiryLabel}'
                                  : sub.expired
                                      ? 'Expired on ${sub.expiryLabel} • ${sub.listingsUsed} listings'
                                      : sub.usageLabel)
                              .replaceAll(' • ', '  •  '),
                          style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Free listings note
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                child: const Icon(Icons.card_giftcard, color: AppColors.secondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('First ${sub.listingsLimit} listings are free.',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w700)),
                    Text('Subscribe for unlimited listings.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Choose your plan', style: AppTextStyles.h3),
        const SizedBox(height: AppSpacing.md),
        for (final p in plans)
          _PlanTile(
            plan: p,
            selected: _selected == p.id,
            badge: p.id == 'yearly' && savePct > 0 ? 'Save $savePct%' : null,
            onTap: () => setState(() => _selected = p.id),
          ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F8F4),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            children: const [
              _Feature('Unlimited property listings'),
              Divider(height: 1, color: AppColors.border),
              _Feature('Add listings for all your clients'),
              Divider(height: 1, color: AppColors.border),
              _Feature('Plan renews by adding time on top of what is left'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        GestureDetector(
          onTap: _busy || plans.isEmpty ? null : _subscribe,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1A4BA0), Color(0xFF0C3476)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5)),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 24),
                Expanded(
                  child: Center(
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(sub.isActive ? 'Renew / Extend' : 'Subscribe',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                ),
                const Icon(Icons.security, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.shield_outlined, size: 18, color: AppColors.secondary),
            ),
            const SizedBox(width: 8),
            Text('Secure payment  •  Cancel anytime',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Payment history', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.sm),
          for (final r in _history) _ReceiptTile(r: r, onTap: () => _showReceipt(r)),
        ],
      ],
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  final SubscriptionReceipt r;
  final VoidCallback onTap;
  const _ReceiptTile({required this.r, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = r.paidAt;
    final dateStr = _SubscriptionPlansScreenState._date(d);
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
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.planName, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                    Text('$dateStr • ${r.receiptNo}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${r.amount.toStringAsFixed(r.amount % 1 == 0 ? 0 : 2)}', style: AppTextStyles.bodyMedium),
                  Text('Paid', style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 18),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight.withValues(alpha: 0.6) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: selected ? AppColors.secondary : AppColors.border, width: selected ? 1.5 : 1),
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
              Container(width: 1, height: 44, color: AppColors.border),
              const SizedBox(width: AppSpacing.md),
              Text('₹${plan.price}', style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 2),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 24, color: AppColors.success),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
          ],
        ),
      );
}