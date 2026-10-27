import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'commission_service.dart';
import 'lease_models.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';
import 'receipt_screen.dart';

/// All paid rent months + the security deposit, newest first. Same list for owner and tenant.
class LeaseReceiptsTab extends StatefulWidget {
  final Lease lease;
  const LeaseReceiptsTab({super.key, required this.lease});

  @override
  State<LeaseReceiptsTab> createState() => _LeaseReceiptsTabState();
}

class _LeaseReceiptsTabState extends State<LeaseReceiptsTab> {
  late final Future<List<ReceiptData>> _future = _load();

  String _period(String due) {
    final d = DateTime.tryParse(due);
    if (d == null) return due;
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${m[d.month - 1]} ${d.year}';
  }

  Future<List<ReceiptData>> _load() async {
    final l = widget.lease;
    final svc = LeaseService.instance;
    final rent = await svc.rent(l.id);
    Deposit? dep;
    try {
      dep = await svc.deposit(l.id);
    } catch (_) {}

    final out = <ReceiptData>[];
    for (final p in rent.$1.where((p) => p.status == 'paid')) {
      out.add(ReceiptData(
        title: '${_period(p.dueDate)} rent',
        receiptNo: p.receiptNo,
        amount: p.total,
        paidAt: p.paidAt,
        loadPdf: () => svc.receiptPdf(p.id),
        rows: [
          ('Property', l.propertyTitle),
          ('Rent for', _period(p.dueDate)),
          ('Rent', inr(p.amount)),
          ('Late fee', p.lateFee > 0 ? '${inr(p.lateFee)} (${p.lateDays} days)' : ''),
          ('Total paid', inr(p.total)),
          ('Paid by', l.tenantName),
          ('Received by', l.ownerName),
          ('Payment method', prettify(p.paymentMethod)),
          ('Transaction ID', p.reference),
          ('Paid on', fmtDateTime(p.paidAt)),
        ],
      ));
    }
    if (dep != null && dep.status != 'pending' && dep.status != 'submitted') {
      out.add(ReceiptData(
        title: 'Security deposit',
        receiptNo: '',
        fileName: 'deposit-receipt',
        amount: dep.amount,
        paidAt: dep.receivedAt,
        loadPdf: () => svc.depositReceiptPdf(l.id),
        rows: [
          ('Property', l.propertyTitle),
          ('Deposit', inr(dep.amount)),
          ('Paid by', l.tenantName),
          ('Received by', l.ownerName),
          ('Payment method', prettify(dep.paymentMethod)),
          ('Transaction ID', dep.reference),
          ('Paid on', fmtDateTime(dep.receivedAt)),
        ],
      ));
    }
    if (dep != null && dep.status == 'refunded') {
      out.add(ReceiptData(
        title: 'Deposit refund',
        heading: 'Refund successful',
        receiptNo: '',
        fileName: 'deposit-refund-receipt',
        amount: dep.refundAmount,
        paidAt: dep.refundedAt,
        loadPdf: () => svc.depositRefundReceiptPdf(l.id),
        rows: [
          ('Property', l.propertyTitle),
          ('Deposit paid', inr(dep.amount)),
          ('Deductions', dep.totalDeductions > 0 ? '- ${inr(dep.totalDeductions)}' : 'None'),
          ('Refund amount', inr(dep.refundAmount)),
          ('Refunded to', l.tenantName),
          ('Refunded by', l.ownerName),
          ('Refund mode', dep.refundMethod == 'online_refund' ? 'Online (original payment method)' : prettify(dep.refundMethod)),
          ('Reference', dep.refundReference),
          ('Refunded on', fmtDateTime(dep.refundedAt)),
        ],
      ));
    }
    // Agent commission (only the tenant and the agent can read it; for the owner this just throws and is skipped).
    try {
      final c = await CommissionService.instance.forLease(l.id);
      if (c != null && c.paid) out.add(commissionReceipt(c));
    } catch (_) {}

    out.sort((a, b) {
      final x = a.paidAt, y = b.paidAt;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReceiptData>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text(snap.error.toString().replaceFirst('Exception: ', '')));
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(child: Text('No receipts yet.', style: GoogleFonts.inter(color: AppColors.textSecondary)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = items[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryLight,
                child: Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
              ),
              title: Text(r.title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${inr(r.amount)} • ${fmtDateTime(r.paidAt)}',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(data: r))),
            );
          },
        );
      },
    );
  }
}