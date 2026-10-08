import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/router/route_names.dart';
import '../../app/theme/app_colors.dart';
import '../../core/api/token_store.dart';
import '../lease/lease_service.dart';
import 'agreement.dart';
import 'agreement_service.dart';
import 'agreement_status_widgets.dart';

/// Agreement status (spec 12.5): Pending -> Approved / Rejected -> Signed ->
/// Expired / Cancelled. Shows a timeline, who signed, the deadline, why an
/// agreement was closed, and the actions the current user may take
/// (continue, reject, cancel, request again).
/// Always fetches fresh from the backend; pull down to refresh.
class AgreementStatusScreen extends StatefulWidget {
  final String agreementId;

  const AgreementStatusScreen({super.key, required this.agreementId});

  @override
  State<AgreementStatusScreen> createState() => _AgreementStatusScreenState();
}

enum _StepState { done, current, upcoming, closed }

class _Step {
  final String label;
  final String? detail;
  final IconData icon;
  final _StepState state;
  final Color? color;
  const _Step(this.label, this.icon, this.state, {this.detail, this.color});
}

class _AgreementStatusScreenState extends State<AgreementStatusScreen> {
  Agreement? _agreement;
  String? _currentUserId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _isOwner => _currentUserId != null && _currentUserId == _agreement?.ownerId;
  bool get _isTenant => _currentUserId != null && _currentUserId == _agreement?.tenantId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final userId = await TokenStore.instance.getUserId();
      final agreement = await AgreementService.instance.getById(widget.agreementId);
      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _agreement = agreement;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _agreement != null) {
        _snack(e.toString().replaceFirst('Exception: ', ''));
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- timeline -----------------------------------------------------------

  String _signerLine(String role, bool signed, DateTime? at) {
    if (!signed) return '$role: waiting to sign';
    return at != null ? '$role: signed on ${formatAgreementDate(at)}' : '$role: signed';
  }

  List<_Step> _buildSteps(Agreement a) {
    final status = a.status;
    final closed = status.isClosedWithoutSigning;
    final anySigned = a.ownerHasSigned || a.tenantHasSigned;

    // How many of the 4 stages are fully behind us.
    int done;
    if (status == AgreementStatus.completed) {
      done = 4;
    } else if (closed) {
      done = (anySigned || a.hasDraft) ? 2 : 1;
    } else if (status == AgreementStatus.requested) {
      done = 1;
    } else {
      done = 2; // approved, now collecting signatures
    }

    final signDetail = [
      _signerLine('Owner', a.ownerHasSigned, a.ownerSignedAt),
      _signerLine('Tenant', a.tenantHasSigned, a.tenantSignedAt),
    ].join('\n');

    final base = <_Step>[
      _Step('Pending', Icons.hourglass_top_rounded, _StepState.upcoming,
          detail: a.createdAt != null ? 'Requested on ${formatAgreementDate(a.createdAt!)}' : 'Request sent'),
      const _Step('Approved', Icons.thumb_up_alt_outlined, _StepState.upcoming,
          detail: 'Owner accepted and the draft is ready'),
      _Step('Signatures', Icons.edit_outlined, _StepState.upcoming, detail: signDetail),
      const _Step('Signed', Icons.verified_outlined, _StepState.upcoming,
          detail: 'Both parties signed. The agreement is final.'),
    ];

    final steps = <_Step>[];
    for (var i = 0; i < base.length; i++) {
      // Nothing after the point it stopped; keep the signatures stage visible if
      // someone had already signed, so their signature is not hidden.
      if (closed && i >= done && !(i == 2 && anySigned)) break;
      final b = base[i];
      final st = i < done
          ? _StepState.done
          : (i == done ? _StepState.current : _StepState.upcoming);
      // Only show signer detail once that stage is reached.
      final detail = (i == 2 && st == _StepState.upcoming) ? null : b.detail;
      steps.add(_Step(b.label, b.icon, st, detail: detail));
    }

    if (closed) {
      final by = a.statusChangedByName;
      final reason = a.statusReason;
      final parts = <String>[
        if (status == AgreementStatus.expired) 'Not completed before the deadline',
        if (status != AgreementStatus.expired && by != null) 'By $by',
        if (status != AgreementStatus.expired && reason != null && reason.isNotEmpty) 'Reason: $reason',
        if ((a.statusChangedAt ?? a.updatedAt) != null) formatAgreementDate((a.statusChangedAt ?? a.updatedAt)!),
      ];
      steps.add(_Step(
        status.displayLabel,
        agreementStatusIcon(status),
        _StepState.closed,
        detail: parts.join('\n'),
        color: agreementStatusColor(status),
      ));
    }
    return steps;
  }

  // ---- actions ------------------------------------------------------------

  Future<String?> _askReason({
    required String title,
    required String message,
    required String confirmLabel,
    bool askReason = true,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (askReason) ...[
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmLabel, style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _changeStatus(String status, {required String doneMessage, String? reason}) async {
    setState(() => _busy = true);
    try {
      final updated = await AgreementService.instance.updateStatus(
        id: widget.agreementId,
        status: status,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _agreement = updated;
        _busy = false;
      });
      _snack(doneMessage);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''));
      _load(silent: true); // state may have moved (e.g. expired meanwhile)
    }
  }

  Future<void> _reject() async {
    final reason = await _askReason(
      title: 'Reject this agreement?',
      message: 'The tenant will be told it was rejected. This cannot be undone.',
      confirmLabel: 'Reject',
    );
    if (reason == null) return;
    await _changeStatus('rejected', doneMessage: 'Agreement rejected.', reason: reason);
  }

  Future<void> _cancel() async {
    final reason = await _askReason(
      title: 'Cancel this agreement?',
      message: 'The other party will be told it was cancelled. This cannot be undone.',
      confirmLabel: 'Cancel agreement',
    );
    if (reason == null) return;
    await _changeStatus('cancelled', doneMessage: 'Agreement cancelled.', reason: reason);
  }

  Future<void> _openDraft() async {
    await context.push(RouteNames.agreementDraft.replaceFirst(':id', widget.agreementId));
    if (mounted) _load(silent: true);
  }

  Future<void> _openLease(Agreement a) async {
    try {
      final lease = await LeaseService.instance.leaseForAgreement(a.id);
      if (!mounted) return;
      context.push('/lease/${lease.id}');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _requestAgain(Agreement a) {
    context.push(
      RouteNames.agreementRequest.replaceFirst(':id', a.propertyId),
      extra: {
        'propertyTitle': a.propertyTitle,
        'propertyImageUrl': a.propertyImageUrl,
        'counterpartyName': _isOwner ? a.tenantName : a.ownerName,
        'ownerId': a.ownerId,
        'tenantId': a.tenantId,
      },
    );
  }

  String _primaryLabel(Agreement a) {
    final iSigned = _isOwner ? a.ownerHasSigned : a.tenantHasSigned;
    if (a.status == AgreementStatus.requested) {
      return _isOwner ? 'Approve & prepare draft' : 'View request';
    }
    if (iSigned) return 'View agreement';
    return 'Review & sign';
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Agreement Status', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.textHint, size: 40),
                          const SizedBox(height: 12),
                          Text('Could not load agreement.\n$_error', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(silent: true),
                    child: _buildContent(_agreement!),
                  ),
      ),
    );
  }

  Widget _buildContent(Agreement a) {
    final steps = _buildSteps(a);
    final status = a.status;
    final isParty = _isOwner || _isTenant;
    final canReject = _isOwner &&
        const {
          AgreementStatus.requested,
          AgreementStatus.draftReady,
          AgreementStatus.awaitingSignatures,
        }.contains(status);
    final canCancel = isParty && !status.isFinal;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.propertyTitle, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${a.ownerName} ↔ ${a.tenantName}',
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AgreementStatusChip(status: status),
          ],
        ),
        AgreementExpiryNote(agreement: a),
        const SizedBox(height: 22),
        AgreementClosedBanner(agreement: a),
        for (var i = 0; i < steps.length; i++) _timelineTile(steps[i], isLast: i == steps.length - 1),
        const SizedBox(height: 8),
        if (status == AgreementStatus.completed) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Both parties have signed. The agreement is finalized.',
                    style: GoogleFonts.inter(color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.home_work_outlined),
              label: const Text('View lease & rent'),
              onPressed: () => _openLease(a),
            ),
          ),
        ] else if (!status.isFinal && isParty) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _openDraft,
              child: Text(_primaryLabel(a)),
            ),
          ),
          if (canReject) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: _busy ? null : _reject,
                child: const Text('Reject agreement'),
              ),
            ),
          ],
          if (canCancel) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : _cancel,
                child: Text('Cancel agreement',
                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ] else if (status.isClosedWithoutSigning && isParty) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _requestAgain(a),
              child: const Text('Request a new agreement'),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => context.push(RouteNames.propertyDetail.replaceFirst(':id', a.propertyId)),
              child: const Text('View property'),
            ),
          ),
        ],
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ],
    );
  }

  Widget _timelineTile(_Step step, {required bool isLast}) {
    final Color accent = step.color ?? AppColors.primary;
    final bool done = step.state == _StepState.done;
    final bool current = step.state == _StepState.current;
    final bool closed = step.state == _StepState.closed;

    final Color fill = (done || closed) ? accent : (current ? Colors.white : AppColors.surfaceSoft);
    final Color border = (done || closed || current) ? accent : AppColors.border;
    final Color iconColor = (done || closed) ? Colors.white : (current ? accent : AppColors.textHint);
    final bool lit = done; // connector below a finished step is coloured

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: border, width: current ? 2 : 1),
                ),
                child: Icon(step.icon, size: 18, color: iconColor),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: lit ? AppColors.primary : AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: (done || current || closed) ? FontWeight.w600 : FontWeight.w400,
                      color: closed
                          ? accent
                          : ((done || current) ? AppColors.textPrimary : AppColors.textHint),
                    ),
                  ),
                  if (step.detail != null && step.detail!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      step.detail!,
                      style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}