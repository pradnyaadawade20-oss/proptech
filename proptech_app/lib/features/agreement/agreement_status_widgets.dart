import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import 'agreement.dart';

/// Colour for each agreement state (spec 12.5), shared by chip, banner, timeline.
Color agreementStatusColor(AgreementStatus s) => switch (s) {
      AgreementStatus.requested => AppColors.warning,
      AgreementStatus.draftReady => AppColors.primary,
      AgreementStatus.awaitingSignatures => AppColors.primary,
      AgreementStatus.signedByOwner => AppColors.secondary,
      AgreementStatus.signedByTenant => AppColors.secondary,
      AgreementStatus.completed => AppColors.success,
      AgreementStatus.rejected => AppColors.error,
      AgreementStatus.cancelled => AppColors.textSecondary,
      AgreementStatus.expired => AppColors.textSecondary,
    };

IconData agreementStatusIcon(AgreementStatus s) => switch (s) {
      AgreementStatus.requested => Icons.hourglass_top_rounded,
      AgreementStatus.draftReady => Icons.thumb_up_alt_outlined,
      AgreementStatus.awaitingSignatures => Icons.thumb_up_alt_outlined,
      AgreementStatus.signedByOwner => Icons.edit_outlined,
      AgreementStatus.signedByTenant => Icons.edit_outlined,
      AgreementStatus.completed => Icons.verified_outlined,
      AgreementStatus.rejected => Icons.cancel_outlined,
      AgreementStatus.cancelled => Icons.block_outlined,
      AgreementStatus.expired => Icons.timer_off_outlined,
    };

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatAgreementDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// "Expires in 3 days" for an open agreement; null once it is final.
String? agreementExpiryText(Agreement a) {
  if (a.status.isFinal || a.expiresAt == null) return null;
  final left = a.expiresAt!.difference(DateTime.now());
  if (left.isNegative) return 'Deadline passed. This agreement is about to expire.';
  if (left.inHours < 1) return 'Expires in less than an hour';
  if (left.inHours < 24) return 'Expires in ${left.inHours} hour(s)';
  return 'Expires in ${left.inDays} day(s)';
}

/// True when the open agreement is inside its last 24 hours (or already late).
bool agreementExpiresSoon(Agreement a) =>
    !a.status.isFinal &&
    a.expiresAt != null &&
    a.expiresAt!.difference(DateTime.now()).inHours < 24;

/// Small pill showing the user-facing state (Pending / Approved / Signed ...).
class AgreementStatusChip extends StatelessWidget {
  final AgreementStatus status;
  const AgreementStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = agreementStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(agreementStatusIcon(status), size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            status.displayLabel,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Banner explaining a closed agreement (rejected / cancelled / expired): who,
/// when and why. Renders nothing for any other status.
class AgreementClosedBanner extends StatelessWidget {
  final Agreement agreement;
  const AgreementClosedBanner({super.key, required this.agreement});

  String _headline() {
    final by = agreement.statusChangedByName;
    switch (agreement.status) {
      case AgreementStatus.rejected:
        return by != null ? 'Rejected by $by' : 'Agreement rejected';
      case AgreementStatus.cancelled:
        return by != null ? 'Cancelled by $by' : 'Agreement cancelled';
      case AgreementStatus.expired:
        return 'Agreement expired';
      default:
        return '';
    }
  }

  String _detail() {
    final reason = agreement.statusReason;
    if (agreement.status == AgreementStatus.expired) {
      return 'It was not completed before the deadline. Request a new agreement to continue.';
    }
    if (reason != null && reason.isNotEmpty) return 'Reason: $reason';
    return 'No reason was given.';
  }

  @override
  Widget build(BuildContext context) {
    if (!agreement.status.isClosedWithoutSigning) return const SizedBox.shrink();
    final color = agreementStatusColor(agreement.status);
    final when = agreement.statusChangedAt ?? agreement.updatedAt;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(agreementStatusIcon(agreement.status), color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_headline(),
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 3),
                Text(_detail(),
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary, height: 1.4)),
                if (when != null) ...[
                  const SizedBox(height: 3),
                  Text(formatAgreementDate(when),
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Expires in N days" line for open agreements; turns red in the last 24h.
class AgreementExpiryNote extends StatelessWidget {
  final Agreement agreement;
  const AgreementExpiryNote({super.key, required this.agreement});

  @override
  Widget build(BuildContext context) {
    final text = agreementExpiryText(agreement);
    if (text == null) return const SizedBox.shrink();
    final color = agreementExpiresSoon(agreement) ? AppColors.error : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: color))),
        ],
      ),
    );
  }
}