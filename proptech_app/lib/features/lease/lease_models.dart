double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;
String _s(dynamic v) => v?.toString() ?? '';
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class Lease {
  final String id, agreementId, propertyId, propertyTitle, propertyImageUrl;
  final String ownerId, ownerName, tenantId, tenantName;
  final double monthlyRent, securityDeposit, lateFeePerDay;
  final String startDate, endDate;
  final int graceDays;
  final String status; // active | notice_given | moved_out | renewed
  final String renewalStatus; // none | renew_requested | renew_accepted | renew_declined | vacate
  final String? moveOutDate, renewedAgreementId, nextDueDate;
  final DateTime? moveInConfirmedAt;
  final int overdueCount, daysToExpiry;
  final String depositStatus;

  const Lease({
    required this.id,
    required this.agreementId,
    required this.propertyId,
    required this.propertyTitle,
    required this.propertyImageUrl,
    required this.ownerId,
    required this.ownerName,
    required this.tenantId,
    required this.tenantName,
    required this.monthlyRent,
    required this.securityDeposit,
    required this.lateFeePerDay,
    required this.startDate,
    required this.endDate,
    required this.graceDays,
    required this.status,
    required this.renewalStatus,
    required this.overdueCount,
    required this.daysToExpiry,
    required this.depositStatus,
    this.moveOutDate,
    this.renewedAgreementId,
    this.nextDueDate,
    this.moveInConfirmedAt,
  });

  /// What to show as the lease status: a lease whose end date has passed (and
  /// where nobody is renewing) is "ended", not "active".
  String get displayStatus =>
      status == 'active' && daysToExpiry < 0 && (renewalStatus == 'none' || renewalStatus == 'renew_declined')
          ? 'ended'
          : status;

  factory Lease.fromJson(Map<String, dynamic> j) => Lease(
        id: _s(j['id']),
        agreementId: _s(j['agreement_id']),
        propertyId: _s(j['property_id']),
        propertyTitle: _s(j['property_title']),
        propertyImageUrl: _s(j['property_image_url']),
        ownerId: _s(j['owner_id']),
        ownerName: _s(j['owner_name']),
        tenantId: _s(j['tenant_id']),
        tenantName: _s(j['tenant_name']),
        monthlyRent: _n(j['monthly_rent']),
        securityDeposit: _n(j['security_deposit']),
        lateFeePerDay: _n(j['late_fee_per_day']),
        startDate: _s(j['start_date']),
        endDate: _s(j['end_date']),
        graceDays: (j['grace_days'] as num?)?.toInt() ?? 0,
        status: _s(j['status']),
        renewalStatus: _s(j['renewal_status']).isEmpty ? 'none' : _s(j['renewal_status']),
        moveOutDate: j['move_out_date']?.toString(),
        renewedAgreementId: j['renewed_agreement_id']?.toString(),
        nextDueDate: j['next_due_date']?.toString(),
        moveInConfirmedAt: _dt(j['move_in_confirmed_at']),
        overdueCount: (j['overdue_count'] as num?)?.toInt() ?? 0,
        daysToExpiry: (j['days_to_expiry'] as num?)?.toInt() ?? 0,
        depositStatus: _s(j['deposit_status']),
      );
}

class RentPayment {
  final String id, dueDate, status, displayStatus;
  final int periodNo, lateDays;
  final double amount, lateFee, total;
  final String paymentMethod, reference, receiptNo, rejectReason;
  final DateTime? submittedAt, paidAt;
  final bool paidLate;

  const RentPayment({
    required this.id,
    required this.dueDate,
    required this.status,
    required this.displayStatus,
    required this.periodNo,
    required this.lateDays,
    required this.amount,
    required this.lateFee,
    required this.total,
    required this.paymentMethod,
    required this.reference,
    required this.receiptNo,
    required this.rejectReason,
    required this.paidLate,
    this.submittedAt,
    this.paidAt,
  });

