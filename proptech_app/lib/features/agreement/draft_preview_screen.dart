import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../core/api/token_store.dart';
import '../../core/widgets/app_button.dart';
import 'agreement.dart';
import 'agreement_service.dart';
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

  bool get _isDraftEditable => _isOwner && _agreement?.status == AgreementStatus.requested;
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

  Future<void> _openSignatureScreen() async {
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
                        else
                          AppButton(
                            label: _hasSignedAlready ? 'You already signed' : 'Review & Sign Agreement',
                            onPressed: (_hasSignedAlready || _saving) ? null : _openSignatureScreen,
                          ),
                      ],
                    ),
                  ),
      ),
    );
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