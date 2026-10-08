import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'lease_models.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';

class LeaseDepositTab extends StatefulWidget {
  final Lease lease;
  final String role;
  final Future<void> Function() onChanged;
  const LeaseDepositTab({super.key, required this.lease, required this.role, required this.onChanged});

  @override
  State<LeaseDepositTab> createState() => _LeaseDepositTabState();
}

class _LeaseDepositTabState extends State<LeaseDepositTab> {
  late final Future<Deposit?> _future = LeaseService.instance.deposit(widget.lease.id);
  bool _busy = false;

  bool get _tenant => widget.role == 'tenant';
  bool get _owner => widget.role == 'owner';
  String get _id => widget.lease.id;

  Future<void> _run(Future<void> Function() fn, String ok) async {
    setState(() => _busy = true);
    final done = await runGuarded(context, fn, success: ok);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) await widget.onChanged();
  }

  Future<void> _tenantPay(Deposit d) async {
    final r = await askPayment(
      context,
      title: 'Security deposit',
      subtitle: 'Pay ${inr(d.amount)} to ${widget.lease.ownerName}, then enter the payment details. The owner will confirm.',
      button: 'I have paid',
    );
    if (r == null) return;
    await _run(() => LeaseService.instance.depositPay(_id, r.method, r.reference), 'Sent to owner for confirmation');
  }

  Future<void> _refund(Deposit d) async {
    final r = await askPayment(
      context,
      title: 'Record refund',
      subtitle: 'How did you refund ${inr(d.refundAmount)} to ${widget.lease.tenantName}?',
      button: 'Mark refunded',
    );
    if (r == null) return;
    await _run(() => LeaseService.instance.depositRefund(_id, r.method, r.reference), 'Refund recorded');
  }

  Future<void> _addDeduction() async {
    final r = await showModalBottomSheet<_DeductionInput>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _DeductionSheet(),
    );
    if (r == null) return;
    await _run(
      () => LeaseService.instance.addDeduction(_id, category: r.category, reason: r.reason, amount: r.amount, photos: r.photos),
      'Deduction added',
    );
  }

  Future<void> _dispute(Deposit d) async {
    final note = await askText(context,
        title: 'Dispute settlement',
        hint: 'What do you disagree with?',
        minLength: 5,
        button: 'Dispute',
        keyboard: TextInputType.multiline);
    if (note == null) return;
    await _run(() => LeaseService.instance.respondSettlement(_id, false, note), 'Dispute sent. PropTech support will review it.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Deposit?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text(snap.error.toString().replaceFirst('Exception: ', '')));
        final d = snap.data;
        if (d == null) {
          return Center(
            child: Text('No security deposit on this lease.', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          );
        }
        return RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SectionCard(
                title: 'Security deposit',
                trailing: StatusPill.status(d.status),
                child: Column(children: [
                  InfoRow('Amount', inr(d.amount)),
                  if (d.paymentMethod.isNotEmpty)
                    InfoRow('Paid via', prettify(d.paymentMethod) + (d.reference.isEmpty ? '' : ' • ${d.reference}')),
                  if (d.refundMethod.isNotEmpty)
                    InfoRow('Refunded via', prettify(d.refundMethod) + (d.refundReference.isEmpty ? '' : ' • ${d.refundReference}')),
                ]),
              ),
              _statusBlock(d),
              if (d.deductions.isNotEmpty || d.status == 'inspection') _deductions(d),
              if (_showTotals(d)) _totals(d),
              if (d.tenantNote.isNotEmpty) InfoBanner('Tenant note: ${d.tenantNote}', color: AppColors.warning, icon: Icons.chat_outlined),
              if (d.adminNote.isNotEmpty) InfoBanner('PropTech support: ${d.adminNote}', icon: Icons.support_agent),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        );
      },
    );
  }

  bool _showTotals(Deposit d) => const {'inspection', 'settlement', 'disputed', 'refund_due', 'refunded', 'carried_forward'}.contains(d.status);

  Widget _totals(Deposit d) {
    final inspecting = d.status == 'inspection';
    final refund = inspecting ? d.previewRefund : d.refundAmount;
    return SectionCard(
      title: 'Settlement',
      child: Column(children: [
        InfoRow('Deposit held', inr(d.amount)),
        InfoRow('Total deductions', '- ${inr(d.totalDeductions)}', valueColor: d.totalDeductions > 0 ? AppColors.error : null),
        InfoRow(inspecting ? 'Refund (so far)' : 'Refund to tenant', inr(refund), valueColor: AppColors.success),
        if (d.tenantOwes > 0) InfoRow('Tenant still owes', inr(d.tenantOwes), valueColor: AppColors.error),
      ]),
    );
  }

  Widget _deductions(Deposit d) {
    final canEdit = _owner && d.status == 'inspection';
    return SectionCard(
      title: 'Deductions',
      trailing: canEdit ? TextButton.icon(onPressed: _busy ? null : _addDeduction, icon: const Icon(Icons.add, size: 18), label: const Text('Add')) : null,
      child: d.deductions.isEmpty
          ? Text('No deductions.', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13))
          : Column(
              children: d.deductions
                  .map((x) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            StatusPill(prettify(x.category), AppColors.primary),
                            const Spacer(),
                            Text(inr(x.amount), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.error)),
                            if (canEdit)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await confirmDialog(context, 'Remove deduction', 'Remove this deduction?', yes: 'Remove')) {
                                          await _run(() => LeaseService.instance.deleteDeduction(_id, x.id), 'Deduction removed');
                                        }
                                      },
                              ),
                          ]),
                          const SizedBox(height: 4),
                          Text(x.reason, style: GoogleFonts.inter(fontSize: 13)),
                          if (x.photos.isNotEmpty) ...[const SizedBox(height: 6), PhotoStrip(x.photos)],
                        ]),
                      ))
                  .toList(),
            ),
    );
  }

  Widget _statusBlock(Deposit d) {
    Widget btn(String label, VoidCallback onTap, {bool outlined = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: outlined
                ? OutlinedButton(onPressed: _busy ? null : onTap, child: Text(label))
                : ElevatedButton(onPressed: _busy ? null : onTap, child: Text(label)),
          ),
        );

    switch (d.status) {
      case 'pending':
        return _tenant
            ? btn('Pay deposit (${inr(d.amount)})', () => _tenantPay(d))
            : const InfoBanner('Waiting for the tenant to pay the deposit.', icon: Icons.hourglass_empty);
      case 'submitted':
        return _owner
            ? Column(children: [
                const InfoBanner('The tenant says the deposit is paid. Confirm once you have received it.', color: AppColors.warning),
                btn('Confirm received', () => _run(() => LeaseService.instance.depositConfirm(_id), 'Deposit is now held')),
                btn('Not received', () => _run(() => LeaseService.instance.depositReject(_id), 'Tenant notified'), outlined: true),
              ])
            : const InfoBanner('Waiting for the owner to confirm the deposit.', color: AppColors.warning, icon: Icons.hourglass_empty);
      case 'held':
        return Column(children: [
          const InfoBanner('The deposit is held by the owner for the duration of the lease.', color: AppColors.success, icon: Icons.lock_outline),
          if (_owner && widget.lease.status == 'moved_out')
            btn('Start deposit inspection', () => _run(() => LeaseService.instance.startInspection(_id), 'Inspection started')),
        ]);
      case 'inspection':
        return _owner
            ? Column(children: [
                const InfoBanner('Add deductions with proof (damage needs a photo). The tenant sees them before anything is final.', icon: Icons.fact_check_outlined),
                btn('Send settlement to tenant', () async {
                  if (await confirmDialog(context, 'Send settlement', 'The tenant will be asked to accept or dispute. You cannot add deductions afterwards.', yes: 'Send')) {
                    await _run(() => LeaseService.instance.sendSettlement(_id), 'Settlement sent');
                  }
                }),
              ])
            : const InfoBanner('The owner is inspecting the property. Any deductions will appear below.', icon: Icons.fact_check_outlined);
      case 'settlement':
        return _tenant
            ? Column(children: [
                const InfoBanner('The owner has sent the final settlement. Please review and respond.', color: AppColors.warning, icon: Icons.rate_review_outlined),
                btn('Accept settlement', () async {
                  if (await confirmDialog(context, 'Accept settlement', 'Accept the deductions and refund shown below?', yes: 'Accept')) {
                    await _run(() => LeaseService.instance.respondSettlement(_id, true, ''), 'Settlement accepted');
                  }
                }),
                btn('Dispute', () => _dispute(d), outlined: true),
              ])
            : const InfoBanner('Waiting for the tenant to accept or dispute the settlement.', color: AppColors.warning, icon: Icons.hourglass_empty);
      case 'disputed':
        return const InfoBanner('The tenant disputed the settlement. PropTech support will review and decide.', color: AppColors.error, icon: Icons.gavel);
      case 'refund_due':
        return _owner
            ? Column(children: [
                InfoBanner('Refund ${inr(d.refundAmount)} to ${widget.lease.tenantName}, then record it here.', color: AppColors.warning, icon: Icons.payments_outlined),
                btn('Record refund', () => _refund(d)),
              ])
            : InfoBanner('Settlement agreed. The owner will refund ${inr(d.refundAmount)}.', color: AppColors.warning, icon: Icons.payments_outlined);
      case 'refunded':
        return const InfoBanner('The deposit has been settled and refunded.', color: AppColors.success, icon: Icons.check_circle_outline);
      case 'carried_forward':
        return const InfoBanner('The deposit was carried forward to the renewed lease.', color: AppColors.success, icon: Icons.autorenew);
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------- add deduction

class _DeductionInput {
  final String category, reason;
  final double amount;
  final List<XFile> photos;
  _DeductionInput(this.category, this.reason, this.amount, this.photos);
}

class _DeductionSheet extends StatefulWidget {
  const _DeductionSheet();

  @override
  State<_DeductionSheet> createState() => _DeductionSheetState();
}

class _DeductionSheetState extends State<_DeductionSheet> {
  String _category = 'damage';
  final _reason = TextEditingController();
  final _amount = TextEditingController();
  final List<XFile> _photos = [];
  String? _error;

  static const _cats = {'damage': 'Damage', 'unpaid_rent': 'Unpaid rent', 'cleaning': 'Cleaning', 'other': 'Other'};

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await ImagePicker().pickMultiImage(limit: 6);
    if (files.isNotEmpty) setState(() => _photos..clear()..addAll(files.take(6)));
  }

  void _submit() {
    final amt = double.tryParse(_amount.text.trim());
    if (_reason.text.trim().length < 3) return setState(() => _error = 'Write the reason for this deduction');
    if (amt == null || amt <= 0) return setState(() => _error = 'Enter a valid amount');
    if (_category == 'damage' && _photos.isEmpty) return setState(() => _error = 'Add at least one photo as proof of the damage');
    Navigator.pop(context, _DeductionInput(_category, _reason.text.trim(), amt, List.of(_photos)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add deduction', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _cats.entries
                .map((e) => ChoiceChip(label: Text(e.value), selected: _category == e.key, onSelected: (_) => setState(() => _category = e.key)))
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason')),
          const SizedBox(height: 8),
          TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_photos.isEmpty ? (_category == 'damage' ? 'Add proof photos (required)' : 'Add photos (optional)') : '${_photos.length} photo(s) selected'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submit, child: const Text('Add deduction'))),
        ]),
      ),
    );
  }
}