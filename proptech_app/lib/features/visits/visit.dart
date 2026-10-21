enum VisitStatus { pending, confirmed, completed, cancelled }

class Visit {
  final String id;
  final String propertyId;
  final String propertyTitle;
  final String propertyImageUrl;
  final String visitorName;
  final DateTime scheduledAt;
  final VisitStatus status;

  /// Visitor's feedback after a completed visit: 'interested' | 'maybe' |
  /// 'not_interested' | '' (not given yet).
  final String feedbackInterest;
  final String feedbackNote;

  /// How many times this visit was rescheduled.
  final int rescheduleCount;

  /// 6-digit visit OTP. Only the visitor (buyer) receives it, once the owner
  /// confirms the visit. The buyer tells it to the owner at the visit.
  final String otpCode;
  final bool otpVerified;

  /// Confirmed, but the OTP stays hidden until the visit time has come.
  final bool otpPending;

  const Visit({
    required this.id,
    this.propertyId = '',
    required this.propertyTitle,
    required this.propertyImageUrl,
    required this.visitorName,
    required this.scheduledAt,
    required this.status,
    this.feedbackInterest = '',
    this.feedbackNote = '',
    this.rescheduleCount = 0,
    this.otpCode = '',
    this.otpVerified = false,
    this.otpPending = false,
  });

  bool get hasFeedback => feedbackInterest.isNotEmpty;

  bool get isUpcoming => status == VisitStatus.pending || status == VisitStatus.confirmed;

  /// Mirrors the backend cap (maxReschedules = 3).
  bool get canReschedule => isUpcoming && rescheduleCount < 3;

  factory Visit.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'pending';
    return Visit(
      id: json['id'] as String,
      propertyId: json['property_id'] as String? ?? '',
      propertyTitle: json['property_title'] as String? ?? '',
      propertyImageUrl: json['property_image_url'] as String? ?? '',
      visitorName: json['visitor_name'] as String? ?? '',
      scheduledAt: DateTime.tryParse(json['scheduled_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      status: VisitStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => VisitStatus.pending,
      ),
      feedbackInterest: json['feedback_interest'] as String? ?? '',
      feedbackNote: json['feedback_note'] as String? ?? '',
      rescheduleCount: (json['reschedule_count'] as num?)?.toInt() ?? 0,
      otpCode: json['otp_code'] as String? ?? '',
      otpVerified: json['otp_verified'] as bool? ?? false,
      otpPending: json['otp_pending'] as bool? ?? false,
    );
  }
}