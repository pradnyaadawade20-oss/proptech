import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'lease_widgets.dart';

/// Everything a receipt shows. Built from a paid rent month or the security deposit.
class ReceiptData {
  final String title; // "December 2026 rent" / "Security deposit"
  final String receiptNo;
  final double amount;
  final DateTime? paidAt;
  final List<(String, String)> rows;
  final Future<Uint8List> Function()? loadPdf; // null = no PDF (button hidden)
  const ReceiptData({
    required this.title,
    required this.receiptNo,
    required this.amount,
    required this.paidAt,
    required this.rows,
    this.loadPdf,
  });
}

/// A proper receipt page (same for owner and tenant) with a Share / Download PDF button.
class ReceiptScreen extends StatefulWidget {
  final ReceiptData data;
  const ReceiptScreen({super.key, required this.data});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  bool _busy = false;

  Future<void> _sharePdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.data.loadPdf!();
      final no = widget.data.receiptNo;
      final name = '${no.isEmpty ? 'receipt' : no}.pdf';
      await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'application/pdf', name: name)], fileNameOverrides: [name]);
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final label = GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary);
    final value = GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              const SizedBox(height: 4),
              const Icon(Icons.check_circle, color: AppColors.success, size: 52),
              const SizedBox(height: 8),
              Text('Payment successful', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(inr(d.amount), style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(d.title, style: label),
              if (d.receiptNo.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Receipt no. ${d.receiptNo}', style: label),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 8),
              for (final r in d.rows.where((r) => r.$2.isNotEmpty && r.$2 != '-'))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 4, child: Text(r.$1, style: label)),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: Text(r.$2, textAlign: TextAlign.right, style: value)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          if (d.loadPdf != null)
          ElevatedButton.icon(
            onPressed: _busy ? null : _sharePdf,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Download / Share PDF'),
          ),
        ],
      ),
    );
  }
}