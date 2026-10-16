import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import 'commission_service.dart';
import 'lease_widgets.dart';
import 'online_payment.dart';
import 'receipt_screen.dart';

/// Tenant's "Agent commission" card. Used on the agreement screen (accept / decline before signing)
/// and on the lease overview (pay after both signed). Hidden when there is no agent or no proposal.
class CommissionCard extends StatefulWidget {
  final String agreementId, propertyTitle, tenantName;
  final Future<void> Function()? onChanged;
  const CommissionCard({
    super.key,
    required this.agreementId,
    required this.propertyTitle,
    required this.tenantName,
    this.onChanged,
  });

  @override
  State<CommissionCard> createState() => _CommissionCardState();
}

class _CommissionCardState extends State<CommissionCard> {
  late Future<CommissionView> _future = CommissionService.instance.get(widget.agreementId);
  bool _busy = false;

  void _refresh() => setState(() => _future = CommissionService.instance.get(widget.agreementId));

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      snack(context, done);
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _refresh();
    await widget.onChanged?.call();
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    final paid = await payOnline(context, start: () => CommissionService.instance.checkout(widget.agreementId));
    if (!mounted) return;
    setState(() => _busy = false);
    _refresh();
    if (paid) snack(context, 'Commission paid successfully');
    await widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CommissionView>(
      future: _future,
      builder: (context, snap) {
        final v = snap.data;
        final c = v?.commission;
        if (v == null || !v.hasAgent || c == null || v.role != 'tenant') return const SizedBox.shrink();

        final agent = v.agentName.isEmpty ? 'your agent' : v.agentName;
        final label = c.paid ? 'Paid' : (c.accepted ? 'Accepted' : 'Needs your approval');
        final color = c.paid ? AppColors.success : (c.accepted ? AppColors.primary : AppColors.warning);

        late final String line;
        if (c.paid) {
          line = 'Paid to $agent';
        } else if (c.accepted) {
          line = v.canPay ? 'You agreed to this. Please pay $agent.' : 'You agreed to this. You can pay once both of you have signed the agreement.';
        } else {
          line = '$agent has proposed this commission. This is separate from your rent agreement.';
        }

        return SectionCard(
          title: 'Agent commission',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(inr(c.amount), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(line, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            if (c.note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(c.note, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            if (v.canAccept)
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _run(() => CommissionService.instance.decline(widget.agreementId), 'Commission declined'),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _run(() => CommissionService.instance.accept(widget.agreementId), 'Commission accepted'),
                    child: const Text('Accept'),
                  ),
                ),
              ])
            else if (v.canPay)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _pay,
                  icon: const Icon(Icons.payment, size: 18),
                  label: Text('Pay commission ${inr(c.amount)}'),
                ),
              )
            else if (c.paid)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReceiptScreen(
                      data: commissionReceipt(c: c, property: widget.propertyTitle, paidBy: widget.tenantName, receivedBy: v.agentName),
                    ),
                  )),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('View receipt'),
                ),
              ),
          ]),
        );
      },
    );
  }
}