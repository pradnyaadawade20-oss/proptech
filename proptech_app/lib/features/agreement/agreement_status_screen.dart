import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import 'agreement.dart';
import 'agreement_service.dart';

/// Step 4: shows the overall status of an agreement as a simple vertical
/// timeline — requested -> draft ready -> signatures -> completed.
/// Fetches fresh from the backend by [agreementId] so status is always
/// current (not a stale snapshot passed in at navigation time).
class AgreementStatusScreen extends StatefulWidget {
  final String agreementId;

  const AgreementStatusScreen({super.key, required this.agreementId});

  @override
  State<AgreementStatusScreen> createState() => _AgreementStatusScreenState();
}

class _AgreementStatusScreenState extends State<AgreementStatusScreen> {
  Agreement? _agreement;
  bool _loading = true;
  String? _error;

  static const _timelineSteps = [
    (AgreementStatus.requested, 'Requested', Icons.send_outlined),
    (AgreementStatus.draftReady, 'Draft ready', Icons.description_outlined),
    (AgreementStatus.awaitingSignatures, 'Awaiting signatures', Icons.edit_outlined),
    (AgreementStatus.completed, 'Completed', Icons.verified_outlined),
  ];

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
      final agreement = await AgreementService.instance.getById(widget.agreementId);
      if (!mounted) return;
      setState(() {
        _agreement = agreement;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _currentStepIndex(AgreementStatus status) {
    switch (status) {
      case AgreementStatus.requested:
        return 0;
      case AgreementStatus.draftReady:
        return 1;
      case AgreementStatus.awaitingSignatures:
      case AgreementStatus.signedByOwner:
      case AgreementStatus.signedByTenant:
        return 2;
      case AgreementStatus.completed:
        return 3;
      case AgreementStatus.rejected:
      case AgreementStatus.cancelled:
        return -1;
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
                : _buildContent(_agreement!),
      ),
    );
  }

  Widget _buildContent(Agreement agreement) {
    final currentIndex = _currentStepIndex(agreement.status);
    final isTerminatedBadly =
        agreement.status == AgreementStatus.rejected || agreement.status == AgreementStatus.cancelled;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(agreement.propertyTitle,
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${agreement.ownerName} ↔ ${agreement.tenantName}',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 28),
          if (isTerminatedBadly)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel_outlined, color: AppColors.error),
                  const SizedBox(width: 10),
                  Text('Agreement ${agreement.status.label.toLowerCase()}',
                      style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else
            ..._timelineSteps.asMap().entries.map((entry) {
              final index = entry.key;
              final (_, label, icon) = entry.value;
              final done = index <= currentIndex;
              final isLast = index == _timelineSteps.length - 1;
              return _timelineTile(label, icon, done: done, isLast: isLast);
            }),
          const SizedBox(height: 12),
          if (agreement.status == AgreementStatus.completed) ...[
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
          ],
        ],
      ),
    );
  }

  Widget _timelineTile(String label, IconData icon, {required bool done, required bool isLast}) {
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
                  color: done ? AppColors.primary : AppColors.surfaceSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: done ? AppColors.primary : AppColors.border),
                ),
                child: Icon(icon, size: 18, color: done ? Colors.white : AppColors.textHint),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? AppColors.primary : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                color: done ? AppColors.textPrimary : AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}