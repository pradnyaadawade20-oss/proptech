import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import 'lease_widgets.dart';
import 'upi_service.dart';

/// Tenant pays by UPI:
///   1. server gives UPI id + exact amount (locked)  2. "Open UPI app" fills them in
///   3. tenant enters the 12-digit UTR + attaches the screenshot  4. owner confirms.
/// Returns true when the proof was sent.
Future<bool> showUpiPaySheet(
  BuildContext context, {
  required String title,
  required Future<UpiLink> Function() loadLink,
  required Future<void> Function(String utr, XFile screenshot) submit,
}) async {
  final UpiLink link;
  try {
    link = await loadLink();
  } catch (e) {
    if (context.mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    return false;
  }
  if (!context.mounted) return false;
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _UpiSheet(title: title, link: link, submit: submit),
  );
  return done == true;
}

class _UpiSheet extends StatefulWidget {
  final String title;
  final UpiLink link;
  final Future<void> Function(String utr, XFile screenshot) submit;
  const _UpiSheet({required this.title, required this.link, required this.submit});

  @override
  State<_UpiSheet> createState() => _UpiSheetState();
}

class _UpiSheetState extends State<_UpiSheet> {
  final _utr = TextEditingController();
  XFile? _shot;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  Future<void> _openUpiApp() async {
    final ok = await launchUrl(Uri.parse(widget.link.link), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'No UPI app found. Pay ${inr(widget.link.amount)} to ${widget.link.upiId} in any UPI app, then enter the details below.');
    }
  }

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (f != null && mounted) setState(() => _shot = f);
  }

  Future<void> _send() async {
    final utr = _utr.text.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(utr)) {
      setState(() => _error = 'UTR must be exactly 12 digits (see your UPI app > payment details)');
      return;
    }
    if (_shot == null) {
      setState(() => _error = 'Attach the payment screenshot');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(utr, _shot!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.link;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(children: [
            InfoRow('Pay to', l.payeeName),
            InfoRow('UPI ID', l.upiId),
            InfoRow('Amount', inr(l.amount), valueColor: AppColors.primary),
          ]),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _openUpiApp,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('1. Pay ${inr(l.amount)} in UPI app'),
          ),
        ),
        const SizedBox(height: 14),
        Text('2. After paying, add the proof', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _utr,
          keyboardType: TextInputType.number,
          maxLength: 12,
          decoration: const InputDecoration(labelText: 'UTR / transaction number (12 digits)', counterText: ''),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pick,
          icon: Icon(_shot == null ? Icons.add_photo_alternate_outlined : Icons.check_circle, size: 18, color: _shot == null ? null : AppColors.success),
          label: Text(_shot == null ? 'Attach payment screenshot' : 'Screenshot attached - change'),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: GoogleFonts.inter(color: AppColors.error, fontSize: 12))),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _send,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send to owner for confirmation'),
          ),
        ),
        const SizedBox(height: 6),
        Text('The owner confirms once the money reaches their account.',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
      ]),
    );
  }
}

/// Owner/tenant: shows the screenshot the tenant attached.
Future<void> showProofDialog(BuildContext context, Future<Uint8List> Function() load) async {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: FutureBuilder<Uint8List>(
        future: load(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
            return const Padding(padding: EdgeInsets.all(24), child: Text('No screenshot was attached.'));
          }
          return InteractiveViewer(child: Image.memory(snap.data!));
        },
      ),
    ),
  );
}

/// Owner: add / change the UPI id that receives rent.
Future<void> editOwnerUpi(BuildContext context) async {
  String current = '';
  try {
    current = await UpiService.instance.ownerUpi();
  } catch (_) {}
  if (!context.mounted) return;
  final v = await askText(
    context,
    title: 'Your UPI ID',
    hint: current.isEmpty ? 'name@bank' : 'Current: $current',
    minLength: 5,
    button: 'Save',
  );
  if (v == null || !context.mounted) return;
  await runGuarded(context, () async {
    await UpiService.instance.saveOwnerUpi(v);
  }, success: 'UPI ID saved');
}