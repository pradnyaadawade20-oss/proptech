import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import 'commission_agreement_screen.dart';
import 'commission_service.dart';
import 'lease_widgets.dart';
import 'online_payment.dart';
import 'receipt_screen.dart';

/// Tenant's "Agent commission" card on the lease overview: pay the commission that was agreed in the
/// signed commission agreement. Hidden when this lease has no commission agreement.
class CommissionCard extends StatefulWidget {
  final String leaseId;
  final Future<void> Function()? onChanged;
  const CommissionCard({super.key, required this.leaseId, this.onChanged});

  @override
  State<CommissionCard> createState() => _CommissionCardState();
}

class _CommissionCardState extends State<CommissionCard> {
  late Future<CommissionAgreement?> _future = _load();
  bool _busy = false;

  Future<CommissionAgreement?> _load() async {
    try {
      return await CommissionService.instance.forLease(widget.leaseId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pay(CommissionAgreement c) async {
    setState(() => _busy = true);
    final paid = await payOnline(context, start: () => CommissionService.instance.checkout(c.id));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _future = _load();
    });
    if (paid) snack(context, 'Commission paid successfully');
    await widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CommissionAgreement?>(
      future: _future,
      builder: (context, snap) {
        final c = snap.data;
        if (c == null || !c.isTenant) return const SizedBox.shrink();
        final color = c.paid ? AppColors.success : AppColors.warning;
        return SectionCard(
          title: 'Agent commission',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(inr(c.amount), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(c.paid ? 'Paid' : 'Due',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              c.paid
                  ? 'Paid to ${c.agentName}'
                  : 'As agreed in your commission agreement with ${c.agentName}. This is separate from the rent.',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: c.paid
                  ? OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ReceiptScreen(data: commissionReceipt(c))),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('View receipt'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _busy ? null : () => _pay(c),
                      icon: const Icon(Icons.payment, size: 18),
                      label: Text('Pay commission ${inr(c.amount)}'),
                    ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CommissionAgreementScreen(id: c.id)),
              ),
              child: const Text('View commission agreement'),
            ),
          ]),
        );
      },
    );
  }
}