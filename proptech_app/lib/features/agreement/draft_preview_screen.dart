import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../core/api/token_store.dart';
import '../../core/widgets/app_button.dart';
import 'agreement.dart';
import 'agreement_service.dart';
import 'agreement_status_widgets.dart';
import 'signature_screen.dart';

/// Step 2/3: shows the drafted agreement terms and lets the current user
/// review & sign. Owner sees an editable draft form first time; tenant
/// (or owner after draft is set) sees a read-only preview + sign button.
///
/// Fetches the Agreement fresh from the backend by [agreementId] — isOwner
/// and the current user's display name are derived from that (comparing
/// the logged-in user id to agreement.ownerId/tenantId), so callers only
/// need to pass the id.
class DraftPreviewScreen extends StatefulWidget {
  final String agreementId;

  const DraftPreviewScreen({super.key, required this.agreementId});

  @override
  State<DraftPreviewScreen> createState() => _DraftPreviewScreenState();
}

class _DraftPreviewScreenState extends State<DraftPreviewScreen> {
  Agreement? _agreement;
  String? _currentUserId;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  TextEditingController? _rentController;
  TextEditingController? _depositController;
  TextEditingController? _durationController;
  TextEditingController? _termsController;

  bool get _isOwner => _currentUserId != null && _currentUserId == _agreement?.ownerId;
  String get _currentUserName => _isOwner ? (_agreement?.ownerName ?? '') : (_agreement?.tenantName ?? '');

  // Owner can edit until anyone has signed (backend allows it too), not only on the first save.
  bool get _isDraftEditable =>
      _isOwner &&
      !(_agreement?.ownerHasSigned ?? false) &&
      !(_agreement?.tenantHasSigned ?? false) &&
      const {
        AgreementStatus.requested,
        AgreementStatus.draftReady,
        AgreementStatus.awaitingSignatures,
      }.contains(_agreement?.status);

  // Rejected / cancelled / expired: read-only, no signing.
  bool get _isClosed => _agreement?.status.isClosedWithoutSigning ?? false;

