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
  });

  bool get hasFeedback => feedbackInterest.isNotEmpty;

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
    );
  }
}