  factory RentPayment.fromJson(Map<String, dynamic> j) => RentPayment(
        id: _s(j['id']),
        dueDate: _s(j['due_date']),
        status: _s(j['status']),
        displayStatus: _s(j['display_status']),
        periodNo: (j['period_no'] as num?)?.toInt() ?? 0,
        lateDays: (j['late_days'] as num?)?.toInt() ?? 0,
        amount: _n(j['amount']),
        lateFee: _n(j['late_fee']),
        total: _n(j['total']),
        paymentMethod: _s(j['payment_method']),
        reference: _s(j['reference']),
        receiptNo: _s(j['receipt_no']),
        rejectReason: _s(j['reject_reason']),
        paidLate: j['paid_late'] == true,
        submittedAt: _dt(j['submitted_at']),
        paidAt: _dt(j['paid_at']),
      );
}

class RentSummary {
  final double paid, pending, overdue, lateFees;
  const RentSummary({this.paid = 0, this.pending = 0, this.overdue = 0, this.lateFees = 0});

  factory RentSummary.fromJson(Map<String, dynamic> j) => RentSummary(
        paid: _n(j['paid_total']),
        pending: _n(j['pending_total']),
        overdue: _n(j['overdue_total']),
        lateFees: _n(j['late_fees']),
      );
}

class LeasePhoto {
  final String id, kind, room, caption, url, uploaderName, uploaderId;
  final String? deductionId;
  final bool isVideo;
  const LeasePhoto({
    required this.uploaderId,
    required this.id,
    required this.kind,
    required this.room,
    required this.caption,
    required this.url,
    required this.uploaderName,
    this.deductionId,
    this.isVideo = false,
  });

  factory LeasePhoto.fromJson(Map<String, dynamic> j) => LeasePhoto(
        id: _s(j['id']),
        kind: _s(j['kind']),
        room: _s(j['room']),
        caption: _s(j['caption']),
        url: _s(j['url']),
        uploaderName: _s(j['uploader_name']),
        uploaderId: _s(j['uploader_id']),
        deductionId: j['deduction_id']?.toString(),
        isVideo: j['is_video'] == true || _s(j['content_type']).startsWith('video/'),
      );
}

class Deduction {
  final String id, category, reason;
  final double amount;
  final List<LeasePhoto> photos;
  const Deduction({
    required this.id,
    required this.category,
    required this.reason,
    required this.amount,
    required this.photos,
  });

