import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../agreement/signature_screen.dart';
import 'commission_service.dart';
import 'lease_widgets.dart';
import 'online_payment.dart';
import 'receipt_screen.dart';

/// One commission agreement (broker <-> tenant): read it, sign / decline (tenant), cancel (broker),
/// download the PDF, and pay once the rental agreement is completed.
class CommissionAgreementScreen extends StatefulWidget {
  final String id;
  const CommissionAgreementScreen({super.key, required this.id});

  @override
  State<CommissionAgreementScreen> createState() => _CommissionAgreementScreenState();
}

class _CommissionAgreementScreenState extends State<CommissionAgreementScreen> {
  CommissionAgreement? _c;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await CommissionService.instance.get(widget.id);
      if (!mounted) return;
      setState(() {
        _c = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) snack(context, done);
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _sign(CommissionAgreement c) async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => SignatureScreen(agreementId: c.id, signerName: c.tenantName)),
    );
    if (result == null || !mounted) return;
    await _run(
      () => CommissionService.instance.sign(c.id, result['signatureType']!, result['signatureData']!),
      'Signed. You can now request the rental agreement.',
    );
  }

  Future<void> _confirm(String title, String body, Future<void> Function() onYes, String done) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (ok == true) await _run(onYes, done);
  }

  Future<void> _pay(CommissionAgreement c) async {
    setState(() => _busy = true);
    final paid = await payOnline(context, start: () => CommissionService.instance.checkout(c.id));
    if (!mounted) return;
    setState(() => _busy = false);
    if (paid) snack(context, 'Commission paid successfully');
    await _load();
  }

  Future<void> _sharePdf(CommissionAgreement c) async {
    setState(() => _busy = true);
    try {
      final bytes = await CommissionService.instance.pdf(c.id);
      final name = '${c.number.isEmpty ? 'commission-agreement' : c.number}.pdf';
      await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'application/pdf', name: name)], fileNameOverrides: [name]);
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commission agreement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _body(_c!),
    );
  }

  Widget _row(String label, String value) {
    final l = GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary);
    final v = GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(label, style: l)),
        const SizedBox(width: 12),
        Expanded(flex: 6, child: Text(value.isEmpty ? '-' : value, textAlign: TextAlign.right, style: v)),
      ]),
    );
  }

  Widget _signRow(String who, String name, DateTime? at) {
    final done = at != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(done ? Icons.check_circle : Icons.pending_outlined, color: done ? AppColors.success : AppColors.warning),
      title: Text('$who: $name', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(done ? 'Signed on ${fmtDateTime(at)}' : 'Waiting for signature',
          style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
    );
  }

  Widget _body(CommissionAgreement c) {
    final terms = <String>[
      'The tenant agrees to pay the commission above to the agent for helping the tenant find this property.',
      'The commission becomes payable after the rental agreement for this property is signed by both the owner and the tenant.',
      'The commission is paid through the PropTech app, and a receipt is available to both parties.',
      'This agreement is only between the agent and the tenant. The property owner is not a party to it.',
    ];
    final color = c.paid ? AppColors.success : (c.signed ? AppColors.primary : AppColors.warning);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(inr(c.amount), style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(c.statusLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ),
            ]),
            const SizedBox(height: 8),
            const Divider(height: 1),
            _row('Agreement no.', c.number),
            _row('Property', c.propertyTitle),
            _row('Agent (broker)', c.agentName),
            _row('Tenant', c.tenantName),
            _row('Note', c.note),
          ]),
        ),
        SectionCard(
          title: 'Terms',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < terms.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${i + 1}. ${terms[i]}', style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
              ),
          ]),
        ),
        SectionCard(
          title: 'Signatures',
          child: Column(children: [
            _signRow('Agent', c.agentName, c.agentSignedAt),
            _signRow('Tenant', c.tenantName, c.tenantSignedAt),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),
        ..._actions(c),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  List<Widget> _actions(CommissionAgreement c) {
    final out = <Widget>[];
    Widget gap() => const SizedBox(height: 10);

    if (c.status == 'sent' && c.isTenant) {
      out.add(ElevatedButton.icon(
        onPressed: _busy ? null : () => _sign(c),
        icon: const Icon(Icons.draw_outlined, size: 18),
        label: const Text('Sign commission agreement'),
      ));
      out.add(gap());
      out.add(OutlinedButton(
        onPressed: _busy
            ? null
            : () => _confirm('Decline?', 'The agent will be told you did not accept this commission.',
                () => CommissionService.instance.decline(c.id), 'Declined'),
        child: const Text('Decline'),
      ));
    }
    if (c.status == 'sent' && c.isAgent) {
      out.add(OutlinedButton(
        onPressed: _busy
            ? null
            : () => _confirm('Cancel agreement?', 'The tenant will no longer be able to sign it.',
                () => CommissionService.instance.cancel(c.id), 'Cancelled'),
        child: const Text('Cancel this agreement'),
      ));
    }
    if (c.signed) {
      if (c.isTenant && !c.paid) {
        if (c.leaseId.isNotEmpty) {
          out.add(ElevatedButton.icon(
            onPressed: _busy ? null : () => _pay(c),
            icon: const Icon(Icons.payment, size: 18),
            label: Text('Pay commission ${inr(c.amount)}'),
          ));
        } else {
          out.add(Text(
            'Next: request the rental agreement for this property. You can pay the commission once the owner and you have both signed it.',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
          ));
        }
        out.add(gap());
      }
      if (c.paid) {
        out.add(ElevatedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReceiptScreen(data: commissionReceipt(c))),
          ),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('View receipt'),
        ));
        out.add(gap());
      } else if (c.isAgent) {
        out.add(Text(
          c.leaseId.isEmpty
              ? 'Waiting for the rental agreement to be completed. Then the tenant can pay.'
              : 'The rental agreement is done. Waiting for the tenant to pay.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ));
        out.add(gap());
      }
      out.add(OutlinedButton.icon(
        onPressed: _busy ? null : () => _sharePdf(c),
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: const Text('Download / Share PDF'),
      ));
    }
    return out;
  }
}