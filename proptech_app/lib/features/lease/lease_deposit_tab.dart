import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'lease_models.dart';
import 'lease_service.dart';
import 'lease_widgets.dart';
import 'online_payment.dart';
import 'receipt_screen.dart';

class LeaseDepositTab extends StatefulWidget {
  final Lease lease;
  final String role;
  final Future<void> Function() onChanged;
  const LeaseDepositTab({super.key, required this.lease, required this.role, required this.onChanged});

  @override
  State<LeaseDepositTab> createState() => _LeaseDepositTabState();
}

class _LeaseDepositTabState extends State<LeaseDepositTab> {
  late final Future<Deposit?> _future = _loadDeposit();

  /// If a refund is still processing at Cashfree, check on it first so the screen shows the latest.
  Future<Deposit?> _loadDeposit() async {
    var d = await LeaseService.instance.deposit(widget.lease.id);
    if (d != null && d.refundInProgress) {
      try {
        await LeaseService.instance.refreshOnlineRefund(widget.lease.id);
        d = await LeaseService.instance.deposit(widget.lease.id);
      } catch (_) {}
    }
    return d;
  }
  bool _busy = false;
  Future<EarlyExit?>? _suggestFuture;

  bool get _tenant => widget.role == 'tenant';
  bool get _owner => widget.role == 'owner';
  String get _id => widget.lease.id;

