import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'commission_service.dart';
import 'lease_widgets.dart';
import 'receipt_screen.dart';

/// Broker's screen: every lease they brought, set the commission, see who paid.
class AgentCommissionsScreen extends StatefulWidget {
  const AgentCommissionsScreen({super.key});

  @override
  State<AgentCommissionsScreen> createState() => _AgentCommissionsScreenState();
}

class _AgentCommissionsScreenState extends State<AgentCommissionsScreen> {
  late Future<List<AgentAgreement>> _future = CommissionService.instance.agentAgreements();

  void _reload() => setState(() => _future = CommissionService.instance.agentAgreements());

  Future<void> _setCommission(AgentAgreement l) async {
    final amount = TextEditingController(text: l.commission == null ? '' : l.commission!.amount.toStringAsFixed(0));
    final note = TextEditingController(text: l.commission?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Propose commission'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Amount you agreed with ${l.tenantName}. They will review and accept it before signing the agreement.',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Commission (₹)', prefixText: '₹ '),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final value = double.tryParse(amount.text.trim());
    final text = note.text.trim();
    amount.dispose();
    note.dispose();
    if (ok != true || !mounted) return;
    if (value == null || value < 1) {
      snack(context, 'Enter the commission amount.', error: true);
      return;
    }
    try {
      await CommissionService.instance.set(l.agreementId, value, text);
      if (!mounted) return;
      snack(context, 'Commission sent to the tenant for approval.');
      _reload();
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _openReceipt(AgentAgreement l) {
    final c = l.commission!;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiptScreen(
        data: commissionReceipt(c: c, property: l.propertyTitle, paidBy: l.tenantName, receivedBy: 'You'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent commissions')),
      body: FutureBuilder<List<AgentAgreement>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text(snap.error.toString().replaceFirst('Exception: ', '')));
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Nothing here yet. When a tenant requests an agreement for a property you listed, it shows up here.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final l = items[i];
                final c = l.commission;
                return SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.propertyTitle, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Tenant: ${l.tenantName}', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    if (c == null)
                      Text('Commission not set', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary))
                    else
                      Row(children: [
                        Text(inr(c.amount), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 10),
                        Text(
                          c.paid ? 'Paid' : (c.accepted ? 'Accepted, tenant pays after signing' : 'Waiting for tenant to accept'),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: c.paid ? AppColors.success : AppColors.warning,
                          ),
                        ),
                      ]),
                    const SizedBox(height: 10),
                    if (c != null && c.paid)
                      OutlinedButton.icon(
                        onPressed: () => _openReceipt(l),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('View receipt'),
                      )
                    else if (c != null && c.accepted)
                      const SizedBox.shrink()
                    else
                      OutlinedButton.icon(
                        onPressed: () => _setCommission(l),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(c == null ? 'Propose commission' : 'Change amount'),
                      ),
                  ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}