  factory Deduction.fromJson(Map<String, dynamic> j) => Deduction(
        id: _s(j['id']),
        category: _s(j['category']),
        reason: _s(j['reason']),
        amount: _n(j['amount']),
        photos: ((j['photos'] as List?) ?? const [])
            .map((e) => LeasePhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Deposit {
  final String id;
  final double amount, totalDeductions, refundAmount, tenantOwes, previewRefund;
  // pending | submitted | held | inspection | settlement | disputed | refund_due | refunded | carried_forward
  final String status, paymentMethod, reference, tenantNote, adminNote, refundMethod, refundReference;
  final List<Deduction> deductions;
  final DateTime? receivedAt, refundedAt;
  final String onlineRefundStatus; // '' | SUCCESS | PENDING | ONHOLD | CANCELLED | FAILED
  final bool canRefundOnline; // deposit was paid in the app, so it can be refunded in the app

  const Deposit({
    required this.id,
    required this.amount,
    required this.totalDeductions,
    required this.refundAmount,
    required this.tenantOwes,
    required this.previewRefund,
    required this.status,
    required this.paymentMethod,
    required this.reference,
    required this.tenantNote,
    required this.adminNote,
    required this.refundMethod,
    required this.refundReference,
    required this.deductions,
    this.receivedAt,
    this.refundedAt,
    this.onlineRefundStatus = '',
    this.canRefundOnline = false,
  });

  bool get refundInProgress => onlineRefundStatus == 'PENDING' || onlineRefundStatus == 'ONHOLD';

  factory Deposit.fromJson(Map<String, dynamic> j) => Deposit(
        id: _s(j['id']),
        amount: _n(j['amount']),
        totalDeductions: _n(j['total_deductions']),
        refundAmount: _n(j['refund_amount']),
        tenantOwes: _n(j['tenant_owes']),
        previewRefund: _n(j['preview_refund']),
        status: _s(j['status']),
        paymentMethod: _s(j['payment_method']),
        reference: _s(j['reference']),
        tenantNote: _s(j['tenant_note']),
        adminNote: _s(j['admin_note']),
        refundMethod: _s(j['refund_method']),
        refundReference: _s(j['refund_reference']),
        receivedAt: _dt(j['received_at']),
        refundedAt: _dt(j['refunded_at']),
        onlineRefundStatus: _s(j['online_refund_status']),
        canRefundOnline: j['can_refund_online'] == true,
        deductions: ((j['deductions'] as List?) ?? const [])
            .map((e) => Deduction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LeaseEvent {
  final String actorName, event, detail;
  final DateTime? createdAt;
  const LeaseEvent({required this.actorName, required this.event, required this.detail, this.createdAt});

  factory LeaseEvent.fromJson(Map<String, dynamic> j) => LeaseEvent(
        actorName: _s(j['actor_name']),
        event: _s(j['event']),
        detail: _s(j['detail']),
        createdAt: _dt(j['created_at']),
      );
}

class RoomComparison {
  final String room;
  final List<LeasePhoto> moveIn, moveOut;
  const RoomComparison({required this.room, required this.moveIn, required this.moveOut});

  factory RoomComparison.fromJson(Map<String, dynamic> j) {
    List<LeasePhoto> list(dynamic v) =>
        ((v as List?) ?? const []).map((e) => LeasePhoto.fromJson(e as Map<String, dynamic>)).toList();
    return RoomComparison(room: _s(j['room']), moveIn: list(j['move_in']), moveOut: list(j['move_out']));
  }
}

/// One suggested deposit deduction for an early move-out.
class EarlyExitItem {
  final String category, reason;
  final double amount;
  const EarlyExitItem({required this.category, required this.reason, required this.amount});

  factory EarlyExitItem.fromJson(Map<String, dynamic> j) =>
      EarlyExitItem(category: _s(j['category']), reason: _s(j['reason']), amount: _n(j['amount']));
}

/// What a move-out costs: unpaid rent and (for an exit before the lease end) the notice shortfall.
class EarlyExit {
  final bool early;
  final String endDate, moveOutDate;
  final int noticeRequiredDays, noticeGivenDays, shortfallDays, unpaidMonths;
  final double shortfallAmount, unpaidRent, totalDeduction, depositAmount, estimatedRefund;
  final List<EarlyExitItem> items;

  const EarlyExit({
    required this.early,
    required this.endDate,
    required this.moveOutDate,
    required this.noticeRequiredDays,
    required this.noticeGivenDays,
    required this.shortfallDays,
    required this.unpaidMonths,
    required this.shortfallAmount,
    required this.unpaidRent,
    required this.totalDeduction,
    required this.depositAmount,
    required this.estimatedRefund,
    required this.items,
  });

  factory EarlyExit.fromJson(Map<String, dynamic> j) => EarlyExit(
        early: j['early'] == true,
        endDate: _s(j['end_date']),
        moveOutDate: _s(j['move_out_date']),
        noticeRequiredDays: (j['notice_required_days'] as num?)?.toInt() ?? 0,
        noticeGivenDays: (j['notice_given_days'] as num?)?.toInt() ?? 0,
        shortfallDays: (j['shortfall_days'] as num?)?.toInt() ?? 0,
        unpaidMonths: (j['unpaid_months'] as num?)?.toInt() ?? 0,
        shortfallAmount: _n(j['shortfall_amount']),
        unpaidRent: _n(j['unpaid_rent']),
        totalDeduction: _n(j['total_deduction']),
        depositAmount: _n(j['deposit_amount']),
        estimatedRefund: _n(j['estimated_refund']),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => EarlyExitItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}