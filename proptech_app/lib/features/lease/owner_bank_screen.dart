import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'lease_widgets.dart';
import 'payment_models.dart';
import 'payment_service.dart';

/// Owner: add the bank account that receives rent + see what was collected / settled.
class OwnerBankScreen extends StatefulWidget {
  const OwnerBankScreen({super.key});

  @override
  State<OwnerBankScreen> createState() => _OwnerBankScreenState();
}

class _OwnerBankScreenState extends State<OwnerBankScreen> {
  final _holder = TextEditingController();
  final _account = TextEditingController();
  final _confirm = TextEditingController();
  final _ifsc = TextEditingController();
  final _pan = TextEditingController();

  OwnerBank? _bank;
  List<PaymentOrder> _orders = const [];
  SettlementTotals _totals = const SettlementTotals();
  bool _loading = true, _saving = false, _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _holder.dispose();
    _account.dispose();
    _confirm.dispose();
    _ifsc.dispose();
    _pan.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bank = await PaymentService.instance.ownerBank();
      final (orders, totals) = await PaymentService.instance.settlements();
      if (!mounted) return;
      setState(() {
        _bank = bank;
        _orders = orders;
        _totals = totals;
        _editing = bank == null;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      final b = await PaymentService.instance.saveOwnerBank(
        holder: _holder.text.trim(),
        accountNumber: _account.text.trim(),
        confirmAccountNumber: _confirm.text.trim(),
        ifsc: _ifsc.text.trim().toUpperCase(),
        pan: _pan.text.trim().toUpperCase(),
      );
      if (mounted) setState(() => _bank = b);
    }, success: 'Bank details saved');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _account.clear();
      _confirm.clear();
      await _load();
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      final b = await PaymentService.instance.refreshOwnerBank();
      if (mounted) setState(() => _bank = b);
    });
    if (mounted) setState(() => _saving = false);
    if (ok && mounted) snack(context, _bank?.ready == true ? 'Your account is active' : 'Still being verified');
  }

  Future<void> _checkSettlement(PaymentOrder o) async {
    final ok = await runGuarded(context, () => PaymentService.instance.refreshSettlement(o.orderId));
    if (ok) await _load();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return AppColors.success;
      case 'verification_failed':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payouts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (_error != null) InfoBanner(_error!, color: AppColors.error, icon: Icons.error_outline),
                  _bankCard(),
                  if (_bank?.ready == true) ...[
                    SectionCard(
                      child: Row(children: [
                        _stat('Collected', inr(_totals.collected), AppColors.primary),
                        _stat('Settled', inr(_totals.settled), AppColors.success),
                        _stat('Pending', inr(_totals.pending), AppColors.warning),
                      ]),
                    ),
                    if (_orders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('No online payments yet.', style: GoogleFonts.inter(color: AppColors.textSecondary))),
                      ),
                    ..._orders.map(_orderCard),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Column(children: [
          Text(value, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      );

  Widget _bankCard() {
    final b = _bank;
    if (b != null && !_editing) {
      return SectionCard(
        title: 'Bank account',
        trailing: StatusPill(prettify(b.status), _statusColor(b.status)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InfoRow('Account holder', b.accountHolder),
          InfoRow('Account number', 'XXXXXX${b.accountLast4}'),
          InfoRow('IFSC', b.ifsc),
          if (b.statusDetail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(b.statusDetail, style: GoogleFonts.inter(fontSize: 12, color: _statusColor(b.status))),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            if (!b.ready)
              OutlinedButton(onPressed: _saving ? null : _refreshStatus, child: const Text('Check status')),
            OutlinedButton(onPressed: _saving ? null : () => setState(() => _editing = true), child: const Text('Change account')),
          ]),
        ]),
      );
    }
    return SectionCard(
      title: b == null ? 'Add your bank account' : 'Change bank account',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rent and deposits paid online are sent to this account.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(controller: _holder, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Account holder name')),
        const SizedBox(height: 10),
        TextField(
          controller: _account,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Account number'),
        ),
        const SizedBox(height: 10),
        TextField(controller: _confirm, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm account number')),
        const SizedBox(height: 10),
        TextField(controller: _ifsc, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'IFSC code')),
        const SizedBox(height: 10),
        TextField(
          controller: _pan,
          textCapitalization: TextCapitalization.characters,
          maxLength: 10,
          decoration: const InputDecoration(
            labelText: 'PAN of account holder',
            helperText: 'Needed by our payment partner for KYC',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save bank details'),
            ),
          ),
          if (b != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
          ],
        ]),
      ]),
    );
  }

  Widget _orderCard(PaymentOrder o) {
    final settled = o.settlementStatus == 'settled';
    return SectionCard(
      title: o.title,
      trailing: StatusPill(
        o.status == 'duplicate' ? 'Refund needed' : (settled ? 'Settled' : 'Settlement pending'),
        o.status == 'duplicate' ? AppColors.error : (settled ? AppColors.success : AppColors.warning),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InfoRow('Property', o.propertyTitle),
        if (o.payerName.isNotEmpty) InfoRow('Paid by', o.payerName),
        InfoRow('Paid on', fmtDateTime(o.paidAt)),
        InfoRow('Amount paid', inr(o.amount)),
        if (o.platformFee > 0) InfoRow('Platform fee', '-${inr(o.platformFee)}'),
        InfoRow('You receive', inr(o.ownerAmount), valueColor: AppColors.success),
        if (settled) ...[
          if (o.settlementUtr.isNotEmpty) InfoRow('UTR', o.settlementUtr),
          InfoRow('Settled on', fmtDateTime(o.settledAt)),
        ] else if (o.status == 'paid')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _checkSettlement(o),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Check settlement'),
            ),
          ),
      ]),
    );
  }
}