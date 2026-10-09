import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import 'lease_widgets.dart';
import 'payment_models.dart';
import 'payment_service.dart';

/// "Online payments" history of one lease (both owner and tenant see it).
class LeasePaymentsSection extends StatelessWidget {
  final String leaseId;
  final String role;
  const LeasePaymentsSection({super.key, required this.leaseId, required this.role});

  Color _color(PaymentOrder o) {
    switch (o.status) {
      case 'paid':
        return AppColors.success;
      case 'duplicate':
        return AppColors.warning;
      case 'created':
        return o.failureReason.isNotEmpty ? AppColors.error : AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  String _label(PaymentOrder o) {
    switch (o.status) {
      case 'paid':
        return 'Paid';
      case 'duplicate':
        return 'Paid twice - refund';
      case 'created':
        return o.failureReason.isNotEmpty ? 'Failed' : 'Not completed';
      default:
        return 'Expired';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PaymentOrder>>(
      future: PaymentService.instance.leasePayments(leaseId),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final list = snap.data!;
        return SectionCard(
          title: 'Online payments',
          child: Column(
            children: list.map((o) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(o.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
                    Text(inr(o.amount), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    StatusPill(_label(o), _color(o)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fmtDateTime(o.paidAt ?? o.createdAt) + (o.paymentMethod.isEmpty ? '' : ' • ${prettify(o.paymentMethod)}'),
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  ]),
                  if (o.status == 'created' && o.failureReason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(o.failureReason, style: GoogleFonts.inter(fontSize: 11, color: AppColors.error)),
                    ),
                  if (role == 'owner' && o.status == 'paid')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        o.settlementStatus == 'settled'
                            ? 'Settled to your bank${o.settlementUtr.isEmpty ? '' : ' • UTR ${o.settlementUtr}'}'
                            : 'You receive ${inr(o.ownerAmount)} • settlement pending',
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  const Divider(height: 14),
                ]),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}