  // The owner has not filled in the draft yet, so there is nothing to sign.
  bool get _waitingForOwner => !_isOwner && _agreement?.status == AgreementStatus.requested;
  bool get _hasSignedAlready =>
      _isOwner ? (_agreement?.ownerHasSigned ?? false) : (_agreement?.tenantHasSigned ?? false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final userId = await TokenStore.instance.getUserId();
      final agreement = await AgreementService.instance.getById(widget.agreementId);
      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _agreement = agreement;
        _rentController = TextEditingController(text: agreement.monthlyRent?.toStringAsFixed(0) ?? '');
        _depositController = TextEditingController(text: agreement.securityDeposit?.toStringAsFixed(0) ?? '');
        _durationController = TextEditingController(text: agreement.durationMonths?.toString() ?? '11');
        _termsController = TextEditingController(
          text: agreement.terms ??
              'This rental agreement is entered into between the Owner and the Tenant for the '
                  'property "${agreement.propertyTitle}". The tenant agrees to pay the monthly rent and '
                  'security deposit as specified, for the duration mentioned above, subject to '
                  'standard terms and conditions.',
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _rentController?.dispose();
    _depositController?.dispose();
    _durationController?.dispose();
    _termsController?.dispose();
    super.dispose();
  }

  /// Server says KYC is missing: offer to do it now. After KYC the user taps Sign again.
  Future<void> _promptKyc() async {
    if (!mounted) return;
    final goKyc = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('KYC required'),
        content: const Text('Complete Aadhaar KYC before signing this agreement. It only takes a minute.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verify now')),
        ],
      ),
    );
    if (goKyc == true && mounted) await context.push(RouteNames.kycVerification);
  }

  /// Sends an OTP to the signer's email and asks for it. true = verified.
  Future<bool> _verifySignOtp() async {
    final role = _isOwner ? 'owner' : 'tenant';
    try {
      await AgreementService.instance.sendSignOtp(id: widget.agreementId, signerRole: role);
    } on KycRequiredException {
      await _promptKyc();
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return false;
    }
    if (!mounted) return false;

    final codeController = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Verify OTP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('We emailed a 6-digit code to your account email.'),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(counterText: '', errorText: error, hintText: '------'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                try {
                  await AgreementService.instance.verifySignOtp(
                    id: widget.agreementId,
                    signerRole: role,
                    code: codeController.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setLocal(() => error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );
    codeController.dispose();
    return ok == true;
  }

  Future<void> _openSignatureScreen() async {
    if (!await _verifySignOtp()) return;
    if (!mounted) return;
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => SignatureScreen(
          agreementId: widget.agreementId,
          signerName: _currentUserName,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final updated = await AgreementService.instance.sign(
        id: widget.agreementId,
        signerRole: _isOwner ? 'owner' : 'tenant',
        signatureType: result['signatureType']!,
        signatureData: result['signatureData']!,
      );
      if (!mounted) return;
      setState(() {
        _agreement = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.status == AgreementStatus.completed
                ? 'Both parties have signed — agreement completed!'
                : 'Signature saved.',
          ),
        ),
      );
    } on KycRequiredException {
      if (!mounted) return;
      setState(() => _saving = false);
      await _promptKyc();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save signature: $e')),
      );
    }
  }

  Future<void> _saveDraftAndContinue() async {
    if (_termsController == null) return;
    setState(() => _saving = true);
    try {
      final updated = await AgreementService.instance.updateDraft(
        id: widget.agreementId,
        monthlyRent: double.tryParse(_rentController!.text),
        securityDeposit: double.tryParse(_depositController!.text),
        durationMonths: int.tryParse(_durationController!.text),
        terms: _termsController!.text,
      );
      if (!mounted) return;
      setState(() {
        _agreement = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved. Sent for signature.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save draft: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Agreement Draft', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Agreement status',
            icon: const Icon(Icons.timeline_outlined),
            onPressed: () => context.push(RouteNames.agreementStatus.replaceFirst(':id', widget.agreementId)),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.textHint, size: 40),
                          const SizedBox(height: 12),
                          Text('Could not load agreement.\n$_loadError', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _isOwner
                                        ? (_isDraftEditable
                                            ? 'Logged in as Owner (you can edit)'
                                            : (_isClosed ? 'Logged in as Owner (agreement closed)' : 'Logged in as Owner (locked, already signed)'))
                                        : 'Logged in as Tenant (view only, only the owner edits the draft)',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                                  ),
                                ),
                                Row(
                                  children: [
                                    AgreementStatusChip(status: _agreement!.status),
                                    const Spacer(),
                                  ],
                                ),
                                AgreementExpiryNote(agreement: _agreement!),
                                const SizedBox(height: 12),
                                AgreementClosedBanner(agreement: _agreement!),
                                if (_waitingForOwner) ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Waiting for the owner to fill in the rent, deposit and terms. You can sign once the draft is ready.',
                                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.warning, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: _field('Monthly Rent (₹)', _rentController!, editable: _isDraftEditable),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _field('Security Deposit (₹)', _depositController!, editable: _isDraftEditable),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _field('Duration (months)', _durationController!, editable: _isDraftEditable),
                                const SizedBox(height: 14),
                                Text('Terms', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _termsController,
                                  readOnly: !_isDraftEditable,
                                  onTap: _isDraftEditable ? null : _explainReadOnly,
                                  maxLines: 8,
                                  style: GoogleFonts.inter(fontSize: 13.5, height: 1.5),
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: AppColors.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(12)),
                                      borderSide: BorderSide(color: AppColors.border),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildSignatureStatusRow(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_isDraftEditable)
                          AppButton(
                            label: 'Save Draft & Send for Signature',
                            onPressed: _saving ? null : _saveDraftAndContinue,
                          )
                        else if (_isClosed)
                          AppButton(
                            label: 'Agreement ${_agreement!.status.displayLabel.toLowerCase()}',
                            onPressed: null,
                          )
                        else
                          AppButton(
                            label: _waitingForOwner
                                ? 'Waiting for owner'
                                : (_hasSignedAlready ? 'You already signed' : 'Review & Sign Agreement'),
                            onPressed: (_hasSignedAlready || _saving || _waitingForOwner) ? null : _openSignatureScreen,
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  void _explainReadOnly() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(_isClosed
            ? 'This agreement is ${_agreement!.status.displayLabel.toLowerCase()}, so it can no longer be edited.'
            : _isOwner
            ? 'This draft is locked because a party has already signed.'
            : 'Only the owner can edit the draft. Log in as the owner to fill it in.'),
      ));
  }

  Widget _field(String label, TextEditingController controller, {required bool editable}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: !editable,
          onTap: editable ? null : _explainReadOnly,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureStatusRow() {
    final a = _agreement!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _signatureRow('Owner (${a.ownerName})', a.ownerHasSigned),
          const SizedBox(height: 10),
          _signatureRow('Tenant (${a.tenantName})', a.tenantHasSigned),
        ],
      ),
    );
  }

  Widget _signatureRow(String label, bool signed) {
    return Row(
      children: [
        Icon(
          signed ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: signed ? AppColors.success : AppColors.textHint,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13))),
        Text(
          signed ? 'Signed' : 'Pending',
          style: GoogleFonts.inter(fontSize: 12, color: signed ? AppColors.success : AppColors.textHint),
        ),
      ],
    );
  }
}