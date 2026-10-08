import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'lease_models.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';

class LeaseRentTab extends StatefulWidget {
  final Lease lease;
  final String role;
  final Future<void> Function() onChanged;
  const LeaseRentTab({super.key, required this.lease, required this.role, required this.onChanged});

  @override
  State<LeaseRentTab> createState() => _LeaseRentTabState();
}

class _LeaseRentTabState extends State<LeaseRentTab> {
  late final Future<(List<RentPayment>, RentSummary)> _future = LeaseService.instance.rent(widget.lease.id);
  String? _busyId;

  bool get _tenant => widget.role == 'tenant';
  bool get _owner => widget.role == 'owner';

  Future<void> _run(String id, Future<void> Function() fn, String ok) async {
    setState(() => _busyId = id);
    final done = await runGuarded(context, fn, success: ok);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (done) await widget.onChanged();
  }

  Future<void> _pay(RentPayment p) async {
    final r = await askPayment(
      context,
      title: 'Pay ${_period(p.dueDate)} rent',
      subtitle: 'Pay ${inr(p.total)} to ${widget.lease.ownerName} (UPI / bank / cash), then enter the details here. The owner will confirm.',
      button: 'I have paid',
    );
    if (r == null) return;
    await _run(p.id, () => LeaseService.instance.payRent(p.id, r.method, r.reference), 'Sent to owner for confirmation');
  }

  Future<void> _markPaid(RentPayment p) async {
    final r = await askPayment(
      context,
      title: 'Record ${_period(p.dueDate)} rent as paid',
      subtitle: 'Use this when the tenant paid you outside the app.',
      button: 'Mark as paid',
    );
    if (r == null) return;
    await _run(p.id, () => LeaseService.instance.markRentPaid(p.id, r.method, r.reference), 'Marked as paid');
  }

  Future<void> _reject(RentPayment p) async {
    final reason = await askText(context, title: 'Payment not received', hint: 'Tell the tenant why', minLength: 3, button: 'Reject');
    if (reason == null) return;
    await _run(p.id, () => LeaseService.instance.rejectRent(p.id, reason), 'Tenant notified');
  }

  Future<void> _receipt(RentPayment p) async {
    setState(() => _busyId = p.id);
    try {
      final bytes = await LeaseService.instance.receiptPdf(p.id);
      final name = '${p.receiptNo.isEmpty ? 'rent-receipt' : p.receiptNo}.pdf';
      await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'application/pdf', name: name)], fileNameOverrides: [name]);
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _period(String due) {
    final d = DateTime.tryParse(due);
    if (d == null) return due;
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<RentPayment>, RentSummary)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return Center(child: Text(snap.error.toString().replaceFirst('Exception: ', '')));
        }
        final (payments, s) = snap.data!;
        return RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SectionCard(
                child: Row(children: [
                  _stat('Paid', inr(s.paid), AppColors.success),
                  _stat('Pending', inr(s.pending), AppColors.warning),
                  _stat('Overdue', inr(s.overdue), AppColors.error),
                ]),
              ),
              if (s.lateFees > 0) InfoBanner('Late fees paid so far: ${inr(s.lateFees)}', color: AppColors.warning),
              if (payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('No rent schedule yet.', style: GoogleFonts.inter(color: AppColors.textSecondary))),
                ),
              ...payments.map(_card),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Column(children: [
          Text(value, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      );

  Widget _card(RentPayment p) {
    final busy = _busyId == p.id;
    final st = p.displayStatus;
    final unpaid = st == 'pending' || st == 'overdue';

    final actions = <Widget>[];
    if (_tenant && unpaid) actions.add(ElevatedButton(onPressed: busy ? null : () => _pay(p), child: Text('Pay ${inr(p.total)}')));
    if (_owner && st == 'submitted') {
      actions.add(ElevatedButton(
        onPressed: busy ? null : () => _run(p.id, () => LeaseService.instance.confirmRent(p.id), 'Rent confirmed'),
        child: const Text('Confirm received'),
      ));
      actions.add(OutlinedButton(onPressed: busy ? null : () => _reject(p), child: const Text('Not received')));
    }
    if (_owner && unpaid) actions.add(OutlinedButton(onPressed: busy ? null : () => _markPaid(p), child: const Text('Mark as paid')));
    if (p.status == 'paid') {
      actions.add(OutlinedButton.icon(
        onPressed: busy ? null : () => _receipt(p),
        icon: const Icon(Icons.receipt_long_outlined, size: 18),
        label: const Text('Receipt'),
      ));
    }

    return SectionCard(
      title: _period(p.dueDate),
      trailing: StatusPill.status(st),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InfoRow('Due date', fmtDate(p.dueDate)),
        InfoRow('Rent', inr(p.amount)),
        if (p.lateFee > 0) InfoRow('Late fee (${p.lateDays} days)', inr(p.lateFee), valueColor: AppColors.error),
        InfoRow('Total', inr(p.total)),
        if (p.paymentMethod.isNotEmpty) InfoRow('Paid via', prettify(p.paymentMethod) + (p.reference.isEmpty ? '' : ' • ${p.reference}')),
        if (p.paidAt != null) InfoRow('Paid on', fmtDateTime(p.paidAt)),
        if (p.paidLate) const Padding(padding: EdgeInsets.only(top: 4), child: StatusPill('Paid late', AppColors.warning)),
        if (unpaid && p.rejectReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InfoBanner('Owner did not receive the last payment: ${p.rejectReason}', color: AppColors.error, icon: Icons.error_outline),
          ),
        if (st == 'submitted' && _tenant)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('Waiting for the owner to confirm.', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary))),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (busy) const LinearProgressIndicator(),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ]),
    );
  }
}