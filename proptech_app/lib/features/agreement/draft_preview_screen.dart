import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Stored in `terms` when the owner adds nothing extra (the backend requires a non-empty value).
const _kNoExtraTerms = 'No additional terms.';

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_monthNames[d.month - 1]} ${d.year}';

/// 125000 -> 1,25,000 (Indian grouping).
String _inr(double v) {
  final s = v.round().toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

class _Clause {
  final String title, short, full;
  const _Clause(this.title, this.short, this.full);
}

/// Step 2/3: shows the drafted agreement and lets the current user review & sign.
/// The owner fills the details (address, rent, deposit, duration, start date,
/// notice period, rent due day, extra terms) until someone signs; the tenant sees
/// a read-only version.
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

  TextEditingController? _addressController;
  TextEditingController? _rentController;
  TextEditingController? _depositController;
  TextEditingController? _durationController;
  TextEditingController? _noticeController;
  TextEditingController? _dueDayController;
  TextEditingController? _termsController; // "additional terms"
  DateTime? _startDate;

  final Set<int> _expanded = {};

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
  bool get _hasSignedAlready => _isOwner ? (_agreement?.ownerHasSigned ?? false) : (_agreement?.tenantHasSigned ?? false);

  // ---- live values (always read from the controllers, which start from the saved agreement)
  double? get _rent => double.tryParse(_rentController?.text.trim() ?? '');
  double? get _deposit => double.tryParse(_depositController?.text.trim() ?? '');
  int? get _months => int.tryParse(_durationController?.text.trim() ?? '');
  int? get _notice => int.tryParse(_noticeController?.text.trim() ?? '');
  int? get _dueDay => int.tryParse(_dueDayController?.text.trim() ?? '');
  String get _address => _addressController?.text.trim() ?? '';
  String get _extraTerms {
    final t = _termsController?.text.trim() ?? '';
    return t == _kNoExtraTerms ? '' : t;
  }

  DateTime? get _endDate {
    if (_startDate == null || _months == null) return null;
    final s = _startDate!;
    return DateTime(s.year, s.month + _months!, s.day).subtract(const Duration(days: 1));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  TextEditingController _ctl(String text) {
    final c = TextEditingController(text: text);
    c.addListener(_onChanged);
    return c;
  }

  void _disposeControllers() {
    _addressController?.dispose();
    _rentController?.dispose();
    _depositController?.dispose();
    _durationController?.dispose();
    _noticeController?.dispose();
    _dueDayController?.dispose();
    _termsController?.dispose();
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
      final now = DateTime.now();
      setState(() {
        _disposeControllers();
        _currentUserId = userId;
        _agreement = agreement;
        _addressController = _ctl(agreement.propertyAddress ?? '');
        _rentController = _ctl(agreement.monthlyRent?.toStringAsFixed(0) ?? '');
        _depositController = _ctl(agreement.securityDeposit?.toStringAsFixed(0) ?? '');
        _durationController = _ctl(agreement.durationMonths?.toString() ?? '11');
        _noticeController = _ctl((agreement.noticePeriodDays ?? 30).toString());
        _dueDayController = _ctl((agreement.rentDueDay ?? 5).toString());
        final t = agreement.terms;
        _termsController = _ctl((t == null || t == _kNoExtraTerms) ? '' : t);
        _startDate = agreement.startDate ?? DateTime(now.year, now.month + 1, 1);
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
    _disposeControllers();
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

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveDraftAndContinue() async {
    if (_termsController == null) return;

    // ---- validate before calling the server
    if (_address.length < 10) {
      _toast('Please enter the full property address (house/flat no., building, area, city, PIN).');
      return;
    }
    if ((_rent ?? 0) <= 0) {
      _toast('Enter the monthly rent.');
      return;
    }
    if (_deposit == null || _deposit! < 0) {
      _toast('Enter the security deposit (0 if none).');
      return;
    }
    if (_months == null || _months! < 1 || _months! > 120) {
      _toast('Duration must be between 1 and 120 months.');
      return;
    }
    if (_dueDay == null || _dueDay! < 1 || _dueDay! > 28) {
      _toast('Rent due day must be between 1 and 28.');
      return;
    }
    if (_notice == null || _notice! < 0 || _notice! > 365) {
      _toast('Notice period must be between 0 and 365 days.');
      return;
    }
    if (_startDate == null) {
      _toast('Pick the agreement start date.');
      return;
    }

    final s = _startDate!;
    final startIso = '${s.year.toString().padLeft(4, '0')}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';

    setState(() => _saving = true);
    try {
      final updated = await AgreementService.instance.updateDraft(
        id: widget.agreementId,
        monthlyRent: _rent,
        securityDeposit: _deposit,
        startDate: startIso,
        durationMonths: _months,
        terms: _extraTerms.isEmpty ? _kNoExtraTerms : _extraTerms,
        propertyAddress: _address,
        noticePeriodDays: _notice,
        rentDueDay: _dueDay,
      );
      if (!mounted) return;
      setState(() {
        _agreement = updated;
        _saving = false;
      });
      _toast('Draft saved. Sent for signature.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save draft: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  // =====================================================================
  // Clauses (standard wording filled with this agreement's numbers)
  // =====================================================================

  List<_Clause> _clauses() {
    final due = _dueDay;
    final notice = _notice;
    final dueText = due == null ? 'the due date mentioned above' : 'the ${_ordinal(due)} day of every month';
    final noticeText = notice == null ? 'written notice' : "$notice days' written notice";
    final rentText = _rent == null ? 'the monthly rent' : 'the monthly rent of ₹${_inr(_rent!)}';
    final depositText = _deposit == null ? 'the security deposit' : 'a security deposit of ₹${_inr(_deposit!)}';

    final list = <_Clause>[
      const _Clause(
        'Use of Premises',
        'The premises shall be used only for residential purposes. Subletting or transfer is not allowed.',
        'The Tenant shall use the premises strictly for residential purposes only. The Tenant shall not sublet, '
            'assign or transfer possession of the premises or any part of it to any other person, and shall not '
            'carry out any illegal or commercial activity on the premises.',
      ),
      _Clause(
        'Payment of Rent',
        'Rent shall be paid in advance on or before $dueText.',
        'The Tenant shall pay $rentText in advance on or before $dueText. Rent is paid directly to the Owner '
            'by UPI, and the payment proof (UTR and screenshot) is recorded on the platform for both parties.',
      ),
      const _Clause(
        'Maintenance & Utilities',
        'Tenant shall be responsible for electricity, water, internet and other utility charges.',
        'The Tenant shall pay all electricity, water, gas, internet and other utility charges for the period of '
            'stay, and shall keep the premises in good condition. Major structural repairs remain the responsibility '
            'of the Owner.',
      ),
      _Clause(
        'Security Deposit',
        'The deposit will be refunded within 30 days after vacating the premises, subject to deductions for any damages or unpaid dues.',
        'The Tenant shall pay $depositText, which is refundable and interest-free. The Owner shall refund it within '
            '30 days after the Tenant vacates and hands over the premises, after deducting any unpaid rent, utility '
            'dues or the cost of damage beyond normal wear and tear.',
      ),
      _Clause(
        'Termination',
        'Either party may terminate this agreement by giving $noticeText.',
        'Either the Owner or the Tenant may terminate this agreement by giving the other party $noticeText. '
            'On termination the Tenant shall vacate and hand over the premises in good condition.',
      ),
      const _Clause(
        'Dispute Resolution',
        'Any disputes shall be resolved amicably. Jurisdiction will be the courts of the city where the property is located.',
        'The parties shall first try to resolve any dispute amicably through discussion. If it cannot be resolved, '
            'it shall be subject to the jurisdiction of the courts of the city where the property is located.',
      ),
    ];
    if (_extraTerms.isNotEmpty) {
      list.add(_Clause('Additional Terms', _extraTerms, _extraTerms));
    }
    return list;
  }

  // =====================================================================
  // UI
  // =====================================================================

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
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _roleBanner(),
                              AgreementClosedBanner(agreement: _agreement!),
                              if (_waitingForOwner) _waitingBanner(),
                              _headerCard(),
                              if (_isDraftEditable) _editCard(),
                              _summaryCard(),
                              _keyTermsCard(),
                              _signatureCard(),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: _bottomButton(),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _bottomButton() {
    if (_isDraftEditable) {
      return AppButton(
        label: 'Save Draft & Send for Signature',
        onPressed: _saving ? null : _saveDraftAndContinue,
      );
    }
    if (_isClosed) {
      return AppButton(label: 'Agreement ${_agreement!.status.displayLabel.toLowerCase()}', onPressed: null);
    }
    return AppButton(
      label: _waitingForOwner ? 'Waiting for owner' : (_hasSignedAlready ? 'You already signed' : 'Review & Sign Agreement'),
      onPressed: (_hasSignedAlready || _saving || _waitingForOwner) ? null : _openSignatureScreen,
    );
  }

  // ---- small building blocks ----

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _sectionTitle(String t) => Text(
        t,
        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary),
      );

  InputDecoration _dec({String? hint, String? prefix}) {
    const side = BorderSide(color: AppColors.border);
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textHint),
      prefixText: prefix,
      isDense: true,
      counterText: '',
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: side),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: side),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _roleBanner() {
    final text = _isOwner
        ? (_isDraftEditable
            ? 'Logged in as Owner (you can edit the draft)'
            : (_isClosed ? 'Logged in as Owner (agreement closed)' : 'Logged in as Owner (locked, already signed)'))
        : 'Logged in as Tenant (view only, only the owner edits the draft)';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _waitingBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Waiting for the owner to fill in the address, rent, deposit and terms. You can sign once the draft is ready.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.warning, fontWeight: FontWeight.w500),
        ),
      );

  // ---- header (title, ids, status, address + parties) ----

  Widget _docBadge() => SizedBox(
        width: 64,
        height: 78,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 58,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.description_outlined, size: 34, color: AppColors.textHint),
            ),
            const Positioned(right: 0, bottom: 0, child: Icon(Icons.workspace_premium, size: 28, color: AppColors.primary)),
          ],
        ),
      );

  Widget _headerCard() {
    final a = _agreement!;
    final isFinal = a.status == AgreementStatus.completed;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _docBadge(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFinal ? 'RESIDENTIAL RENTAL AGREEMENT' : 'RESIDENTIAL RENTAL AGREEMENT – DRAFT',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text('Agreement ID: ${a.agreementNumber}', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      '${isFinal ? 'Created' : 'Draft created'} on: ${a.createdAt == null ? '—' : formatAgreementDate(a.createdAt!)}',
                      style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgreementStatusChip(status: a.status),
              const SizedBox(width: 12),
              Flexible(child: AgreementExpiryNote(agreement: a)),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppColors.border)),
          _addressAndParties(),
        ],
      ),
    );
  }

  Widget _addressAndParties() {
    final a = _agreement!;

    final addressBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('Property Address', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        if (_isDraftEditable)
          TextField(
            controller: _addressController,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.inter(fontSize: 14, height: 1.4),
            decoration: _dec(hint: 'Flat / house no., building, area, city, PIN code'),
          )
        else
          Text(
            _address.isEmpty ? (_isOwner ? 'Not added yet' : 'The owner has not added the address yet') : _address,
            style: GoogleFonts.inter(fontSize: 14, height: 1.45, color: _address.isEmpty ? AppColors.textHint : AppColors.textPrimary),
          ),
        if (!_isDraftEditable && _address.isEmpty && a.propertyTitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Property: ${a.propertyTitle}', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ],
    );

    final parties = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parties', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          _partyRow('Owner', ' (Landlord)', a.ownerName),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: AppColors.border)),
          _partyRow('Tenant', '', a.tenantName),
        ],
      ),
    );

    if (_isDraftEditable) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [addressBlock, const SizedBox(height: 12), parties]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: addressBlock),
        const SizedBox(width: 12),
        Expanded(flex: 6, child: parties),
      ],
    );
  }

  Widget _partyRow(String role, String roleHint, String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.person_outline, size: 24, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: role,
                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textPrimary),
                  children: [
                    if (roleHint.isNotEmpty) TextSpan(text: roleHint, style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name.isEmpty ? '—' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- owner edit form ----

  Widget _labeled(String label, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          field,
        ],
      );

  Widget _numField(TextEditingController c, {String? prefix, String? hint}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: GoogleFonts.inter(fontSize: 14),
        decoration: _dec(prefix: prefix, hint: hint),
      );

  Widget _dateField() => InkWell(
        onTap: _pickStartDate,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: _dec().copyWith(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary)),
          child: Text(
            _startDate == null ? 'Select date' : _fmt(_startDate!),
            style: GoogleFonts.inter(fontSize: 14, color: _startDate == null ? AppColors.textHint : AppColors.textPrimary),
          ),
        ),
      );

  Widget _editCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Fill in agreement details'),
            const SizedBox(height: 4),
            Text(
              'You can change these until someone signs. The summary below updates as you type.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _labeled('Monthly Rent (₹)', _numField(_rentController!, prefix: '₹ '))),
                const SizedBox(width: 10),
                Expanded(child: _labeled('Security Deposit (₹)', _numField(_depositController!, prefix: '₹ '))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _labeled('Duration (months)', _numField(_durationController!))),
                const SizedBox(width: 10),
                Expanded(child: _labeled('Notice period (days)', _numField(_noticeController!))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _labeled('Rent due day (1-28)', _numField(_dueDayController!))),
                const SizedBox(width: 10),
                Expanded(child: _labeled('Start date', _dateField())),
              ],
            ),
            const SizedBox(height: 12),
            _labeled(
              'Additional terms (optional)',
              TextField(
                controller: _termsController,
                minLines: 3,
                maxLines: 6,
                style: GoogleFonts.inter(fontSize: 13.5, height: 1.4),
                decoration: _dec(hint: 'Any extra conditions, e.g. parking, pets, lock-in period'),
              ),
            ),
          ],
        ),
      );

  // ---- summary tiles ----

  Widget _tile(IconData icon, String label, String value, String sub) => Container(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 9.5, height: 1.3, color: AppColors.textSecondary),
            ),
          ],
        ),
      );

  Widget _summaryCard() {
    final months = _months;
    final notice = _notice;
    final due = _dueDay;
    final end = _endDate;
    final durationSub = (_startDate != null && end != null) ? '${_fmt(_startDate!)} to ${_fmt(end)}' : 'Start date not set';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Agreement Summary'),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _tile(
                    Icons.home_outlined,
                    'Monthly Rent (₹)',
                    _rent == null ? '—' : _inr(_rent!),
                    due == null ? 'Payable every month' : 'Payable on or before ${_ordinal(due)} of every month',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _tile(
                    Icons.shield_outlined,
                    'Security Deposit (₹)',
                    _deposit == null ? '—' : _inr(_deposit!),
                    'Refundable as per terms of agreement',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _tile(
                    Icons.calendar_month_outlined,
                    'Duration',
                    months == null ? '—' : '$months Month${months == 1 ? '' : 's'}',
                    durationSub,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _tile(
                    Icons.notifications_none,
                    'Notice Period',
                    notice == null ? '—' : '$notice Days',
                    notice == null ? 'Either party to give notice' : "Either party to give $notice days' notice",
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- key terms ----

  Widget _keyTermsCard() {
    final clauses = _clauses();
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Key Terms & Conditions')),
              InkWell(
                onTap: _openFullAgreement,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View Full Agreement', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    const SizedBox(width: 4),
                    const Icon(Icons.open_in_new, size: 15, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < clauses.length; i++) _clauseRow(i, clauses[i], last: i == clauses.length - 1),
        ],
      ),
    );
  }

  Widget _clauseRow(int i, _Clause c, {required bool last}) {
    final open = _expanded.contains(i);
    return InkWell(
      onTap: () => setState(() => open ? _expanded.remove(i) : _expanded.add(i)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(8)),
              child: Text('${i + 1}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(
                    open ? c.full : c.short,
                    maxLines: open ? null : 3,
                    overflow: open ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(open ? Icons.keyboard_arrow_up : Icons.chevron_right, size: 22, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _openFullAgreement() {
    final a = _agreement!;
    final clauses = _clauses();
    final end = _endDate;
    TextStyle body() => GoogleFonts.inter(fontSize: 13.5, height: 1.55, color: AppColors.textPrimary);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'RESIDENTIAL RENTAL AGREEMENT',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Agreement ID: ${a.agreementNumber}', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 18),
            Text(
              'This agreement is made between ${a.ownerName.isEmpty ? 'the Owner' : a.ownerName} (the "Owner") and '
              '${a.tenantName.isEmpty ? 'the Tenant' : a.tenantName} (the "Tenant") for the property at: '
              '${_address.isEmpty ? '(address not added yet)' : _address}.',
              style: body(),
            ),
            const SizedBox(height: 12),
            Text(
              'Monthly rent: ${_rent == null ? '—' : '₹${_inr(_rent!)}'}\n'
              'Security deposit: ${_deposit == null ? '—' : '₹${_inr(_deposit!)}'}\n'
              'Duration: ${_months == null ? '—' : '$_months month(s)'}'
              '${(_startDate != null && end != null) ? ' (${_fmt(_startDate!)} to ${_fmt(end)})' : ''}\n'
              'Notice period: ${_notice == null ? '—' : '$_notice days'}',
              style: body().copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < clauses.length; i++) ...[
              Text('${i + 1}. ${clauses[i].title}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(clauses[i].full, style: body()),
              const SizedBox(height: 14),
            ],
            Text(
              'Both parties must sign for this agreement to be valid and enforceable.',
              style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ---- signatures ----

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _signerRow(int n, String role, String name, bool signed, {required Color pendingColor}) {
    final color = signed ? AppColors.success : pendingColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
            child: Text('$n', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(
                  name.isEmpty ? '—' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _pill(signed ? 'Signed' : 'Awaiting Signature', color),
          const SizedBox(width: 8),
          CustomPaint(
            painter: _DashedRectPainter(signed ? AppColors.success : AppColors.textHint),
            child: SizedBox(
              width: 48,
              height: 38,
              child: Icon(signed ? Icons.verified_outlined : Icons.draw_outlined, size: 20, color: signed ? AppColors.success : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _signatureCard() {
    final a = _agreement!;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Signature Status'),
          const SizedBox(height: 6),
          _signerRow(1, 'Owner', a.ownerName, a.ownerHasSigned, pendingColor: AppColors.warning),
          const Divider(height: 1, color: AppColors.border),
          _signerRow(2, 'Tenant', a.tenantName, a.tenantHasSigned, pendingColor: AppColors.primary),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Both parties need to sign to make this agreement valid and enforceable.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed rounded rectangle used for the signature box.
class _DashedRectPainter extends CustomPainter {
  final Color color;
  _DashedRectPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color;
}