  Future<void> _run(Future<void> Function() fn, String ok) async {
    setState(() => _busy = true);
    final done = await runGuarded(context, fn, success: ok);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) {
      setState(() => _suggestFuture = null); // refresh suggestions after any change
      await widget.onChanged();
    }
  }

  /// Early-exit suggestions (unpaid rent, notice shortfall) - owner only, during inspection.
  Future<EarlyExit?> _loadSuggestions() async {
    try {
      return await LeaseService.instance.earlyExit(_id);
    } catch (_) {
      return null; // suggestions are optional
    }
  }

  Widget _suggestions(Deposit d) {
    if (!_owner || d.status != 'inspection') return const SizedBox.shrink();
    _suggestFuture ??= _loadSuggestions();
    return FutureBuilder<EarlyExit?>(
      future: _suggestFuture,
      builder: (context, snap) {
        final ex = snap.data;
        if (ex == null) return const SizedBox.shrink();
        final added = d.deductions.map((x) => x.reason).toSet();
        final todo = ex.items.where((i) => !added.contains(i.reason)).toList();
        if (todo.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: 'Suggested deductions',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              ex.early
                  ? 'The tenant left before the lease end (${fmtDate(ex.endDate)}). Add what applies; the rest of the deposit is refunded.'
                  : 'Based on unpaid rent. Add what applies; the rest of the deposit is refunded.',
              style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            for (final it in todo)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.reason, style: GoogleFonts.inter(fontSize: 13)),
                      Text(inr(it.amount), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.error)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => LeaseService.instance.addDeduction(_id, category: it.category, reason: it.reason, amount: it.amount),
                              'Deduction added',
                            ),
                    child: const Text('Add'),
                  ),
                ]),
              ),
          ]),
        );
      },
    );
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

  /// Pay button -> Cashfree page (UPI / card / net banking) -> deposit held automatically.
  Future<void> _payOnline(Deposit d) async {
    setState(() => _busy = true);
    final paid = await payOnline(context, start: () => PaymentService.instance.depositCheckout(_id));
    if (!mounted) return;
    setState(() => _busy = false);
    if (paid) snack(context, 'Deposit paid successfully');
    await widget.onChanged();
  }

  /// Downloads the payment receipt or (refund = true) the refund receipt into the phone's Downloads.
  Future<void> _receipt({bool refund = false}) async {
    setState(() => _busy = true);
    try {
      final bytes = refund
          ? await LeaseService.instance.depositRefundReceiptPdf(_id)
          : await LeaseService.instance.depositReceiptPdf(_id);
      if (!mounted) return;
      await savePdfToDownloads(context, bytes, refund ? 'deposit-refund-receipt' : 'deposit-receipt');
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Long ids are shortened on screen (the full id is on the receipt).
  String _short(String ref) => ref.length > 16 ? '${ref.substring(0, 6)}...${ref.substring(ref.length - 6)}' : ref;

  Future<void> _refundOnline(Deposit d) async {
    final ok = await confirmDialog(
      context,
      'Refund in the app',
      '${inr(d.refundAmount)} will be refunded to ${widget.lease.tenantName}\'s original payment method (the UPI, card or bank they paid the deposit with). It can take a few days to reach them.',
      yes: 'Refund now',
    );
    if (!ok) return;
    await _run(() => LeaseService.instance.refundDepositOnline(_id), 'Refund started');
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InfoRow('Deposit amount', inr(d.amount)),
                  if (d.paymentMethod.isNotEmpty) InfoRow('Paid via', prettify(d.paymentMethod)),
                  if (d.reference.isNotEmpty) InfoRow('Payment ID', _short(d.reference)),
                  if (d.receivedAt != null) InfoRow('Paid on', fmtDateTime(d.receivedAt)),
                  if (d.status == 'refunded') ...[
                    const Divider(height: 20),
                    InfoRow('Refund amount', inr(d.refundAmount), valueColor: AppColors.success),
                    if (d.refundMethod.isNotEmpty)
                      InfoRow('Refunded via', d.refundMethod == 'online_refund' ? 'Online (original payment method)' : prettify(d.refundMethod)),
                    if (d.refundReference.isNotEmpty) InfoRow('Refund ID', _short(d.refundReference)),
                    if (d.refundedAt != null) InfoRow('Refunded on', fmtDateTime(d.refundedAt)),
                  ],
                  if (d.paymentMethod.isNotEmpty && d.status != 'pending' && d.status != 'submitted' && d.status != 'carried_forward') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _receipt(),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Download payment receipt'),
                      ),
                    ),
                  ],
                  if (d.status == 'refunded') ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : () => _receipt(refund: true),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Download refund receipt'),
                      ),
                    ),
                  ],
                ]),
              ),
              _statusBlock(d),
              _suggestions(d),
              if (d.deductions.isNotEmpty || d.status == 'inspection' || _showTotals(d)) _deductions(d),
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

  /// One simple card: deposit - deductions = refund.
  Widget _deductions(Deposit d) {
    final canEdit = _owner && d.status == 'inspection';
    final inspecting = d.status == 'inspection';
    final refund = inspecting ? d.previewRefund : d.refundAmount;
    final totals = _showTotals(d);
    return SectionCard(
      title: 'Deductions & refund',
      trailing: canEdit ? TextButton.icon(onPressed: _busy ? null : _addDeduction, icon: const Icon(Icons.add, size: 18), label: const Text('Add')) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InfoRow('Deposit amount', inr(d.amount)),
        const SizedBox(height: 4),
        if (d.deductions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('No deductions - the full deposit comes back.', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
          )
        else
          for (final x in d.deductions)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  StatusPill(prettify(x.category), AppColors.primary),
                  const Spacer(),
                  Text('- ${inr(x.amount)}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.error)),
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
            ),
        if (totals) ...[
          const Divider(height: 24),
          InfoRow('Total deductions', '- ${inr(d.totalDeductions)}', valueColor: d.totalDeductions > 0 ? AppColors.error : null),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inspecting ? 'Refund to tenant (so far)' : 'Refund to tenant', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(inr(refund), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.success)),
              const SizedBox(height: 2),
              Text('${inr(d.amount)} deposit - ${inr(d.totalDeductions)} deductions = ${inr(refund)}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          if (d.tenantOwes > 0) InfoRow('Tenant still owes', inr(d.tenantOwes), valueColor: AppColors.error),
        ],
      ]),
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
            ? Column(children: [
                btn('Pay deposit ${inr(d.amount)}', () => _payOnline(d)),
                btn('Cash / other', () => _tenantPay(d), outlined: true),
              ])
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
                const InfoBanner('Deductions for unpaid rent and short notice are already added. Remove any that are wrong, add anything else (damage needs a photo), then send the settlement. The tenant sees everything before it is final.', icon: Icons.fact_check_outlined),
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
        if (d.refundInProgress) {
          return InfoBanner(
            _owner
                ? 'Refund of ${inr(d.refundAmount)} is being processed. It goes back to the tenant\'s original payment method.'
                : 'Your refund of ${inr(d.refundAmount)} is being processed. It goes back to the payment method you paid the deposit with.',
            color: AppColors.warning,
            icon: Icons.sync,
          );
        }
        if (!_owner) {
          return InfoBanner('Settlement agreed. The owner will refund ${inr(d.refundAmount)}.', color: AppColors.warning, icon: Icons.payments_outlined);
        }
        if (d.onlineRefundStatus == 'FAILED' || d.onlineRefundStatus == 'CANCELLED') {
          return Column(children: [
            const InfoBanner('The last refund did not go through. You can try again.', color: AppColors.error, icon: Icons.error_outline),
            if (d.canRefundOnline) btn('Try refund again', () => _refundOnline(d)),
            btn('I refunded outside the app', () => _refund(d), outlined: true),
          ]);
        }
        return Column(children: [
          InfoBanner(
            d.canRefundOnline
                ? 'Refund ${inr(d.refundAmount)} to ${widget.lease.tenantName}. The tenant paid in the app, so you can refund it from here in one tap.'
                : 'Refund ${inr(d.refundAmount)} to ${widget.lease.tenantName}, then record it here.',
            color: AppColors.warning,
            icon: Icons.payments_outlined,
          ),
          if (d.canRefundOnline) btn('Refund ${inr(d.refundAmount)} in the app', () => _refundOnline(d)),
          btn(d.canRefundOnline ? 'I refunded outside the app' : 'Record refund', () => _refund(d), outlined: d.canRefundOnline),
        ]);
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
  final List<XFile> _photos = []; // photos and videos
  final Set<String> _videoPaths = {};
  String? _error;

  static const _maxItems = 6;
  static const _maxVideos = 2;
  static const _maxVideoBytes = 30 * 1024 * 1024; // keep in step with the server (30 MB)

  static const _cats = {'damage': 'Damage', 'unpaid_rent': 'Unpaid rent', 'cleaning': 'Cleaning', 'other': 'Other'};

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Camera / gallery for photos and videos.
  Future<void> _pick() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, 'camera_photo')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose photos from gallery'), onTap: () => Navigator.pop(ctx, 'gallery_photos')),
          ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Record video (up to 15 sec)'), onTap: () => Navigator.pop(ctx, 'camera_video')),
          ListTile(leading: const Icon(Icons.video_library_outlined), title: const Text('Choose video from gallery'), onTap: () => Navigator.pop(ctx, 'gallery_video')),
        ]),
      ),
    );
    if (choice == null) return;
    final picker = ImagePicker();
    try {
      switch (choice) {
        case 'camera_photo':
          final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
          if (f != null) _add([f]);
        case 'gallery_photos':
          final fs = await picker.pickMultiImage(imageQuality: 80, limit: _maxItems);
          _add(fs);
        case 'camera_video':
          final f = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 15));
          if (f != null) await _addVideo(f);
        case 'gallery_video':
          final f = await picker.pickVideo(source: ImageSource.gallery);
          if (f != null) await _addVideo(f);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera or gallery. Check the app permissions.');
    }
  }

  void _add(List<XFile> files) {
    if (files.isEmpty) return;
    setState(() {
      _error = null;
      for (final f in files) {
        if (_photos.length >= _maxItems) {
          _error = 'You can add up to $_maxItems photos or videos.';
          break;
        }
        _photos.add(f);
      }
    });
  }

  Future<void> _addVideo(XFile f) async {
    if (_videoPaths.length >= _maxVideos) {
      setState(() => _error = 'You can add up to $_maxVideos videos.');
      return;
    }
    if (await f.length() > _maxVideoBytes) {
      setState(() => _error = 'This video is too large (max 30 MB). Record a shorter one.');
      return;
    }
    _videoPaths.add(f.path);
    _add([f]);
  }

  void _submit() {
    final amt = double.tryParse(_amount.text.trim());
    if (_reason.text.trim().length < 3) return setState(() => _error = 'Write the reason for this deduction');
    if (amt == null || amt <= 0) return setState(() => _error = 'Enter a valid amount');
    if (_category == 'damage' && _photos.isEmpty) return setState(() => _error = 'Add at least one photo or video as proof of the damage');
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
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_photos.isEmpty
                ? (_category == 'damage' ? 'Add proof: photo / video (required)' : 'Add photo / video (optional)')
                : 'Add more (${_photos.length}/$_maxItems)'),
          ),
          if (_photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final f in _photos)
                  InputChip(
                    avatar: Icon(_videoPaths.contains(f.path) ? Icons.videocam_outlined : Icons.image_outlined, size: 18),
                    label: Text(_videoPaths.contains(f.path) ? 'Video' : 'Photo'),
                    onDeleted: () => setState(() {
                      _videoPaths.remove(f.path);
                      _photos.remove(f);
                    }),
                  ),
              ]),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submit, child: const Text('Add deduction'))),
        ]),
      ),
    );
  }
}